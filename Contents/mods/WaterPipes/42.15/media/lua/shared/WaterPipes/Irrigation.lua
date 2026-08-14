WaterPipes = WaterPipes or {}
WaterPipes.Irrigation = WaterPipes.Irrigation or {}

require "WaterPipes/Constants"
require "WaterPipes/NetworkAccess"
require "WaterPipes/PipeObjectUtils"
require "WaterPipes/Pressure"

local Constants = WaterPipes.Constants
local Irrigation = WaterPipes.Irrigation
local NetworkAccess = WaterPipes.NetworkAccess
local PipeObjectUtils = WaterPipes.PipeObjectUtils

-- Drip emitters and sprinklers. Both are pipe variants: they sit on the line, pass water onward, and
-- water crops as it goes -- so a row of drips down a furrow behaves like real drip tape.
--
-- What makes them different is efficiency, not throughput. That is deliberate: vanilla crops drain
-- only 1 waterLvl per 5 in-game hours, so a barrel would keep a field alive for a year and water
-- COST can never be the balance. Instead the drip only spends litres on a tile that actually has a
-- thirsty crop, while the sprinkler sprays its whole 3x3 regardless -- which is exactly the
-- real-world trade and gives the player a reason to pick one.

local function getModData(worldObject)
    if not worldObject or not worldObject.getModData then
        return nil
    end
    local ok, modData = pcall(worldObject.getModData, worldObject)
    return ok and modData or nil
end

local function transmit(worldObject)
    if worldObject and worldObject.transmitModData then
        pcall(worldObject.transmitModData, worldObject)
    end
end

local function getCellSquare(x, y, z)
    if not getCell then
        return nil
    end
    local cell = getCell()
    if not cell or not cell.getGridSquare then
        return nil
    end
    return cell:getGridSquare(x, y, z)
end

-- ===== Identity =====

function Irrigation.isDrip(worldObject)
    local modData = getModData(worldObject)
    return modData and modData[Constants.DRIP_MODDATA_KEY] == true or false
end

function Irrigation.isSprinkler(worldObject)
    local modData = getModData(worldObject)
    return modData and modData[Constants.SPRINKLER_MODDATA_KEY] == true or false
end

local function findEmitterOnSquare(square, predicate)
    if not square then
        return nil
    end
    for _, worldObject in ipairs(PipeObjectUtils.getPipeObjectsOnSquare(square)) do
        if predicate(worldObject) then
            return worldObject
        end
    end
    return nil
end

function Irrigation.findDripOnSquare(square)
    return findEmitterOnSquare(square, Irrigation.isDrip)
end

function Irrigation.findSprinklerOnSquare(square)
    return findEmitterOnSquare(square, Irrigation.isSprinkler)
end

-- ===== Drip condition (burst / repair) =====

function Irrigation.getDripCondition(worldObject)
    local modData = getModData(worldObject)
    local value = modData and modData[Constants.DRIP_CONDITION_KEY]
    if type(value) == "number" then
        return math.min(math.max(value, 0), Constants.DRIP_MAX_CONDITION)
    end
    return Constants.DRIP_MAX_CONDITION
end

function Irrigation.setDripCondition(worldObject, value)
    local modData = getModData(worldObject)
    if not modData then
        return
    end
    modData[Constants.DRIP_CONDITION_KEY] =
        math.min(math.max(value or 0, 0), Constants.DRIP_MAX_CONDITION)
    transmit(worldObject)
end

function Irrigation.isDripBurst(worldObject)
    return Irrigation.getDripCondition(worldObject) <= 0
end

function Irrigation.repairDrip(worldObject)
    Irrigation.setDripCondition(worldObject, Constants.DRIP_MAX_CONDITION)
end

function Irrigation.burstPressure()
    local sv = SandboxVars and SandboxVars.WaterPipes
    local v = sv and sv.DripBurstPressure
    if type(v) == "number" then
        if v <= 0 then
            return nil   -- 0 = emitters never burst
        end
        return v / 10
    end
    return Constants.DRIP_BURST_PRESSURE
