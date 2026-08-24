#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Check every JSON the mod ships, the way the GAME reads it.

Reads BYTES, and does not decode first. A set of translation files once shipped with a BOM (Python's
`utf-8-sig` PREPENDS one), PZ's org.json refused them with "A JSONObject text must begin with '{'",
and every translated string in the mod vanished on the loading screen. The validator that had passed
them read them back with `utf-8-sig` -- an encoding whose whole purpose is to strip a leading BOM.

  * the first byte must be `{`: no BOM, no leading whitespace
  * the bytes must decode as UTF-8, and the result must parse as JSON
  * keys must be unique: org.json keeps the last of a duplicate pair, a human reads the first
  * no string may be double-encoded, which is valid UTF-8 and valid JSON and still wrong
  * no string may carry a bare `%`, which reaches Java's Formatter as a conversion specifier

    python lint_json.py [path ...]      # default: everything the mod ships

Exits 1 on any finding.
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


# The signature of text that was UTF-8 and got read as Latin-1 somewhere: a lead byte followed by a
# continuation byte, both now standing as separate characters. Real Spanish or Chinese never looks
# like this -- a mojibaked "n-tilde" reads as U+00C3 U+00B1 where it should be a single U+00F1.
MOJIBAKE = re.compile("[" + chr(0x00C2) + "-" + chr(0x00F4) + "][" + chr(0x0080) + "-" + chr(0x00BF) + "]")

# getText substitutes %1..%9. A BARE percent reaches Java's Formatter as a conversion specifier and
# throws at display time; %% is the escape.
# The escaped pairs are REMOVED before this is applied rather than excluded by the pattern: written as
# "%(?![0-9%])" it lets the first % of a pair through and flags the second, which reported all 21
# correctly-escaped strings as broken.
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
