WaterPipes = WaterPipes or {}
WaterPipes.Mains = WaterPipes.Mains or {}

require "WaterPipes/Constants"

local Constants = WaterPipes.Constants
local Mains = WaterPipes.Mains

-- The town water supply, as a network source.
--
-- Plumbing a fixture switches the engine's infinite city water OFF on it, which used to mean that
-- connecting your kitchen sink on day 3 made it WORSE than leaving it alone. Now the opposite: while
-- the service is still running, a plumbed fixture is an inlet. It fills the network's containers at a
-- bounded rate and it pressurises the whole zone, so sprinklers run without a pump right up to the
-- day the water is cut. That day then actually means something.
--
-- ===== How we know the service is still on =====
--
-- IsoObject.isWaterInfinite() is private, so we cannot ask it. It answers true when, in order: the
-- sprite carries the `waterPiped` flag, the square is in a room, the square is not `noWater`, the
-- fixture does not use an external water source, the world is younger than the shutoff, and modData
-- `canBeWaterPiped` is not true. Every one of those is public except the shutoff clock -- and the
-- last one is only modData, which we own.
--
-- So the structural conditions are checked here directly, and the clock is asked of the engine: clear
-- `canBeWaterPiped`, read getFluidCapacity(), put it back. Infinite water reports exactly 10000; our
-- own mirror reports the network's capacity. Reading it BOTH ways and requiring the two to differ is
-- what keeps a network that happens to hold 10000 L from looking like a live mains. Nothing observes
-- the intermediate state -- Lua here is single-threaded and we never transmit.
--
-- Replicating the shutoff arithmetic instead (world age, TimeSinceApo, WaterShutModifier) would have
-- worked today and quietly drifted the first time those numbers were retuned.

local INFINITE = Constants.MAINS_INFINITE_AMOUNT

local function getModData(worldObject)
    if not worldObject or not worldObject.getModData then
        return nil
    end
    local ok, modData = pcall(worldObject.getModData, worldObject)
    return ok and modData or nil
end

-- ===== Per-save tunables =====

function Mains.isEnabled()
    local sv = SandboxVars and SandboxVars.WaterPipes
    local v = sv and sv.MainsSupply
    if type(v) == "boolean" then
        return v
    end
    return true
end

-- Head the supply holds the network at. Real mains run 20-40 m.c.a.; stored in tenths so an integer
-- sandbox slider can say 25.0.
function Mains.head()
    local sv = SandboxVars and SandboxVars.WaterPipes
    local v = sv and sv.MainsHead
    if type(v) == "number" then
        return math.max(v, 0) / 10
    end
    return Constants.MAINS_HEAD
end

-- How much the supply may push in `dt` in-game minutes.
function Mains.intakeFor(dt)
    local sv = SandboxVars and SandboxVars.WaterPipes
    local rate = sv and sv.MainsIntakeRate
    if type(rate) ~= "number" then
        rate = Constants.MAINS_INTAKE_RATE
    end
    return math.max(rate, 0) * math.max(dt or 0, 0)
end

-- ===== Is the supply live here? =====

local function readCapacity(worldObject)
    if not worldObject.getFluidCapacity then
        return nil
    end
    local ok, capacity = pcall(worldObject.getFluidCapacity, worldObject)
    return ok and capacity or nil
end

-- The structural half: everything isWaterInfinite() checks that does not depend on the clock.
local function isMainsFixture(worldObject)
    local square = worldObject.getSquare and worldObject:getSquare() or nil
    if not square then
        return false
    end

    -- Outdoors has no plumbing to be connected to.
    if not square.getRoom or not square:getRoom() then
        return false
    end
    if square.isNoWater then
        local ok, noWater = pcall(square.isNoWater, square)
        if ok and noWater then
            return false
        end
    end

    -- The fixture must be piped to the town supply in the first place.
    if not worldObject.hasProperty or not IsoFlagType or not IsoFlagType.waterPiped then
        return false
    end
    local okProp, piped = pcall(worldObject.hasProperty, worldObject, IsoFlagType.waterPiped)
    if not okProp or not piped then
        return false
    end

    -- An external-water fixture reads its water somewhere else entirely; isWaterInfinite() bails on
    -- those, and so do we.
    if worldObject.getUsesExternalWaterSource then
        local okExt, external = pcall(worldObject.getUsesExternalWaterSource, worldObject)
        if okExt and external then
            return false
        end
    end

    return true
end

-- The clock half, asked of the engine. See the module header for why it is a probe.
local function probeServiceLive(worldObject)
    local modData = getModData(worldObject)
    if not modData then
        return false
    end

    local saved = modData.canBeWaterPiped

    modData.canBeWaterPiped = true          -- forced NOT infinite: this is the mirror's own reading
    local mirrored = readCapacity(worldObject)

    modData.canBeWaterPiped = nil           -- infinite allowed again
    local probed = readCapacity(worldObject)

    modData.canBeWaterPiped = saved

    if not probed or not mirrored then
        return false
    end
    -- Live only when letting the engine answer CHANGED the reading to the infinite marker. A network
    -- whose own capacity happens to be 10000 reads the same both ways and is correctly ignored.
    return probed >= INFINITE and mirrored ~= probed
end

-- Probing every fixture on every network walk would be wasteful for an answer that changes once per
-- save. Cached per fixture position, briefly -- long enough to cover a burst of queries, short enough
-- that the shutoff is noticed within seconds of happening.
local probeCache = {}

local function cacheKey(worldObject)
    local square = worldObject.getSquare and worldObject:getSquare() or nil
    if not square then
        return nil
    end
    return tostring(square:getX()) .. ":" .. tostring(square:getY()) .. ":" .. tostring(square:getZ())
end

local function now()
    if getTimestampMs then
        local ok, ms = pcall(getTimestampMs)
        if ok and type(ms) == "number" then
            return ms
        end
    end
    return nil
end

function Mains.clearCache()
    probeCache = {}
end

-- Is `worldObject` a plumbed fixture that still has town water behind it?
function Mains.isLiveAt(worldObject)
    if not Mains.isEnabled() or not worldObject then
        return false
    end

    local modData = getModData(worldObject)
    if not modData or modData[Constants.PLUMBED_ENDPOINT_MODDATA_KEY] ~= true then
        return false
    end

    if not isMainsFixture(worldObject) then
        return false
    end

    local key = cacheKey(worldObject)
    local stamp = now()
    if key and stamp then
        local cached = probeCache[key]
        if cached and (stamp - cached.stamp) < Constants.MAINS_PROBE_TTL_MS then
            return cached.live
        end
    end

    local live = probeServiceLive(worldObject)
    if key and stamp then
        probeCache[key] = { live = live, stamp = stamp }
    end
    return live
end

-- The live inlet on a square, or nil. A square holds at most one fixture worth calling an inlet.
function Mains.findOnSquare(square)
    if not Mains.isEnabled() or not square or not square.getObjects then
        return nil
    end

    local ok, objects = pcall(square.getObjects, square)
    if not ok or not objects then
        return nil
    end

    for index = 0, objects:size() - 1 do
        local worldObject = objects:get(index)
        if worldObject and Mains.isLiveAt(worldObject) then
            return worldObject
        end
    end
    return nil
end

return Mains
