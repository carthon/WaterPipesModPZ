# Irrigation

| Emitter | Recipe | Coverage | Default pressure | Network use |
|---|---|---|---:|---:|
| Drip Emitter | Farming 1, Pipe Wrench, 1 Metal Pipe | Its own tile | No minimum; bursts above 15 m | 0.2 L/hour |
| Sprinkler | Farming 2, Pipe Wrench, 1 Metal Pipe, 1 Sheet Metal | Full 3×3 | Needs 20 m | 1.8 L/hour |

Construction awards 10 Farming XP for a drip and 20 for a sprinkler. Both are pipe segments: they carry fluid onward and may be laid over crops. They add 10 crop-water points per in-game hour while a living crop needs water. Tainted water irrigates as effectively as clean water.

The drip charges only its own tile. The sprinkler pays for all nine tiles whether crops occupy them or not and, when enabled in sandbox settings, makes noise within a 12-tile radius. Its spray also wets characters standing in the 3×3.

## Safe layouts

- **Drip line:** source or pump → Fluid Router limited below the burst threshold → row of drips.
- **Sprinkler zone:** source → pump or mains → router → short branch of sprinklers. Split large farms into zones because shared demand starves the far end.
- Right-click **Check irrigation emitter** to see no water, no pressure, insufficient pressure, burst risk, or burst state.

![Pressure-safe drip line](../assets/images/diagram-irrigation-safe.svg){ .wp-diagram }

One +25 m pump feeds a router capped below 15 m, then four drips using 0.2 L/hour each.

A burst drip still conducts water but no longer irrigates. Repair it with a Pipe Wrench and 1 Duct Tape. Setting the sandbox burst pressure to 0 disables bursting.

<!-- SCREENSHOT: 17-sprinkler-coverage.png — Active sprinkler showing its complete 3×3 coverage. -->
<!-- SCREENSHOT: 18-emitter-diagnostics.png — Check irrigation emitter result for a pressure problem. -->
