#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Validate the mod's translations against each other and against the code.

lint_json.py checks that each file is readable the way the game reads it. This checks that the CONTENT
is coherent, which is a different set of failures and all of them silent:

  * a key the Lua asks for that no language defines -- getText returns the key itself
  * a key one language defines and another does not, usually a rename applied to one file
  * PLACEHOLDER DRIFT: EN says %1 and %2, a translation says only %1, and a value is dropped
  * an empty string, which renders as a blank line in a tooltip

    python lint_translations.py [root]

Exits 1 on anything visibly wrong. Key parity is reported but does not fail: a partial translation is
a normal state.
"""

import io
import json
import os
import re
import sys

DEFAULT_ROOT = os.path.join(
    os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
    "Contents", "mods", "WaterPipes")

REFERENCE = "EN"

# getText("KEY") / getTextOrNull("KEY"), literal first argument only. A key built by
# concatenation cannot be checked this way and is counted rather than guessed at.
GETTEXT = re.compile(r'\bgetText(?:OrNull)?\s*\(\s*"([^"]+)"')
GETTEXT_DYNAMIC = re.compile(r'\bgetText(?:OrNull)?\s*\(\s*(?!")')
PLACEHOLDER = re.compile(r"%(\d)")


# Where the base game keeps its own strings. A mod legitimately borrows them -- this one reads
# ContextMenu_PlumbItem to find the engine's "Plumb %1" option by its localized prefix -- so a key the
# mod does not define is only a fault if VANILLA does not define it either.
VANILLA = [
    "D:/Archivos de Programas/SteamLibrary/steamapps/common/ProjectZomboid",
    "C:/Program Files (x86)/Steam/steamapps/common/ProjectZomboid",
    "B:/SteamLibrary/steamapps/common/ProjectZomboid",
]


def load_language(base):
    """Every key in every json of one language, as {key: (value, file)}."""
    out = {}
    if not os.path.isdir(base):
        return out
    for name in sorted(os.listdir(base)):
        if not name.lower().endswith(".json"):
            continue
        path = os.path.join(base, name)
        raw = io.open(path, "rb").read()
        data = json.loads(raw.decode("utf-8"))
        for key, value in data.items():
            out[key] = (value, name)
    return out


VANILLA_KEY = re.compile(r'^\s*"([^"]+)"\s*:', re.M)


def vanilla_keys():
    """Every key name the base game defines, with where they came from, or (set(), None).

    Read with a regex rather than a JSON parser: PZ's own translation files carry trailing commas,
    which org.json accepts and json.loads does not. Only the key NAMES are wanted here.
    """
    for root in VANILLA:
        base = os.path.join(root, "media", "lua", "shared", "Translate", REFERENCE)
        if not os.path.isdir(base):
            continue
        found = set()
        for name in sorted(os.listdir(base)):
            if not name.lower().endswith(".json"):
                continue
            raw = io.open(os.path.join(base, name), "rb").read()
            found.update(VANILLA_KEY.findall(raw.decode("utf-8", "replace")))
        return found, base
    return set(), None


def placeholders(text):
    return set(PLACEHOLDER.findall(text)) if isinstance(text, str) else set()


def lua_keys(root):
    """Keys the code asks for, and how many asks could not be read literally."""
    used, dynamic = {}, 0
    for base, _dirs, names in os.walk(root):
        for name in names:
            if not name.endswith(".lua"):
                continue
            path = os.path.join(base, name)
            text = io.open(path, encoding="utf-8", errors="replace").read()
            for index, line in enumerate(text.split("\n")):
                line = re.sub(r"--.*$", "", line)
                for key in GETTEXT.findall(line):
                    used.setdefault(key, []).append("%s:%d" % (path, index + 1))
                for _ in GETTEXT_DYNAMIC.finditer(line):
                    dynamic += 1
    return used, dynamic


def main(argv):
    root = argv[1] if len(argv) > 1 else DEFAULT_ROOT
    translate = os.path.join(root, "42.15", "media", "lua", "shared", "Translate")
    if not os.path.isdir(translate):
        print("no Translate directory under %s" % root)
        return 1

    languages = sorted(name for name in os.listdir(translate)
                       if os.path.isdir(os.path.join(translate, name)))
    table = {lang: load_language(os.path.join(translate, lang)) for lang in languages}

    if REFERENCE not in table:
        print("no %s to compare against" % REFERENCE)
        return 1

    reference = table[REFERENCE]
    problems, notes = [], []

    # 1. Keys the code asks for.
    used, dynamic = lua_keys(root)
    vanilla, vanilla_where = vanilla_keys()
    borrowed = []
    for key in sorted(used):
        if key in reference:
            continue
        if key in vanilla:
            borrowed.append(key)
            continue
        problems.append("%s is asked for by the code and defined by neither the mod nor the "
                        "base game\n      %s" % (key, used[key][0]))

    # 2. Empty values anywhere.
    for lang in languages:
        for key, (value, where) in sorted(table[lang].items()):
            if isinstance(value, str) and not value.strip():
                problems.append("%s/%s: %s is empty" % (lang, where, key))

    # 3. Placeholder drift against the reference language.
    for lang in languages:
        if lang == REFERENCE:
            continue
        for key, (value, where) in sorted(table[lang].items()):
            if key not in reference:
                continue
            want = placeholders(reference[key][0])
            have = placeholders(value)
            if want != have:
                problems.append(
                    "%s/%s: %s uses %s where %s uses %s -- a value would be dropped or nil"
                    % (lang, where, key,
                       "".join("%" + p for p in sorted(have)) or "none",
                       REFERENCE,
                       "".join("%" + p for p in sorted(want)) or "none"))

    # 4. Key parity, reported rather than failed: a partial translation is normal.
    for lang in languages:
        if lang == REFERENCE:
            continue
        missing = sorted(set(reference) - set(table[lang]))
        extra = sorted(set(table[lang]) - set(reference))
        if missing:
            notes.append("%s is missing %d key(s) %s defines: %s"
                         % (lang, len(missing), REFERENCE, ", ".join(missing[:6])
                            + (" ..." if len(missing) > 6 else "")))
        if extra:
            notes.append("%s defines %d key(s) %s does not: %s"
                         % (lang, len(extra), REFERENCE, ", ".join(extra[:6])
                            + (" ..." if len(extra) > 6 else "")))

    # 5. Keys nobody asks for. Informational: sandbox options, recipe and item names are
    #    looked up by the engine, never through getText.
    unused = sorted(key for key in reference
                    if key not in used
                    and not key.startswith(("Sandbox_", "Recipe_", "ItemName_",
                                            "DisplayName_", "Tooltip_craft_",
                                            "ContextMenu_", "UI_")))
    if unused:
        notes.append("%d key(s) no getText call names (may be looked up elsewhere): %s"
                     % (len(unused), ", ".join(unused[:6])
                        + (" ..." if len(unused) > 6 else "")))

    if vanilla_where is None:
        notes.append("the base game's Translate directory was not found, so a key borrowed from "
                     "vanilla cannot be told apart from a missing one")
    elif borrowed:
        notes.append("%d key(s) borrowed from the base game, which is fine: %s"
                     % (len(borrowed), ", ".join(borrowed)))

    print("languages: %s" % ", ".join("%s (%d keys)" % (l, len(table[l])) for l in languages))
    if vanilla_where:
        print("base game: %d key(s) available to borrow" % len(vanilla))
    print("code asks for %d distinct key(s); %d ask(s) built a key dynamically and were skipped"
          % (len(used), dynamic))
    print("")

    for note in notes:
        print("note:  %s" % note)
    if notes:
        print("")

    for problem in problems:
        print("PROBLEM: %s" % problem)

    if problems:
        print("\n%d problem(s). None of these throws; they reach the player looking deliberate."
              % len(problems))
        return 1

    print("No problems: every key the code asks for exists, no placeholder drifts, "
          "nothing is empty.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
