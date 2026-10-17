# Compatibility

## Supported environment

| Component | Status |
|---|---|
| Project Zomboid | Build 42.15 or newer |
| Water Pipes | Documentation covers the v0.11.x series |
| Single player | Supported |
| Multiplayer and dedicated servers | Supported; construction and fluid mutations are server-authoritative |
| Languages in the mod | English, Spanish, Simplified Chinese |
| Languages in this guide | English, Spanish |

Confirmed integrations are **Take A Bath And Shower** fixtures and **Useful Barrels** containers; that mod turns the map's [barrels](glossary.md#barrel), scenery in the base game, into containers. Container support is capability-based and sends fluid-change notifications so compatible barrel mods can refresh their fill sprites, but an untested mod is not guaranteed compatible.

## Project Viewpoint (optional 3D models)

The same Workshop item includes a second, optional mod, **Water Pipes - Viewpoint** (mod ID `waterpipesviewpoint`). It gives every pipe and component a 3D model, and watering sprinklers an animated spray, in the first- and third-person views of [Project Viewpoint](https://steamcommunity.com/sharedfiles/filedetails/?id=3809306528). Water Pipes does not need it: enable it only if you play with Project Viewpoint, which in turn needs ZombieBuddy.

- Enable `waterpipes`, `Viewpoint` and `waterpipesviewpoint`. Without Project Viewpoint the add-on does nothing.
- Viewpoint's isometric view keeps the normal sprites.
- The spray is animated in single player; in multiplayer the sprinkler head shows a still spray.
- Project Viewpoint loads every model pack into one shared memory budget. On its lowest memory profile some models may not fit and keep their flat sprite; choose a higher profile if pieces are missing.
- With **Viewpoint Placement Fix**, building previews also show the 3D model.
- In the first- and third-person views, [Show pipe network](glossary.md#show-pipe-network) does not outline anything: Project Viewpoint does not draw the game's object highlights there. Switch to Viewpoint's isometric view to see the network.

## Dedicated-server checklist

1. Install Workshop item `3739595559` for server and clients.
2. Add mod ID `waterpipes` and keep the same mod version everywhere.
3. Configure the Water Pipes sandbox group before starting or restarting the save.
4. Back up the save before updates and test important networks after updating.
5. If an old fixture behaves incorrectly after migration, unplumb it and plumb it again.

## Removing the mod

Back up the save first. Build 42 mods that register buildable objects can trigger a `WorldDictionary` load error when removed from an existing world. Dismantle Water Pipes objects where practical, stop the server, back up again, then remove the mod for server and clients together. If the world fails, restore the backup and follow the linked [World Dictionary recovery guide](https://steamcommunity.com/sharedfiles/filedetails/?id=3187340365).

## API for mod authors

The shared global `WaterPipesAPI` is available from game/server start. Pass an `IsoGridSquare` containing a pipe:

| Member | Result |
|---|---|
| `VERSION` | API version; currently `1` |
| `hasNetwork(square)` | Whether a network is reachable |
| `getWaterAmount(square)` | Usable amount, or `0` when none is available or the network holds incompatible liquids at once |
| `getWaterSummary(square)` | `{ amount, capacity, fluidType, isMixed }` or `nil`; `isMixed` flags vessels holding different liquids on one network, not liquids blended inside a vessel |
| `drawWater(square, fluidType, amount)` | Amount actually removed |
| `fillWater(square, fluidType, amount)` | Amount actually added; never creates a mixture |

Read calls are safe on either side. `drawWater` and `fillWater` mutate containers and therefore work only on the server or in single player; on a plain multiplayer client they return `0`. Always guard for `WaterPipesAPI` being present.

