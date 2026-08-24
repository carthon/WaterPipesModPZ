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

Each row is a COLD pass: `measure()` starts from an empty frame. That was the typical
case while every cache was frame-scoped. It no longer is -- the head field, the vessel
classification and the pipe-object scan all live until an event drops them -- so a
cold row is now the WORST case, not the usual one. `client/15s steady` is the row that
models steady play, and it is the one to read for "what does this cost while playing".

## And it still cannot tell you milliseconds

It counts calls, and treats them all alike. An `instanceof` and a `getObjects` are one
each here and are not one each in the JVM. Twice this model has ranked candidates in an
order the in-game profiler then contradicted. Use it for SHAPE -- work that scales with
the network, work landing per frame that belongs per minute -- and use the profiler
(pipe Debug menu) for what anything actually costs.