end

-- ===== Farming bridge =====

-- Server-only: SFarmingSystem.lua starts with `if isClient() then return end`, so instance is nil on
-- an MP client. Every caller below is already inside the server-side pass.
local function farmingSystem()
    return SFarmingSystem and SFarmingSystem.instance or nil
end

-- The thirsty crop on a square, or nil. "plow" is tilled soil with nothing planted; a dead plant
-- cannot be revived by watering, so both are skipped.
local function thirstyPlantOn(square)
    local system = farmingSystem()
    if not system or not square or not system.getLuaObjectOnSquare then
        return nil
    end
    local ok, plant = pcall(system.getLuaObjectOnSquare, system, square)
    if not ok or not plant then
        return nil
    end
    if plant.state == "plow" then
        return nil
    end
    if plant.isAlive and not plant:isAlive() then
        return nil
    end
    if (plant.waterLvl or 0) >= Constants.IRRIGATION_MAX_WATER_LEVEL then
        return nil
    end
    return plant
end

-- Add waterLvl directly rather than via plant:water(), which only moves in whole +10 steps. The
-- fields are the ones SFarmingSystem persists, and saveData() is what makes it stick.
local function addWater(plant, amount)
    local before = plant.waterLvl or 0
    local after = math.min(before + amount, Constants.IRRIGATION_MAX_WATER_LEVEL)
    local added = after - before
    if added <= 0 then
        return 0
    end
    plant.waterLvl = after
    local system = farmingSystem()
    if system and system.hoursElapsed then
        plant.lastWaterHour = system.hoursElapsed
    end
    if plant.saveData then
        pcall(plant.saveData, plant)
    end
    return added
end

function Irrigation.litresFor(waterLevels)
    return math.max(waterLevels or 0, 0) * Constants.IRRIGATION_LITRES_PER_WATER_LEVEL
end

-- ===== Debug logging =====
-- Off by default. The debug overlay flips it on so every watering event lands in console.txt with
-- the tile, the amount and the source -- which is how you tell "not watering" from "watering, but
-- too slowly to see".
Irrigation.debugLog = false

local function debugLog(fmt, ...)
    if Irrigation.debugLog and WaterPipes.Logger then
        WaterPipes.Logger.log("[irrigation] " .. string.format(fmt, ...))
    end
end

-- ===== Live emitter status (for the overlay; never waters) =====

-- Everything the overlay needs about one emitter, computed instantly with no time passing: whether it
-- CAN water right now and, if not, why. This is the real diagnostic -- a sprinkler with no pump
-- reads "needs 20.0, has 1.0" the moment you look, instead of you waiting an hour to see nothing.
function Irrigation.getEmitterStatus(worldObject, square)
    local isDrip = Irrigation.isDrip(worldObject)
    local isSprinkler = Irrigation.isSprinkler(worldObject)
    if not isDrip and not isSprinkler then
        return nil
    end

    local NetworkAccess = WaterPipes.NetworkAccess
    local kind = isDrip and Constants.PRESSURE_KIND_DRIP or Constants.PRESSURE_KIND_SPRINKLER
    local status = {
        kind = kind,
        pressure = NetworkAccess.getPressureAtSquare(square, kind),
        minimum = WaterPipes.Pressure.minimumFor(kind),
        burst = isDrip and Irrigation.isDripBurst(worldObject) or false,
    }

    -- Is there actually water to draw here? (A dry network makes an emitter idle even at full pressure.)
    local available, fluidTypeName = NetworkAccess.availableToPull(square, kind)
    status.hasWater = fluidTypeName ~= nil
        and (fluidTypeName == "Water" or fluidTypeName == "TaintedWater")
        and (available or 0) > 0

    -- With the pressure model off every connected emitter qualifies, exactly as the irrigation pass
    -- itself decides (Pressure.canReach short-circuits) -- otherwise the readout would call an emitter
    -- starved while it was happily watering.
    status.reaches = status.pressure ~= nil
        and (not WaterPipes.Pressure.isEnabled() or status.pressure >= status.minimum)
    status.active = status.reaches and status.hasWater and not status.burst
    return status
