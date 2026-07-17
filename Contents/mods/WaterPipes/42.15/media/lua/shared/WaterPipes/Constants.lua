WaterPipes = WaterPipes or {}
WaterPipes.Constants = WaterPipes.Constants or {}

local Constants = WaterPipes.Constants

Constants.MOD_DATA_KEY = "WaterPipes"
Constants.STATE_VERSION = 1

Constants.NODE_KIND_PIPE = "pipe"
Constants.NODE_KIND_CONTAINER = "container"

Constants.REDISTRIBUTION_INTERVAL_MINUTES = 10

Constants.PIPE_OBJECT_NAME = "Water Pipe"
Constants.PIPE_BUILD_ENTITY_NAME = "WaterPipe"
Constants.PIPE_BUILD_ENTITY_FULL_NAME = "WaterPipes.WaterPipe"
Constants.PIPE_ITEM_TYPE = "Base.Pipe"
Constants.PIPE_TOOL_TYPE = "Base.PipeWrench"
Constants.PIPE_MODDATA_KEY = "waterpipesPipe"
Constants.PIPE_SURFACE_MODDATA_KEY = "waterpipesSurface"
Constants.PIPE_AXIS_MODDATA_KEY = "waterpipesAxis"
Constants.PLUMBED_ENDPOINT_MODDATA_KEY = "waterpipesEndpointPlumbed"
Constants.PLUMBED_ENDPOINT_SOURCE_MODDATA_KEY = "waterpipesEndpointSource"
-- Snapshot of the endpoint's own FluidContainer before we overwrite it with the network mirror,
-- so we can restore the fixture to its original state on unplumb.
Constants.ENDPOINT_ORIGINAL_FLUID_KEY = "waterpipesEndpointOriginalFluid"

