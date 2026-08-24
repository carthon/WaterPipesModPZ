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
-- COST can never be the balance. Both spend water whenever they are actually emitting -- the spray
-- you see is water leaving the line -- but the drip wets one tile while the sprinkler is charged
-- for its whole 3x3, crops or not. Nine times the footprint, nine times the bill (plus the noise):
-- that is the real-world trade and the reason to pick one over the other.

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
    local Hydraulics = WaterPipes.Hydraulics
    local Pressure = WaterPipes.Pressure
    local kind = isDrip and Constants.PRESSURE_KIND_DRIP or Constants.PRESSURE_KIND_SPRINKLER

    -- Two questions, and they have different scopes. Which vessels hold water this emitter can lift
    -- from is a property of the ZONE and the LEVEL, so it is shared (see getStatusSummary); what head
    -- arrives HERE is a property of the tile, so it is read from the field, which is already solved
    -- and cached. Building a whole summary per emitter to answer both was measured at 4.3 ms each.
    local summary = NetworkAccess.getStatusSummary(square, kind)
    local status = {
        kind = kind,
        minimum = Pressure.minimumFor(kind),
        burst = isDrip and Irrigation.isDripBurst(worldObject) or false,
    }

    if not Pressure.isEnabled() then
        -- With the model off the gate never runs and the summary carries the flat container base,
        -- which is the reading the old code reported. Nothing here is per-tile.
        status.pressure = summary and summary.pressure or nil
    else
        -- Hydraulics.canDrawAt, never a head comparison of our own: a consumer the solve excluded
        -- reads a healthy head BECAUSE it was excluded. The head is still reported -- a starved
        -- emitter showing the static pressure behind it, next to the minimum it cannot meet, says
        -- more than a blank line does.
        local solution = Hydraulics.solveAt(square)
        local canDraw, head = Hydraulics.canDrawAt(solution, square, kind)
        status.pressure = head
        status.canDraw = canDraw and true or false

        -- WHY it cannot draw, which is not the same question and has two very different answers.
        --
        -- `starved` means the servable-set search excluded this emitter: the line cannot carry it on
        -- top of what it is already serving. The head reported above is then the pressure this tile
        -- has WITH THIS EMITTER OFF, and it can look perfectly healthy -- 37 against a minimum of 20 --
        -- because it is high precisely because the emitter is not drawing. Telling the player "not
        -- enough pressure, needs 20" under a reading of 37 is not a hint, it is a contradiction, and
        -- the fix it suggests (shorten the run) is not the fix that works (add a pump, or fewer
        -- emitters on the line).
        --
        -- Anything else that fails the gate really is below the minimum, and the old message is right.
        status.starved = Hydraulics.isStarvedAt
            and Hydraulics.isStarvedAt(solution, square) and true or false
    end

    -- Is there actually water to draw here? (A dry network makes an emitter idle even at full pressure.)
    local fluidTypeName = summary and not summary.isMixed and summary.fluidTypeName or nil
    status.hasWater = fluidTypeName ~= nil
        and (fluidTypeName == "Water" or fluidTypeName == "TaintedWater")
        and (summary.totalAmount or 0) > 0

    -- With the pressure model off every connected emitter qualifies, exactly as the irrigation pass
    -- itself decides (Pressure.canReach short-circuits) -- otherwise the readout would call an emitter
    -- starved while it was happily watering. With it on, the solve's verdict is the authority.
    if not Pressure.isEnabled() then
        status.reaches = status.pressure ~= nil
    else
        status.reaches = status.canDraw == true
    end
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

-- Pull `litres` of whatever water an already-built summary holds. Returns (drawn, fluidTypeName).
--
-- Takes a summary rather than a square on purpose. Each emitter used to build three identical network
-- summaries -- pressure, availability, draw -- and on a field of sprinklers that tripling was the
-- single biggest cost in the mod. One summary answers all three, and because the summary is live the
-- draw it performs is visible to whatever asks it next.
local function drawWater(summary, litres)
    if litres <= 0 or not summary then
        return 0, nil
    end
    local fluidTypeName = summary.isMixed and nil or summary.fluidTypeName
    if not fluidTypeName or not isWaterFluid(fluidTypeName) or (summary.totalAmount or 0) <= 0 then
        return 0, nil
    end
    local drawn = NetworkAccess.drawFromSummary(summary, fluidTypeName, litres)
    return drawn or 0, fluidTypeName
end

