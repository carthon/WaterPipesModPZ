# Water Pipes

Experimental mod for Project Zomboid Build 42.15.x that adds buildable water networks.

## Goal

Project Zomboid has no real way to move or distribute water. This mod lets you lay pipes in the
world and link placeable fluid containers and fixtures so they share a single network. The
current version focuses on a solid, stable base before tackling pumps, valves, pressure or
filtering.

## Current features

- Valid Build 42.15 structure (`mod.info`, `tiledef=waterpipes 1000`, `pack=waterpipes`).
- Buildable pipe from the vanilla build menu, category `Piping`.
- **Auto-connecting floor pipes**: straights, corners, T-junctions, crosses and end caps are
  chosen automatically from neighbouring pipes.
- **Wall risers** (vertical covers on North/West walls) that connect floor pipes on both sides
  of the wall and link different floors.
- Own tileset (`waterpipes_01_*`), produced by a procedural sprite generator.
- Generic detection of world fluid containers with a finite `FluidContainer` (rain collectors,
  barrels, vessels, etc.).
- Single-fluid redistribution per network; networks mixing different fluids are skipped for safety.
- **Plumbing without a phantom object**: a plumbed fixture (sink, shower, toilet…) gets its own
  `FluidContainer` mirroring the network, so vanilla Drink / Fill / Wash work directly from it.
- The tap **purifies** like vanilla: rain (tainted) water is stored tainted but served clean.
- "Transfer Fluids" is reconciled back to the network (no free water / no loss).
- You can plumb an **empty** network; water starts flowing once a source is connected.
- **Generators**: connect a generator to a network carrying gasoline (`Petrol`) and it refuels
  itself from the network automatically when its tank runs low.
- **Dismantle returns the item**: picking a pipe back up gives you the `Pipe` item again.
- **Vertical separation**: two stacked networks only merge through a vertical pipe (wall cover);
  otherwise they stay independent.
- Debug menu (force global water shutoff, force network tick, diagnostics) when the game runs in
  debug mode.

## How to use

A quick 1‑2‑3 once the mod is enabled:

1. **Lay pipes.** Open the build menu → category `Piping` → `Water Pipe`. You need a `Pipe` and a
   `Pipe Wrench` (the wrench is kept, not consumed). Place pipes on the floor — they auto-connect
   into straights, corners, T-junctions and crosses. While placing, rotate to switch between the
   floor pipe and **wall risers** (North / West) to run pipes up a wall and link different floors.
2. **Add a water source.** Place a rain collector, barrel or vessel next to a pipe on the same
   floor. Its contents are now shared across the whole connected network.
3. **Connect a sink / shower / toilet.** Make sure a pipe sits on the fixture's own tile, then
   right‑click it → **“Plumb <name>”** (with a Pipe Wrench in your inventory). Vanilla
   Drink / Wash / Fill now draw straight from the network, and rain (tainted) water comes out
   **clean**. Right‑click → **“Unplumb <name>”** to disconnect; the fixture returns to its
   original state.
4. **Feed a generator.** Put a pipe on the generator's tile and right‑click → **“Plumb
   Generator”**. If the network carries gasoline (`Petrol`) — e.g. an amphora or barrel of Petrol
   connected to it — the generator tops up its tank automatically when it drops low.
5. **Remove / recover.** Pick a pipe back up (Pipe Wrench) to get the `Pipe` item back. Removing
   the pipe on a fixture/generator's own tile disconnects it instantly; breaking the chain
   somewhere else just stops the flow until you restore it, then it reconnects on its own.

> **One fluid per network.** A network carries a single fluid at a time — water **or** petrol,
> never mixed. A sink needs a water network; a generator needs a Petrol network.

## Current limitations

- Consumption is integrated for water fixtures (sinks/showers/toilets) and generators (`Petrol`).
  Other fluids still redistribute between containers, but have no dedicated consumer yet.
- No pressure, loss, priority, pumps or filtering yet.
- Not fully validated in multiplayer.

## Structure

- `Contents/mods/WaterPipes/42.15`: code and metadata for Build 42.15.x.
- `docs/architecture.md`: technical overview of the system.
- `docs/texturepack.md`: tileset and packaging notes (sprite generator + `.tiles` editor).
- `tools/texturepack`: procedural sprite generator (`gen_pipes.py`) and a binary `.tiles` editor
  (`edit_tiles.py`).

## Local install

Project Zomboid must read this folder:

```text
Contents/mods/WaterPipes
```

For local testing, link it into:

```text
C:\Users\<your_user>\Zomboid\mods\WaterPipes
```

The most convenient option is a Windows junction/symlink pointing at
`<workspace>\Contents\mods\WaterPipes`.

## Building

Use the vanilla build panel:

- Category: `Piping`
- Recipe: `Water Pipe`
- Requirements: `Base.Pipe` and `Base.PipeWrench` (kept, not consumed)

While placing, rotation cycles through:

- Floor pipe (orientation resolves automatically once connected)
- Wall riser — North wall
- Wall riser — West wall

## Plumbing and consumption

- `Plumb` a sink/shower/toilet (or equivalent) that has a mod pipe on its tile to join it to the
  network. No water source is required to plumb — water flows once a container is connected.
- Vanilla Drink / Fill / Wash are served from the fixture's own `FluidContainer`.
- Tainted (rain) water comes out of the tap as clean water, matching vanilla plumbing.
- Use `Unplumb` to disconnect a fixture from the network.

## Quick test flow

1. Place pipes from `Piping -> Water Pipe`.
2. Place water containers (e.g. rain collectors) adjacent to the pipes on the same floor.
3. Plumb a sink or equivalent that sits on a pipe tile.
4. Drink / fill / wash from it; the source level should drop.
5. To test without map water, use the mod's debug menu to force the global water shutoff.

## Roadmap

### Sprites / art

The current pipe and riser sprites are **procedurally generated placeholders**. The plan is to
replace them with proper, hand-finished art that matches Project Zomboid's style:

- Higher-quality metal pipe sprites and cleaner isometric shading.
- More connection variants and better-looking wall risers (improved depth/sorting).
- Distinct pipe materials/states (e.g. galvanised metal vs PVC, rust/wear).

### Beyond art

- Pumps, valves, pressure and filtering.
- Broader multiplayer validation.

### Contributing

This mod is experimental and actively evolving. If you'd like to help — **especially with
sprite/tile art** — please get in touch with the author through the Steam Workshop page
(comments or Discussions). Feedback and bug reports are very welcome too.
