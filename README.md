# Water Pipes

A Project Zomboid (Build 42) mod that adds buildable water pipes: lay a network through your base
and link sinks, barrels, rain collectors and generators so they share a single supply.
Multiplayer-ready and bilingual (EN/ES).

## Installation

Subscribe on the Steam Workshop, or for local use point Project Zomboid at the mod folder:

```text
Contents/mods/WaterPipes
```

For local testing, link `Contents/mods/WaterPipes` (a Windows junction/symlink is easiest) into:

```text
C:\Users\<your_user>\Zomboid\mods\WaterPipes
```

## Usage

You need a **Pipe Wrench** (kept, not consumed) and a **Metal Pipe** for each pipe placed. Metal
pipes can be scavenged or **forged** at a blacksmith forge from bar stock, so the network stays
renewable even in a low-loot game.

1. **Lay pipes.** Build menu → category **Piping** → **Water Pipe**. Floor pipes auto-connect into
   straights, corners, T-junctions and crosses. While placing, rotate to switch to the **vertical
   pipe** (North / West wall) to run pipes up a wall and link different floors.
2. **Add a source.** Put a pipe on the same tile as a barrel or rain collector to add it to the
   network; its contents are shared across the whole network.
3. **Plumb a sink.** With a pipe on the fixture's own tile, right-click it → **Plumb** (wrench in
   inventory). Vanilla Drink / Wash / Fill now draw from the network, and tainted rain water comes
   out clean. Use **Unplumb** to disconnect and restore its original state.
4. **Fuel a generator.** With a pipe on the generator's tile, right-click → **Connect**. If the
   network carries gasoline (Petrol), the generator refuels itself when its tank runs low.
5. **Inspect the network.** Right-click any pipe → **Show pipe network** to highlight it: pipes in
   red, fluid sources in green, consumers (sinks/generators) in blue.
6. **Remove.** Right-click a pipe → **Disassemble** (hammer) to take it down; you get the **Metal
   Pipe** back ~90% of the time.

**One fluid per network** — water *or* petrol, never mixed. A sink needs a water network; a
generator needs a Petrol network.

## Credits

- **Tileset and sprite art** — [aariak_einherjer](https://steamcommunity.com/id/aariak_einherjer/)
  ([ArtStation](https://www.artstation.com/adrianechanizrol))
- **Simplified Chinese translation** — rakkasumi
- Everything else by Carthon.

Still open to more hands: art, translations into a language that is not covered yet, or ideas worth
trying. Open an issue or say hello on the Workshop page.

## Licence

Copyright (c) 2026 Carthon. All rights reserved — see [LICENSE](LICENSE).

Short version: play with it, host it, read the source and learn from it. Do **not** re-upload it or
publish a modified version without asking first, and credit *Water Pipes by Carthon* wherever you
reuse any of it. Asking usually gets a yes.

Note that some sprites are cropped from Project Zomboid's own tilesheets and remain The Indie Stone's
property — they are not mine to sublicense. Project Zomboid is © The Indie Stone; this mod is
unofficial and not endorsed by them.
