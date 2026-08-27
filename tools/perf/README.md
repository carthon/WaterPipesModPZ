# Performance harness

There is no Lua interpreter outside the game, so this is the next best thing: a hand
transcription of the mod's hot paths that counts **Lua → Java bridge calls**
(`getGridSquare`, `getObjects`, `getModData`, `getSprite`, `instanceof`, and the
`pcall`-wrapped accessors). Those calls are what costs time in PZ's Kahlua VM; pure
Lua arithmetic is noise next to them.

**Two counters, not one.** `bc()` counts Lua->Java bridge calls; `lua()` counts pure-Lua
node visits. The second exists because the sentence below used to be the whole story and
stopped being true: the hydraulic solver trades world access for a servable-set search and
a relaxation, which cross into Java never and cost real frames anyway. A harness that
counted only bridge calls reported that trade as free, and a regression that made the
field re-solve every frame instead of every in-game minute -- 145x more Lua work -- showed
up as "no change". They are reported separately on purpose: one table read is nowhere near
one JNI call, and adding them would invent an exchange rate nobody measured. Use each to
spot its own shape.

It is deliberately approximate. What it gets right is the shape — how many network
walks each pass makes, how many object scans each walk makes, and how both grow with
the size of the build. **Use the deltas, not the absolute numbers.**

## Use

```sh
python wp_bench.py                  # report
python wp_bench.py --check          # diff vs baseline, exit 1 on regression
python wp_bench.py --save-baseline  # re-record after an intentional change
```

Workflow for an optimisation: `--check` before, make the change in Lua, mirror it in
`wp_model.py`, `--check` again to see the win, then `--save-baseline` to lock it in.

## Files

| file | what |
|---|---|
| `wp_model.py` | the world model, the BFS, and one function per periodic pass |
| `wp_bench.py` | scenarios, report, baseline diff |
| `baseline.json` | recorded counts; committed so regressions are visible in review |
| `release_gate.py` | the pre-release gate: runs the conservation suite against the tree AND against the last release -- see below |
| `lint_forward_refs.py` | finds a `local` used above its declaration -- see below |
| `lint_json.py` | reads every shipped JSON the way the GAME does -- see below |
| `lint_calls.py` | finds calls to a module member that is never defined -- see below |
| `lint_translations.py` | key parity, placeholder drift, and keys the code asks for -- see below |
| `add_emitter_strings.py` | writes the emitter-diagnosis strings, byte-safely |

## Keeping it honest

The model is only worth what its fidelity to the real control flow is worth. When you
change the traversal in `NetworkAccess`, the per-tick passes in `WaterPipeSystem`, or
what a client module scans, **update `wp_model.py` in the same commit**. A stale model
gives confident wrong answers, which is worse than no model.

Known assumptions, all in `wp_model.py`:

- 5 objects per tile (floor, walls, furniture, pipe). At 3 objects costs drop to ~0.66×,
  at 9 they rise to ~1.68×; the growth curve does not change.
- One bridge call ≈ 0.05–0.3 µs. Only used to print milliseconds; nothing else depends on it.
- Every scenario is one connected network on one floor, with no risers.

To calibrate for real: wrap `onEveryOneMinute` (`WaterPipeSystem.lua`) in
`getTimestampMs()` and log the delta in a save with a known pipe count. Two measurements
at two sizes fix the constant and confirm the exponent.

## The harness has its own tests, and it needs them

`python test_model.py`

This model is a simulator whose numbers get used to justify changes to the mod, and
for a long time nothing checked it. It produced confident fiction twice.

**It counted only bridge calls.** The premise -- that pure-Lua work is noise beside
them -- held while every hot path was a world traversal, and stopped holding the day
the hydraulic solver landed. The harness reported a 145x regression as free.

**Caches leaked between scenarios.** Once the mod's caches correctly began to outlive
a frame, they also survived the scenario rebuild `run_suite` performs between the
server and client pass groups. The second scenario inherited the first one's answers.
`client/sprayfx` reported 512 where the truth was 31,478 -- and that 60x
understatement was read, and reported, as a 98% improvement.

