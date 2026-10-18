# Irrigation

| Emitter | Recipe | Coverage | Default pressure | Network use |
|---|---|---|---:|---:|
| Drip Emitter | Agriculture 1, Pipe Wrench, 1 Iron Pipe | Its own tile | No minimum; bursts above 15 m | 0.2 L/hour |
| Sprinkler | Agriculture 2, Pipe Wrench, 1 Iron Pipe, 1 Steel Sheet | Full 3×3 | Needs 20 m | 1.8 L/hour |

Construction awards 10 Agriculture XP for a drip and 20 for a sprinkler. Both are pipe segments: they carry fluid onward and may be laid over crops. They add 10 crop-water points per in-game hour while a living crop needs water. Tainted water irrigates as effectively as clean water.

The drip charges only its own tile. The sprinkler pays for all nine tiles whether crops occupy them or not and, when enabled in sandbox settings, makes noise within a 12-tile radius. Its spray also wets characters standing in the 3×3.

## Safe layouts

- **Drip line:** source or pump → Fluid Router limited below the burst threshold → row of drips.
- **Sprinkler zone:** source → pump or mains → router → short branch of sprinklers. Split large farms into zones because shared demand starves the far end.
- Right-click **Check irrigation emitter** to see no water, no pressure, insufficient pressure, burst risk, or burst state.
- **Automatic watering:** a Shut-off Valve in front of the zone, linked to a [Soil Moisture Sensor](#moisture-sensor) among the crops, opens only when they are dry.

![Pressure-safe drip line](../assets/images/diagram-irrigation-safe.svg){ .wp-diagram }

- **1–2** Barrel and powered pump: 1 m + 25 m = **26 m**.
- **3** Router with **Set pressure limit** at 12 m, under the 15 m that bursts a drip.
- **4** Four 0.2 L/hour drips on consecutive tiles: **12 m**. Together they lose under 0.1 m per tile.

A burst drip still conducts water but no longer irrigates. Repair it with a Pipe Wrench and 1 Duct Tape. Setting the sandbox burst pressure to 0 disables bursting.

<div class="wp-gallery wp-gallery--2" markdown>
![Active sprinkler showing its complete 3×3 coverage](../assets/images/17-sprinkler-coverage-cropped.png){ .wp-screenshot loading=lazy }
![Irrigation-emitter diagnostic reporting a pressure problem](../assets/images/18-emitter-diagnostics-cropped.png){ .wp-screenshot loading=lazy }
</div>

## Soil Moisture Sensor { #moisture-sensor }

A stake you push into the soil next to a crop. It reads how much water the crop on its tile has, the same 0–100 % the game's farming uses, and opens or closes the [Shut-off Valves](routers-and-valves.md#shut-off-valve) you link to it. Put a valve in front of a drip line or a sprinkler zone and the crops water themselves only when they need it.

| Recipe | Skill | Tools |
|---|---|---|
| 1 Motion Sensor, 1 Receiver, 1 Electrical Wire, 2 Scrap Electronics | Electrical 3 (awards 20 Electrical XP) | Screwdriver, kept |

### Placing it

- Only on soil that can be planted (dirt or grass), or on a tile that already holds a furrow or a crop. One sensor per tile.
- Press **R** while placing to choose which corner of the tile the stake stands in.
- It shares its tile with pipes, drips, sprinklers, valves and gauges, and never stops a drip or sprinkler on its tile: it only measures.

### How it decides

- When the crop's moisture **drops to the minimum**, it gives a signal; when it **climbs to the maximum**, it stops. In between it keeps doing what it was doing, so the valve does not flicker open and shut around one value. The defaults are **80 %** and **95 %**.
- **Invert** swaps the ends: signal at the maximum, none at the minimum.
- With no crop on its tile or no power, it gives no signal.
- It checks every 10 in-game minutes. While nobody is near, it keeps its last signal until a player comes back.
- Its light shows the state: **green** = signal, **red** = no signal, **unlit** = no power.

### Power

It runs on the tile's electricity (grid or generator). Without it, it uses a Battery: right-click the sensor, **Open sensor**, and drag the battery into the battery slot (or click the slot to put in the fullest one you carry), as on a radio. A full battery lasts 30 in-game days by default (see [Sandbox settings](sandbox-settings.md#irrigation-and-town-water)) and only drains while the tile has no electricity. Right-click the slot to take it back with the charge it has left.

### Linking valves

1. Right-click the sensor and choose **Open sensor**. The window shows the reading, the signal and why, the power, the range, and the linked valves.
2. Set **Minimum** and **Maximum** (and **Invert** if you need it), then **Apply**.
3. Click **Link valves**. Valves around you are outlined: **green** can be linked, **yellow** is already linked (click it to unlink), **red** cannot be linked. The first time you link a valve you give it a name, shown in lists and tooltips.
4. Press **Esc** or right-click to finish.

A linked valve **opens while any of its sensors gives a signal** and closes when none does. One sensor can drive several valves, and several sensors can drive one valve. Your hand still wins: **Close valve** keeps it closed whatever the sensors say, and **Open valve** hands it back to them. The valve's tooltip says which sensors drive it and why it is closed.

In multiplayer, a valve inside a safehouse can only be linked by its members or an admin. The sandbox can limit how far a valve may be from its sensor (no limit by default).

### Moving and removing it

- **Pick up** moves it: its name, range and invert setting go with it; its battery goes to your inventory and its links are dropped.
- **Disassemble** with a Screwdriver returns its battery and some of its parts (Motion Sensor, Receiver and Electrical Wire usually; the Scrap Electronics less often). A destroyed sensor returns only its battery.

<!-- SCREENSHOT: 27-moisture-sensor.png — Soil Moisture Sensor in a crop row and its window with linked valves. -->