-- Generator fuel consumers: a plumbed generator pulls Petrol from the network into its tank.
Constants.GENERATOR_PLUMBED_MODDATA_KEY = "waterpipesGeneratorPlumbed"
Constants.GENERATOR_FUEL_FLUID = "Petrol"
-- Auto-refuel defaults (fractions of max fuel). Overridable PER-SAVE via Sandbox Options
-- (WaterPipes.GeneratorRefuelThreshold / GeneratorRefuelTarget); these remain the fallback.
Constants.GENERATOR_REFUEL_THRESHOLD = 0.25   -- start refuelling once fuel drops below this
Constants.GENERATOR_REFUEL_TARGET = 1.0       -- fill the tank up to this fraction
Constants.ADAPTER_SOURCE_MODDATA_KEY = "waterpipesAdapterSource"
Constants.ADAPTER_SOURCE_ENDPOINT_X_KEY = "waterpipesAdapterEndpointX"
Constants.ADAPTER_SOURCE_ENDPOINT_Y_KEY = "waterpipesAdapterEndpointY"
Constants.ADAPTER_SOURCE_ENDPOINT_Z_KEY = "waterpipesAdapterEndpointZ"
Constants.ADAPTER_SOURCE_ENDPOINT_INDEX_KEY = "waterpipesAdapterEndpointIndex"
Constants.ADAPTER_SOURCE_LAST_SYNC_AMOUNT_KEY = "waterpipesAdapterLastSyncAmount"
Constants.ADAPTER_SOURCE_OBJECT_NAME = "Water Pipes Adapter Source"
Constants.ADAPTER_SOURCE_MAX_CAPACITY = 600
-- Endpoint-owned FluidContainer mirror (replaces the hidden adapter object).
-- The plumbed endpoint (sink/tap) carries its own FluidContainer that mirrors the
-- connected network, so no phantom world object is needed.
Constants.ENDPOINT_FLUID_LAST_SYNC_KEY = "waterpipesEndpointLastSync"
Constants.ENDPOINT_FLUID_SYNCING_KEY = "waterpipesEndpointSyncing"
Constants.PIPE_SURFACE_FLOOR = "floor"
Constants.PIPE_SURFACE_WALL = "wall"
Constants.PIPE_SURFACE_WALLCOVER = "wallcover"   -- decorative vertical pipe drawn on a wall
Constants.PIPE_AXIS_EW = "ew"
Constants.PIPE_AXIS_NS = "ns"
-- Sprites exported by this mod's waterpipes tileset.
-- The current build cursor still exposes 4 placement modes only:
-- floor EW, floor NS, wall EW and wall NS.
-- Keep these IDs aligned with the sprites actually present in
-- media/texturepacks/waterpipes.pack.
Constants.PIPE_FLOOR_WEST_SPRITE = "waterpipes_01_8"   -- straight E/W
Constants.PIPE_FLOOR_NORTH_SPRITE = "waterpipes_01_9"  -- straight N/S
Constants.PIPE_WALL_WEST_SPRITE = "waterpipes_01_24"
Constants.PIPE_WALL_NORTH_SPRITE = "waterpipes_01_25"
-- Floor auto-connect sprites (generated tileset). Directions: N=-y, E=+x, S=+y, W=-x.
Constants.PIPE_FLOOR_CORNER_NE_SPRITE = "waterpipes_01_10"
Constants.PIPE_FLOOR_CORNER_ES_SPRITE = "waterpipes_01_11"
Constants.PIPE_FLOOR_CORNER_SW_SPRITE = "waterpipes_01_12"
Constants.PIPE_FLOOR_CORNER_WN_SPRITE = "waterpipes_01_13"
Constants.PIPE_FLOOR_T_NOW_SPRITE = "waterpipes_01_14"  -- T junction, no West arm
Constants.PIPE_FLOOR_T_NOE_SPRITE = "waterpipes_01_15"  -- T junction, no East arm
Constants.PIPE_FLOOR_T_NOS_SPRITE = "waterpipes_01_16"  -- T junction, no South arm
Constants.PIPE_FLOOR_T_NON_SPRITE = "waterpipes_01_17"  -- T junction, no North arm
Constants.PIPE_FLOOR_CROSS_SPRITE = "waterpipes_01_18"
Constants.PIPE_FLOOR_END_W_SPRITE = "waterpipes_01_19"
Constants.PIPE_FLOOR_END_N_SPRITE = "waterpipes_01_21"
Constants.PIPE_FLOOR_END_E_SPRITE = "waterpipes_01_22"
Constants.PIPE_FLOOR_END_S_SPRITE = "waterpipes_01_23"
-- Wall risers: floor stub toward an edge + vertical climb. PZ tiles only have N and W walls
-- (S/E walls belong to the neighbouring tile), so risers exist only for the North and West walls.
Constants.PIPE_WALL_RISER_N_SPRITE = "waterpipes_01_24"
Constants.PIPE_WALL_RISER_W_SPRITE = "waterpipes_01_25"
Constants.PIPE_RISER_MODDATA_KEY = "waterpipesRiser"
Constants.PIPE_RISER_EDGE_MODDATA_KEY = "waterpipesRiserEdge"
-- Concealed ("invisible") pipe variant: full network functionality, but rendered with a fully
-- transparent tile client-side. The flag is baked in at build time (modData, synced) and never
-- toggled at runtime, so no extra network sync is needed -- each client just paints it transparent.
Constants.PIPE_HIDDEN_MODDATA_KEY = "waterpipesHidden"
Constants.PIPE_HIDDEN_SPRITE = "waterpipes_01_20"   -- fully transparent tile in the tileset
-- Purifier: a NON-pipe tank placed on a router tile that turns the connected network's tainted water
-- clean while it is "working" (electric-only: the tile must have power). The tier is baked in at build
-- time (modData, synced). The legacy filter/fire tier strings are still recognised by getTier so old
-- saves keep working, but only the electric tier is buildable now.
Constants.PURIFIER_MODDATA_KEY = "waterpipesPurifier"       -- value = tier string below
Constants.PURIFIER_TIER_FILTER = "filter"
Constants.PURIFIER_TIER_FIRE = "fire"
Constants.PURIFIER_TIER_ELECTRIC = "electric"
-- Filter condition (maintenance): the carbon/cloth filter medium wears out with USE, not idle time.
-- Every unit of tainted water actually converted to clean spends FILTER_WEAR_PER_UNIT of condition.
-- At 0 the purifier can no longer clean tainted water (clean water still passes) until it is repaired
-- (Charcoal + RippedSheets). Condition lives in the anchor's modData, server-authoritative, synced.
Constants.PURIFIER_FILTER_CONDITION_KEY = "waterpipesFilterCondition"
Constants.PURIFIER_FILTER_MAX_CONDITION = 100              -- % scale; a fresh/repaired filter starts here
-- Base wear per unit of tainted water filtered. Scaled PER-SAVE by the Sandbox Option
-- WaterPipes.PurifierFilterWear (percentage: 100 = this base, 0 = never wears); this stays the fallback.
Constants.PURIFIER_FILTER_WEAR_PER_UNIT = 0.02            -- % lost per unit of tainted water filtered
Constants.PURIFIER_FILTER_WARN_CONDITION = 25             -- UI turns amber at/below this (repair soon)
-- Repair kit: consumed by the "Repair Filter" timed action to restore condition to MAX.
Constants.PURIFIER_REPAIR_ITEMS = {
    { type = "Base.Charcoal", count = 1 },
    { type = "Base.RippedSheets", count = 2 },
}
Constants.PURIFIER_REPAIR_TIME = 150                       -- timed-action ticks (build is 200)
-- Purifier-container is a NON-pipe object placed on a router tile. It holds two internal buffers
-- (modData): IN (tainted intake) and OUT (clean output). The router drives intake -> convert -> output.
Constants.PURIFIER_IN_AMOUNT_KEY = "waterpipesPurIn"
Constants.PURIFIER_IN_TAINTED_KEY = "waterpipesPurInTainted"
Constants.PURIFIER_OUT_AMOUNT_KEY = "waterpipesPurOut"
Constants.PURIFIER_BUFFER_CAPACITY = 50
-- Rates are per IN-GAME MINUTE (the server sub-steps them by elapsed game-time each tick, so throughput
-- is the same whatever the framerate). Intake is FASTER than convert/output on purpose: the IN buffer
-- fills faster than the filter processes it, so it visibly holds a level instead of draining to 0.
Constants.PURIFIER_INTAKE_RATE = 20
Constants.PURIFIER_CONVERT_RATE = 10
Constants.PURIFIER_OUTPUT_RATE = 10
-- Electric purifier tank: a 2x2 multi-tile object. The vanilla industry_02 cylinder is split into
-- four perspective quadrants (industry 72/73/74/75), tinted electric-blue and packed into atlas
-- cells 36-39. The entity script (WaterPurifierElectric, face S) lays them on the footprint:
--   (0,0) top->36   (1,0) right->37   (0,1) left->39   (1,1) body/front->38
Constants.PURIFIER_TANK_TOP_SPRITE = "waterpipes_01_36"    -- industry 74, back tile (0,0)
Constants.PURIFIER_TANK_RIGHT_SPRITE = "waterpipes_01_37"  -- industry 75, tile (1,0)
Constants.PURIFIER_TANK_LEFT_SPRITE = "waterpipes_01_39"   -- industry 72, tile (0,1)
Constants.PURIFIER_TANK_BODY_SPRITE = "waterpipes_01_38"   -- industry 73, front tile (1,1)
-- The anchor/front body sprite doubles as the purifier's identity sprite.
Constants.PURIFIER_ELECTRIC_SPRITE = Constants.PURIFIER_TANK_BODY_SPRITE
-- Fluid router: a directional floor pipe that acts as a BOUNDARY between two separate networks (the
-- IN side and the OUT side never merge), bridged only through a container on its tile. Baked in at
-- build time (modData, synced). The IN->OUT direction is set later via the context menu (step 4).
Constants.ROUTER_MODDATA_KEY = "waterpipesRouter"
Constants.ROUTER_DIRECTION_KEY = "waterpipesRouterDir"   -- "N"/"E"/"S"/"W" = the OUT side
Constants.ROUTER_SPRITE = "waterpipes_01_13"             -- placeholder until the arrow art is packed
Constants.ROUTER_DEFAULT_DIRECTION = "N"
Constants.ROUTER_TRANSFER_RATE = 30                      -- max fluid units moved IN->OUT per minute tick
Constants.ADAPTER_SOURCE_SPRITE = "carpentry_02_54"
Constants.ADAPTER_SOURCE_HIDDEN_SPRITE = "waterpipes_01_20"
Constants.MAX_FINITE_FLUID_CAPACITY = 9999

