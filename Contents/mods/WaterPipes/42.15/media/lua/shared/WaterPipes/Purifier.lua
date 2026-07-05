WaterPipes = WaterPipes or {}
WaterPipes.Purifier = WaterPipes.Purifier or {}

require "WaterPipes/Constants"
require "WaterPipes/Logger"
require "WaterPipes/PipeObjectUtils"

local Constants = WaterPipes.Constants
local Logger = WaterPipes.Logger
local PipeObjectUtils = WaterPipes.PipeObjectUtils
local Purifier = WaterPipes.Purifier

-- A purifier is a floor pipe carrying the purifier tier in its modData. It is detected the same
-- modData-based way as every other pipe variant (never by sprite), so hiding/placeholder art never
-- affects behaviour.

local function getModData(worldObject)
    if not worldObject or not worldObject.getModData then
        return nil
    end
    local ok, modData = pcall(worldObject.getModData, worldObject)
    return ok and modData or nil
end

local function getSquare(x, y, z)
    if not getCell then
        return nil
    end
    local cell = getCell()
    return cell and cell.getGridSquare and cell:getGridSquare(x, y, z) or nil
end

-- The tier string ("filter"/"fire"/"electric") baked into a purifier, or nil if not a purifier.
function Purifier.getTier(worldObject)
    local modData = getModData(worldObject)
    local tier = modData and modData[Constants.PURIFIER_MODDATA_KEY]
    if tier == Constants.PURIFIER_TIER_FILTER
        or tier == Constants.PURIFIER_TIER_FIRE
        or tier == Constants.PURIFIER_TIER_ELECTRIC then
        return tier
    end
    return nil
end

function Purifier.isPurifier(worldObject)
    return Purifier.getTier(worldObject) ~= nil
end

-- The fixed device sprite for a purifier tier (placeholder art for now, see Constants).
function Purifier.spriteForTier(tier)
    if tier == Constants.PURIFIER_TIER_FIRE then
        return Constants.PURIFIER_FIRE_SPRITE
    elseif tier == Constants.PURIFIER_TIER_ELECTRIC then
        return Constants.PURIFIER_ELECTRIC_SPRITE
    end
    return Constants.PURIFIER_FILTER_SPRITE
end

function Purifier.spriteFor(worldObject)
    return Purifier.spriteForTier(Purifier.getTier(worldObject))
end

-- ===== Filter charges =====

function Purifier.getCharges(worldObject)
    local modData = getModData(worldObject)
    local value = modData and modData[Constants.PURIFIER_FILTER_CHARGES_KEY]
    return type(value) == "number" and math.max(value, 0) or 0
end

local function setCharges(worldObject, value)
    local modData = getModData(worldObject)
    if not modData then
        return
    end
    modData[Constants.PURIFIER_FILTER_CHARGES_KEY] = math.max(value or 0, 0)
    if worldObject.transmitModData then
        pcall(worldObject.transmitModData, worldObject)
    end
end

-- Install a fresh cartridge: refill to max. Authoritative callers only (server / single-player).
function Purifier.insertCartridge(worldObject)
    if Purifier.getTier(worldObject) ~= Constants.PURIFIER_TIER_FILTER then
        return false
    end
    setCharges(worldObject, Constants.PURIFIER_FILTER_MAX_CHARGES)
    Logger.log("Purifier: filter cartridge installed (charges refilled).")
    return true
end

-- ===== Per-tier "working" predicate =====

-- A lit heat source on a single square (campfire/fireplace/fire/activated brazier or stove).
-- Heuristic + fully defensive (feature-detected, pcall-guarded): if the engine shape differs on a
-- given build it simply reads as "no heat" and the fire distiller stays idle -- never an error.
local function squareHasLitHeatSource(square)
    if not square or not square.getObjects then
        return false
    end
    local objects = square:getObjects()
    for index = 0, objects:size() - 1 do
        local object = objects:get(index)
        if instanceof and instanceof(object, "IsoFire") then
            return true
        end
        if instanceof and instanceof(object, "IsoFireplace") and object.isLit then
            local ok, lit = pcall(object.isLit, object)
            if ok and lit then
                return true
            end
        end
        if object and object.isActivated and object.isHeatSource then
            local okA, activated = pcall(object.isActivated, object)
            local okH, heat = pcall(object.isHeatSource, object)
            if okA and activated and okH and heat then
                return true
            end
        end
    end
    return false
end

local function hasAdjacentHeat(square)
    if not square then
        return false
    end
    if squareHasLitHeatSource(square) then
        return true
    end
    for _, offset in ipairs(Constants.CARDINAL_OFFSETS) do
        if squareHasLitHeatSource(getSquare(square:getX() + offset.x, square:getY() + offset.y, square:getZ())) then
            return true
        end
    end
    return false
end

local function squareHasPower(square)
    if not square or not square.haveElectricity then
        return false
    end
    local ok, powered = pcall(square.haveElectricity, square)
    return ok and powered or false
end

-- Is this purifier currently able to work?
function Purifier.isWorking(worldObject)
    local tier = Purifier.getTier(worldObject)
    if not tier then
        return false
    end

    if tier == Constants.PURIFIER_TIER_FILTER then
        return Purifier.getCharges(worldObject) > 0
    end

    local square = worldObject.getSquare and worldObject:getSquare() or nil
    if tier == Constants.PURIFIER_TIER_FIRE then
        return hasAdjacentHeat(square)
    end
    if tier == Constants.PURIFIER_TIER_ELECTRIC then
        return squareHasPower(square)
    end
    return false
end

-- Spend one unit of the purifier's consumable for a completed conversion. Only the filter tier has
-- a consumable (the cartridge); fire/electric are free while their condition holds.
function Purifier.consumeForConversion(worldObject)
    if Purifier.getTier(worldObject) ~= Constants.PURIFIER_TIER_FILTER then
        return
    end
    local remaining = Purifier.getCharges(worldObject) - 1
    setCharges(worldObject, remaining)
    if remaining <= 0 then
        Logger.log("Purifier: filter cartridge spent (needs replacing).")
    end
end

-- ===== Network integration =====

-- The first purifier world object sitting on a square, or nil.
function Purifier.findOnSquare(square)
    if not square then
        return nil
    end
    for _, worldObject in ipairs(PipeObjectUtils.getPipeObjectsOnSquare(square)) do
        if Purifier.isPurifier(worldObject) then
            return worldObject
        end
    end
    return nil
end

-- Return the first WORKING purifier world object anywhere in a network component (nil if none). The
-- component's pipe nodes carry the square coordinates; we look up the live world object to read its
-- state. Squares that are not loaded (far chunks on a dedicated server) are skipped, exactly like the
-- rest of the redistribution pass.
function Purifier.componentWorkingPurifier(component)
    if not component or not component.nodes then
        return nil
    end
    for _, node in pairs(component.nodes) do
        if node.kind == Constants.NODE_KIND_PIPE then
            local purifier = Purifier.findOnSquare(getSquare(node.x, node.y, node.z))
            if purifier and Purifier.isWorking(purifier) then
                return purifier
            end
        end
    end
    return nil
end

return Purifier
