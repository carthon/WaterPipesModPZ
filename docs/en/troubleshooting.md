# Troubleshooting

Use this page to diagnose a network that is already built. For general how-to questions, start with the [FAQ](faq.md) or [Practical examples](practical-examples.md).

## General diagnostic sequence

1. Confirm Project Zomboid 42.15+, Water Pipes v0.11.x, and matching server/client mod versions.
2. Choose **Show pipe network** and trace the complete route.
3. Verify a pipe on every endpoint's own tile and a Vertical Fluid Pipe at each floor change.
4. Check closed valves, Fluid Router direction, and any configured pressure ceiling.
5. Check that connected storage contains the fluid required by the consumer and is not empty.
6. Read local pressure with **Check pump**, a Pressure Gauge, or **Check irrigation emitter**.
7. Check electricity and manual on/off state for pumps and purifiers.
8. Review this save's Water Pipes Sandbox settings.
9. In multiplayer, reproduce once after reconnecting and confirm identical mod versions.
10. If unresolved, save the overlay/status screenshot and relevant `console.txt` lines.

## Network does not connect

**Symptom:** The endpoint is absent from the overlay or behaves as a separate network.  
**Possible causes:** Pipe is adjacent rather than on the same tile; a floor change lacks a vertical pipe; a valve is closed; a gap exists.  
**Checks:** Reveal the network and inspect the entire route and wall-mounted vertical pieces.  
**Resolution:** Correct the missing tile or vertical transition, or open the isolating valve.  
**Related:** [Pipe networks](pipe-networks.md)

## Fixture has no supply

**Symptom:** A plumbed fixture is empty.  
**Possible causes:** No connected storage; storage is dry, contains the wrong fluid, or is below the fixture without enough pressure; a remote break isolated it.
**Checks:** Inspect storage, overlay, valves, and local pressure.  
**Resolution:** Restore a valid route and a compatible water supply. Incompatible transfers are rejected rather than mixed.
**Related:** [Sources and storage](sources-and-storage.md), [Fixtures](fixtures-and-plumbing.md)

## Pump is not moving water

**Symptom:** Storage does not fill or pressure is absent.  
**Possible causes:** Pump off; no electricity; source outside suction range; destination full; no valid natural source.  
**Checks:** Use **Check pump** for power, source, input pressure, output pressure, and contribution.  
**Resolution:** Act on the reported condition. A source-less pump can add pressure to stored water but cannot create water.  
**Related:** [Pumps and pressure](pumps-and-pressure.md)

## Pressure is too low or uneven

**Symptom:** Nearby consumers work but distant or upper consumers do not.  
**Possible causes:** Distance, elevation, shared demand, router limit, or purifier pressure loss.  
**Checks:** Compare Pressure Gauge readings along the route and review customized Sandbox settings.  
**Resolution:** Reduce demand or distance, divide branches with routers, or add a correctly powered pump where the design permits.  
**Related:** [Pumps and pressure](pumps-and-pressure.md), [Routers and valves](routers-and-valves.md)

## The purifier cannot be placed

**Symptom:** The purifier's build preview stays red.  
**Possible causes:** The anchor (top/back corner) is not on a Fluid Router; that router already has a purifier; there is floor on the level above the anchor. Game engine checks, on all four tiles: no solid floor; a barrel, rain collector, piece of furniture or tree in the way; a player, zombie, animal or vehicle on a tile; a wall, fence or window crossing the 2×2.  
**Checks:** Hover the anchor over the router and look at what stands on the other three tiles and on the level above.  
**Resolution:** Clear the footprint or move the router to an open spot with nothing built above it. Pipes on the footprint are fine.  
**Related:** [Purification](purification.md#placement-conditions)

## Purifier does not process water

**Symptom:** No clean water reaches the output.  
**Possible causes:** No power; clogged filter; input is clean or is not water; output tank full; incorrect router orientation.
**Checks:** Open the purifier window and verify the green input/red output layout.  
**Resolution:** Restore power or capacity, repair the filter, or correct the input network.  
**Related:** [Purification](purification.md)

## Sprinkler or drip emitter is not watering

**Symptom:** Crops remain unwatered.  
**Possible causes:** Dry network; insufficient sprinkler pressure; burst drip emitter; no living crop currently needs water.  
**Checks:** Use **Check irrigation emitter**.  
**Resolution:** Follow the reported condition; repair a burst drip emitter with the required materials and limit upstream pressure.  
**Related:** [Irrigation](irrigation.md)

## A moisture sensor does not open its valve

**Symptom:** The crops dry out but the linked valve stays closed.  
**Possible causes:** No power (unlit light): no electricity on the tile and no charged Battery; no crop on the sensor's tile; the moisture has not dropped to the minimum yet (it holds between the two ends); **Invert** is on; the valve was closed by hand; the valve is not linked.  
**Checks:** Right-click the sensor, **Open sensor**: it shows the reading, the signal and why, the power, and the linked valves. The valve's tooltip says whether it was switched off by hand or is waiting for a signal.  
**Resolution:** Give it power or a Battery, plant on its tile, adjust the range, or **Open valve** by hand to hand it back to the sensors.  
**Related:** [Soil Moisture Sensor](irrigation.md#moisture-sensor)

## One connected network contains water and petrol

**Symptom:** Fixtures or generators receive no usable fluid even though their own storage is not empty.
**Possible cause:** Separate vessels containing incompatible fluids are attached to the same network. The liquids do not blend or contaminate one another, but delivery is refused while the network holds more than one incompatible liquid.
**Checks:** Reveal the network and locate the connection between the water and petrol routes.
**Resolution:** Close a valve or separate the routes. No draining or decontamination procedure is needed; the fluids remain in their original vessels.

**Related:** [Fuel transport](fuel-transport.md), [Sources and storage](sources-and-storage.md)

## Multiplayer state differs between players

**Symptom:** An action appears delayed, rejected, or inconsistent.  
**Possible causes:** Server validation rejected the action, a client disconnected while inspecting a world building's plumbing, or mod versions differ.
**Checks:** Confirm matching mod versions and review the visible server response.  
**Resolution:** Reconnect and retry after correcting the reported condition. An interrupted building inspection is settled by the server on the next pass.
**Related:** [Compatibility](compatibility.md), [Inspecting building plumbing](building-plumbing.md)

If the documented checks do not explain the problem, report it through [GitHub Issues](https://github.com/carthon/WaterPipesModPZ/issues) with game/mod versions, multiplayer status, relevant settings, steps, logs, and screenshots.
