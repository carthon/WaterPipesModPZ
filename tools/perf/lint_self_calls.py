#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Find a local function that returns a call to ITSELF with its own arguments unchanged.

A linter for one bug, which froze the game and wrote nothing to any log.

Pump.lua grew a wrapper meant to route a call through the profiler when one is loaded:

    local function timed(name, fn, ...)
        local Profiler = WaterPipes.Profiler
        if Profiler and Profiler.time then
            return timed(name, fn, ...)          -- meant to be Profiler.time(...)
        end
        return fn(...)
    end

`fn` is never called. Worse, `return timed(...)` is a TAIL call, so Lua reuses the frame and the
stack never grows: there is no stack overflow, no error, no log line. The pass simply never returns
and the frame never ends. It reached a player as "the game froze when I walked to the farm", and the
only evidence was a console log that stopped mid-sentence.

Legitimate self-recursion exists, so the test is narrow: the recursive call is flagged only when its
argument list is TEXTUALLY IDENTICAL to the function's own parameter list. Recursion that terminates
has to change something on the way down; recursion that hands its parameters straight back cannot.

    python lint_self_calls.py [path ...]      # default: the mod's lua tree

Limits: comments and strings are stripped with regexes rather than parsed, and arguments are compared
as normalised text, so a call that rebuilds the same values under different names is not caught.

The body is delimited by counting block keywords to the function's own `end`. Reading it as "up to the
next definition" instead is what the first version did, and it swallowed the NEXT function whole -- so
every `local function helper(x)` called by the ordinary function below it was reported as recursive.
Four healthy places, all of the same shape.
"""

import io
import os
import re
import sys

DEFAULT_ROOT = os.path.join(
    os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
    "Contents", "mods", "WaterPipes")


def strip_noise(text):
    """Comments and string literals cannot contain a call we care about."""
    text = re.sub(r"--\[\[.*?\]\]", "", text, flags=re.S)
    text = re.sub(r"--[^\n]*", "", text)
    text = re.sub(r'"[^"\n]*"', '""', text)
    text = re.sub(r"'[^'\n]*'", "''", text)
    return text


def normalise(args):
    return re.sub(r"\s+", "", args)


DEF = re.compile(r"local function (\w+)\s*\(([^)]*)\)")

# `for` and `while` are NOT openers: each is always followed by the `do` that is counted instead.
# `elseif`/`else` continue a block rather than opening one. `repeat`/`until` close without an `end`.
OPENERS = ("function", "if", "do")
KEYWORD = re.compile(r"\b(function|if|do|end)\b")


def body_of(text, start):
    """The function body, from just after its parameter list to its matching `end`."""
    depth = 1
    for token in KEYWORD.finditer(text, start):
        if token.group(1) == "end":
            depth -= 1
            if depth == 0:
                return text[start:token.start()]
        elif token.group(1) in OPENERS:
            depth += 1
    return text[start:]


def scan(path):
    text = strip_noise(io.open(path, encoding="utf-8", errors="replace").read())
    findings = []

    for match in DEF.finditer(text):
        name, params = match.group(1), match.group(2)
        if not params.strip():
            continue          # a no-argument helper cannot pass its arguments back

        body = body_of(text, match.end())

        for call in re.finditer(r"return\s+" + re.escape(name) + r"\s*\(([^)]*)\)", body):
            if normalise(call.group(1)) != normalise(params):
                continue      # something changed on the way down, so it can terminate
            line = text[:match.end() + call.start()].count("\n") + 1
            findings.append((line, name, call.group(0).strip()))

    return findings


def main(argv):
    roots = argv[1:] or [DEFAULT_ROOT]
    files = []
    for root in roots:
        if os.path.isfile(root):
            files.append(root)
            continue
        for base, _, names in os.walk(root):
            for name in names:
                if name.endswith(".lua"):
                    files.append(os.path.join(base, name))
    files.sort()

    total = 0
    for path in files:
        for line, name, source in scan(path):
            total += 1
            print("%s:%d" % (path, line))
            print("    %s" % source)
            print("    -> '%s' returns itself with its own arguments unchanged." % name)
            print("    -> a tail call, so this spins forever without growing the stack:")
            print("       no error, no log line, and the frame never ends.")

    if total:
        print("\n%d non-terminating self-call(s). Did you mean to call something else?" % total)
        return 1

    print("%d files scanned: no local function returns itself unchanged." % len(files))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
