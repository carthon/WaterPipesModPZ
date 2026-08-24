#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Add or update the emitter-diagnosis strings in the three IG_UI.json files.

A file rather than a shell one-liner, deliberately: three encoding accidents came out of doing this
from a heredoc -- writing with `utf-8-sig`, which PREPENDS a BOM and crashed the game on load;
double-encoding the accents through `.decode('unicode_escape')`; and the shell eating the backslashes
out of the regex patterns.

So the strings below are ordinary Python literals. Bytes in, bytes out, one decode and one encode, and
the file's existing line ending is preserved rather than guessed at. Re-running replaces what is there.

    python add_emitter_strings.py

Then check the result with lint_json.py, which reads bytes and catches all three accidents.
"""

import io
import os
import re
import sys

BASE = os.path.join(
    os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
    "Contents", "mods", "WaterPipes", "42.15", "media", "lua", "shared", "Translate")

BOM = b"\xef\xbb\xbf"
ANCHOR = "IGUI_WaterPipesEmitterLow"

# The minimum is deliberately never restated in these. It reads fine for a sprinkler
# and absurd for a drip, whose minimum is 0.0 -- "0.2 short of the 0.0 it needs".
STRINGS = {
    # The water answer. It used to open with "Pressure is fine, but..." -- which is only true when there
    # IS water and the pressure happens to be adequate; with the pipes empty there is no reading at all.
    "IGUI_WaterPipesEmitterDry": {
        "EN": "There is no water in the network for it to draw. "
              "Fill a barrel on the line, or switch on a pump with a source.",
        "ES": "No hay agua en la red de la que beber. "
              "Llena un barril de la línea o enciende una bomba con fuente.",
        "CN": "管网中没有可取用的水。"
              "请为管路上的水桶加水，或启动一台有水源的水泵。",
    },

    # ONE message, and the number in it is how much more head the LINE needs -- not how far this tile is
    # below its own minimum. A sprinkler reading 30 against a minimum of 20 is short of nothing itself; it
    # is off because turning it on would push a DIFFERENT emitter under. Asking the whole set covers both
    # reasons in one figure. "At least", because the search serves a prefix: other starved emitters in
    # between have to clear their own minimums too.
    "IGUI_WaterPipesEmitterShort": {
        "EN": "Cannot water: the line needs at least %1 m more pressure for it. "
              "Add a pump, shorten the run, or move some emitters onto another line.",
        "ES": "No puede regar: la línea necesita al menos %1 m más de presión para él. "
              "Añade una bomba, acorta el recorrido o pasa algunos emisores a otra línea.",
        "CN": "无法灌溉：管路至少还需要 %1 米压力才能带动它。"
              "请加装水泵、缩短管路，或将部分灌溉头移到另一条管路。",
    },
}

# Retired: IGUI_WaterPipesEmitterShared. It existed to explain why a healthy-looking reading still
# would not water, and the number above says it in fewer words.
RETIRED = ("IGUI_WaterPipesEmitterShared",)

KEY_LINE = '^([ \t]*)"%s":.*?(\r?\n)'


def apply_to(path, key, text):
    raw = io.open(path, "rb").read()
    if raw.startswith(BOM):
        return "refusing, file already has a BOM"

    content = raw.decode("utf-8")          # strict: a bad byte raises here
    escaped = text.replace("\\", "\\\\").replace('"', '\\"')

    existing = re.search(KEY_LINE % key, content, re.M)
    if existing:
        line = '%s"%s": "%s",%s' % (existing.group(1), key, escaped, existing.group(2))
        content = content[:existing.start()] + line + content[existing.end():]
        io.open(path, "wb").write(content.encode("utf-8"))
        return "updated"

    anchor = re.search(KEY_LINE % ANCHOR, content, re.M)
    if not anchor:
        return "anchor %s not found" % ANCHOR

    line = '%s"%s": "%s",%s' % (anchor.group(1), key, escaped, anchor.group(2))
    content = content[:anchor.end()] + line + content[anchor.end():]
    io.open(path, "wb").write(content.encode("utf-8"))
    return "added"


def drop(path, key):
    raw = io.open(path, "rb").read()
    content = raw.decode("utf-8")
    match = re.search(KEY_LINE % key, content, re.M)
    if not match:
        return "absent"
    content = content[:match.start()] + content[match.end():]
    io.open(path, "wb").write(content.encode("utf-8"))
    return "removed"


def main():
    failed = False
    for key in RETIRED:
        for lang in ("CN", "EN", "ES"):
            path = os.path.join(BASE, lang, "IG_UI.json")
            print("%-4s %-34s %s" % (lang, key, drop(path, key)))

    for key in sorted(STRINGS):
        for lang in sorted(STRINGS[key]):
            path = os.path.join(BASE, lang, "IG_UI.json")
            result = apply_to(path, key, STRINGS[key][lang])
            print("%-4s %-34s %s" % (lang, key, result))
            if result not in ("added", "updated"):
                failed = True
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