-- ===== Pressure model =====
-- Pressure is measured in METRES OF WATER COLUMN (m.c.a.), the unit real irrigation uses:
-- 1 m.c.a. = 0.098 bar. Municipal mains run 20-40, a garden sprinkler needs ~20, gravity drip
-- works at 1-2. Keeping the unit real means every constant below can be sanity-checked against
-- a plumbing table instead of being a made-up number.
--
-- The pressure a source delivers to a consumer is:
--     P = CONTAINER_BASE_PRESSURE
--       + PRESSURE_PER_LEVEL * (z_source - z_consumer)     -- falling gains, climbing costs
--       - friction(consumer) * hops                        -- distance always costs
--
-- The elevation term telescopes (it depends only on the endpoints, not the route), so the only
-- path-dependent term is friction, which is uniform per hop. Minimising loss is therefore just
-- minimising hop count -- the existing BFS with a distance counter, no Dijkstra needed. This
-- stops holding once pumps add head at a node (they break the telescoping); see the pump phase.
Constants.PRESSURE_PER_LEVEL = 3.0          -- a PZ floor is ~2.4-3 m tall; 1 m of water = 0.098 bar
Constants.CONTAINER_BASE_PRESSURE = 1.0     -- a full ~1 m tall barrel pushes 1 m.c.a. at its base
-- Friction scales with flow squared (Darcy-Weisbach), so a barely-open tap loses far less head per
-- tile than a sprinkler running wide open. Modelling that is what keeps existing bases alive: a tap
-- reaches 20 tiles on the flat (1.0 / 0.05), where one flat rate would have cut it to 5.
Constants.PRESSURE_FRICTION_DRIP = 0.02     -- trickle flow
Constants.PRESSURE_FRICTION_TAP = 0.05      -- taps, generators: low flow
Constants.PRESSURE_FRICTION_SPRINKLER = 0.2 -- wide-open flow through scavenged pipe
-- Minimum pressure a consumer needs to draw at all.
Constants.PRESSURE_MIN_TAP = 0.0
Constants.PRESSURE_MIN_DRIP = 0.0
Constants.PRESSURE_MIN_SPRINKLER = 20.0     -- a real sprinkler head needs ~2 bar
-- Consumer kinds, used to pick a friction coefficient.
Constants.PRESSURE_KIND_TAP = "tap"
Constants.PRESSURE_KIND_DRIP = "drip"
Constants.PRESSURE_KIND_SPRINKLER = "sprinkler"
-- Sandbox PressureModel enum values (WaterPipes.PressureModel).
Constants.PRESSURE_MODEL_REALISTIC = 1      -- full model: height, distance, pumps
Constants.PRESSURE_MODEL_SIMPLE = 2         -- height only: no distance loss
Constants.PRESSURE_MODEL_OFF = 3            -- pre-pressure behaviour: pure gravity reachability

