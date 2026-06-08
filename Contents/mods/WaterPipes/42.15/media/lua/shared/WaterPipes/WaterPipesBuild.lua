-- B42 entity build hooks for the Water Pipe buildables.
--
-- The pipes are placed through the native B42 entity build system (ISBuildIsoEntity), which is
-- multiplayer-safe: the engine validates on the server and runs :create() server-side. We only
-- supply two SpriteConfig hooks per entity:
--   OnIsValid(params) -> bool   (runs on client cursor AND server; pure validation)
--   OnCreate(params)            (runs inside :create(), i.e. on the server in MP; registers the pipe)
--
-- The hooks are referenced from the entity scripts by the dotted global path
-- "WaterPipesBuild.<fn>", so this table MUST be a global and must load before scripts are parsed.

require "WaterPipes/Constants"
require "WaterPipes/PipeObjectUtils"
require "WaterPipes/Logger"

WaterPipes = WaterPipes or {}
WaterPipes.Build = WaterPipes.Build or {}

local Constants = WaterPipes.Constants
local PipeObjectUtils = WaterPipes.PipeObjectUtils
local Logger = WaterPipes.Logger
local Build = WaterPipes.Build

-- The vertical pipe is a single rotatable entity: facing "w" -> West wall, anything else -> North.
local function edgeFromFacing(params)
    return (params and params.facing == "w") and "W" or "N"
end

local function getModData(worldObject)
    if worldObject and worldObject.getModData then
        local ok, modData = pcall(worldObject.getModData, worldObject)
        return ok and modData or nil
    end
    return nil
end

local function squareHasFloorPipe(square)
    if not square then
        return false
    end
    for _, worldObject in ipairs(PipeObjectUtils.getPipeObjectsOnSquare(square)) do
        if PipeObjectUtils.getPipePlacement(worldObject).surface == Constants.PIPE_SURFACE_FLOOR then
            return true
        end
    end
    return false
end

local function squareHasRiserEdge(square, edge)
    if not square then
        return false
    end
    for _, worldObject in ipairs(PipeObjectUtils.getPipeObjectsOnSquare(square)) do
        local modData = getModData(worldObject)
        if modData and modData[Constants.PIPE_RISER_MODDATA_KEY] == true
            and modData[Constants.PIPE_RISER_EDGE_MODDATA_KEY] == edge then
            return true
        end
    end
    return false
end

-- ===== OnIsValid (both sides) =====

-- One floor pipe per square (any orientation) -- they auto-connect.
function Build.floorOnIsValid(params)
    return not squareHasFloorPipe(params and params.square)
end

-- One riser per edge (N/W) per square; the edge follows the rotation (facing).
function Build.riserOnIsValid(params)
    return not squareHasRiserEdge(params and params.square, edgeFromFacing(params))
end

-- ===== OnCreate (server / single-player) =====

local function markAndRegister(thumpable, surface, riser, edge)
    if not thumpable then
        return
    end

    local modData = getModData(thumpable)
    if modData then
        modData[Constants.PIPE_MODDATA_KEY] = true
        modData[Constants.PIPE_SURFACE_MODDATA_KEY] = surface
        modData[Constants.PIPE_AXIS_MODDATA_KEY] = Constants.PIPE_AXIS_EW
        modData[Constants.PIPE_RISER_MODDATA_KEY] = riser and true or nil
        modData[Constants.PIPE_RISER_EDGE_MODDATA_KEY] = edge or nil
    end
    if thumpable.transmitModData then
        pcall(thumpable.transmitModData, thumpable)
    end

    local square = thumpable.getSquare and thumpable:getSquare() or nil
    if square and WaterPipes.System and WaterPipes.System.registerPipeAt then
        if riser then
            Logger.log(string.format("Placed vertical pipe (wall cover) edge=%s at %d:%d:%d",
                tostring(edge), square:getX(), square:getY(), square:getZ()))
        end
        -- registerPipeAt rebuilds the network, refreshes plumbed endpoints and runs the autotile.
        WaterPipes.System.registerPipeAt(square:getX(), square:getY(), square:getZ())
    end
end

function Build.floorOnCreate(params)
    markAndRegister(params and params.thumpable, Constants.PIPE_SURFACE_FLOOR, false, nil)
end

function Build.riserOnCreate(params)
    markAndRegister(params and params.thumpable, Constants.PIPE_SURFACE_WALLCOVER, true, edgeFromFacing(params))
end

-- Global alias used by the entity SpriteConfig OnCreate/OnIsValid dotted paths.
WaterPipesBuild = Build

return Build
