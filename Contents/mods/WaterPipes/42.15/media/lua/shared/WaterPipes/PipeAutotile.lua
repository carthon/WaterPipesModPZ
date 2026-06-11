WaterPipes = WaterPipes or {}
WaterPipes.PipeAutotile = WaterPipes.PipeAutotile or {}

require "WaterPipes/Constants"
require "WaterPipes/Logger"
require "WaterPipes/PipeObjectUtils"

local Constants = WaterPipes.Constants
local Logger = WaterPipes.Logger
local PipeObjectUtils = WaterPipes.PipeObjectUtils
local PipeAutotile = WaterPipes.PipeAutotile

-- Direction bits and world offsets. Isometric mapping: E=+x, W=-x, S=+y, N=-y.
local N, E, S, W = 1, 2, 4, 8
local DIRS = {
    { bit = N, dx = 0, dy = -1 },
    { bit = E, dx = 1, dy = 0 },
    { bit = S, dx = 0, dy = 1 },
    { bit = W, dx = -1, dy = 0 },
}
local EDGE_BIT = { N = N, E = E, S = S, W = W }

-- Connected-neighbour mask (N=1,E=2,S=4,W=8) -> floor sprite name.
local MASK_SPRITE = {
    [N]            = Constants.PIPE_FLOOR_END_N_SPRITE,
    [E]            = Constants.PIPE_FLOOR_END_E_SPRITE,
    [S]            = Constants.PIPE_FLOOR_END_S_SPRITE,
    [W]            = Constants.PIPE_FLOOR_END_W_SPRITE,
    [N + S]        = Constants.PIPE_FLOOR_NORTH_SPRITE,   -- straight N/S
    [E + W]        = Constants.PIPE_FLOOR_WEST_SPRITE,    -- straight E/W
    [N + E]        = Constants.PIPE_FLOOR_CORNER_NE_SPRITE,
    [E + S]        = Constants.PIPE_FLOOR_CORNER_ES_SPRITE,
    [S + W]        = Constants.PIPE_FLOOR_CORNER_SW_SPRITE,
    [W + N]        = Constants.PIPE_FLOOR_CORNER_WN_SPRITE,
    [N + E + S]    = Constants.PIPE_FLOOR_T_NOW_SPRITE,
    [N + E + W]    = Constants.PIPE_FLOOR_T_NOS_SPRITE,
    [N + S + W]    = Constants.PIPE_FLOOR_T_NOE_SPRITE,
    [E + S + W]    = Constants.PIPE_FLOOR_T_NON_SPRITE,
    [N + E + S + W] = Constants.PIPE_FLOOR_CROSS_SPRITE,
}

-- Connection sprites are purely cosmetic: each client derives them locally from the pipes it can
-- see and they are NEVER transmitted (the server only tracks "is there a pipe on this tile"). So
-- autotiling runs on every side that renders a screen: single-player, a remote client, AND a co-op
-- host. A co-op host is isServer()==true but DOES render its own game, so it must autotile too --
-- the ONLY side we skip is a headless/dedicated server (no local player to render for).
local function isRenderingSide()
    if isServer and isServer() then
        return (isCoopHost and isCoopHost()) == true
    end
    return true
end

local function getSquare(x, y, z)
    if not getCell then
        return nil
    end
    local cell = getCell()
    if not cell or not cell.getGridSquare then
        return nil
    end
    return cell:getGridSquare(x, y, z)
end

local function getFloorPipeOnSquare(square, exclude)
    if not square then
        return nil
    end
    for _, worldObject in ipairs(PipeObjectUtils.getPipeObjectsOnSquare(square, exclude)) do
        if PipeObjectUtils.getPipePlacement(worldObject).surface == Constants.PIPE_SURFACE_FLOOR then
            return worldObject
        end
    end
    return nil
end

local function spriteName(worldObject)
    if worldObject.getSprite and worldObject:getSprite() and worldObject:getSprite().getName then
        return worldObject:getSprite():getName()
    end
    return nil
end

-- Set of wall-cover edges ("N"/"W") sitting on a square. PZ walls only exist on the N and W
-- edges of a tile, so a cover always has edge N or W.
local function getWallCoverEdgeSet(square)
    local edges = {}
    if not square then
        return edges
    end
    for _, worldObject in ipairs(PipeObjectUtils.getPipeObjectsOnSquare(square)) do
        local modData = worldObject.getModData and worldObject:getModData() or nil
        if modData and modData[Constants.PIPE_RISER_MODDATA_KEY] == true then
            local edge = modData[Constants.PIPE_RISER_EDGE_MODDATA_KEY]
            if edge == "N" or edge == "W" then
                edges[edge] = true
            end
        end
    end
    return edges
end

-- A PZ wall is the N or W edge of a tile and is SHARED with the neighbour across it, so a
-- wall cover must connect floor pipes on BOTH sides of that wall. Covers on the floor below
-- (risers climbing up) connect to the floor pipe above too. Adds the proper arm bits to
-- `present` for the floor pipe at (x,y,z).
local function addCoverArms(present, x, y, z)
    local function take(cx, cy, cz, map)
        local edges = getWallCoverEdgeSet(getSquare(cx, cy, cz))
        for edge, bit in pairs(map) do
            if edges[edge] then
                present[bit] = true
            end
        end
    end
    -- same floor: our own N/W walls, plus the shared walls owned by S and E neighbours
    take(x,     y,     z, { N = N, W = W })   -- own N / W wall
    take(x,     y + 1, z, { N = S })          -- south neighbour's N wall == our S edge
    take(x + 1, y,     z, { W = E })          -- east neighbour's W wall == our E edge
    -- floor below (riser climbing up to this tile)
    take(x,     y,     z - 1, { N = N, W = W })
    take(x,     y + 1, z - 1, { N = S })
    take(x + 1, y,     z - 1, { W = E })
