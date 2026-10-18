# Purification

## Construction

The **Water Purifier (Electric)** requires Electrical 4, Welding 3, a Pipe Wrench, 3 Welding Torch uses, 2 Welding Rods uses, 3 Iron Pipes, 2 Steel Sheets, 1 Scrap Electronics, 1 Wire, 1 Lighter - Improvised Battery, 1 Charcoal, and 2 Rags. Building it awards 40 Electrical XP and 30 Welding XP.

First build and orient a Fluid Router: green is tainted-water **IN**, red is clean-water **OUT**. The purifier occupies 2×2 tiles and only has one orientation: aim the router before placing it.

### Placement conditions

The mod checks the **anchor**, the top/back corner of the 2×2 (the tile furthest from the camera):

- It must be on a Fluid Router tile. The other three tiles do not need one.
- It must not already hold a purifier.
- The level directly above it must have no floor: the tank is tall and would clip through it. Only the anchor is checked; the other three tiles may be under a roof.

The game engine applies its own checks to every building on all four tiles; they are not part of the mod:

- Solid floor under each tile.
- Nothing solid on them: barrels, rain collectors, furniture, trees.
- No players, zombies, animals or vehicles on them.
- No wall, fence or window between tiles of the 2×2.

Pipes on the other three tiles do not get in the way.

![Purifier flow](../assets/images/diagram-purifier-flow.svg){ .wp-diagram }

- **1** Tainted storage.
- **2** Green router IN.
- **3** Powered purifier and filter, placed on the router.
- **4** Red router OUT.
- **5** Clean storage.

![Purifier placement preview showing its router anchor and 2×2 footprint](../assets/images/13-purifier-placement-cropped.png){ .wp-screenshot loading=lazy }

## Operation and filter

While powered, it draws tainted water at up to 20 L/min and converts up to 10 L/min (its window shows "u", units; one unit is one litre). Its internal input and output tanks hold 50 L each. It does not process clean water or incompatible non-water liquids. External clean-side storage is optional, but recommended: without it, processing pauses when the 50 L output tank fills.

The filter starts at 100%. At the default wear rate it cleans about 5,000 L before clogging. Right-click **Repair filter** with 1 Charcoal and 2 Rags; repair returns it to 100%. **Open Purifier** reports power, input, output, rate, and filter condition. Ambient machine sound can be disabled under **Options → Mods → Water Pipes**.

By default the clean side receives 60% of incoming pressure: 25 m becomes 15 m, enough for taps and drip irrigation but below a sprinkler's 20 m requirement. Add a pump after the purifier or change the sandbox transfer percentage when necessary.

## Dismantling

Use a fueled Welding Torch and Welder Mask. Each return is rolled separately: 1 Steel Sheet and 2 Iron Pipes at 80%, plus 1 Scrap Electronics and 1 Wire at 60%. Battery, charcoal, and rags are not returned; destruction returns nothing.

![Purifier status window while actively filtering](../assets/images/15-purifier-status-window-cropped.png){ .wp-screenshot loading=lazy }