-- ===== Water pump =====
-- A pump is a pipe variant that needs power. Where you PUT it decides what it does, exactly like a
-- real self-priming surface pump:
--   * sitting on a pipe that already has water -> a booster; it just adds head.
--   * next to a well / open water / a container -> an extractor; it also injects fluid.
-- The asymmetry between the two numbers below is the real physics that makes one device do both
-- jobs: a surface pump can only SUCK water up about 7 m (atmospheric pressure caps it at 10.33 m,
-- ~7-8 m in practice) but can PUSH it 25 m and more. That is why deep wells use submersible pumps.
Constants.PUMP_MODDATA_KEY = "waterpipesPump"
Constants.PUMP_SPRITE_EW = "industry_02_52"   -- vanilla industry_02 machine, E/W axis
Constants.PUMP_SPRITE_NS = "industry_02_53"   -- ...and its N/S mirror
Constants.PUMP_HEAD = 25.0                  -- m.c.a. added; a domestic pressure set is ~2.5 bar
Constants.PUMP_SUCTION_LIMIT = 7.0          -- m.c.a. it can lift a source from below (~2 floors)
Constants.PUMP_INTAKE_RATE = 20             -- litres per in-game minute; a real pump does 33-50
-- Natural sources the extractor mode can tap. A well is a plain IsoObject carrying a FluidContainer
-- component (10 000 L of CLEAN water, refilled only by rain at RainFactor 0.1 -- so it is a big
-- reservoir, not an infinite tap). Open water is identified the way vanilla does it, by the floor
-- tile's `water` flag, and is infinite but TAINTED -- which is what gives the purifier a job.
Constants.WELL_SCRIPT_NAME = "Base.Well"
-- Both wells (10 000) and water tiles (10 000) sit above MAX_FINITE_FLUID_CAPACITY on purpose: they
-- must never join the network as ordinary containers, or rebalanceSummary would smear 10 000 L
-- across every pipe and the network would read as permanently full. The pump INJECTS from them at a
-- bounded rate instead, the same shape as the purifier's intake step.

-- ===== Router pressure regulator =====
-- A router already splits the network in two, so pressure cannot cross it either. That makes it the
-- natural place to REGULATE: the player sets a ceiling and the OUT-side zone runs at it.
-- It can only ever reduce (P_out = min(P_in, setting)) -- exactly what a real pressure-reducing
-- valve does, and the reason a router can never replace a pump.
Constants.ROUTER_PRESSURE_KEY = "waterpipesRouterPressure"
Constants.ROUTER_PRESSURE_UNSET = -1        -- "no ceiling": pass the incoming head through untouched
Constants.ROUTER_PRESSURE_MAX = 100         -- ceiling the context menu offers
Constants.ROUTER_PRESSURE_STEP = 5          -- granularity of the context-menu options