**And then they leaked between PASSES, which is the same bug one notch finer.** Fixing
the scenario rebuild left `measure()` clearing only the frame -- so `10min/scan`,
measured straight after `1min/routers`, was charged a warm scan memo and recorded 260
where the truth is 19,000. Every row of the baseline was a worst case for the first
pass of its group and fiction for every pass after it. `measure()` now calls `cold()`,
which empties every world-derived cache by name, and `test_model.py` asserts that a
pass costs the same whatever ran before it -- in both directions, because a leak that
happened to be order-independent would have slipped past a forward-only check. The
residue that found the last of it was three bridge calls: the mains liveness probe,
small enough to read as rounding.

The baselines recorded before that fix are not comparable with the ones after. The
jump is the harness telling the truth, not the mod getting slower.

Neither was subtle. Both are caught in under a second by asserting things that must
hold of any cost model at all:

* a measurement must not depend on what was measured before it
* a cache may change what something COSTS, never what it ANSWERS
* warm is never dearer than cold
* the two counters measure different things and must not bleed into one another
* a pass that reads the world must not rewrite it

Those are `test_model.py`. Run it before trusting a number out of `wp_bench.py`, and
when the model changes, check the new invariant FAILS with the change reverted --
a test that cannot fail is how this went unnoticed in the first place.

## What the per-pass rows mean now

Each row is a COLD pass: `measure()` empties every world-derived cache first. That was
the typical case while every cache was frame-scoped. It no longer is -- the head field,
the vessel classification, the pipe-object scan and the fill topology all live until an
event drops them -- so a cold row is now the WORST case, not the usual one.

Two rows model steady play instead, and they are the ones to read for "what does this
cost while playing":

| row | what it models |
|---|---|
| `client/15s steady` | fifteen real seconds of spray FX, wetness, sound and registry sweeps |
| `server/5min steady` | five consecutive in-game minutes of the four EveryOneMinute handlers |

`server/5min steady` exists because a bench made only of cold single passes is
structurally blind to what a cache lifetime buys. The whole benefit of giving the fill
topology an event lifetime is that minute two does not re-walk what minute one walked,
and no per-pass row can show that -- each of them is minute one by construction. Only a
run of minutes can, with `frame_reset()` between them and nothing else, because that is
exactly the OnTick boundary and what survives it is what the mod says survives it.

## What it was blind to, and now charges for

`bc()` counts what crosses into Java. A model that reaches through the fence for free is not counting
the same thing the game is, and twice that gap hid a real cost:

* **Coordinates off a registry entry.** `Registry.near` knew each tile's x/y/z -- it stored them --
  but returned only the square, so the Lua asked the engine for them again: nine bridge calls per
  emitter per rebuild, plus two string builds. This model read `sq.x` as a Python attribute and
  charged nothing, so no amount of running it could ever have found 66 000 bridge calls a minute.
  The entry now carries the coordinates in both the mod and the model.
* **The clock.** A cached status read is a table lookup and a subtraction, and it spent a `pcall` and
  a bridge call per emitter asking what time it was -- the same answer for every emitter in the same
  rebuild. The model called a cache hit "free". It now charges one stamp per pass, which is what the
  code does.

The lesson is not "add more counters". It is that anything the model reaches for **directly** instead
of **through the same call the mod makes** is invisible to it by construction.

## The forward-reference linter

```sh
python lint_forward_refs.py
```

Nothing to do with performance; it lives here because this is where the tooling is. It finds
references to a Lua `local` that appear above its declaration -- which is valid Lua, compiles to a
**global** read that is nil at run time, and is invisible to `luac -p`. This repo has shipped that bug
three times, most recently as a public function with no caller in any test: green suite, nil global,
found in a player's game log. Exits 1 on a finding, so it can gate a commit.

## The JSON linter

```sh
python lint_json.py
```

Also nothing to do with performance, and here for the same reason: this is the tracked tools
directory. It checks every JSON the mod ships -- first byte is `{`, decodes as UTF-8, parses, unique
keys -- and it reads BYTES rather than decoding first.

