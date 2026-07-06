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
-- Purifier pipe nodes: a purifier is a floor pipe (part of the network like any pipe) that turns the
-- whole connected network's tainted water clean while it is "working". Three tiers, differing only in
-- what makes them work (see Purifier.lua): filter (spends a cartridge), fire (needs an adjacent lit
-- heat source), electric (needs power). The tier is baked in at build time (modData, synced).
Constants.PURIFIER_MODDATA_KEY = "waterpipesPurifier"       -- value = tier string below
Constants.PURIFIER_TIER_FILTER = "filter"
Constants.PURIFIER_TIER_FIRE = "fire"
Constants.PURIFIER_TIER_ELECTRIC = "electric"
Constants.PURIFIER_FILTER_CHARGES_KEY = "waterpipesFilterCharges"
Constants.PURIFIER_FILTER_MAX_CHARGES = 10                  -- charges a fresh cartridge provides
Constants.PURIFIER_CARTRIDGE_ITEM_TYPE = "Base.WaterFilterCartridge"
-- Placeholder sprites until the artist delivers dedicated purifier tiles (reserved atlas cells
-- 26/27/28). These are existing visible pack sprites so the tiles can be built/tested now; purifiers
-- are excluded from autotiling so they keep this fixed sprite. Swap these three + the entity face
-- rows in entity_water_pipe.txt when the real art is packed.
Constants.PURIFIER_FILTER_SPRITE = "waterpipes_01_10"
Constants.PURIFIER_FIRE_SPRITE = "waterpipes_01_11"
Constants.PURIFIER_ELECTRIC_SPRITE = "waterpipes_01_12"
-- Fluid router: a directional floor pipe that acts as a BOUNDARY between two separate networks (the
-- IN side and the OUT side never merge), bridged only through a container on its tile. Baked in at
-- build time (modData, synced). The IN->OUT direction is set later via the context menu (step 4).
Constants.ROUTER_MODDATA_KEY = "waterpipesRouter"
Constants.ROUTER_DIRECTION_KEY = "waterpipesRouterDir"   -- "N"/"E"/"S"/"W" = the OUT side (step 4)
Constants.ROUTER_SPRITE = "waterpipes_01_13"             -- placeholder until the arrow art is packed
Constants.ADAPTER_SOURCE_SPRITE = "carpentry_02_54"
Constants.ADAPTER_SOURCE_HIDDEN_SPRITE = "waterpipes_01_20"
Constants.MAX_FINITE_FLUID_CAPACITY = 9999

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