-- ===== Irrigation =====
-- Both emitters are PIPE variants: they sit on the line, conduct water onward, and water as it
-- passes. Chaining them along a furrow is exactly what real drip tape is.
--
-- Vanilla farming numbers this is built on (all verified against B42 source):
--   * a crop's waterLvl runs 0-100; one "use" adds 10 and costs 200 mL = 0.2 network litres
--     (ZomboidGlobals.farmingFluidContainerMillilitresPerUse, shared/defines.lua)
--   * crops die only at waterLvl <= 0, and drain just 1 per 5 in-game hours by default
--   * rain only reaches crops with exterior == true -- INDOOR crops get nothing, which is the real
--     reason to build this
--   * tainted water waters crops exactly like clean water (ISFarmingMenu whitelists both)
Constants.DRIP_MODDATA_KEY = "waterpipesDrip"
Constants.DRIP_SPRITE_EW = "industry_02_20"   -- vanilla short pipe stub, E/W axis
Constants.DRIP_SPRITE_NS = "industry_02_21"   -- ...and its N/S mirror
Constants.DRIP_WATER_PER_HOUR = 10            -- waterLvl per in-game hour on its own tile
-- Real drip emitters are built for ~1-1.5 bar and blow out above that, which is why every real drip
-- line has a pressure regulator ahead of it. Over this head the emitter bursts: it stops watering
-- but still conducts, exactly like a spent purifier filter still passes clean water.
Constants.DRIP_BURST_PRESSURE = 15.0
Constants.DRIP_CONDITION_KEY = "waterpipesDripCondition"
Constants.DRIP_MAX_CONDITION = 100
Constants.DRIP_REPAIR_ITEMS = {
    { type = "Base.DuctTape", count = 1 },
}
Constants.DRIP_REPAIR_TIME = 80

Constants.SPRINKLER_MODDATA_KEY = "waterpipesSprinkler"
Constants.SPRINKLER_SPRITE_EW = "industry_02_26"   -- vanilla upright elbow: reads as a spray head
Constants.SPRINKLER_SPRITE_NS = "industry_02_24"
Constants.SPRINKLER_RADIUS = 1                     -- 1 = the 3x3 around it
Constants.SPRINKLER_WATER_PER_HOUR = 10            -- waterLvl per in-game hour, per covered tile
-- A sprinkler sprays the whole 3x3 whether or not there is a crop under it, so it wastes most of
-- what it draws. That inefficiency IS the balance: water cost alone can never balance irrigation
-- (crops drain far too slowly), so the drip-vs-sprinkler choice has to be paid for somewhere else.
Constants.SPRINKLER_WASTE_TILES = 9                -- litres are charged for all 9, crops or not
Constants.SPRINKLER_NOISE_RADIUS = 12              -- zombie attraction while running
Constants.SPRINKLER_NOISE_VOLUME = 8

-- Litres of network fluid per +1 waterLvl. 10 waterLvl = 1 use = 200 mL, so 1 waterLvl = 0.02 L.
Constants.IRRIGATION_LITRES_PER_WATER_LEVEL = 0.02
Constants.IRRIGATION_MAX_WATER_LEVEL = 100

-- ===== Pressure gauge =====
-- Pressure is otherwise an invisible number; this is the only way the player can see it.
Constants.GAUGE_MODDATA_KEY = "waterpipesGauge"
Constants.GAUGE_SPRITE_N = "industry_01_4"    -- vanilla vented wall box, North wall
Constants.GAUGE_SPRITE_W = "industry_01_5"    -- ...and the West wall mirror
Constants.GAUGE_READ_DISTANCE = 2             -- matches ISFluidUtil.isoMaxPanelDist

Constants.CARDINAL_OFFSETS = {
    { x = 1, y = 0, z = 0 },
    { x = -1, y = 0, z = 0 },
    { x = 0, y = 1, z = 0 },
    { x = 0, y = -1, z = 0 },
}

Constants.VERTICAL_OFFSETS = {
    { x = 0, y = 0, z = 1 },
    { x = 0, y = 0, z = -1 },
}

Constants.NETWORK_NEIGHBOR_OFFSETS = {
    { x = 1, y = 0, z = 0 },
    { x = -1, y = 0, z = 0 },
    { x = 0, y = 1, z = 0 },
    { x = 0, y = -1, z = 0 },
    { x = 0, y = 0, z = 1 },
    { x = 0, y = 0, z = -1 },
}
