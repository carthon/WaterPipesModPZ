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
