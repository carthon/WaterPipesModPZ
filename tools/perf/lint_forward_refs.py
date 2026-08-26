#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Find references to a Lua `local` that appear ABOVE its declaration.

A linter for one bug, which has shipped from this repo three times. In Lua a name used before its
`local` is neither an error nor an upvalue: it compiles to a GLOBAL access, nil at run time. It loads
cleanly, passes `luac -p`, and passes every test that does not CALL the function.

A READ of a nil global tends to blow up. A WRITE is quieter -- the local simply never changes and the
feature it controls stops working -- and an assignment carries no `(`, `.` or `[`, which is all the
first version of this file looked for. It looks for any use now.

    python lint_forward_refs.py [path ...]      # default: the mod's lua tree

Limits: comments and strings are stripped with regexes rather than parsed, and there is no notion of
scope, so a name is reported only when NO `local` for it appears anywhere above the use.
"""

import io
import os
import re
import sys

DEFAULT_ROOT = os.path.join(
    os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
    "Contents", "mods", "WaterPipes")

NAME = r"[A-Za-z_]\w*"


def strip_noise(line):
    """Comments and string literals cannot contain a reference we care about."""
    line = re.sub(r"--.*$", "", line)
    line = re.sub(r'"[^"]*"', '""', line)
    line = re.sub(r"'[^']*'", "''", line)
    return line


def without_table_keys(lines):
    """Blank out `name =` where `name` is a table-constructor KEY, not a variable.

    `{ parent = parent, ceiling = ceiling }` mentions each name twice and only the
    second is a use; `capacity = Constants.PURIFIER_BUFFER_CAPACITY,` on its own
    line inside a constructor is a key too. Reading those as uses reported ten
    healthy places.

    Telling a key from a real assignment needs to know whether the line sits inside
    an open brace, so the depth is tracked across the file. At depth zero only a key
    that follows `{` or `,` on the same line counts, which leaves a genuine
    top-level `stamp = nil` alone -- and that assignment shape is the whole reason
    this linter looks at assignments at all.
    """
    out = []
    depth = 0
    for line in lines:
        # A declaration's NAME LIST is not a table constructor, and stripping inside it destroyed the very
        # thing the scan reads: `local okType, fullType = ...` became `local okType, = ...`. Only the
        # right-hand side of a `local` can hold a constructor, so only that side is cleaned.
        prefix = ""
        if re.match(r"\s*local\s", line) and "=" in line:
            cut = line.index("=") + 1
            prefix, line = line[:cut], line[cut:]

        if depth > 0:
            cleaned = re.sub(r"(^|[{,])(\s*)" + NAME + r"(\s*=(?!=))", r"\1\2\3", line)
        else:
            cleaned = re.sub(r"([{,])(\s*)" + NAME + r"(\s*=(?!=))", r"\1\2\3", line)
        out.append(prefix + cleaned)
        depth += (prefix + line).count("{") - (prefix + line).count("}")
        if depth < 0:
            depth = 0
    return out


def scan(path):
    text = io.open(path, encoding="utf-8", errors="replace").read()
    code = without_table_keys(
        [strip_noise(line) for line in text.split(chr(10))])

    declared_at = {}
    bound_elsewhere = set()      # parameters and loop variables: not the same name

    def note_locals(names, index):
        # `local a, b = f()` declares BOTH of them, on that line.
        for raw in names.split(","):
            candidate = raw.strip()
            if re.match(r"^" + NAME + r"$", candidate):
                declared_at.setdefault(candidate, index)

    for index, line in enumerate(code):
        match = re.match(r"\s*local\s+function\s+(" + NAME + r")\s*\(([^)]*)\)", line)
        if match:
            declared_at.setdefault(match.group(1), index)
            bound_elsewhere.update(p.strip() for p in match.group(2).split(",") if p.strip())
            continue

        if "function" in line:
            params = re.search(r"\(([^)]*)\)", line)
            if params:
                bound_elsewhere.update(
                    p.strip() for p in params.group(1).split(",") if p.strip())

        match = re.match(r"\s*local\s+(" + NAME + r"[\w,\s]*?)\s*(?:=|$)", line)
        if match:
            note_locals(match.group(1), index)

        for names in re.findall(r"\bfor\s+([\w,\s]+?)\s+(?:in|=)", line):
            bound_elsewhere.update(n.strip() for n in names.split(","))

    findings = []
    for name, declaration in declared_at.items():
        if name in bound_elsewhere or len(name) < 3:
            continue
        # Any use at all: a call, a field read, an index, an assignment, or a bare mention. All of them bind,
        # and the assignment is the one that fails silently.
        used = re.compile(r"(?<![\w.:])" + re.escape(name) + r"(?![\w])")
        for index in range(declaration):
            if used.search(code[index]):
                findings.append((index + 1, declaration + 1, name, code[index].strip()[:88]))
                break

    return findings


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

    total = 0
    for path in files:
        for line, declaration, name, source in scan(path):
            total += 1
            print("%s:%d" % (path, line))
            print("    uses '%s', which is declared local at line %d" % (name, declaration))
            print("    %s" % source)
            print("    -> this binds to a nil GLOBAL, not to that local.")

    if total:
        print("\n%d forward reference(s) to a local. Move the declaration above the use."
              % total)
        return 1

    print("%d files scanned: no local is referenced above its declaration." % len(files))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
