# Sandbox settings

Water Pipes v0.10.x exposes 26 per-save options. Values described as **tenths** are divided by ten in play: `250` means 25.0 m of water head.

## Liquids and generators

| Setting | Default | Range | Effect |
|---|---:|---:|---|
| Realistic water purification | On | On/Off | Tainted water stays tainted until a purifier; Off restores vanilla tap cleaning |
| Generator auto-refuel threshold | 25% | 0–100 | Starts refuelling below this; 0 disables it |
| Generator auto-refuel target | 100% | 0–100 | Stops refuelling at this tank percentage |
| Purifier filter wear rate | 100% | 0–1000 | Scales filter wear; 0 disables wear |

## Pressure and pumps

| Setting | Default | Range | Effect |
|---|---:|---:|---|
| Water pressure model | Realistic | Realistic/Simple/Off | Full model; height only; or legacy gravity behavior |
| Pressure gained per floor | 30 | 0–200 tenths | Default 3.0 m per floor |
| Base pressure of a container | 10 | 0–200 tenths | Default 1.0 m on its own floor |
| Pipe friction | 100% | 0–500 | Scales distance loss; 0 removes it |
| Pressure a purifier passes on | 60% | 0–100 | Share of input head reaching clean side |
| Shared-pipe demand | 100% | 0–100 | How strongly simultaneous consumers starve one another |
| Pressure added by one pump | 250 | 0–1000 tenths | Default 25.0 m; pumps in series add |
| Pump suction limit | 70 | 0–500 tenths | Default 7.0 m below the pump |
| Pump intake rate | 20 L/min | 0–500 | Well/open-water extraction rate |
| Pumps draw from rivers/lakes | On | On/Off | Allows unlimited tainted open-water intake |

## Irrigation and town water

| Setting | Default | Range | Effect |
|---|---:|---:|---|
| Drip burst pressure | 150 | 0–1000 tenths | Bursts above 15.0 m; 0 prevents bursting |
| Sprinklers make noise | On | On/Off | Running sprinklers attract zombies |
| Town water fills the network | On | On/Off | Plumbed fixtures act as mains inlets before shutoff |
| Town water pressure | 250 | 0–1000 tenths | Default 25.0 m mains head |
| Town water intake rate | 60 L/min | 0–1000 | Mains fill rate |

## Water age, rain, and hydrants

| Setting | Default | Range | Effect |
|---|---:|---:|---|
| Water stagnation | On | On/Off | Motionless stored water can become tainted |
| Days before sealed water spoils | 30 | 0–180 | 0 disables sealed-water spoilage |
| Days before open water spoils | 10 | 0–180 | 0 disables timer; rain can still taint it |
| Rain taints open water | On | On/Off | Outdoor rain-catching storage taints its network |
| Fire hydrant reserve | 1,000 L | 0–20,000 | Water left after town shutoff |
| Fire hydrant pressure | 400 | 0–1000 tenths | Default 40.0 m while mains-fed |

## Building-plumbing inspection

| Setting | Default | Range | Effect |
|---|---:|---:|---|
| Metal pipe per fixture | 1 | 0–10 | Cost per fixture revealed and connected by **Plumb this building** in a world building |

## Suggested starting profiles

- **Accessible:** realistic purification Off, pressure Simple, stagnation Off, drip bursting 0.
- **Default survival:** leave every value at its shipped default.
- **Hard survival:** reduce intake rates and reserves, raise friction/filter wear, and shorten stagnation timers.

Changing values affects the current save's simulation; it does not rebuild layouts or replace already constructed objects.

## Mod Options: local presentation

These settings are under **Options → Mods → Water Pipes** and affect the current client, not the save's hydraulic simulation:

| Option | Effect |
|---|---|
| Machine sounds | Enables looping machine audio such as a powered purifier |
| Machine sound volume (%) | Sets that audio from 0 to 100 |
| Water spray effects | Shows animated spray on running sprinklers and open hydrants |

<!-- SCREENSHOT: 26-sandbox-options.png — Water Pipes sandbox page showing the complete option group. -->
