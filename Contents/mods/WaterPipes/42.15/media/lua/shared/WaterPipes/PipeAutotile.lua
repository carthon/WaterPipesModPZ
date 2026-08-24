WaterPipes = WaterPipes or {}
WaterPipes.PipeAutotile = WaterPipes.PipeAutotile or {}

require "WaterPipes/Constants"
require "WaterPipes/Logger"
require "WaterPipes/PipeObjectUtils"
require "WaterPipes/Router"

local Constants = WaterPipes.Constants
local Logger = WaterPipes.Logger
local PipeObjectUtils = WaterPipes.PipeObjectUtils
local Router = WaterPipes.Router
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

-- Connection sprites are purely cosmetic: each client derives them locally from the pipes it can see
-- and they are NEVER transmitted. So autotiling runs on every side that renders a screen -- a co-op
-- host included, since it renders its own game. The only side skipped is a headless/dedicated server.
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

local function modDataOf(worldObject)
    return worldObject and worldObject.getModData and worldObject:getModData() or nil
end

local function isHidden(worldObject)
    local modData = modDataOf(worldObject)
    return modData and modData[Constants.PIPE_HIDDEN_MODDATA_KEY] == true or false
end

local function isRiser(worldObject)
    local modData = modDataOf(worldObject)
    return modData and modData[Constants.PIPE_RISER_MODDATA_KEY] == true or false
end

-- Fixed sprite for the pipe variant that REPLACES its tile art outright: the pump, which is a whole
-- machine rather than a fitting. One E/W and one N/S cell, so the build axis picks it and the neighbour
-- mask is irrelevant. Read straight from modData, to keep this file free of requires it does not need.
local DEVICE_SPRITES = {
    [Constants.PUMP_MODDATA_KEY] = { ew = Constants.PUMP_SPRITE_EW, ns = Constants.PUMP_SPRITE_NS },
}

local function deviceSprite(worldObject)
    local modData = modDataOf(worldObject)
    if not modData then
        return nil
    end
    for key, sprites in pairs(DEVICE_SPRITES) do
        if modData[key] == true then
            return modData[Constants.PIPE_AXIS_MODDATA_KEY] == Constants.PIPE_AXIS_NS
                and sprites.ns or sprites.ew
        end
    end
    return nil
end

-- Emitters are a HEAD that sits ON the pipe, not a replacement for it: the pipe below keeps autotiling
-- and the head rides on top as the engine's overlay sprite, the same route vanilla paints a sign onto a
-- wall. Two cells per emitter so a later art drop can give each facing its own head.
local EMITTER_OVERLAYS = {
    [Constants.DRIP_MODDATA_KEY] = { ew = Constants.DRIP_SPRITE_EW, ns = Constants.DRIP_SPRITE_NS },
    [Constants.SPRINKLER_MODDATA_KEY] = { ew = Constants.SPRINKLER_SPRITE_EW, ns = Constants.SPRINKLER_SPRITE_NS },
}

local function emitterOverlay(worldObject)
    local modData = modDataOf(worldObject)
    if not modData then
        return nil
    end
    for key, sprites in pairs(EMITTER_OVERLAYS) do
        if modData[key] == true then
            return modData[Constants.PIPE_AXIS_MODDATA_KEY] == Constants.PIPE_AXIS_NS
                and sprites.ns or sprites.ew
        end
    end
    return nil
end

-- Apply a sprite to a pipe only if it changed (client-cosmetic: never transmitted).
local function setSpriteIfChanged(worldObject, sprite)
    if not sprite or spriteName(worldObject) == sprite then
        return
    end
    pcall(worldObject.setSprite, worldObject, sprite)
    local square = worldObject.getSquare and worldObject:getSquare() or nil
    if square and square.RecalcProperties then
        pcall(square.RecalcProperties, square)
    end
end

-- Paint (or clear) the emitter head riding on top of a pipe. "Cleared" is our own transparent cell
-- rather than a nil sprite, which vanilla never passes from Lua. Deliberately NOT folded into
-- setSpriteIfChanged, which early-returns on an unchanged pipe shape and would then skip the head.
local function setOverlayIfChanged(worldObject, sprite)
    if not worldObject or not worldObject.setOverlaySprite then
        return
    end
    sprite = sprite or Constants.PIPE_HIDDEN_SPRITE
    local current = worldObject.getOverlaySprite and worldObject:getOverlaySprite() or nil
    local currentName = current and current.getName and current:getName() or nil
    if currentName == sprite then
        return
    end
    pcall(worldObject.setOverlaySprite, worldObject, sprite)
end

-- The fixed sprite a wall riser should show given its edge (N/W).
local function riserSprite(worldObject)
    local modData = modDataOf(worldObject)
    local edge = modData and modData[Constants.PIPE_RISER_EDGE_MODDATA_KEY]
    return edge == "W" and Constants.PIPE_WALL_RISER_W_SPRITE or Constants.PIPE_WALL_RISER_N_SPRITE
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

-- A PZ wall is the N or W edge of a tile and is SHARED with the neighbour across it, so a wall cover
-- must connect floor pipes on BOTH sides of it. Covers on the floor below (risers climbing up) connect
-- to the floor pipe above too.
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

