# Practical Water Pipes installations

These Project Zomboid plumbing examples use the v0.10.x mechanics. Recipe details are in the [component reference](component-reference.md); use [Troubleshooting](troubleshooting.md) if a final check fails.

## First water network

**Goal:** supply one sink from a finite water container.

**Materials:** Pipe Wrench, one container, and one Metal Pipe or fired Clay Pipe Segment per pipe tile.

1. Place the container and, if its design requires it, open or uncap it.
2. Build a **Fluid Pipe** on the container's own tile.
3. Extend the pipe route to the sink and place the final pipe on the sink's own tile.
4. Carry the Pipe Wrench, right-click the sink, and choose the game's **Plumb** action.
5. Choose **Show pipe network** and test the sink.

**Check:** container/source is green, sink is blue, and the whole pipe route is red. **Common errors:** placing the endpoint pipe beside the object, omitting a vertical riser, or expecting the pump itself to store water. See [Pipe networks](pipe-networks.md) and [Fixtures](fixtures-and-plumbing.md).

## Inspect a world house's plumbing

**Goal:** inspect a world-generated house and reveal the concealed plumbing that is treated as already existing there.

This action materializes the network on demand so the mod does not have to generate plumbing for every building on the map. It cannot auto-plumb a player-built house; build that network manually instead.

**Materials:** usable Pipe Wrench and, by default, one Metal Pipe per fixture that will be connected.

1. Stand inside the building and choose a floored root tile near the intended supply.
2. Right-click and select **Plumb this building**; review the reported price.
3. Let the timed inspection finish. If interrupted, plumbing already revealed remains.
4. Connect the root to storage or a source and show the revealed network.
5. If the result is partial, read the result reason and run another pass from a better location.

**Check:** each reached fixture is blue and the concealed tree appears in the overlay. **Common errors:** attempting it in a player-built structure, no recognized world building, insufficient pipes, no north/west wall for a floor change, or the 200-new-tile limit. See [Inspecting a building's plumbing](building-plumbing.md).

## Draw water from a well or river

**Goal:** feed storage from a natural source.

**Materials:** Water Pump recipe, electricity, pipe route, and a finite storage vessel.

1. Build the pump on or next to the well/open-water source within its default 7 m suction limit.
2. Connect its pipe axis to the storage network and power its tile.
3. Right-click it and choose **Turn on**.
4. Use **Check pump** to confirm power and the detected source.

**Check:** the pump reports well water or open water and storage rises at up to 20 L/min by default. **Common errors:** pump switched off, no electricity, source out of reach, full destination, or river/lake intake disabled. Open water is tainted; wells are clean. See [Sources and storage](sources-and-storage.md).

## Purify tainted water

**Goal:** separate tainted input from clean output.

**Materials:** Fluid Router, Water Purifier (Electric), tainted supply, electricity, and optional clean-side storage.

1. Orient the router so green **IN** faces the tainted network and red **OUT** faces the clean network.
2. Place the purifier's top/back anchor on the router tile and keep the floor above clear.
3. Power it and open **Open Purifier**.
4. Confirm tainted intake, filter condition, and free room in its 50-unit output buffer.
5. Add clean-side storage for more capacity; add downstream pressure if required.

**Check:** the window says **Filtering** and clean output increases, up to 10 units/min. **Common errors:** reversed router, clean or non-water input, no power, clogged filter, or full output. See [Water purification](purification.md).

## Install irrigation

**Goal:** water crops automatically without bursting low-pressure emitters.

**Materials:** Drip Emitters or Sprinklers, water storage, and pressure/control devices as needed.

1. Use a drip on each crop for a low-pressure line, or place a sprinkler centrally for a 3×3 area.
2. For drips downstream of a default +25 m pump, add a router and set its limit below 15 m.
3. For sprinklers, provide at least 20 m at the emitter by default.
4. Choose **Check irrigation emitter** and correct the reported condition.

**Check:** living crops that need water receive it. **Common errors:** dry network, insufficient sprinkler pressure, excessive drip pressure, dead/missing crops, or shared demand starving distant emitters. See [Automatic irrigation](irrigation.md).

## Supply a generator with petrol

**Goal:** auto-refuel a generator from an isolated petrol network.

**Materials:** petrol-only container, pipes, Pipe Wrench, and optionally a powered pump.

1. Put a **Fluid Pipe** on the petrol container's tile and build an isolated route.
2. Put the final pipe on the generator's tile.
3. Right-click with the Pipe Wrench and choose **Plumb Generator**.
4. Keep every connected vessel petrol-only. Add pressure if distance or elevation requires it.
5. Let the generator fall below the default 25% threshold; it checks once per minute and draws toward 100%.

**Check:** petrol leaves storage and enters the generator. **Common errors:** only water is available, petrol storage is empty, pressure is insufficient, threshold is set to 0, or the generator is not plumbed. See [Fuel transport](fuel-transport.md).

## Separate and control branches

**Goal:** isolate maintenance/liquid zones with a valve or enforce one-way flow with a router.

1. Fit a **Shut-off Valve** over an existing plain pipe when you need a reversible two-way boundary.
2. Close it before maintenance or before two unlike liquids could meet; reopen only after verifying both sides.
3. Use a **Fluid Router** where flow must be one-way. Rotate green **IN** toward the source and red **OUT** downstream.
4. Set a pressure ceiling when protecting drips or zoning consumers.
5. Reveal each side to confirm the intended boundary.

**Check:** a closed valve produces two independent networks; a router transfers only IN→OUT. **Common errors:** reversed router, opening a valve between petrol and water, or setting a limit below the consumer minimum. See [Routers and valves](routers-and-valves.md).

