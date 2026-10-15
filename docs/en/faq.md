# Frequently asked questions

This section also covers questions raised by players in the [Steam Workshop comments and discussions](https://steamcommunity.com/sharedfiles/filedetails/?id=3739595559).

## Installation and requirements

### Which game version is supported?

Water Pipes v0.10.x requires **Project Zomboid Build 42.15 or newer**. See [Compatibility](compatibility.md).

### Does Water Pipes have dependencies?

No additional mod dependency is declared. Install Water Pipes itself for the server and every multiplayer client.

### Can I add it to an existing save?

The mod does not require a new world, but adding it to an established save has not been covered by an automated in-game test. Back up the save first, then test a small network before committing important supplies.

### Can I remove it safely?

Back up first. Removing Build 42 mods with registered buildable objects can cause a `WorldDictionary` load error. Dismantle Water Pipes objects where practical and follow [Removing the mod](compatibility.md#removing-the-mod).

### Do tools get consumed?

The Pipe Wrench is required for many actions but is not consumed. Parts and consumables depend on the construction recipe.

## Construction and connections

### Why does a nearby barrel or sink not connect?

The pipe must be on the object's **own tile**. Adjacent is not enough. Between floors, add a Vertical Fluid Pipe.

### How do I connect a barrel to the network?

Build a Fluid Pipe on the **same tile**. Containers join automatically; they do not need an additional installation action. In the base game, the barrel that holds water is the Rain Collector Barrel; the barrels found around the map only work with the [Useful Barrels](glossary.md#barrel) mod, and you open one first by unscrewing its plug with a Pipe Wrench.

### How can I see concealed pipes?

Right-click any pipe and choose **Show pipe network**. The overlay remains visible briefly.

## Storage and liquids

### Does a pump store water?

No. Connect at least one container; sources supply liquid but do not replace storage.

### Can one network carry water and petrol?

Water and petrol never mix: an incompatible transfer is rejected. Keep them in isolated networks anyway, because fixtures and generators require the correct fluid. Clean and tainted water can combine, and the result is tainted.

## Pumps and pressure

### Why does water reach one fixture but not another?

Height, pipe distance, shared demand, and available pressure can differ along the route. Use **Check pump**, a Pressure Gauge, and [pumps and pressure](pumps-and-pressure.md).

## Purification

### Do sinks clean tainted water?

With realistic purification enabled by default, no. Use a **Water Purifier (Electric)**.

### Why did the purifier stop?

It needs power, tainted input water, free output capacity, and a usable filter. Open its status window to identify the state.

### How do I place the purifier on the router?

The purifier occupies a 2 × 2 area. Its top/back corner must sit directly on the Fluid Router tile. The router's green side is the input and its red side is the output.

### Why is the purifier working but no water reaches my fixtures?

The purifier has its own 50 L clean-water output tank, so an extra container is not strictly required. A downstream amphora or rain collector barrel adds useful capacity. If fixtures still receive nothing, check the output tank, available pressure, and red-side connection.

### How do I use a fire hydrant?

Build a Fluid Pipe on the hydrant's own tile, equip a Pipe Wrench, and open it. It uses town water before shutoff and then its configured reserve. See [Sources and storage](sources-and-storage.md).

## Irrigation

### Why did my drip emitter break?

By default it bursts above 15 m of pressure. Put a Fluid Router with an appropriate pressure limit upstream.

### Why is a sprinkler idle?

By default it needs 20 m of pressure, network water, and a living crop that needs watering. Use **Check irrigation emitter**.

## Fuel and generators

### When does a plumbed generator refuel?

Once per minute when it is below the configured threshold (25% by default), toward the configured target (100% by default), from a petrol-only network.

### Why does the generator not receive petrol even with a pipe underneath it?

After placing the pipe on its tile, equip a Pipe Wrench and use **Plumb Generator**. The network must contain petrol only and have enough pressure for the height and distance. Follow the [generator example](practical-examples.md#supply-a-generator-with-petrol).

### How do I use a Shut-off Valve?

Build it over an existing plain floor pipe. Use **Close valve** to split both sides into independent networks and **Open valve** to join them again. Never reopen it between petrol and water. See the [control example](practical-examples.md#separate-and-control-branches).

### What does “Plumb this building” actually do?

In a world-generated building, it inspects and reveals plumbing that is treated as already existing. The mod materializes the concealed tree only on demand to avoid generating networks for every building on the map. It does **not** auto-plumb player-built structures; pipe those manually. See the [complete walkthrough](practical-examples.md#inspect-a-world-houses-plumbing).

## Movement and collision

### Do floor pipes block characters or vehicles?

No. Pipes do not block movement.

## Compatibility and multiplayer

### Is multiplayer supported?

Yes. Important state-changing actions are validated by the server.

### Which mod integrations are confirmed?

Take A Bath And Shower fixtures and Useful Barrels containers are documented integrations. See [compatibility](compatibility.md).