-- The connecting floor sprite the pipe at (x,y,z) should show based on its neighbours. Isolated
-- pipes keep the orientation the player placed them in.
local function floorConnectionSprite(pipe, x, y, z)
    local mask = PipeAutotile.computeMask(x, y, z)
    if mask == 0 then
        local placement = PipeObjectUtils.getPipePlacement(pipe)
        return placement.axis == Constants.PIPE_AXIS_NS
            and Constants.PIPE_FLOOR_NORTH_SPRITE
            or Constants.PIPE_FLOOR_WEST_SPRITE
    end
    return MASK_SPRITE[mask]
end

-- A wall riser is never autotiled: paint it transparent when concealed, else its fixed edge sprite.
local function refreshRiserVisibility(pipe)
    if not isRiser(pipe) then
        return
    end
    setSpriteIfChanged(pipe, isHidden(pipe) and Constants.PIPE_HIDDEN_SPRITE or riserSprite(pipe))
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

    -- Concealed floor pipes render transparent, but still count as a floor connection for
    -- neighbours (getFloorPipeOnSquare finds them by modData, not by sprite).
    if isHidden(pipe) then
        setSpriteIfChanged(pipe, Constants.PIPE_HIDDEN_SPRITE)
        setOverlayIfChanged(pipe, nil)   -- a concealed emitter hides its head too
        return
    end

    -- Risers keep their fixed (manual) sprite; they still count as a floor connection
    -- for neighbouring pipes (handled in getFloorPipeOnSquare), but we never repaint them.
    if isRiser(pipe) then
        return
    end

    -- Routers keep a fixed device sprite (the IN->OUT band) and never autotile.
    if Router.isRouter(pipe) then
        setSpriteIfChanged(pipe, Router.spriteFor(pipe))
        setOverlayIfChanged(pipe, nil)
        return
    end

    -- The pump keeps a fixed sprite chosen by its build axis: it is a whole machine, so it replaces
    -- the pipe art rather than sitting on it. It still conducts and still counts as a floor
    -- connection for its neighbours -- only its own sprite is pinned.
    local device = deviceSprite(pipe)
    if device then
        setSpriteIfChanged(pipe, device)
        setOverlayIfChanged(pipe, nil)
        return
    end

    -- Ordinary pipe, or a pipe carrying an emitter: either way the pipe autotiles to its neighbours,
    -- and the emitter head (if any) is painted on top of that shape instead of replacing it.
    setSpriteIfChanged(pipe, floorConnectionSprite(pipe, x, y, z))
    setOverlayIfChanged(pipe, emitterOverlay(pipe))
end

-- Refresh a square, its 4 cardinal neighbours, and the floors above/below (a wall cover can
-- affect floor pipes on either side of its wall and on the floor it climbs to). Also fixes the
-- visibility of any riser on the centre square (risers aren't touched by the floor autotile).
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

    local center = getSquare(x, y, z)
    if center then
        for _, pipe in ipairs(PipeObjectUtils.getPipeObjectsOnSquare(center)) do
            refreshRiserVisibility(pipe)
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
        local square = getSquare(pipeData.x, pipeData.y, pipeData.z)
        if square then
            for _, pipe in ipairs(PipeObjectUtils.getPipeObjectsOnSquare(square)) do
                refreshRiserVisibility(pipe)
            end
        end
    end
end

-- ===== Concealed-pipe visibility (used by the network visualization) =====

function PipeAutotile.isPipeHidden(pipe)
    return isHidden(pipe)
end

-- Temporarily show a concealed pipe's REAL sprite (does NOT clear the hidden flag). Used so the
-- "Show pipe network" overlay has something to outline and the pipe is briefly visible.
function PipeAutotile.revealPipe(pipe)
    if not pipe then
        return
    end
    local square = pipe.getSquare and pipe:getSquare() or nil
    if not square then
        return
    end
    if isRiser(pipe) then
        setSpriteIfChanged(pipe, riserSprite(pipe))
    else
        setSpriteIfChanged(pipe, floorConnectionSprite(pipe, square:getX(), square:getY(), square:getZ()))
        setOverlayIfChanged(pipe, emitterOverlay(pipe))
    end
end

-- Restore a concealed pipe to transparent after the visualization ends.
function PipeAutotile.rehidePipe(pipe)
    if not isHidden(pipe) then
        return
    end
    if isRiser(pipe) then
        refreshRiserVisibility(pipe)
    else
        setSpriteIfChanged(pipe, Constants.PIPE_HIDDEN_SPRITE)
        setOverlayIfChanged(pipe, nil)
    end
end

-- ===== Client-driven triggers =====
-- Each client recomputes pipe sprites from its OWN world view, so synced pipes get the right connecting
-- sprite without the shape ever crossing the network.

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

-- Chunk streamed in / joined a server: repaint any pipe on the loaded square (floor connection +
-- riser/concealed visibility).
local function onLoadGridsquare(square)
    if not isRenderingSide() or not square then
        return
    end
    PipeAutotile.refreshFloorPipeAt(square:getX(), square:getY(), square:getZ())
    for _, pipe in ipairs(PipeObjectUtils.getPipeObjectsOnSquare(square)) do
        refreshRiserVisibility(pipe)
    end
end

if Events then
    if Events.OnObjectAdded then Events.OnObjectAdded.Add(onPipeObjectAdded) end
    if Events.OnObjectAboutToBeRemoved then Events.OnObjectAboutToBeRemoved.Add(onPipeObjectRemoved) end
    if Events.OnTick then Events.OnTick.Add(onTickProcessPending) end
    if Events.LoadGridsquare then Events.LoadGridsquare.Add(onLoadGridsquare) end
end
