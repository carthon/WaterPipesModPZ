-- B42 entity build hooks for the Water Pipe buildables.
--
-- The pipes are placed through the native B42 entity build system (ISBuildIsoEntity), which is
-- multiplayer-safe: the engine validates on the server and runs :create() server-side. We supply
-- two SpriteConfig hooks per entity:
--   OnIsValid(params) -> bool   (runs on client cursor AND server; pure validation)
--   OnCreate(params)            (runs inside :create(), i.e. on the server in MP; registers the pipe)
--
-- Buildables: floor pipe (auto-connecting), vertical pipe (occupies a tile exclusively, links the
-- floor network to the tile above), and cap (closes the top of a vertical run).
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

local function getModData(worldObject)
    if worldObject and worldObject.getModData then
        local ok, modData = pcall(worldObject.getModData, worldObject)
        return ok and modData or nil
    end
    return nil
end

-- One pipe object per tile: floor, vertical and cap are all mutually exclusive on a square.
local function squareHasAnyPipe(square)
    return square ~= nil and #PipeObjectUtils.getPipeObjectsOnSquare(square) > 0
end

local function squareBelow(square)
    if not square or not getCell then
        return nil
    end
    local cell = getCell()
    return cell and cell.getGridSquare
        and cell:getGridSquare(square:getX(), square:getY(), square:getZ() - 1) or nil
end

-- ===== OnIsValid (both sides) =====

-- Floor pipe: only on an otherwise-empty tile (no floor pipe, vertical or cap already there).
function Build.floorOnIsValid(params)
    return not squareHasAnyPipe(params and params.square)
end

-- Vertical pipe: occupies the tile exclusively, so only on an empty tile.
function Build.verticalOnIsValid(params)
    return not squareHasAnyPipe(params and params.square)
end

-- ===== OnCreate (server / single-player) =====

-- kind: nil = floor, or "vertical".
local function markAndRegister(thumpable, surface, kind)
    if not thumpable then
        return
    end

    local modData = getModData(thumpable)
    if modData then
        modData[Constants.PIPE_MODDATA_KEY] = true
        modData[Constants.PIPE_SURFACE_MODDATA_KEY] = surface
        modData[Constants.PIPE_AXIS_MODDATA_KEY] = Constants.PIPE_AXIS_EW
        modData[Constants.PIPE_RISER_MODDATA_KEY] = (kind == "vertical") and true or nil
        modData[Constants.PIPE_RISER_EDGE_MODDATA_KEY] = nil
    end
    if thumpable.transmitModData then
        pcall(thumpable.transmitModData, thumpable)
    end

    local square = thumpable.getSquare and thumpable:getSquare() or nil
    if square and WaterPipes.System and WaterPipes.System.registerPipeAt then
        if kind then
            Logger.log(string.format("Placed %s pipe at %d:%d:%d",
                kind, square:getX(), square:getY(), square:getZ()))
        end
        -- registerPipeAt rebuilds the network and (in single-player) runs the autotile.
        WaterPipes.System.registerPipeAt(square:getX(), square:getY(), square:getZ())
    end
end

function Build.floorOnCreate(params)
    markAndRegister(params and params.thumpable, Constants.PIPE_SURFACE_FLOOR, nil)
end

function Build.verticalOnCreate(params)
    markAndRegister(params and params.thumpable, Constants.PIPE_SURFACE_WALLCOVER, "vertical")
end

-- Back-compat aliases (old riser names) in case any script still references them.
Build.riserOnIsValid = Build.verticalOnIsValid
Build.riserOnCreate = Build.verticalOnCreate

-- Global alias used by the entity SpriteConfig OnCreate/OnIsValid dotted paths.
WaterPipesBuild = Build

return Build
