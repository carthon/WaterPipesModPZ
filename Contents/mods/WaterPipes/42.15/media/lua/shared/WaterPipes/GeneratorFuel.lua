WaterPipes = WaterPipes or {}
WaterPipes.GeneratorFuel = WaterPipes.GeneratorFuel or {}

require "WaterPipes/Constants"
require "WaterPipes/Logger"
require "WaterPipes/NetworkAccess"
require "WaterPipes/PipeObjectUtils"

local Constants = WaterPipes.Constants
local Logger = WaterPipes.Logger
local NetworkAccess = WaterPipes.NetworkAccess
local PipeObjectUtils = WaterPipes.PipeObjectUtils
local GeneratorFuel = WaterPipes.GeneratorFuel

local function isGenerator(worldObject)
    return worldObject ~= nil and instanceof(worldObject, "IsoGenerator")
end
GeneratorFuel.isGenerator = isGenerator

local function getModData(worldObject)
    if worldObject and worldObject.getModData then
        return worldObject:getModData()
    end
    return nil
end

local function getSquare(worldObject)
    return worldObject and worldObject.getSquare and worldObject:getSquare() or nil
end

local function transmit(worldObject)
    if worldObject and worldObject.transmitModData then
        pcall(function() worldObject:transmitModData() end)
    end
end

function GeneratorFuel.isPlumbed(worldObject)
    local modData = getModData(worldObject)
    return modData and modData[Constants.GENERATOR_PLUMBED_MODDATA_KEY] == true or false
end

function GeneratorFuel.hasPipeOnSquare(worldObject)
    local square = getSquare(worldObject)
    return square ~= nil and PipeObjectUtils.getPipeOnSquare(square) ~= nil
end

function GeneratorFuel.canPlumb(worldObject)
    return isGenerator(worldObject)
        and not GeneratorFuel.isPlumbed(worldObject)
        and GeneratorFuel.hasPipeOnSquare(worldObject)
end

function GeneratorFuel.canUnplumb(worldObject)
    return isGenerator(worldObject) and GeneratorFuel.isPlumbed(worldObject)
end

function GeneratorFuel.plumb(worldObject)
    if not GeneratorFuel.canPlumb(worldObject) then
        Logger.warn("Generator plumb rejected (not a generator, already connected, or no pipe on tile).")
        return false
    end

    local modData = getModData(worldObject)
    if modData then
        modData[Constants.GENERATOR_PLUMBED_MODDATA_KEY] = true
    end

    Logger.log("Generator connected to pipe network.")
    transmit(worldObject)
    GeneratorFuel.refresh(worldObject)
    return true
end

function GeneratorFuel.unplumb(worldObject)
    if not GeneratorFuel.canUnplumb(worldObject) then
        return false
    end

    local modData = getModData(worldObject)
    if modData then
        modData[Constants.GENERATOR_PLUMBED_MODDATA_KEY] = nil
    end

    Logger.log("Generator disconnected from pipe network.")
    transmit(worldObject)
    return true
end

-- Top the generator tank up from the network when it drops below the threshold.
-- Only draws the configured fuel fluid (Petrol) from a matching single-fluid network.
function GeneratorFuel.refresh(worldObject)
    if not GeneratorFuel.isPlumbed(worldObject) then
        return false
    end

    local square = getSquare(worldObject)
    if not square or PipeObjectUtils.getPipeOnSquare(square) == nil then
        -- Hybrid disconnect: pipe gone from the generator's OWN tile -> fully disconnect it.
        -- (A break further down the chain leaves it connected; drawFluidAtSquare just returns 0.)
        GeneratorFuel.unplumb(worldObject)
        return false
    end

    if not (worldObject.getFuel and worldObject.getMaxFuel and worldObject.setFuel) then
        return false
    end

    local maxFuel = worldObject:getMaxFuel()
    if not maxFuel or maxFuel <= 0 then
        return false
    end

    local fuel = worldObject:getFuel() or 0
    if (fuel / maxFuel) >= Constants.GENERATOR_REFUEL_THRESHOLD then
        return false
    end

    local need = maxFuel - fuel
    if need <= 0 then
        return false
    end

    local drawn = NetworkAccess.drawFluidAtSquare(square, Constants.GENERATOR_FUEL_FLUID, need)
    if drawn and drawn > 0 then
        worldObject:setFuel(fuel + drawn)
        Logger.log(string.format("Generator refueled +%.2f %s from network.", drawn, Constants.GENERATOR_FUEL_FLUID))
        return true
    end

    return false
end

return GeneratorFuel
