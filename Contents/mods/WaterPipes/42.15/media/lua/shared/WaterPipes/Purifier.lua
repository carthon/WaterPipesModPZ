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

-- ===== Working predicate =====

local function squareHasPower(square)
    if not square or not square.haveElectricity then
        return false
    end
    local ok, powered = pcall(square.haveElectricity, square)
    return ok and powered or false
end

-- The purifier works while its tile has power (electric tier only for now).
function Purifier.isWorking(worldObject)
    if not Purifier.isPurifier(worldObject) then
        return false
    end
    local square = worldObject.getSquare and worldObject:getSquare() or nil
    return squareHasPower(square)
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