-- A drip emitter waters only its own tile. It drips whenever it can -- which is exactly what the
-- spray FX shows -- so it spends its trickle whether or not anything grows below; a crop only
-- changes where the water ends up. (It used to spend only with a thirsty crop on the tile, and the
-- visible drip read as free water.) Still the efficient choice: one tile's bill, not nine.
-- `summary` is the network as seen from this tile. Callers that already hold one pass it in; omitted,
-- it is built here. Returns the LITRES this emitter took out of the network, which is what the
-- conservation check balances against (see System.checkIrrigationConservation).
function Irrigation.processDrip(drip, square, dtHours, summary)
    summary = summary or NetworkAccess.getDrawSummary(square, Constants.PRESSURE_KIND_DRIP)
    local pressure = summary and summary.pressure or nil
    if not pressure then
        return 0   -- nothing can reach this emitter
    end

    -- Real emitters are rated for ~1-1.5 bar and blow out above it. A burst emitter still conducts
    -- water to the rest of the line -- it just stops watering, exactly like a spent purifier filter
    -- still passes clean water through.
    local burst = Irrigation.burstPressure()
    if burst and pressure > burst and not Irrigation.isDripBurst(drip) then
        Irrigation.setDripCondition(drip, 0)
        return 0
    end
    if Irrigation.isDripBurst(drip) then
        return 0
    end

    local want = Constants.DRIP_WATER_PER_HOUR * math.max(dtHours or 0, 0)
    if want <= 0 then
        return 0
    end
    local drawn, fluidTypeName = drawWater(summary, Irrigation.litresFor(want))
    if drawn <= 0 then
        debugLog("drip %d,%d,%d: reachable but drew no water (network dry?)",
            square:getX(), square:getY(), square:getZ())
        return 0
    end

    local plant = thirstyPlantOn(square)
    if plant then
        local added = addWater(plant, drawn / Constants.IRRIGATION_LITRES_PER_WATER_LEVEL)
        debugLog("drip %d,%d,%d: +%.1f waterLvl (now %.1f) from %s",
            square:getX(), square:getY(), square:getZ(), added, plant.waterLvl or 0,
            tostring(fluidTypeName))
    else
        debugLog("drip %d,%d,%d: %.2f L dripped away (no thirsty crop)",
            square:getX(), square:getY(), square:getZ(), drawn)
    end
    return drawn
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
-- `summary` is the network snapshot; see processDrip. Returns the litres taken from the network.
function Irrigation.processSprinkler(sprinkler, square, dtHours, summary)
    -- The summary's pressure already applies the sprinkler's own minimum head, so nil means either
    -- unreachable or not enough pressure -- which for a sprinkler is the same thing.
    summary = summary or NetworkAccess.getDrawSummary(square, Constants.PRESSURE_KIND_SPRINKLER)
    local pressure = summary and summary.pressure or nil
    if not pressure then
        return 0
    end

    local perTile = Constants.SPRINKLER_WATER_PER_HOUR * math.max(dtHours or 0, 0)
    if perTile <= 0 then
        return 0
    end

    -- Charged for the whole footprint up front: the spray does not care what is under it.
    local litres = Irrigation.litresFor(perTile) * Constants.SPRINKLER_WASTE_TILES
    local drawn = drawWater(summary, litres)
    if drawn <= 0 then
        debugLog("sprinkler %d,%d,%d: has %.1f pressure but drew no water (network dry?)",
            square:getX(), square:getY(), square:getZ(), pressure)
        return 0
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
    return drawn
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

