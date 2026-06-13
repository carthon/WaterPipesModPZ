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
-- Only top the tank up once it drops below this fraction of max fuel (then fill to max).
Constants.GENERATOR_REFUEL_THRESHOLD = 0.25
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
-- Floor connection sprites use vanilla industry_02 pipe tiles (idx 24-39, Material=Pipes).
-- Sprite name = "industry_02_" .. index. Index->connection mapping confirmed in TileZed.
Constants.PIPE_FLOOR_WEST_SPRITE = "industry_02_33"    -- R E/W (straight East-West)
Constants.PIPE_FLOOR_NORTH_SPRITE = "industry_02_32"   -- R N/S (straight North-South)
Constants.PIPE_WALL_WEST_SPRITE = "waterpipes_01_24"   -- riser still ours (vanilla vertical = idx 34, TODO)
Constants.PIPE_WALL_NORTH_SPRITE = "waterpipes_01_25"  -- riser still ours (vanilla vertical = idx 34, TODO)
-- Floor auto-connect sprites. Directions: N=-y, E=+x, S=+y, W=-x.
Constants.PIPE_FLOOR_CORNER_NE_SPRITE = "industry_02_24"   -- L N/E
Constants.PIPE_FLOOR_CORNER_ES_SPRITE = "industry_02_25"   -- L S/E
Constants.PIPE_FLOOR_CORNER_SW_SPRITE = "industry_02_26"   -- L S/W
Constants.PIPE_FLOOR_CORNER_WN_SPRITE = "industry_02_27"   -- L N/W
Constants.PIPE_FLOOR_T_NOW_SPRITE = "industry_02_30"   -- T S/N/E (no West arm)
Constants.PIPE_FLOOR_T_NOE_SPRITE = "industry_02_28"   -- T S/N/W (no East arm)
Constants.PIPE_FLOOR_T_NOS_SPRITE = "industry_02_31"   -- T E/W/N (no South arm)
Constants.PIPE_FLOOR_T_NON_SPRITE = "industry_02_29"   -- T S/E/W (no North arm)
Constants.PIPE_FLOOR_CROSS_SPRITE = "industry_02_39"   -- cross
Constants.PIPE_FLOOR_END_W_SPRITE = "industry_02_36"   -- R W (short, West cap)
Constants.PIPE_FLOOR_END_N_SPRITE = "industry_02_35"   -- R N (short, North cap)
Constants.PIPE_FLOOR_END_E_SPRITE = "industry_02_37"   -- R E (short, East cap)
Constants.PIPE_FLOOR_END_S_SPRITE = "industry_02_38"   -- R S (short, South cap)
-- Wall risers: floor stub toward an edge + vertical climb. PZ tiles only have N and W walls
-- (S/E walls belong to the neighbouring tile), so risers exist only for the North and West walls.
Constants.PIPE_WALL_RISER_N_SPRITE = "waterpipes_01_24"
Constants.PIPE_WALL_RISER_W_SPRITE = "waterpipes_01_25"
Constants.PIPE_RISER_MODDATA_KEY = "waterpipesRiser"
Constants.PIPE_RISER_EDGE_MODDATA_KEY = "waterpipesRiserEdge"
-- Vertical pipe (vanilla industry_02): a vertical run with a floor elbow, keyed by the direction
-- of that floor connection. Occupies a whole tile (exclusive with floor pipes) and links the floor
-- network to the tile directly above. The connecting direction is auto-chosen from the adjacent
-- floor pipe; the sprite below is picked to match.
Constants.PIPE_VERTICAL_SPRITE = {
    E = "industry_02_76",
    S = "industry_02_77",
    N = "industry_02_78",
    W = "industry_02_79",
}
-- A vertical with no adjacent floor pipe (e.g. two verticals stacked) shows the plain vertical pipe
-- with no floor elbow.
Constants.PIPE_VERTICAL_DEFAULT_SPRITE = "industry_02_34"
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
