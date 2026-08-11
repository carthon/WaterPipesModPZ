# Performance harness

There is no Lua interpreter outside the game, so this is the next best thing: a hand
transcription of the mod's hot paths that counts **Lua → Java bridge calls**
(`getGridSquare`, `getObjects`, `getModData`, `getSprite`, `instanceof`, and the
`pcall`-wrapped accessors). Those calls are what costs time in PZ's Kahlua VM; pure
Lua arithmetic is noise next to them.

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