end

-- Bitmask of connected directions: cardinal neighbours holding a floor pipe, PLUS every edge
-- where a wall cover sits (this floor or the floor below, either side of the shared wall).
function PipeAutotile.computeMask(x, y, z)
    local present = {}
    for _, dir in ipairs(DIRS) do
        local neighbor = getSquare(x + dir.dx, y + dir.dy, z)
        if neighbor and getFloorPipeOnSquare(neighbor) then
            present[dir.bit] = true
        end
    end
    addCoverArms(present, x, y, z)

    local mask = 0
    for bit in pairs(present) do
        mask = mask + bit
    end
    return mask
end

-- Recompute and apply the connecting sprite of the floor pipe on one square.
function PipeAutotile.refreshFloorPipeAt(x, y, z)
    if not isRenderingSide() then
        return
    end

    local square = getSquare(x, y, z)
    local pipe = getFloorPipeOnSquare(square)
    if not pipe then
        return
    end

    -- Risers keep their fixed (manual) sprite; they still count as a floor connection
    -- for neighbouring pipes (handled in getFloorPipeOnSquare), but we never repaint them.
    local modData = pipe.getModData and pipe:getModData() or nil
    if modData and modData[Constants.PIPE_RISER_MODDATA_KEY] == true then
        return
    end

    local mask = PipeAutotile.computeMask(x, y, z)
    local sprite
    if mask == 0 then
        -- Isolated: keep the orientation the player placed it in.
        local placement = PipeObjectUtils.getPipePlacement(pipe)
        sprite = placement.axis == Constants.PIPE_AXIS_NS
            and Constants.PIPE_FLOOR_NORTH_SPRITE
            or Constants.PIPE_FLOOR_WEST_SPRITE
    else
        sprite = MASK_SPRITE[mask]
    end

    if not sprite or spriteName(pipe) == sprite then
        return
    end

    -- LOCAL cosmetic change only -- never transmitted. Other clients recompute their own sprite.
    pcall(pipe.setSprite, pipe, sprite)
    local square2 = pipe.getSquare and pipe:getSquare() or nil
    if square2 and square2.RecalcProperties then
        pcall(square2.RecalcProperties, square2)
    end
end

-- Refresh a square, its 4 cardinal neighbours, and the floors above/below (a wall cover can
-- affect floor pipes on either side of its wall and on the floor it climbs to).
function PipeAutotile.refreshAround(x, y, z)
    if not isRenderingSide() then
        return
    end
    for dz = -1, 1 do
        PipeAutotile.refreshFloorPipeAt(x, y, z + dz)
        for _, dir in ipairs(DIRS) do
            PipeAutotile.refreshFloorPipeAt(x + dir.dx, y + dir.dy, z + dz)
        end
    end
end

-- Refresh every pipe in a given list (used internally / on migration).
function PipeAutotile.refreshList(pipes)
    if not isRenderingSide() or not pipes then
        return
    end
    for _, pipeData in pairs(pipes) do
        PipeAutotile.refreshFloorPipeAt(pipeData.x, pipeData.y, pipeData.z)
    end
end

-- ===== Client-driven triggers =====
-- Each client recomputes pipe sprites from its OWN world view, so synced pipes (built by other
-- players, or streamed in on chunk load) get the right connecting sprite without the shape ever
-- crossing the network.

local function squareOf(object)
    return object and object.getSquare and object:getSquare() or nil
end

local function onPipeObjectAdded(object)
    if not isRenderingSide() or not PipeObjectUtils.isPipeObject(object) then
        return
    end
    local square = squareOf(object)
    if square then
        PipeAutotile.refreshAround(square:getX(), square:getY(), square:getZ())
    end
end

-- On removal the object is still on the square, so defer the neighbour refresh one tick.
local pendingRefresh = {}
local function onPipeObjectRemoved(object)
    if not isRenderingSide() or not PipeObjectUtils.isPipeObject(object) then
        return
    end
    local square = squareOf(object)
    if square then
        pendingRefresh[#pendingRefresh + 1] = { x = square:getX(), y = square:getY(), z = square:getZ() }
    end
end

local function onTickProcessPending()
    if #pendingRefresh == 0 then
        return
    end
    local list = pendingRefresh
    pendingRefresh = {}
    for _, coord in ipairs(list) do
        PipeAutotile.refreshAround(coord.x, coord.y, coord.z)
    end
end

-- Chunk streamed in / joined a server: repaint any pipe on the loaded square.
local function onLoadGridsquare(square)
    if not isRenderingSide() or not square then
        return
    end
    PipeAutotile.refreshFloorPipeAt(square:getX(), square:getY(), square:getZ())
end

if Events then
    if Events.OnObjectAdded then Events.OnObjectAdded.Add(onPipeObjectAdded) end
    if Events.OnObjectAboutToBeRemoved then Events.OnObjectAboutToBeRemoved.Add(onPipeObjectRemoved) end
    if Events.OnTick then Events.OnTick.Add(onTickProcessPending) end
    if Events.LoadGridsquare then Events.LoadGridsquare.Add(onLoadGridsquare) end
end
