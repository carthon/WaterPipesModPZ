WaterPipes = WaterPipes or {}
WaterPipes.Purifier = WaterPipes.Purifier or {}

require "WaterPipes/Constants"
require "WaterPipes/Logger"
require "WaterPipes/PipeObjectUtils"

local Constants = WaterPipes.Constants
local Logger = WaterPipes.Logger
local PipeObjectUtils = WaterPipes.PipeObjectUtils
local Purifier = WaterPipes.Purifier

-- A purifier is a NON-pipe container object placed on a router tile, tagged with its tier in modData.
-- It holds two internal buffers (IN tainted / OUT clean); the router drives intake -> convert -> output.
-- Detected by modData (never by sprite).

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

-- ===== IN / OUT buffers (two internal tanks, stored as modData) =====

local function transmit(worldObject)
    if worldObject and worldObject.transmitModData then
        pcall(worldObject.transmitModData, worldObject)
    end
end

function Purifier.getInAmount(worldObject)
    local modData = getModData(worldObject)
    local value = modData and modData[Constants.PURIFIER_IN_AMOUNT_KEY]
    return type(value) == "number" and math.max(value, 0) or 0
end

function Purifier.isInTainted(worldObject)
    local modData = getModData(worldObject)
    return modData and modData[Constants.PURIFIER_IN_TAINTED_KEY] == true or false
end

function Purifier.getOutAmount(worldObject)
    local modData = getModData(worldObject)
    local value = modData and modData[Constants.PURIFIER_OUT_AMOUNT_KEY]
    return type(value) == "number" and math.max(value, 0) or 0
end

-- Add intake into the IN buffer, recording whether it is tainted (an empty buffer adopts the type).
function Purifier.addIn(worldObject, amount, tainted)
    local modData = getModData(worldObject)
    if not modData or (amount or 0) <= 0 then
        return
    end
    if Purifier.getInAmount(worldObject) <= 0 then
        modData[Constants.PURIFIER_IN_TAINTED_KEY] = tainted and true or nil
    end
    modData[Constants.PURIFIER_IN_AMOUNT_KEY] = Purifier.getInAmount(worldObject) + amount
    transmit(worldObject)
end

-- Move fluid IN -> OUT (the OUT buffer is always clean Water). Clears the taint flag when IN empties.
function Purifier.moveInToOut(worldObject, amount)
    local modData = getModData(worldObject)
    if not modData then
        return
    end
    local moved = math.min(amount or 0, Purifier.getInAmount(worldObject))
    if moved <= 0 then
        return
    end
    local newIn = Purifier.getInAmount(worldObject) - moved
    modData[Constants.PURIFIER_IN_AMOUNT_KEY] = newIn
    if newIn <= 0 then
        modData[Constants.PURIFIER_IN_AMOUNT_KEY] = 0
        modData[Constants.PURIFIER_IN_TAINTED_KEY] = nil
    end
    modData[Constants.PURIFIER_OUT_AMOUNT_KEY] = Purifier.getOutAmount(worldObject) + moved
    transmit(worldObject)
end

function Purifier.removeOut(worldObject, amount)
    local modData = getModData(worldObject)
    if not modData or (amount or 0) <= 0 then
        return
    end
    modData[Constants.PURIFIER_OUT_AMOUNT_KEY] = math.max(Purifier.getOutAmount(worldObject) - amount, 0)
    transmit(worldObject)
end

-- ===== Location =====

-- The purifier-container object sitting on a square, or nil. It is a NON-pipe object (placed on a
-- router tile), so we scan every object on the square, not only pipes.
function Purifier.findOnSquare(square)
    if not square or not square.getObjects then
        return nil
    end
    local objects = square:getObjects()
    for index = 0, objects:size() - 1 do
        local worldObject = objects:get(index)
        if Purifier.isPurifier(worldObject) then
            return worldObject
        end
    end
    return nil
end

return Purifier
