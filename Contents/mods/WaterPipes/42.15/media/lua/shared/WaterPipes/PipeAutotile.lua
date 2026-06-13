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

-- Cardinal directions with their letter, for orienting a vertical pipe toward its adjacent floor
-- pipe (the vanilla vertical sprites carry the floor elbow in one direction).
local VDIRS = {
    { name = "N", dx = 0, dy = -1 },
    { name = "E", dx = 1, dy = 0 },
    { name = "S", dx = 0, dy = 1 },
    { name = "W", dx = -1, dy = 0 },
}

-- A same-floor neighbour connects to a floor pipe if it holds a floor pipe OR a vertical pipe
-- (the vertical's floor elbow joins the network on its own tile).
local function neighbourConnects(square)
    return square ~= nil
        and (getFloorPipeOnSquare(square) ~= nil or PipeObjectUtils.hasVerticalOnSquare(square))
end

-- Pick out the floor pipe and the vertical pipe on a square (at most one of each).
local function classifyOnSquare(square)
    local floor, vertical
    if square then
        for _, obj in ipairs(PipeObjectUtils.getPipeObjectsOnSquare(square)) do
            if PipeObjectUtils.isVertical(obj) then
                vertical = vertical or obj
            elseif PipeObjectUtils.getPipePlacement(obj).surface == Constants.PIPE_SURFACE_FLOOR then
                floor = floor or obj
            end
        end
    end
    return floor, vertical
end

-- LOCAL cosmetic sprite change only -- never transmitted. Other clients recompute their own.
local function applySprite(worldObject, sprite)
    if not worldObject or not sprite or spriteName(worldObject) == sprite then
        return
    end
    pcall(worldObject.setSprite, worldObject, sprite)
    local sq = worldObject.getSquare and worldObject:getSquare() or nil
    if sq and sq.RecalcProperties then
        pcall(sq.RecalcProperties, sq)
    end
end

-- Bitmask of connected directions: cardinal neighbours (same floor) holding a floor or vertical pipe.
function PipeAutotile.computeMask(x, y, z)
    local present = {}
    for _, dir in ipairs(DIRS) do
        if neighbourConnects(getSquare(x + dir.dx, y + dir.dy, z)) then
            present[dir.bit] = true
        end
    end

    local mask = 0
    for bit in pairs(present) do
        mask = mask + bit
    end
    return mask
end

-- Recompute and apply the connecting sprite of the pipe(s) on one square: floor pipe (auto-connect
-- mask), vertical (floor elbow oriented toward an adjacent floor pipe), or cap (fixed sprite).
function PipeAutotile.refreshFloorPipeAt(x, y, z)
    if not isRenderingSide() then
        return
    end

    local floor, vertical = classifyOnSquare(getSquare(x, y, z))

    -- Vertical: orient the floor elbow toward the first adjacent floor pipe; if there is none
    -- (e.g. a vertical stacked on another vertical), show the plain vertical with no elbow.
    if vertical then
        local sprite = Constants.PIPE_VERTICAL_DEFAULT_SPRITE
        for _, dir in ipairs(VDIRS) do
            if getFloorPipeOnSquare(getSquare(x + dir.dx, y + dir.dy, z)) then
                sprite = Constants.PIPE_VERTICAL_SPRITE[dir.name] or sprite
                break
            end
        end
        applySprite(vertical, sprite)
    end

    -- Floor pipe: auto-connect mask (counts adjacent floor pipes and verticals).
    if floor then
        local mask = PipeAutotile.computeMask(x, y, z)
        local sprite
        if mask == 0 then
            -- Isolated: keep the orientation the player placed it in.
            local placement = PipeObjectUtils.getPipePlacement(floor)
            sprite = placement.axis == Constants.PIPE_AXIS_NS
                and Constants.PIPE_FLOOR_NORTH_SPRITE
                or Constants.PIPE_FLOOR_WEST_SPRITE
        else
            sprite = MASK_SPRITE[mask]
        end
        applySprite(floor, sprite)
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
