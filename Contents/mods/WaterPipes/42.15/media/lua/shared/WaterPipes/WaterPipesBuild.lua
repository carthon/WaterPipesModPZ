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

local function markAndRegister(thumpable, surface, riser, edge, hidden, purifierTier, router)
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
        -- Concealed variant: baked in at build; clients render it with a transparent tile.
        modData[Constants.PIPE_HIDDEN_MODDATA_KEY] = hidden and true or nil
        -- Purifier variant: a floor pipe that cleans the network's tainted water while it works.
        modData[Constants.PURIFIER_MODDATA_KEY] = purifierTier or nil
        -- The filter tier is built with its first cartridge installed (part of the recipe), so it
        -- works out of the box; replacements are inserted later via the context menu.
        if purifierTier == Constants.PURIFIER_TIER_FILTER then
            modData[Constants.PURIFIER_FILTER_CHARGES_KEY] = Constants.PURIFIER_FILTER_MAX_CHARGES
        end
        -- Router variant: a flow boundary; give it a default OUT direction until the player rotates it.
        modData[Constants.ROUTER_MODDATA_KEY] = router and true or nil
        if router and modData[Constants.ROUTER_DIRECTION_KEY] == nil then
            modData[Constants.ROUTER_DIRECTION_KEY] = Constants.ROUTER_DEFAULT_DIRECTION
        end
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
        -- Routers pass metadata so the graph rebuild can isolate them as flow boundaries.
        WaterPipes.System.registerPipeAt(square:getX(), square:getY(), square:getZ(),
            router and { router = true } or nil)
    end
end

function Build.floorOnCreate(params)
    markAndRegister(params and params.thumpable, Constants.PIPE_SURFACE_FLOOR, false, nil, false)
end

function Build.riserOnCreate(params)
    markAndRegister(params and params.thumpable, Constants.PIPE_SURFACE_WALLCOVER, true, edgeFromFacing(params), false)
end

-- Concealed variants: identical placement/registration, but flagged hidden so each client renders
-- them invisible. Network, auto-connect and verticality are unaffected (detection is modData-based).
function Build.floorHiddenOnCreate(params)
    markAndRegister(params and params.thumpable, Constants.PIPE_SURFACE_FLOOR, false, nil, true)
end

function Build.riserHiddenOnCreate(params)
    markAndRegister(params and params.thumpable, Constants.PIPE_SURFACE_WALLCOVER, true, edgeFromFacing(params), true)
end

-- Purifier variants: floor pipes (auto-connect + carry water like any pipe) tagged with a tier so
-- the network tick knows to clean tainted water through them. Never hidden, never risers.
function Build.filterPurifierOnCreate(params)
    markAndRegister(params and params.thumpable, Constants.PIPE_SURFACE_FLOOR, false, nil, false, Constants.PURIFIER_TIER_FILTER)
end

function Build.firePurifierOnCreate(params)
    markAndRegister(params and params.thumpable, Constants.PIPE_SURFACE_FLOOR, false, nil, false, Constants.PURIFIER_TIER_FIRE)
end

function Build.electricPurifierOnCreate(params)
    markAndRegister(params and params.thumpable, Constants.PIPE_SURFACE_FLOOR, false, nil, false, Constants.PURIFIER_TIER_ELECTRIC)
end

-- Fluid router: a floor pipe that is a flow boundary (splits the network into IN and OUT sides).
function Build.routerOnCreate(params)
    markAndRegister(params and params.thumpable, Constants.PIPE_SURFACE_FLOOR, false, nil, false, nil, true)
end

-- Global alias used by the entity SpriteConfig OnCreate/OnIsValid dotted paths.
WaterPipesBuild = Build

return Build
