# Changelog

All notable changes to Water Pipes are documented here. Dates are in YYYY-MM-DD.

## [0.7.0] - 2026-08-01

### Water pump
- **A pump now has an on/off switch.** Right-click it for a menu of its own: turn it on or off, or
  read its status. A pump that is off contributes nothing at all -- no pressure, no drawing from a
  well -- exactly as if you had cut its power, so you can stop one draining a well without unplugging
  the generator feeding half the base. Flipping it is a physical act: your character walks over and
  works the panel. No tool needed.
- **The status dialog answers what a pump cannot show from the outside**: whether it is switched off
  or simply unpowered, whether it has a well or open water in reach and is drawing from it, and the
  pressure arriving against the pressure leaving. An idle pump also tells you what switching it on
  would actually buy, which on a mains-fed line can be nothing. The switch is in the dialog too.

### Getting wet
- **Running water soaks you.** A sprinkler's 3x3 and an open hydrant's now wet whoever stands in
  them, body and clothing alike, taking about a minute to go from dry to soaked. Crossing at a walk
  leaves you damp; standing there does not.

### Art and effects
- **A new pressure gauge**: a proper round instrument you can read at a glance, replacing the dial
  that all but vanished at normal zoom.
- **An open hydrant now floods its 3x3** instead of trickling onto its own tile -- a heavy, wide jet
  rather than a second sprinkler.

### Fixed
- **Pumps could never draw from a well.** The check that recognised a well never matched, in any
  released version, so a pump beside one silently did nothing while the open-water half of the same
  feature worked fine. Wells work now.

## [0.6.1] - 2026-07-31

### Fixed
- **Concealed pipes answer the right-click menu again.** A concealed pipe alone on its tile now
  offers "Show pipe network" like any other pipe. Nothing about concealed pipes changed: they are
  still invisible once placed and still only appear while the network view is up.

## [0.6.0] - 2026-07-23

### Water pressure
- **Pipes now have pressure**, measured in metres of water column. Height above a consumer adds
  pressure, distance along the pipes spends it, and pumps create it. The full Realistic model is on
  by default; the sandbox also carries a Simple mode (height only, distance is free) and an Off mode
  that restores the old gravity-only behaviour.
- **Electric Water Pump.** A powered pipe: on a run it boosts the network's pressure (chain several
  to add up), and placed next to a well or open water it also draws water in. It lifts water only a
  couple of floors from below but pushes it far higher, so put it low near the source.
- **Pressure Gauge.** A dial that sits on a pipe; right-click it to read the pressure at that point
  and whether a sprinkler would run there.

### Fluid routers
- **A bare router is now a pressure-reducing valve, not a wall.** A draw reaches through it to the
  network upstream and runs at whatever is lower, the incoming pressure or the ceiling you set --
  so a sprinkler on a regulated branch works without needing a tank behind it. It still only lets
  fluid cross one way, so it keeps its no-backflow meaning. Put a container on it and it goes back
  to being the hard boundary it always was.
- **Set the limit with a dialog.** Right-clicking a router opens a window with a slider for feeling
  out a value and a typed field for hitting an exact one, which matters when a drip emitter bursts
  above 15.0 and a sprinkler needs 20.0. It also shows the pressure arriving at the valve and the
  pressure leaving it, so you can see what a limit will actually do before applying it.

### Irrigation
- **Drip Emitter** and **Sprinkler**, built as pipes over your crops. The drip waters its own tile
  and needs only water reaching it; the sprinkler waters a 3x3 but needs real pressure (a pump) and
  is loud enough to draw the dead. Too much pressure bursts a drip emitter, so cap the line with a
  router or keep pumps off it.

### Town water
- **The mains fills your network.** While the water service is still on, a plumbed sink or shower
  feeds your pipes instead of only drawing from them, holding the whole network at mains pressure --
  so sprinklers can run with no pump, right up to the day the water is cut.
- **Fire hydrants.** Open a street hydrant with a pipe wrench and it feeds clean, pressurised water
  into a pipe laid on its tile. Mains-fed and effectively bottomless while the service runs; after
  the shutoff it holds a finite reserve that drains as you use it. An open hydrant left running
  wastes water and can be heard nearby. All tunable in the sandbox.

### Water quality
- **Standing water goes bad.** Water left sitting in a network turns contaminated after a while
  (sealed storage keeps for weeks, open rain-catchers for days), and rain contaminates any open
  water left outside. Using a network keeps it fresh. Every timer is tunable, and the whole feature
  can be switched off.
