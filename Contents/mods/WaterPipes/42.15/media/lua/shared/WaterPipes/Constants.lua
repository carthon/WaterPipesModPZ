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
Constants.PIPE_SURFACE_FLOOR = "floor"
Constants.PIPE_SURFACE_WALL = "wall"
Constants.PIPE_AXIS_EW = "ew"
Constants.PIPE_AXIS_NS = "ns"
-- Sprites exported by this mod's waterpipes tileset.
-- The current build cursor still exposes 4 placement modes only:
-- floor EW, floor NS, wall EW and wall NS.
-- Keep these IDs aligned with the sprites actually present in
-- media/texturepacks/waterpipes.pack.
Constants.PIPE_FLOOR_WEST_SPRITE = "waterpipes_01_24"
Constants.PIPE_FLOOR_NORTH_SPRITE = "waterpipes_01_25"
Constants.PIPE_WALL_WEST_SPRITE = "waterpipes_01_11"
Constants.PIPE_WALL_NORTH_SPRITE = "waterpipes_01_26"
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
