#!/usr/bin/env python3
"""Release gate: prove the test suite still bites before shipping.

A green suite says nothing on its own. `test_fill_path` carried an assertion NAMING the
router levelling bug and passed all the way through the release that shipped it, because
its world let a second mechanism produce the same number. A suite can only be trusted to
the extent it has been shown to FAIL when the code is wrong.

So this runs every conservation test twice: against the working tree, where all of them
must pass, and against the modules as they stood at the PREVIOUS RELEASE, where the ones
covering this cycle's fixes must fail. A test that passes against both is carried-forward
coverage -- fine, but it proved nothing this cycle and is reported as such.

    python tools/perf/release_gate.py                # gate the working tree vs the last release
    python tools/perf/release_gate.py --baseline REV # gate against some other point
    python tools/perf/release_gate.py --no-bench     # skip the bridge-call regression check

Exit 0 only when the tree is shippable.
"""

import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, os.pardir, os.pardir))
SHARED = "Contents/mods/WaterPipes/42.15/media/lua/shared/WaterPipes"
COMMON = "Contents/mods/WaterPipes/common/media/lua/shared/WaterPipes"
SCRIPTS = "Contents/mods/WaterPipes/42.15/media/scripts"
TESTS_DIR = os.path.join(REPO, "tools", "conservation")

# The commit that shipped the last version. There are no tags on this repo; a release is a
# `chore: bump modversion` on main, which is what the release skill produces.
#
# ANCHORED, and it has to be. The first version of this matched "bump modversion" anywhere in a
# message, and the very commit that added this file quotes that phrase while explaining itself -- so
# the gate picked ITSELF as the previous release, diffed today's modules against today's, and
# reported a clean sweep of "carried forward" for a release with four fixes in it. A gate that can
# select the wrong baseline reports the reassuring answer, never the alarming one.
BASELINE_GREP = "^chore: bump modversion"


def git(*args):
    return subprocess.run(["git"] + list(args), cwd=REPO, capture_output=True,
                          text=True, encoding="utf-8", errors="replace")


def die(message, hint=None):
    print("\nGATE FAILED: " + message)
    if hint:
        print("  " + hint)
    sys.exit(1)


def find_baseline():
    out = git("log", "-E", "--format=%H %s", "-1", "--grep=" + BASELINE_GREP)
    if out.returncode != 0 or not out.stdout.strip():
        die("no previous release found",
            "No commit matching " + BASELINE_GREP + ". Pass --baseline REV.")
    sha, _, subject = out.stdout.strip().partition(" ")
    return sha, subject


def extract(rev, path, into, suffix=".lua", flatten=True):
    """Copy one directory out of `rev` into `into`. Returns how many files landed.

    Lua modules are flattened, because that is how WP_LUA_ROOT addresses them. Script .txt
    files keep their tree: the recipes sit several directories down and the tests open
    them by that path.
    """
    os.makedirs(into, exist_ok=True)
    listing = git("ls-tree", "-r", "--name-only", rev, path + "/")
    if listing.returncode != 0:
        return 0
    count = 0
    for entry in listing.stdout.split("\n"):
        entry = entry.strip()
        if not entry.endswith(suffix):
            continue
        blob = subprocess.run(["git", "show", rev + ":" + entry], cwd=REPO,
                              capture_output=True)
        if blob.returncode != 0:
            continue
        if flatten:
            target = os.path.join(into, os.path.basename(entry))
        else:
            target = os.path.join(into, os.path.relpath(entry, path))
            os.makedirs(os.path.dirname(target), exist_ok=True)
        with open(target, "wb") as handle:
            handle.write(blob.stdout)
        count += 1
    return count


