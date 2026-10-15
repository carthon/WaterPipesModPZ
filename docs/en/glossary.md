# Glossary

This page explains the terms used throughout the guide, for readers who have never played Project Zomboid or used mods. Words in **bold** inside a definition have their own entry.

## The game

### Project Zomboid { #project-zomboid }
A survival game set in a zombie-infested world. You scavenge food, water, and materials, and build and maintain your own base. A few weeks into a game the town's water and power are cut (see **utility shutoff**), and from then on water becomes a real problem.

### Build 42 { #build-42 }
The game version this mod requires. "Build" is the developers' name for each major version; Water Pipes needs 42.15 or newer.

### Mod { #mod }
A community-made addition to the game. Water Pipes is a mod: it has to be enabled before you start or load a game.

### Sandbox settings { #sandbox-settings }
When you create a custom game ("Custom Sandbox") you can change many simulation rules. Those rules are the **sandbox settings**, and they are saved with the game. This mod's settings are in the **Water Pipes** group. See [Sandbox settings](sandbox-settings.md).

### Tile { #tile }
The game map is divided into equal squares, like a board. Each square is a tile. A tile holds one floor pipe, and most objects occupy a single tile.

### Floor { #floor }
Each storey of a building. The ground floor is at street level, and each floor adds about 3 metres of height, which is what gives water its pressure (see **pressure**).

### Right-click and context menu { #right-click }
Almost every action in the game starts with a right-click on an object: a list of options (the context menu) appears and you pick one. In this guide, option names appear in **bold**, exactly as the game shows them.

### Recipe { #recipe }
What it takes to build something: materials, tools and sometimes a minimum **skill** level. Materials are used up. Some tools, like the Pipe Wrench, only need to be carried; others, like the Welding Torch, spend part of their charge.

### Skill and XP { #skill }
Your character improves at each trade (Electrical, Welding, Agriculture, Blacksmithing…) by practising it. Experience is counted in XP, and enough XP raises the level. Some recipes require a minimum level.

### Building menu { #building-menu }
The game window where you choose things to build. Everything Water Pipes adds is in its **Piping** category.

### Utility shutoff { #utility-shutoff }
When a game starts the town still has running water and electricity. After a while (configurable in the sandbox settings) both are cut for good. From that day on, any water you have not stored or drawn from a well or river is gone.

### Tainted water { #tainted-water }
Water that makes you sick if you drink it untreated: river and lake water, rain caught in uncovered containers, or water that has stood still too long. Mixing it with clean water taints all of it. In this mod only the **purifier** makes it safe again (unless realistic purification is turned off).

### Generator { #generator }
A petrol machine that provides electricity once the town's power is gone. Water Pipes can refill its fuel tank through pipes.

### Steam Workshop { #steam-workshop }
The part of Steam where mods are published and downloaded. Water Pipes lives there under ID 3739595559.

### Multiplayer, server and client { #multiplayer }
In a multiplayer game the **server** is the computer that keeps the world and decides what happens in it; each connected player is a **client**. That is why some actions take a moment: the server checks them before applying them.

## The mod

### Network { #network }
A set of pipes plus everything connected to them with nothing cutting them apart: containers, components, fixtures and generators. Everything on one network shares its water as if it were one big container. A closed **shut-off valve**, a **router**, or simply a tile with no pipe splits a network in two.

### Pipe { #pipe }
The basic piece of the mod. It is built on a tile's floor and joins its neighbours automatically, forming straights, corners and crossings. It is not a component: components sit on top of pipes or next to them.

### Vertical pipe { #vertical-pipe }
A pipe running up or down a north or west wall to join the pipes of two floors.

### Concealed pipe { #concealed-pipe }
A pipe that works like a normal one but becomes invisible once built, as if it were embedded in the floor or wall. **Show pipe network** reveals it.

### Component { #component }
Anything the mod builds except pipes: Water Pump, Pressure Gauge, Fluid Router, Shut-off Valve, purifier, Drip Emitter and Sprinkler. See the [reference](component-reference.md).

### Fixture { #fixture }
A world object that uses water: sink, washbasin, shower, bathtub, toilet or washing machine. The mod does not build fixtures; they already exist in houses or you build them with the base game. The mod connects them to a network with the **Plumb** action. Some windows call them "Water Fixture".

### Plumb and Unplumb { #plumb }
A base-game action (not one added by the mod) that connects a fixture or a generator to the pipe underneath it. It appears as **Plumb** followed by the object's name, for example "Plumb Generator". **Unplumb** disconnects it without removing the pipe. You need a Pipe Wrench.

### Container { #container }
Any object that stores liquid on a network: barrel, rain collector barrel, amphora, tank, or compatible modded containers. A container joins the network as soon as a pipe sits on its own tile.

### Source { #source }
Where water entering a network comes from: a container with water, a well or river (through a pump), town mains, or a fire hydrant.

### Town mains { #town-mains }
The town's running water. Until the utility shutoff, a plumbed fixture inside a house can feed that water into your network, with pressure and for free.

### Fire hydrant { #fire-hydrant }
The red street hydrant. With a pipe on its tile and opened with a Pipe Wrench, it feeds your network at high pressure; after the shutoff it still holds a limited reserve.

### Show pipe network { #show-pipe-network }
A right-click option on any pipe. For a few seconds it colours the whole network: pipes red, containers and sources green, fixtures blue, and routers with a pressure limit amber. It is the best way to check what is and is not connected.

### Pressure (metres of head) { #pressure }
How strongly water arrives. The mod measures it in metres (m), as real plumbing does: 1 m is the pressure a 1-metre-tall column of water would make. That is why raising a container one floor (about 3 m) adds 3 m of pressure. Below zero no water comes out; too much bursts some components (drip emitters).

### Upstream and downstream { #upstream }
Positions along the direction the water flows. Upstream is earlier, nearer the source; downstream is later, where the water is heading.

### Shared demand { #shared-demand }
When several consumers draw through the same stretch of pipe, that stretch loses more pressure. That is why the sprinklers at the end of a long line can run dry while the first ones work fine.

### Water Pump { #pump }
An electric component that adds pressure to its whole network. Placed beside a well, river or lake it also draws water from it. It stores nothing: the network still needs at least one container.

### Suction { #suction }
How far below itself a pump can draw water from: 7 m (about two floors) by default.

### Fluid Router { #router }
A component that lets water through in one direction only, from its green side (IN) to its red side (OUT), and can also cap the pressure going out. It has nothing to do with an internet router: in real plumbing it would be a check valve with a pressure reducer.

### Shut-off Valve { #shut-off-valve }
A component that, when closed, splits a network into two independent parts. Open, it changes nothing.

### Pressure Gauge { #pressure-gauge }
A component that shows the pressure on its tile.

### Water Purifier { #purifier }
An electric component that turns tainted water into clean water. It sits on a router, and its filter wears with use.

### Drip Emitter and Sprinkler { #drip-emitter }
Irrigation components. The drip emitter waters the crop on its own tile with little pressure. The sprinkler waters a 3×3 square but needs a lot of pressure.

### Unit { #unit }
Some mod windows (purifier, router) show amounts in "u" or "units". One unit is one litre.

### Plumb this building { #plumb-this-building }
The mod action that reveals the hidden plumbing of a building that came with the map (not one you built). See [Inspecting a building's plumbing](building-plumbing.md).