-- Walk the registered pipes and list every emitter sitting on one. Iterating State's pipe registry
-- rather than scanning the map keeps this proportional to what the player actually built.
local function collectEmitters()
    local State = WaterPipes.State
    local state = State and State.ensure and State.ensure() or nil
    if not state or not state.pipes then
        return {}
    end

    local emitters = {}
    for _, pipeData in pairs(state.pipes) do
        -- Skip only what we KNOW carries no emitter. An entry without `kinds` predates the registry
        -- recording it and is still probed, so an existing save keeps watering while the ten-minute
        -- pass fills the gaps in. See WaterPipesBuild's registerPipeAt call.
        local metadata = pipeData.metadata
        local skip = metadata and metadata.kinds and not metadata.drip and not metadata.sprinkler
        local square = (not skip) and getCellSquare(pipeData.x, pipeData.y, pipeData.z) or nil
        if square then
            local drip = Irrigation.findDripOnSquare(square)
            if drip then
                emitters[#emitters + 1] = { object = drip, square = square, drip = true }
            end
            local sprinkler = Irrigation.findSprinklerOnSquare(square)
            if sprinkler then
                emitters[#emitters + 1] = { object = sprinkler, square = square, drip = false }
            end
        end
    end
    return emitters
end

-- Returns the litres this emitter took out of the network.
local function processEmitter(emitter, dtHours)
    local drawn
    if emitter.drip then
        drawn = Irrigation.processDrip(emitter.object, emitter.square, dtHours)
    else
        drawn = Irrigation.processSprinkler(emitter.object, emitter.square, dtHours)
    end
    return drawn or 0
end

-- ===== The pass, spread over frames =====
--
-- Irrigation is hourly, but "hourly" used to mean every emitter on the map ran inside ONE frame. A
-- field of thirty-odd sprinklers therefore paid its whole bill as a single visible hitch every game
-- hour, which is how a cost shows up to a player even after the cost itself has come down. The work
-- is now handed out a few emitters per tick instead.
--
-- Each emitter still gets the same dtHours, so the water delivered is identical -- only the frame it
-- lands in moves, by at most a second or two of real time on a network of any size.
local pendingPass = nil

function Irrigation.hasPendingPass()
    return pendingPass ~= nil
end

-- Start a pass. Any pass still draining is finished off first, so a slow frame can never let two
-- hours' worth of emitters pile up into one queue and silently skip an hour of watering.
function Irrigation.beginPass(dtHours)
    if isClient and isClient() then
        return
    end

    if pendingPass then
        Irrigation.finishPass()
    end

    local emitters = collectEmitters()
    if #emitters == 0 then
        return
    end

    pendingPass = { emitters = emitters, index = 1, dtHours = dtHours, spent = 0 }
end

-- Run up to `budget` emitters. Returns true once the pass is done.
-- Wall clock, or nil on a build that does not expose one -- in which case the emitter count below is
-- the only limit, exactly as it was before.
local function nowMs()
    if not getTimestampMs then
        return nil
    end
    local ok, ms = pcall(getTimestampMs)
    return (ok and type(ms) == "number") and ms or nil
end

function Irrigation.stepPass(budget, budgetMs)
    if not pendingPass then
        return true
    end

    local emitters = pendingPass.emitters
    local dtHours = pendingPass.dtHours
    local ceiling = math.min(pendingPass.index + math.max(budget or 1, 1) - 1, #emitters)

    -- The count is a ceiling; the clock is the limit. One emitter always runs, so the pass advances
    -- however expensive that emitter turns out to be -- and an emitter IS expensive: its draw empties
    -- a barrel, which invalidates the head field, which the next emitter re-solves.
    local limitMs = budgetMs or Constants.IRRIGATION_MS_PER_TICK
    local startedAt = limitMs and nowMs() or nil

    local last = pendingPass.index
    for index = pendingPass.index, ceiling do
        pendingPass.spent = (pendingPass.spent or 0) + processEmitter(emitters[index], dtHours)
        last = index
        if startedAt then
            local stamp = nowMs()
            if stamp and (stamp - startedAt) >= limitMs then
                break
            end
        end
    end

    pendingPass.index = last + 1
    if pendingPass.index > #emitters then
        pendingPass = nil
        return true
    end
    return false
end

-- Abandon whatever is left of the current pass. The emitters already processed keep their water;
-- the rest simply miss this hour.
function Irrigation.cancelPass()
    pendingPass = nil
end

-- Drain whatever is left of the current pass in this frame. A plain emitter count as the budget --
-- not math.huge, which Kahlua would carry through the index arithmetic.
function Irrigation.finishPass()
    if not pendingPass then
        return
    end
    Irrigation.stepPass(#pendingPass.emitters)
end

-- Run a whole pass right now, in this frame, and return the TOTAL LITRES the emitters took out of
-- the network. The debug command and anything that wants the result immediately use this; the hourly
-- tick uses beginPass/stepPass instead.
--
-- That return value is the whole point of the conservation check: whatever this reports as spent has
-- to be exactly what the network is missing afterwards (see System.checkIrrigationConservation).
-- Server-only: this is the one place pressure gets computed for emitters.
function Irrigation.run(dtHours)
    if isClient and isClient() then
        return 0
    end

    local spent = 0
    for _, emitter in ipairs(collectEmitters()) do
        spent = spent + processEmitter(emitter, dtHours)
    end
    return spent
end

return Irrigation
