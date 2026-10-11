# Sources and storage

## What joins a network

A finite world fluid container joins when a floor pipe occupies its **own tile**. This covers vanilla barrels and rain collectors, amphorae and tanks, plus modded containers that expose a normal fluid capacity. Washing machines and other fixtures are treated as consumers, not storage. Objects with a capacity of 9,999 or more are excluded from ordinary finite-container balancing; they only act as sources when specific source logic recognizes them.

Network storage settles every two in-game minutes: lower floors fill first, while containers on the same floor equalize by capacity. A pump is not storage; always include a vessel where incoming water can remain.

![Gravity storage order](../assets/images/diagram-storage-gravity.svg){ .wp-diagram }

Lower-floor containers (1) fill and equalize before an upper-floor container (2).

| Source | Fluid | Default rate or reserve | Setup |
|---|---|---:|---|
| Barrel, collector, amphora, tank | Existing contents | Container capacity | Put a floor pipe on its tile; uncap containers that only expose fluid storage when open |
| Well | Clean water | Pump: 20 L/min | Put a powered pump within suction reach |
| River or lake | Tainted water | Pump: 20 L/min, unlimited source | Put a powered pump beside open water; enabled by sandbox setting |
| Town mains | Clean water | 60 L/min at 25 m head | Plumb an indoor fixture before the water shuts off |
| Fire hydrant | Clean water | 60 L/min; 1,000 L reserve after shutoff | Put a pipe on its tile and open it with a Pipe Wrench |

<!-- SCREENSHOT: 06-source-types.png — Barrel, well pump, open-water pump, mains fixture and hydrant examples. -->

## Fluid quality and mixing

Clean and tainted water combine as tainted water. With realistic purification enabled, only the **Water Purifier (Electric)** restores clean water. Water and petrol in one connected component form a mixed network; normal fixture delivery and generator refuelling stop.

To recover a mixed network, close a valve or dismantle a connecting pipe to isolate the liquid types, then empty or replace every contaminated vessel in the affected component before reconnecting it. The exact in-game removal sequence still needs play verification because available drain actions depend on the vessel type.

<!-- TODO: Verify the safest in-game procedure for emptying every supported vessel after a mixed-fluid accident. -->
