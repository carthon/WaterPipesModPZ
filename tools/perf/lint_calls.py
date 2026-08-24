#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Find calls to a WaterPipes module member that is never defined.

Third linter, third distinct way this codebase has shipped a call to something
that was not there:

  1. `verifySquareVessels` referenced a local declared further down the file, so
     the name bound to a nil GLOBAL. That is lint_forward_refs.py.

  2. `next()` was used three times, and PZ's Kahlua does not expose it.

  3. `Hydraulics.nodeKeyOf` was called from NetworkAccess and then deleted from
     Hydraulics by an edit that replaced the block it happened to sit in. The
     call site was fine, the definition was gone, and the game threw "Object
     tried to call nil in getPressureReport" the next time somebody right-clicked
     a pipe.

All three share one property: `luac -p` accepts them, because they are valid Lua.
A test catches them only if something CALLS the function, and in every one of
these cases nothing in the suite did.

So this reads the module surface directly. For every file it works out which
locals are aliases of a WaterPipes module (`local Hydraulics = WaterPipes.Hydraulics`),
collects every member defined on any module anywhere in the tree, and reports any
`Module.member(...)` call whose member is never defined.

    python lint_calls.py [path ...]      # default: the mod's lua tree

Exits 1 on a finding.

Known limits, stated rather than hidden: it only understands the alias form this
codebase actually uses, it cannot see members assigned dynamically, and it only
looks at CALLS -- `Module.member` read as a value is left alone, because that is
how the code probes for optional functions (`if Module.member then`). Those probes
are the reason a missing member can stay quiet, and also the reason flagging them
would be wrong.
"""

import io
import os
import re
import sys

DEFAULT_ROOT = os.path.join(
    os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
    "Contents", "mods", "WaterPipes")

NAME = r"[A-Za-z_]\w*"

ALIAS = re.compile(r"^\s*local\s+(" + NAME + r")\s*=\s*WaterPipes\.(" + NAME + r")\s*$")
DEF_QUALIFIED = re.compile(r"^\s*function\s+WaterPipes\.(" + NAME + r")\.(" + NAME + r")\s*\(")
DEF_ALIASED = re.compile(r"^\s*function\s+(" + NAME + r")\.(" + NAME + r")\s*\(")
# ANY assignment counts as a definition, not just `= function`. This codebase writes
# `GeneratorFuel.isGenerator = isGenerator` -- promoting a local -- and
# `ContextMenu.originalOnPlumbItem = ... or ISWorldObjectContextMenu.onPlumbItem`, and
# insisting on the `function` keyword reported eight healthy call sites. A linter that
# has to be argued with about correct code does not get run.
ASSIGN_QUALIFIED = re.compile(r"^\s*WaterPipes\.(" + NAME + r")\.(" + NAME + r")\s*=(?!=)")
ASSIGN_ALIASED = re.compile(r"^\s*(" + NAME + r")\.(" + NAME + r")\s*=(?!=)")
# A call, not a read: the trailing paren is what makes a missing member fatal.
CALL = re.compile(r"(?<![\w.:])(" + NAME + r")\.(" + NAME + r")\s*\(")


def strip_noise(line):
    line = re.sub(r"--.*$", "", line)
    line = re.sub(r'"[^"]*"', '""', line)
    line = re.sub(r"'[^']*'", "''", line)
    return line


def read(path):
    text = io.open(path, encoding="utf-8", errors="replace").read()
    return [strip_noise(line) for line in text.split("\n")]


def aliases_in(lines):
    """local Foo = WaterPipes.Foo  ->  {"Foo": "Foo"}"""
    found = {}
    for line in lines:
        match = ALIAS.match(line)
        if match:
            found[match.group(1)] = match.group(2)
    return found


def collect(files):
    """Every member defined on every module, as {module: set(member)}."""
    defined = {}

    def note(module, member):
        defined.setdefault(module, set()).add(member)

    for path in files:
        lines = read(path)
        alias = aliases_in(lines)
        # A module's own file names itself the same way it names its dependencies.
        for line in lines:
            for pattern in (DEF_QUALIFIED, ASSIGN_QUALIFIED):
                match = pattern.match(line)
                if match:
                    note(match.group(1), match.group(2))
            for pattern in (DEF_ALIASED, ASSIGN_ALIASED):
                match = pattern.match(line)
                if match and match.group(1) in alias:
                    note(alias[match.group(1)], match.group(2))
    return defined


def main(argv):
    roots = argv[1:] or [DEFAULT_ROOT]
    files = []
    for root in roots:
        if os.path.isfile(root):
            files.append(root)
            continue
        for base, _dirs, names in os.walk(root):
            for name in names:
                if name.endswith(".lua"):
                    files.append(os.path.join(base, name))
    files.sort()

    defined = collect(files)

    total = 0
    for path in files:
        lines = read(path)
        alias = aliases_in(lines)
        if not alias:
            continue
        for index, line in enumerate(lines):
            for match in CALL.finditer(line):
                local, member = match.group(1), match.group(2)
                module = alias.get(local)
                if module is None or module not in defined:
                    continue
                if member in defined[module]:
                    continue
                total += 1
                print("%s:%d" % (path, index + 1))
                print("    calls %s.%s, which is not defined on WaterPipes.%s anywhere"
                      % (local, member, module))
                print("    %s" % line.strip()[:88])

    if total:
        print("\n%d call(s) to a member that does not exist. Valid Lua, and nil at run time."
              % total)
        return 1

    print("%d file(s) scanned: every WaterPipes module call has a definition behind it."
          % len(files))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