- **Contamination spreads instead of jamming.** Wiring contaminated water into a clean network now
  turns the whole network contaminated (as it should) rather than silently stopping it. It only
  travels one way: clean water poured into a contaminated line does not rinse it, so the purifier is
  the only way back.
- **Realistic purification is now on by default** -- taps no longer auto-clean contaminated water,
  which is the survival baseline the rest of the water model assumes. Turn it off in the sandbox for
  the old behaviour.

### Water effects
- **Running water is now visible.** Sprinklers throw a spray over the 3x3 they water, drip emitters
  show a small trickle, and an open fire hydrant gushes -- each only while it is actually running.
  The whole thing can be turned off in Options -> Mods -> Water Pipes.

### Art
- **Repainted pipes, wall covers and fluid routers.** The whole pipe set is new art. Nothing about
  how they build or connect changed.
- **New art for the sprinkler, the drip emitter and the pressure gauge.** The emitters are now a
  head that sits on the pipe instead of replacing it, so the run stays visible underneath and
  connects to its neighbours as it should. The gauge is a real dial on the pipe rather than the
  wall box it borrowed before.
- Concealed pipes now preview as the pipe they actually build, so the build menu and the placement
  cursor match the visible versions. They are still invisible once placed.

### Compatibility
- **Barrel mods now see the network.** Mods that redraw a barrel by its fill level (Useful Barrels
  and similar) are notified when the network fills or drains one, so their sprites keep up.

### Naming and languages
- The generic pipes are now **Fluid Pipes** (they carry fuel as readily as water). Water devices
  (pump, purifier, drip, sprinkler, gauge) keep their names. Every object description was rewritten
  to be short and direct.
- **Simplified Chinese** is now fully supported alongside English and Spanish.
- The build category now reads in your language instead of showing its internal name.

### Fixes
- Fixes: pumps and gauges no longer vanish or error on world reload, the gauge no longer draws over
  the player, router sprites no longer draw over the player, and a pressure-regulated branch now
  loses pressure with distance as it should.

## [0.5.1] - 2026-07-20

### Fixed
- **Washing machines work again.** A washer on a pipe tile is now a plumbable water consumer (it
  draws its wash water from the network, like a sink) instead of being taken over as storage, which
  had left it unable to run its cycle.

## [0.2.0] - 2026-06-08

### Multiplayer
- **Pipe building now works in multiplayer.** Pipes were migrated to the Build 42 entity system,
  so placement is server-validated and no longer hangs forever on the building animation.
- **Plumbing is server-authoritative.** Connecting/disconnecting sinks and generators now runs on
  the server instead of the client, fixing client/server desync, duplicated fixtures stacking on a
  tile, and `sendObjectChange() can only be called on the server` errors.

### Added
- **Vertical pipe networks.** The vertical pipe (wall riser) is a single, rotatable build entry
  (North/West) and properly links floor pipes across the wall and between floors.
- **Network visualization.** Right-click any pipe → *Show pipe network* highlights the whole
  network: pipes in red, fluid-providing containers in green, and consumers (plumbed sinks,
  showers, toilets, generators) in blue. Auto-clears after a few seconds, or use *Hide pipe network*.
- **Any liquid can be drawn from a tap.** A plumbed tap now serves whatever single fluid its
  network holds (water, petrol, ...). Only Tainted Water is purified into clean Water at the tap;
  every other fluid comes out as-is.

### Changed
- **Taps prioritize their connected network.** A plumbed tap no longer pulls free city-mains water
  on top of its network source. When the water service is on, it serves the network fluid, not
  unlimited mains water.
- **Containers connect by exact tile.** A container only joins the network when a pipe sits on its
  own tile (no more loose adjacency). A vertical riser can be surrounded by horizontal pipes, but
  the object it feeds always needs a horizontal pipe on its tile.
- Completed Spanish/English translations (build category, new context-menu options).

### Fixed
- **Unplumbing restores the original state.** Disconnecting our system returns a fixture to exactly
  how it was before: a former city-mains tap goes back to unlimited water (if the service is on),
  and a fixture using a rain barrel keeps using it.
- Vertical connections that previously failed in single-player now connect correctly.

### Removed
- Legacy B41-style build menu and the old pipe build action (replaced by the entity system).

## [0.1.0]

- Initial release: buildable auto-connecting floor pipes and wall risers, fluid containers and
  fixtures sharing a single network, generator fuelling, any-fluid networks, bilingual UI.