That last part is the whole point. An edit to three translation files crashed the game on load,
because they had been written with Python's `utf-8-sig`, which PREPENDS a byte-order mark; PZ's
org.json sees three bytes before the `{` and reports *"A JSONObject text must begin with '{'"*,
dropping every translated string in the mod. The edit **was** validated -- with a script that read the
files back using `utf-8-sig`, an encoding whose entire purpose is to strip a leading BOM. The check
undid the damage on the way in and reported success.

A validator that decodes before it looks cannot see an encoding bug. Exits 1 on a finding.

## The call linter

```sh
python lint_calls.py
```

Three linters now, because this codebase has shipped a call to something that was not there in three
distinct ways: a forward reference to a local, a `next()` that PZ does not expose, and
`Hydraulics.nodeKeyOf` called from NetworkAccess and then deleted from Hydraulics by an edit that
replaced the block it happened to sit in. That last one threw *"Object tried to call nil in
getPressureReport"* the next time anybody right-clicked a pipe.

All three are valid Lua, so `luac -p` accepts them. A test catches them only if something CALLS the
function, and in every case nothing in the suite did -- the suite was green while the game was broken.
So this reads the module surface instead: every `Module.member(...)` call is checked against every
member defined on that module anywhere in the tree.

Verified by deleting `nodeKeyOf` again: `luac -p` accepted the file, all nine suites stayed green, and
this reported it in one line.

## The translation validator

```sh
python lint_translations.py
```

`lint_json.py` checks that each file is readable the way the game reads it. This checks that the
CONTENT is coherent, which is a different set of failures and all of them silent:

* a key the Lua asks for that nobody defines -- `getText` returns the key itself, so the player reads
  `IGUI_WaterPipesEmitterShort` in a tooltip
* a key EN defines that a translation is missing, or defines that EN does not -- usually a rename
  applied to one file
* **placeholder drift**: EN says `%1 %2`, a translation says only `%1`. The second value is dropped
  and nothing complains
* an empty string, which renders as a blank line

It reads the base game's own Translate directory too, because a mod legitimately borrows vanilla
keys -- this one reads `ContextMenu_PlumbItem` to find the engine's "Plumb %1" option by its
localized prefix. Without that the borrowed key was reported as missing, which is how a linter
teaches people to ignore its output. Those files are read with a regex rather than a JSON parser:
PZ's own translations contain trailing commas, which org.json accepts and `json.loads` does not, and
the game's files are not this mod's to validate.

Verified against a toy tree carrying one of each fault: all three problems reported, the two parity
differences reported as notes rather than failures, since a partial translation is a normal state.

## And it still cannot tell you milliseconds

It counts calls, and treats them all alike. An `instanceof` and a `getObjects` are one
each here and are not one each in the JVM. Twice this model has ranked candidates in an
order the in-game profiler then contradicted. Use it for SHAPE -- work that scales with
the network, work landing per frame that belongs per minute -- and use the profiler
(pipe Debug menu) for what anything actually costs.


## The release gate

```sh
python release_gate.py                # gate the working tree against the last release
python release_gate.py --baseline REV # against some other point
```

A green suite is not evidence. `test_fill_path` carried an assertion **naming** the router
levelling bug and passed through the entire release that shipped it: its world had water on
only one side of the valve, so the pressure gate produced the same `0` the topology should
have. Two mechanisms, one number.

So the gate runs every conservation test twice -- against the working tree, where all must
pass, and against the Lua modules as they stood at the previous `chore: bump modversion`,
where the ones covering this cycle's fixes must **fail**. It sorts them into:

- **proves a fix** -- fails on the old build. The test would have caught the bug.
- **carried forward** -- passes on both. Real coverage, but it earned no trust this cycle.

If a release claims to fix something and nothing fails against the last one, the fix has no
test behind it. That is the signal the gate exists to produce.

It needs `lua` on PATH and `tools/conservation/`, which this `.gitignore` excludes -- so a
fresh clone cannot run the gate until that directory is restored.
