# Water Pipes pipes and components reference

This catalogue lists every pipe and every [component](glossary.md#component) (anything the mod builds other than pipes) available under the **Building** menu, **Piping** category in Water Pipes v0.10.x. A usable Pipe Wrench is kept by every recipe that names it.

## Pipes

| Build entry | Spanish name | Materials and skills | Placement and purpose |
|---|---|---|---|
| **Fluid Pipe** | Tubería de fluidos | 1 Iron Pipe or fired Clay Pipe Segment; no skill | Floor pipe; automatically forms ends, straights, corners, T-junctions, and crosses |
| **Vertical Fluid Pipe** | Tubería vertical de fluidos | 1 Iron Pipe or fired Clay Pipe Segment; no skill | North or west wall; connects floor pipes between levels |
| **Concealed Fluid Pipe** | Tubería de fluidos oculta | 1 pipe and 1 full supported bucket of prepared clay cement or concrete; no skill | Hidden floor pipe; reveal it with **Show pipe network** |
| **Concealed Vertical Fluid Pipe** | Tubería vertical de fluidos oculta | Same as concealed floor pipe; no skill | Hidden north/west riser between levels |

Each concealed pipe consumes one complete prepared bucket; see [Pipe networks](pipe-networks.md#pipe-recipes) for the accepted variants. Metal hand-built pipes have a 90% recovery chance; clay pipes and concealed plumbing revealed by a building inspection return no pipe.

<!-- SCREENSHOT: 03-pipe-shapes.png — Fluid Pipe shapes plus a visible and concealed example. -->
<!-- SCREENSHOT: 04-vertical-pipe-floors.png — Vertical Fluid Pipe joining two levels. -->

## Supply and pressure

### Water Pump — Bomba de agua

- **Purpose:** boosts pressure; beside a well or open water it also supplies the network.
- **Recipe:** Electrical 3, Welding 2; 2 Welding Torch uses, 1 Welding Rods use, 2 Iron Pipes, 4 Steel Sheets, 2 Scrap Electronics, and 1 Wire.
- **Placement:** occupies a floor-pipe tile and has a fixed axis; rotate before building.
- **Defaults:** +25 m head, 7 m suction limit, 20 L/min natural-source intake.
- **Details:** [Pumps and pressure](pumps-and-pressure.md).

<!-- SCREENSHOT: 08-pump-source-placement.png — Water Pump correctly placed beside a source. -->

### Pressure Gauge — Manómetro

- **Purpose:** reads local pressure and reports whether sprinkler pressure is available.
- **Recipe:** 1 Iron Pipe and 1 Scrap Electronics; no skill.
- **Placement:** fits over an existing pipe that has no valve or incompatible device.
- **Details:** [Pumps and pressure](pumps-and-pressure.md#diagnosis).

## Direction and isolation

### Fluid Router — Enrutador de fluidos

- **Purpose:** creates a one-way boundary from green **IN** to red **OUT**, with an optional downstream pressure ceiling.
- **Recipe:** 2 Iron Pipes and 1 Steel Sheet; no skill.
- **Placement:** replaces a floor-pipe tile; rotate before building. A vessel or purifier on its tile exchanges fluid across the boundary.
- **Default transfer:** up to 30 L/min for a bare router (one with nothing placed on its tile).
- **Details:** [Routers and valves](routers-and-valves.md#fluid-router).

<!-- SCREENSHOT: 10-router-orientation.png — Fluid Router showing green IN and red OUT. -->

### Shut-off Valve — Válvula de corte

- **Purpose:** open, it leaves one network; closed, it separates fluid, pressure, and contamination in both directions.
- **Recipe:** 1 Iron Pipe and 1 Iron Bar Half; no skill.
- **Placement:** fits over an existing plain floor pipe. It cannot share the tile with a router, pump, emitter, sprinkler, or gauge.
- **Details:** [Routers and valves](routers-and-valves.md#shut-off-valve).

<!-- SCREENSHOT: 12-valve-open-closed.png — Shut-off Valve in both states. -->

## Treatment

### Water Purifier (Electric) — Purificador de agua (eléctrico)

- **Purpose:** converts tainted input water into clean output water.
- **Skills:** Electrical 4 and Welding 3.
- **Recipe:** 3 Welding Torch uses, 2 Welding Rods uses, 3 Iron Pipes, 2 Steel Sheets, 1 Scrap Electronics, 1 Wire, 1 Lighter - Improvised Battery, 1 Charcoal, and 2 Rags.
- **Placement:** 2×2 footprint; its top/back anchor sits on a correctly oriented Fluid Router. Keep the floor above the anchor clear.
- **Operation:** powered filtering at up to 10 L/min; internal 50 L input and output tanks. Repair a worn filter with 1 Charcoal and 2 Rags.
- **Details:** [Water purification](purification.md).

<!-- SCREENSHOT: 13-purifier-placement.png — Purifier build ghost anchored on a Fluid Router. -->

## Irrigation

### Drip Emitter — Gotero

- **Purpose:** waters a living crop on its own tile while continuing the pipe run.
- **Recipe:** Agriculture 1 and 1 Iron Pipe.
- **Pressure:** no minimum; bursts above 15 m by default. A burst emitter still carries water but stops watering.
- **Repair:** Pipe Wrench and 1 Duct Tape.
- **Details:** [Automatic irrigation](irrigation.md).

### Sprinkler — Aspersor

- **Purpose:** waters the full 3×3 area and can wet nearby characters.
- **Recipe:** Agriculture 2, 1 Iron Pipe, and 1 Steel Sheet.
- **Pressure:** requires 20 m by default; charges water for all nine tiles and can attract zombies.
- **Details:** [Automatic irrigation](irrigation.md).

<!-- SCREENSHOT: 17-sprinkler-coverage.png — Sprinkler operating over its complete 3×3 area. -->

## Related recipe

**Forge a Metal Pipe — Forjar una tubería de metal** is a Primitive Forge recipe. It produces one Iron Pipe and consumes 1 Charcoal, 1 Iron Bar Half, and 1 Iron Bar Quarter; it keeps a hammer, tongs or Metalworking Pliers, and a Metalworking Punch. It requires Blacksmithing 0 and awards 10 Blacksmithing XP.
