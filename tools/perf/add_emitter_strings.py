#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Add or update the emitter-diagnosis strings in the three IG_UI.json files.

Kept as a file rather than run as a shell one-liner, and that is the whole point.
Three encoding accidents in a row came out of doing this from a heredoc:

  1. writing with Python's `utf-8-sig`, which PREPENDS a BOM -- PZ's parser then
     reports "A JSONObject text must begin with '{'" and drops every translated
     string in the mod. That one crashed the game on load.

  2. building the accented text with `.encode('utf-8').decode('unicode_escape')`,
     which double-encoded it: the file ended up holding the two UTF-8 bytes of
     each accented character as two separate characters. Still valid UTF-8, still
     valid JSON, still wrong.

  3. the shell eating the backslash escapes out of the regex patterns, twice.

So: the strings below are ordinary Python literals in a real source file. Bytes
in, bytes out, one decode and one encode, and the file's existing line ending is
preserved rather than guessed at. Re-running replaces what is there, so fixing
the wording is the same one command as adding it.

    python add_emitter_strings.py

Then check the result with lint_json.py, which reads bytes and will catch all
three of the accidents above.
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
    # The water answer. It used to open with "Pressure is fine, but..." -- which is only true when
    # there IS water and the pressure happens to be adequate. With the pipes empty there is no supply
    # for the field to propagate from, so there is no pressure reading at all, and claiming one is
    # fine was the same kind of confident wrong sentence this whole readout has been shedding.
    "IGUI_WaterPipesEmitterDry": {
        "EN": "There is no water in the network for it to draw. "
              "Fill a barrel on the line, or switch on a pump with a source.",
        "ES": "No hay agua en la red de la que beber. "
              "Llena un barril de la línea o enciende una bomba con fuente.",
        "CN": "管网中没有可取用的水。"
              "请为管路上的水桶加水，或启动一台有水源的水泵。",
    },

    # ONE message, and the number in it is how much more head the LINE needs -- not how far this tile
    # is below its own minimum.
    #
    # That distinction is the whole point. A sprinkler reading 30 m against a minimum of 20 is short of
    # nothing itself; it is switched off because turning it on would push a DIFFERENT emitter under.
    # Asking the tile returned zero, so the readout could only say "the line cannot supply this
    # emitter" -- true, and not the number anybody wanted. Asking the whole set gives a figure that
    # covers both reasons an emitter is off, so there is one sentence instead of three.
    #
    # "At least", because the search serves a prefix: other starved emitters between this one and the
    # ones already running have to clear their own minimums too.
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