end

-- ===== The irrigation pass =====

local function isWaterFluid(fluidTypeName)
    -- Tainted water irrigates exactly as well as clean: vanilla whitelists both in ISFarmingMenu and
    -- the fluid type never even reaches SPlantGlobalObject:water. Pumping a river straight onto the
    -- crops is therefore intended, not an oversight.
    return fluidTypeName == "Water" or fluidTypeName == "TaintedWater"
end

-- Pull `litres` of whatever water the network holds at `square`. Returns (drawn, fluidTypeName).
local function drawWater(square, litres, kind)
    if litres <= 0 then
        return 0, nil
    end
    local available, fluidTypeName = NetworkAccess.availableToPull(square, kind)
    if not fluidTypeName or not isWaterFluid(fluidTypeName) or (available or 0) <= 0 then
        return 0, nil
    end
    local drawn = NetworkAccess.drawFluidAtSquare(square, fluidTypeName, math.min(litres, available), kind)
    return drawn or 0, fluidTypeName
end

-- A drip emitter waters only its own tile, and only spends litres when that tile holds a thirsty
-- crop. That is its whole point: ~100% efficient, at the cost of needing one per tile.
function Irrigation.processDrip(drip, square, dtHours)
    local pressure = NetworkAccess.getPressureAtSquare(square, Constants.PRESSURE_KIND_DRIP)
    if not pressure then
        return   -- nothing can reach this emitter
    end

    -- Real emitters are rated for ~1-1.5 bar and blow out above it. A burst emitter still conducts
    -- water to the rest of the line -- it just stops watering, exactly like a spent purifier filter
    -- still passes clean water through.
    local burst = Irrigation.burstPressure()
    if burst and pressure > burst and not Irrigation.isDripBurst(drip) then
        Irrigation.setDripCondition(drip, 0)
        return
    end
    if Irrigation.isDripBurst(drip) then
        return
    end

    local plant = thirstyPlantOn(square)
    if not plant then
        return   -- no crop, no water spent
    end

    local want = Constants.DRIP_WATER_PER_HOUR * math.max(dtHours or 0, 0)
    local drawn, fluidTypeName = drawWater(square, Irrigation.litresFor(want), Constants.PRESSURE_KIND_DRIP)
    if drawn <= 0 then
        debugLog("drip %d,%d,%d: reachable but drew no water (network dry?)",
            square:getX(), square:getY(), square:getZ())
        return
    end
    local added = addWater(plant, drawn / Constants.IRRIGATION_LITRES_PER_WATER_LEVEL)
    debugLog("drip %d,%d,%d: +%.1f waterLvl (now %.1f) from %s",
        square:getX(), square:getY(), square:getZ(), added, plant.waterLvl or 0,
        tostring(fluidTypeName))
end

local function sprinklerNoiseEnabled()
    local sv = SandboxVars and SandboxVars.WaterPipes
    local v = sv and sv.SprinklerNoise
    if type(v) == "boolean" then
        return v
    end
    return true
end