def run_test(name, env_root=None, env_common=None, env_scripts=None):
    env = dict(os.environ)
    if env_root:
        env["WP_LUA_ROOT"] = env_root
        # Set rather than left over: a baseline run that silently loaded today's common
        # modules would be measuring a mixture of two builds.
        env["WP_LUA_COMMON"] = env_common or env_root
        # Same reasoning for the script .txt tree. Balance lives in recipes as much as in
        # modules, and a fix that edits only a recipe is invisible to a baseline that keeps
        # serving today's copy -- it would report itself as carried-forward coverage.
        env["WP_SCRIPTS_ROOT"] = env_scripts or ""
    else:
        env.pop("WP_LUA_ROOT", None)
        env.pop("WP_LUA_COMMON", None)
        env.pop("WP_SCRIPTS_ROOT", None)
    try:
        done = subprocess.run(["lua", name], cwd=TESTS_DIR, capture_output=True,
                              text=True, encoding="utf-8", errors="replace",
                              env=env, timeout=120)
    except FileNotFoundError:
        die("`lua` is not on PATH", "The conservation suite needs a Lua 5.4 interpreter.")
    except subprocess.TimeoutExpired:
        return False, "timed out"
    failed = len(re.findall(r"\bFAIL\b", done.stdout))
    if failed:
        detail = str(failed) + " failing check(s)"
    elif done.returncode:
        detail = "exit " + str(done.returncode)
    else:
        detail = ""
    return done.returncode == 0, detail


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--baseline", help="revision to compare against (default: last release)")
    parser.add_argument("--no-bench", action="store_true", help="skip wp_bench --check")
    args = parser.parse_args()

    if not os.path.isdir(TESTS_DIR):
        die("tools/conservation is missing",
            "The gate has nothing to run. That directory is in .gitignore, so a fresh "
            "clone does not have it -- see the note in tools/perf/README.md.")

    tests = sorted(f for f in os.listdir(TESTS_DIR)
                   if f.startswith("test") and f.endswith(".lua"))
    if not tests:
        die("no test*.lua found in tools/conservation")

    if args.baseline:
        baseline, subject = args.baseline, "(given on the command line)"
    else:
        baseline, subject = find_baseline()

    print("=" * 78)
    print("WaterPipes release gate")
    print("=" * 78)
    print("  working tree : " + str(len(tests)) + " test file(s)")
    print("  baseline     : " + baseline[:7] + "  " + subject)
    if not args.baseline and "modversion" not in subject:
        die("the baseline commit does not look like a release: " + subject,
            "Expected a `chore: bump modversion ...` commit. Pass --baseline REV explicitly.")
    print("")

    # ---- 1. the tree must be green -------------------------------------------------------
    print("-- the working tree must be green --")
    broken = []
    for name in tests:
        ok, detail = run_test(name)
        print("  %-28s %-5s %s" % (name, "pass" if ok else "FAIL", detail))
        if not ok:
            broken.append(name)
    if broken:
        die(str(len(broken)) + " test(s) fail against the working tree: " + ", ".join(broken),
            "Nothing ships until these are green.")

    # ---- 2. and the suite must bite ------------------------------------------------------
    workdir = tempfile.mkdtemp(prefix="wp_gate_")
    try:
        root = os.path.join(workdir, "shared")
        common = os.path.join(workdir, "common")
        scripts = os.path.join(workdir, "scripts")
        n = extract(baseline, SHARED, root)
        extract(baseline, COMMON, common)
        extract(baseline, SCRIPTS, scripts, suffix=".txt", flatten=False)
        if n == 0:
            die("could not extract the baseline's Lua modules from " + baseline[:7])

        print("")
        print("-- and it must FAIL against the previous release --")
        proves, carried = [], []
        for name in tests:
            ok, detail = run_test(name, root + os.sep, common + os.sep, scripts + os.sep)
            if ok:
                carried.append(name)
                print("  %-28s passes there too   (carried forward)" % name)
            else:
                proves.append(name)
                print("  %-28s FAILS there        <- proves a fix   %s" % (name, detail))

        print("")
        print("=" * 78)
        if proves:
            print(str(len(proves)) + " test file(s) demonstrably catch something the last release got wrong:")
            for name in proves:
                print("    " + name)
        else:
            print("NOTHING in the suite fails against the last release.")
            print("  For a release that only adds features that is expected. For one that claims")
            print("  to FIX something it means the fix has no test that would have caught it --")
            print("  which is how the router levelling bug shipped under an assertion naming it.")
        if carried:
            print("")
            print(str(len(carried)) + " file(s) pass against both. Carried-forward coverage: real, but")
            print("  unproven this cycle -- a test only earns trust on a build where it fails.")
    finally:
        shutil.rmtree(workdir, ignore_errors=True)

    # ---- 3. and the bridge-call budget must not have moved -------------------------------
    if not args.no_bench:
        print("")
        print("-- bridge calls per pass --")
        bench = subprocess.run([sys.executable, os.path.join(HERE, "wp_bench.py"), "--check"],
                               cwd=REPO, capture_output=True, text=True,
                               encoding="utf-8", errors="replace")
        print("  " + (bench.stdout.strip().replace("\n", "\n  ") or "(no output)"))
        if bench.returncode != 0:
            die("wp_bench reports a regression",
                "Intentional? Re-record with: python tools/perf/wp_bench.py --save-baseline")

    print("")
    print("GATE PASSED -- the tree is shippable.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
