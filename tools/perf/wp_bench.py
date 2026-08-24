#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
WaterPipes performance harness.

Counts the Lua -> Java bridge calls each periodic pass of the mod makes, for a
set of fixed scenarios, so an optimisation can be measured instead of guessed at.

    python wp_bench.py                 # human-readable report
    python wp_bench.py --save-baseline # record current counts as the baseline
    python wp_bench.py --check         # diff against the baseline, non-zero exit on regression

The model lives in wp_model.py and is a hand transcription of the mod's control
flow -- it is approximate by design. What it gets right is the SHAPE: how many
network walks each pass makes, how many object scans each walk makes, and how
all of that grows with the size of the build. Absolute milliseconds are an
estimate (see --report notes); relative before/after numbers are the point.

Update the model whenever the traversal or the per-tick passes change, or the
baseline stops meaning anything.
"""

import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import wp_model as M

BASELINE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "baseline.json")

# Regression gate: how much a pass may grow before --check fails.
TOLERANCE = 0.02


# ---------------------------------------------------------------------------
# Scenarios: (name, pipes, containers, endpoints, routers, pumps, emitters, mains)
# ---------------------------------------------------------------------------
SCENARIOS = [
    ("tiny    (25 pipes, 1 sink)",       25,   2,  1, 0, 0,  1, 0),
    ("small   (100 pipes, farm)",       100,  10,  3, 1, 1,  4, 1),
    ("medium  (200 pipes, full base)",  200,  20,  6, 2, 2,  8, 1),
    ("large   (400 pipes)",             400,  40, 12, 4, 4, 16, 1),
    ("huge    (800 pipes)",             800,  80, 24, 8, 8, 32, 1),
]

SERVER_PASSES = [
    ("1min/routers",   M.pass_processRouters),
    ("1min/pumps",     M.pass_processPumps),
    ("1min/mains",     M.pass_processAllMains),
    ("1min/endpoints", M.pass_refreshPlumbedEndpoints),
    ("10min/reindex",  M.pass_reindexEndpoints),
    ("10min/scan",     M.pass_scanContainersAroundPipes),
    ("10min/graph",    M.pass_rebuildGraph),
    ("10min/redist",   M.pass_redistributeWater),
    ("1h/irrigation",  M.pass_irrigation),
]

CLIENT_PASSES = [
    ("client/sprayfx", M.pass_sprayfx_rescan),
    ("client/sound",   lambda s: (M.pass_sound_rescan(s, kind="hydrant"),
                                  M.pass_sound_rescan(s, kind="purifier"))),
    ("client/wetness", M.pass_wetness),
]

# Client passes sweep an area around the player, so every tile in range has to
# exist -- otherwise the sweep is free and the numbers lie.
CLIENT_RADIUS = 20


def densify(px=10, py=10, pz=0, radius=CLIENT_RADIUS):
    for dx in range(-radius - 2, radius + 3):
        for dy in range(-radius - 2, radius + 3):
            M.WORLD.ensure(px + dx, py + dy, pz)


def build(spec):
    _, pipes, cont, eps, rout, pumps, emit, mains = spec
    sc = M.Scenario(pipes=pipes, containers=cont, endpoints=eps, routers=rout,
                    pumps=pumps, emitters=emit, mains_inlets=mains)
    sc.pumps_have_source = True
    return sc


def run_suite():
    """Every pass of every scenario -> {scenario: {pass: bridge_calls}}."""
    out = {}
    for spec in SCENARIOS:
        name = spec[0]
        row = {}

        sc = build(spec)
        for label, fn in SERVER_PASSES:
            n, _, calls = M.measure(fn, sc)
            row[label] = n
            row[label + " :walks"] = calls.get("BFS", 0)

        sc = build(spec)
        densify()
        M.registry_populate(sc)
        for label, fn in CLIENT_PASSES:
            # Cold status cache per pass, so each number is the worst case and stays
            # comparable to the pre-registry baseline.
            M.STATUS_CACHE.clear()
            n, _, calls = M.measure(fn, sc)
            row[label] = n
            row[label + " :walks"] = calls.get("BFS", 0)

        M.STATUS_CACHE.clear()
        n, _, calls = M.measure(M.pass_registry_sweep, sc)
        row["client/sweep"] = n

        # What the client actually pays over fifteen real seconds: 20 spray rescans,
        # 60 wetness checks, 15 sound passes, 3 registry sweeps (one per 5 s), and a
        # status cache that expires every 3 s.
        M.STATUS_CACHE.clear()
        M.reset()
        for second in range(15):
            if second % 5 == 0:
                M.pass_registry_sweep(sc)
            if second % 3 == 0:
                M.STATUS_CACHE.clear()          # TTL expiry
            M.pass_sprayfx_rescan(sc)
            M.pass_sprayfx_rescan(sc)           # ~1.33 rescans/s
            for _ in range(4):
                M.pass_wetness(sc)
            M.pass_sound_rescan(sc, kind="hydrant")
            M.pass_sound_rescan(sc, kind="purifier")
        row["client/15s steady"] = M.total_bc()
        row["client/15s steady :lua"] = M.total_lua()
        row["client/15s steady :walks"] = M.CALLS.get("BFS", 0)

        # The four EveryOneMinute handlers all run inside ONE frame, so they share the
        # per-frame caches. Summing the individually-measured passes would charge each
        # of them a cold cache and understate the real behaviour.
        sc = build(spec)
        minute = [fn for l, fn in SERVER_PASSES if l.startswith("1min/")]
        n, _, calls = M.measure_frame(minute, sc)
        row["TOTAL 1min"] = n
        row["TOTAL 1min :walks"] = calls.get("BFS", 0)

        # ...and what five consecutive minutes cost, which is a different question and
        # the one the fill path's cache lifetime actually answers.
        #
        # Every per-pass number above is measured cold on purpose: it is a worst case,
        # and worst cases stay comparable. But no minute after the first is cold in a
        # real game. Only a run of them shows what an event lifetime buys, because the
        # whole benefit is that minute two does not re-walk what minute one walked --
        # and a bench made only of cold single passes is structurally blind to it.
        #
        # frame_reset between minutes, and nothing else: that is exactly the OnTick
        # boundary. What survives it is what the mod says survives it.
        sc = build(spec)
        M.reset()
        M.cold()
        for _ in range(5):
            M.frame_reset()
            for fn in minute:
                fn(sc)
        row["server/5min steady"] = M.total_bc()
        row["server/5min steady :walks"] = M.CALLS.get("BFS", 0)

        out[name] = row
    return out


# ---------------------------------------------------------------------------
def report(results):
    print("=" * 84)
    print("WaterPipes -- bridge calls per pass")
    print("=" * 84)
    labels = ([l for l, _ in SERVER_PASSES] + [l for l, _ in CLIENT_PASSES]
              + ["client/sweep", "client/15s steady", "TOTAL 1min",
                 "server/5min steady"])

    head = "%-22s" % "pass"
    for spec in SCENARIOS:
        head += "%14s" % spec[0].split()[0]
    print(head)
    print("-" * 84)
    for label in labels:
        line = "%-22s" % label
        for spec in SCENARIOS:
            line += "%14s" % "{:,}".format(results[spec[0]][label])
        print(line)

    print("\nNetwork walks (BFS) per pass -- the number that has to come down:")
    print("-" * 84)
    for label in labels[:-1]:
        key = label + " :walks"
        vals = [results[s[0]].get(key, 0) for s in SCENARIOS]
        if not any(vals):
            continue
        line = "%-22s" % label
        for v in vals:
            line += "%14d" % v
        print(line)

    print("\nScaling: TOTAL 1min / pipes^2 (flat = quadratic growth)")
    print("-" * 84)
    line = "%-22s" % "coefficient"
    for spec in SCENARIOS:
        p = spec[1]
        line += "%14.1f" % (results[spec[0]]["TOTAL 1min"] / float(p * p))
    print(line)

    print("\nNote: bridge-call counts are exact for the model; the model itself is an")
    print("approximation of the mod's control flow. Use the deltas, not the absolutes.")


def check(results):
    if not os.path.exists(BASELINE):
        print("No baseline at %s -- run --save-baseline first." % BASELINE)
        return 1
    with open(BASELINE, encoding="utf-8") as fh:
        base = json.load(fh)

    regressions, wins = [], []
    for scenario, row in sorted(results.items()):
        old_row = base.get(scenario)
        if old_row is None:
            print("NEW scenario (not in baseline): %s" % scenario)
            continue
        for label, new in sorted(row.items()):
            if label.endswith(":walks"):
                continue
            old = old_row.get(label)
            if old is None:
                continue
            if old == 0:
                continue
            delta = (new - old) / float(old)
            if delta > TOLERANCE:
                regressions.append((scenario, label, old, new, delta))
            elif delta < -TOLERANCE:
                wins.append((scenario, label, old, new, delta))

    for title, rows in (("IMPROVED", wins), ("REGRESSED", regressions)):
        if not rows:
            continue
        print("\n%s:" % title)
        for scenario, label, old, new, delta in rows:
            print("  %-32s %-18s %12s -> %12s  %+7.1f%%"
                  % (scenario.split("(")[0].strip(), label,
                     "{:,}".format(old), "{:,}".format(new), delta * 100))

    if regressions:
        print("\n%d regression(s) over the %.0f%% tolerance."
              % (len(regressions), TOLERANCE * 100))
        return 1
    if wins:
        print("\nNo regressions. %d pass(es) improved." % len(wins))
    else:
        print("No change beyond the %.0f%% tolerance." % (TOLERANCE * 100))
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--save-baseline", action="store_true",
                    help="record the current counts as the reference")
    ap.add_argument("--check", action="store_true",
                    help="diff against the baseline; exit 1 on regression")
    args = ap.parse_args()

    results = run_suite()

    if args.save_baseline:
        with open(BASELINE, "w", encoding="utf-8") as fh:
            json.dump(results, fh, indent=2, sort_keys=True)
        print("Baseline written to %s" % BASELINE)
        return 0
    if args.check:
        return check(results)

    report(results)
    return 0


if __name__ == "__main__":
    sys.exit(main())