-- A sprinkler covers the 3x3 around it but needs real pressure, and is charged for every tile it
-- sprays whether or not anything is growing there. It is loud, too: that noise plus the wasted water
-- is what the player pays for the coverage.
function Irrigation.processSprinkler(sprinkler, square, dtHours)
    -- getPressureAtSquare already applies the sprinkler's own minimum head, so nil means either
    -- unreachable or not enough pressure -- which for a sprinkler is the same thing.
    local pressure = NetworkAccess.getPressureAtSquare(square, Constants.PRESSURE_KIND_SPRINKLER)
    if not pressure then
        return
    end

    local perTile = Constants.SPRINKLER_WATER_PER_HOUR * math.max(dtHours or 0, 0)
    if perTile <= 0 then
        return
    end

    -- Charged for the whole footprint up front: the spray does not care what is under it.
    local litres = Irrigation.litresFor(perTile) * Constants.SPRINKLER_WASTE_TILES
    local drawn = drawWater(square, litres, Constants.PRESSURE_KIND_SPRINKLER)
    if drawn <= 0 then
        debugLog("sprinkler %d,%d,%d: has %.1f pressure but drew no water (network dry?)",
            square:getX(), square:getY(), square:getZ(), pressure)
        return
    end

    -- Short delivery (a nearly-empty network) waters proportionally rather than not at all.
    local ratio = litres > 0 and (drawn / litres) or 0
    local x, y, z = square:getX(), square:getY(), square:getZ()
    local radius = Constants.SPRINKLER_RADIUS
    local wateredTiles = 0
    for dx = -radius, radius do
        for dy = -radius, radius do
            local plant = thirstyPlantOn(getCellSquare(x + dx, y + dy, z))
            if plant then
                addWater(plant, perTile * ratio)
                wateredTiles = wateredTiles + 1
            end
        end
    end
    debugLog("sprinkler %d,%d,%d: watered %d crop(s) in 3x3 at %.0f%% delivery",
        x, y, z, wateredTiles, ratio * 100)

    if sprinklerNoiseEnabled() and addSound then
        pcall(addSound, sprinkler, x, y, z,
            Constants.SPRINKLER_NOISE_RADIUS, Constants.SPRINKLER_NOISE_VOLUME)
    end
end

-- An open hydrant showers its own 3x3 like a sprinkler while it is losing water -- mains-fed or
-- draining its reserve; the caller has already established that. It spends nothing new and walks
-- nothing: the litres are the ones the open cap is already wasting (see System.processHydrant), so
-- the crops just stand in them. Cost is nine plant lookups per OPEN hydrant per minute, driven off
-- the open-hydrant registry -- no sweep, no network walk.
function Irrigation.waterHydrantSurroundings(square, dtHours)
    local perTile = Constants.SPRINKLER_WATER_PER_HOUR * math.max(dtHours or 0, 0)
    if perTile <= 0 or not square then
        return
    end
    local x, y, z = square:getX(), square:getY(), square:getZ()
    local radius = Constants.SPRINKLER_RADIUS
    local wateredTiles = 0
    for dx = -radius, radius do
        for dy = -radius, radius do
            local plant = thirstyPlantOn(getCellSquare(x + dx, y + dy, z))
            if plant then
                addWater(plant, perTile)
                wateredTiles = wateredTiles + 1
            end
        end
    end
    if wateredTiles > 0 then
        debugLog("hydrant %d,%d,%d: watered %d crop(s) in 3x3 from the open flow",
            x, y, z, wateredTiles)
    end
end

-- Walk the registered pipes and run whatever emitters sit on them. Iterating State's pipe registry
-- rather than scanning the map keeps this proportional to what the player actually built.
-- Server-only, and deliberately on a slow cadence: this is the one place pressure gets computed.
function Irrigation.run(dtHours)
    if isClient and isClient() then
        return
    end

    local State = WaterPipes.State
    local state = State and State.ensure and State.ensure() or nil
    if not state or not state.pipes then
        return
    end

    for _, pipeData in pairs(state.pipes) do
        local square = getCellSquare(pipeData.x, pipeData.y, pipeData.z)
        if square then
            local drip = Irrigation.findDripOnSquare(square)
            if drip then
                Irrigation.processDrip(drip, square, dtHours)
            end
            local sprinkler = Irrigation.findSprinklerOnSquare(square)
            if sprinkler then
                Irrigation.processSprinkler(sprinkler, square, dtHours)
            end
        end
    end
end

return Irrigation
