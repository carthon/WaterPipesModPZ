#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Check every JSON the mod ships, the way the GAME reads it.

Written because an edit to three translation files crashed the game on load:

    JSON Error in: ...Translate/EN/IG_UI.json
    org.json.JSONException: A JSONObject text must begin with '{'
                            at 1 [character 2 line 1]

The files were valid JSON. They had been written with Python's `utf-8-sig`
encoding, which PREPENDS a byte-order mark -- and PZ's org.json parser sees those
three bytes before the `{` and refuses the file. Every translated string in the
mod vanished, in the loading screen, before any of it could be noticed.

The part worth remembering is how it got past a check. The edit WAS validated,
with a script that read the files back using `utf-8-sig` -- an encoding whose
entire purpose is to strip a leading BOM. The validator was blind to precisely
the thing the edit had broken, because it undid it on the way in.

So this reads BYTES. It does not decode first and it does not trust an encoding
argument to tell it what is there:

  * the first byte must be `{`, so no BOM and no leading whitespace
  * the bytes must decode as UTF-8
  * the result must parse as JSON
  * the keys must be unique, since org.json silently keeps the last of a
    duplicate pair while a human reading the file sees the first
  * no string may be double-encoded, which is valid UTF-8 and valid JSON and
    still wrong -- it is the second way an edit to these files has gone bad
  * no string may carry a bare `%`, which reaches Java's Formatter as a
    conversion specifier

    python lint_json.py [path ...]      # default: everything the mod ships

Exits 1 on any finding, so it can gate a commit or a deploy.
"""

import io
import json
import re
import os
import sys

DEFAULT_ROOT = os.path.join(
    os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
    "Contents", "mods", "WaterPipes")

BOM = b"\xef\xbb\xbf"


# The signature of text that was UTF-8 and got read as Latin-1 somewhere: a byte in the
# lead range followed by one in the continuation range, both now standing as separate
# characters. Real Spanish or Chinese never looks like this -- "Anade" mojibaked reads
# as U+00C3 U+00B1 where it should be a single U+00F1.
MOJIBAKE = re.compile("[" + chr(0x00C2) + "-" + chr(0x00F4) + "][" + chr(0x0080) + "-" + chr(0x00BF) + "]")

# getText substitutes %1..%9. A BARE percent reaches Java's Formatter as a conversion
# specifier and throws at display time -- this repo has fixed that once already, across
# 21 strings. %% is the escape.
#
# The escaped pairs are REMOVED before this is applied, rather than excluded by the
# pattern: written as "%(?![0-9%])" it lets the first % of a pair through and then flags
# the second, which reported all 21 of the correctly-escaped strings as broken. A linter
# that cries wolf over the fix somebody already made is worse than no linter.
BARE_PERCENT = re.compile("%(?![0-9])")


def scan_values(node, path, problems):
    """Walk the decoded JSON and check the strings themselves, not just the shape."""
    if isinstance(node, dict):
        for key, value in node.items():
            scan_values(value, path + [str(key)], problems)
    elif isinstance(node, list):
        for index, value in enumerate(node):
            scan_values(value, path + ["[%d]" % index], problems)
    elif isinstance(node, str):
        where = ".".join(path) or "(root)"
        found = MOJIBAKE.search(node)
        if found:
            problems.append(
                "%s looks double-encoded around %r -- UTF-8 read as Latin-1 somewhere. "
                "It is still valid JSON and still valid UTF-8, which is why nothing else "
                "catches it." % (where, found.group(0)))
        if BARE_PERCENT.search(node.replace("%%", "")):
            problems.append(
                "%s contains a bare '%%'. getText substitutes %%1..%%9; anything else "
                "reaches Java's Formatter as a conversion specifier. Write %%%% for a "
                "literal percent." % where)


def duplicate_keys(pairs):
    seen = {}
    for key, value in pairs:
        if key in seen:
            raise ValueError("duplicate key %r" % key)
        seen[key] = value
    return seen


def check(path):
    """Every problem found in one file, as a list of strings."""
    problems = []
    raw = io.open(path, "rb").read()

    if raw.startswith(BOM):
        problems.append(
            "starts with a UTF-8 BOM (ef bb bf). PZ's parser reports "
            "\"A JSONObject text must begin with '{'\" and drops the whole file.")
        return problems      # nothing after this would be news

    if not raw.strip():
        problems.append("is empty")
        return problems

    if raw[:1] != b"{":
        problems.append("does not begin with '{' (first bytes: %s)"
                        % " ".join("%02x" % b for b in raw[:4]))
        return problems

    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError as error:
        problems.append("is not valid UTF-8: %s" % error)
        return problems

    try:
        parsed = json.loads(text, object_pairs_hook=duplicate_keys)
    except ValueError as error:
        problems.append("does not parse: %s" % error)
        return problems

    scan_values(parsed, [], problems)
    return problems


def main(argv):
    roots = argv[1:] or [DEFAULT_ROOT]
    files = []
    for root in roots:
        if os.path.isfile(root):
            files.append(root)
            continue
        for base, _dirs, names in os.walk(root):
            for name in names:
                if name.lower().endswith(".json"):
                    files.append(os.path.join(base, name))
    files.sort()

    total = 0
    for path in files:
        for problem in check(path):
            total += 1
            print("%s\n    %s" % (path, problem))

    if total:
        print("\n%d problem(s). The game reads these at load; a bad one is a crash, "
              "not a warning." % total)
        return 1

    print("%d JSON file(s) checked: all begin with '{', decode as UTF-8, parse, have "
          "unique keys, are not double-encoded, and escape their percent signs."
          % len(files))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
