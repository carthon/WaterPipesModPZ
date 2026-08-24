WaterPipes = WaterPipes or {}
WaterPipes.System = WaterPipes.System or {}

require "WaterPipes/Constants"
require "WaterPipes/Logger"
require "WaterPipes/State"
require "WaterPipes/ContainerAdapter"
require "WaterPipes/EndpointAdapterSource"
require "WaterPipes/EndpointFluidSource"
require "WaterPipes/EndpointPlumbing"
require "WaterPipes/EndpointObjects"
require "WaterPipes/GeneratorFuel"
require "WaterPipes/PipeObjectUtils"
require "WaterPipes/Purifier"
require "WaterPipes/GravityFlow"
require "WaterPipes/Router"
require "WaterPipes/NetworkAccess"
require "WaterPipes/Mains"
require "WaterPipes/Pump"
require "WaterPipes/Hydrant"
require "WaterPipes/Stagnation"
require "WaterPipes/Hydraulics"
require "WaterPipes/Irrigation"
require "WaterPipes/Profiler"
require "WaterPipes/API"
require "WaterPipes/PipeAutotile"

local Adapter = WaterPipes.ContainerAdapter
local Constants = WaterPipes.Constants
local AdapterSource = WaterPipes.EndpointAdapterSource
local FluidSource = WaterPipes.EndpointFluidSource
local EndpointPlumbing = WaterPipes.EndpointPlumbing
local EndpointObjects = WaterPipes.EndpointObjects
local GeneratorFuel = WaterPipes.GeneratorFuel
local Logger = WaterPipes.Logger
local PipeObjectUtils = WaterPipes.PipeObjectUtils
local Profiler = WaterPipes.Profiler
local PipeAutotile = WaterPipes.PipeAutotile
local Purifier = WaterPipes.Purifier
local GravityFlow = WaterPipes.GravityFlow
local Router = WaterPipes.Router
local NetworkAccess = WaterPipes.NetworkAccess
local Mains = WaterPipes.Mains
local Pump = WaterPipes.Pump
local Hydrant = WaterPipes.Hydrant
local Stagnation = WaterPipes.Stagnation
local Hydraulics = WaterPipes.Hydraulics
local Irrigation = WaterPipes.Irrigation
local State = WaterPipes.State
local System = WaterPipes.System

-- Single-player has no client/server split. PipeAutotile is driven by client-side events that do not
-- reliably fire on a freshly-built entity in SP, so the build path repaints directly -- ONLY in SP.
-- A dedicated/host server must never change and sync the sprite.
local function isSinglePlayer()
    return not (isClient and isClient()) and not (isServer and isServer())
end

local function mergeInto(target, source)
    for key, value in pairs(source) do
        target[key] = value
    end
end

local function getSquare(x, y, z)
    if not getCell then
        return nil
    end

    local cell = getCell()
    if not cell or not cell.getGridSquare then
        return nil
    end

    return cell:getGridSquare(x, y, z)
end

local function refreshPlumbedEndpointsNearCoordinates(coordinates)
    local visited = {}

    for _, position in ipairs(coordinates or {}) do
        local square = getSquare(position.x, position.y, position.z)
        if square then
            for _, endpointObject in ipairs(EndpointObjects.collectOnSquare(square)) do
                local key = tostring(square:getX()) .. ":" .. tostring(square:getY()) .. ":" .. tostring(square:getZ()) .. ":" .. tostring(endpointObject:getObjectIndex())
                if not visited[key] and EndpointPlumbing.isPlumbed(endpointObject) then
                    visited[key] = true
                    -- Every path that finds a plumbed fixture feeds the index, so a save made before the index existed
                    -- gets picked up the first time anything is built near one of its sinks.
                    State.registerEndpoint(position.x, position.y, position.z)
                    EndpointPlumbing.refreshEndpointSource(endpointObject)
                end
            end
        end
    end
end

local function refreshPlumbedGeneratorsNearCoordinates(coordinates)
    local visited = {}

    for _, position in ipairs(coordinates or {}) do
        local square = getSquare(position.x, position.y, position.z)
        if square and square.getObjects then
            local objects = square:getObjects()
            for i = 0, objects:size() - 1 do
                local worldObject = objects:get(i)
                if GeneratorFuel.isGenerator(worldObject) and GeneratorFuel.isPlumbed(worldObject) then
                    local key = tostring(square:getX()) .. ":" .. tostring(square:getY()) .. ":" .. tostring(square:getZ()) .. ":" .. tostring(worldObject:getObjectIndex())
                    if not visited[key] then
                        visited[key] = true
                        State.registerEndpoint(position.x, position.y, position.z)
                        GeneratorFuel.refresh(worldObject)
                    end
                end
            end
        end
    end
end

local function releasePlumbedEndpointReservationsNearCoordinates(coordinates)
    local visited = {}

    for _, position in ipairs(coordinates or {}) do
        local square = getSquare(position.x, position.y, position.z)
        if square then
            for _, endpointObject in ipairs(EndpointObjects.collectOnSquare(square)) do
                local key = tostring(square:getX()) .. ":" .. tostring(square:getY()) .. ":" .. tostring(square:getZ()) .. ":" .. tostring(endpointObject:getObjectIndex())
                if not visited[key] and EndpointPlumbing.isPlumbed(endpointObject) then
                    visited[key] = true
                    EndpointPlumbing.releaseReservation(endpointObject)
                end
            end
        end
    end
end

function System.scanContainersAroundPipes()
    local state = State.ensure()
    local found = {}

    -- A container connects only when a (horizontal) pipe sits on its OWN tile -- not by adjacency.
    for _, pipeData in pairs(state.pipes) do
        local square = getSquare(pipeData.x, pipeData.y, pipeData.z)
        if square then
            mergeInto(found, Adapter.collectSquareContainers(square))

            -- Reconcile the purifier registry and fill in a missing `kind` while standing on the tile anyway: a
            -- save made before either existed carries devices nobody recorded, and the answer is on the object.
            -- Only router tiles are asked. One pass over ten in-game minutes fills the whole base.
            local metadata = pipeData.metadata
            if not metadata or not metadata.kinds then
                metadata = metadata or {}
                for _, worldObject in ipairs(PipeObjectUtils.getPipeObjectsOnSquare(square)) do
                    if Router.isRouter(worldObject) then metadata.router = true end
                    if Pump.isPump(worldObject) then metadata.pump = true end
                    if Irrigation.isDrip(worldObject) then metadata.drip = true end
                    if Irrigation.isSprinkler(worldObject) then metadata.sprinkler = true end
                end
                metadata.kinds = true
                pipeData.metadata = metadata
            end

            if pipeData.metadata and pipeData.metadata.router == true then
                local purifier = Purifier.findForRouterSquare(square)
                if purifier then
                    local ok, purifierSquare = pcall(purifier.getSquare, purifier)
                    if not ok or not purifierSquare then
                        purifierSquare = square
                    end
                    State.registerPurifier(purifierSquare:getX(), purifierSquare:getY(),
                        purifierSquare:getZ())
                end
            end
        end
    end

    State.replaceContainers(found)
    return found
end

-- ===== Conservation accounting =====
-- Every litre the mod is holding anywhere, counted by reading the WORLD rather than any summary, cache
-- or graph. That independence is the point: a check that asked NetworkAccess would be grading the
-- network's arithmetic against itself and would pass however broken the writes were.
-- Counted: every fluid vessel sharing a tile with a registered pipe, plus the IN and OUT buffers of any
-- purifier, which are modData numbers no container scan would see. Returns (litres, vesselCount).
function System.totalNetworkWater()
    local state = State.ensure()
    local total = 0
    local vessels = 0

    -- Vessels keyed by descriptor key, purifiers by object, so a device reachable from two registered tiles
    -- is still counted once.
    local seenVessels = {}
    local seenPurifiers = {}

    for _, pipeData in pairs(state.pipes) do
        local square = getSquare(pipeData.x, pipeData.y, pipeData.z)
        if square then
            for key, descriptor in pairs(Adapter.collectSquareContainers(square)) do
                if not seenVessels[key] then
                    seenVessels[key] = true
                    total = total + math.max(descriptor.waterAmount or 0, 0)
                    vessels = vessels + 1
                end
            end

            -- findForRouterSquare scans a 2x2 footprint, so it is only worth asking on tiles that carry a router.
            local purifier
            if pipeData.metadata and pipeData.metadata.router == true then
                purifier = Purifier.findForRouterSquare(square)
            else
                purifier = Purifier.findOnSquare(square)
            end
            if purifier and not seenPurifiers[tostring(purifier)] then
                seenPurifiers[tostring(purifier)] = true
                total = total + math.max(Purifier.getInAmount(purifier) or 0, 0)
                    + math.max(Purifier.getOutAmount(purifier) or 0, 0)
                vessels = vessels + 1
            end
        end
    end

    return total, vessels
end

-- Run one irrigation pass and check the books: the litres the emitters report spending must equal the
-- litres the world is missing afterwards.
-- The accounting is spread across five places -- the epsilon guard that may decline a write, the carry
-- that re-homes what it declined, the nearest-vessel draw, the summary write-back and the emitters' own
-- bookkeeping -- and any of them could conjure or destroy a litre with nothing looking wrong on screen.
-- `error` is (missing - spent): positive means water was destroyed, negative means it was conjured.
function System.checkIrrigationConservation(dtHours)
    dtHours = dtHours or 1.0

    -- Read the world cold: neither measurement may be served from something built earlier by whatever
    -- triggered the check, and none of these caches is frame-scoped any more.
    Adapter.invalidateVesselCache()
    NetworkAccess.invalidateTraversalCache()
    PipeObjectUtils.invalidateScanCache()

    local before, vessels = System.totalNetworkWater()
    local spent = Irrigation.run(dtHours) or 0

    Adapter.invalidateVesselCache()
    local after = System.totalNetworkWater()

    local missing = before - after
    local report = {
        dtHours = dtHours,
        before = before,
        after = after,
        missing = missing,
        spent = spent,
        error = missing - spent,
        vessels = vessels,
    }
    -- One hundredth of a litre is the write guard's own threshold, so anything under it is the rounding the
    -- design allows. Above it, something is genuinely losing or inventing water.
    report.ok = math.abs(report.error) <= Constants.FLUID_WRITE_EPSILON

    Logger.log(string.format(
        "[conservation] dt=%.2fh vessels=%d | before %.4f L -> after %.4f L | missing %.4f L, emitters spent %.4f L | error %+.4f L -> %s",
        report.dtHours, report.vessels, report.before, report.after,
        report.missing, report.spent, report.error, report.ok and "OK" or "MISMATCH"))

    return report
end

function System.redistributeWater()
    local components = State.getComponents()

    for _, component in ipairs(components) do
        local containers = {}
        local totalCapacity = 0
        local totalWater = 0
        local totalByFluidType = {}
        local fluidTypeCount = 0
        local networkFluidType = nil

        for _, node in pairs(component.nodes) do
            if node.kind == Constants.NODE_KIND_CONTAINER then
                local square = getSquare(node.x, node.y, node.z)
                if square and square.getObjects then
                    local squareContainers = Adapter.collectSquareContainers(square)
                    local containerKey = node.key
                    local descriptor = squareContainers[containerKey]

                    if descriptor and descriptor.container then
                        containers[#containers + 1] = descriptor
                        totalCapacity = totalCapacity + math.max(descriptor.capacity or 0, 0)
                        totalWater = totalWater + math.max(descriptor.waterAmount or 0, 0)
                    elseif descriptor and descriptor.object then
                        containers[#containers + 1] = descriptor
                        totalCapacity = totalCapacity + math.max(descriptor.capacity or 0, 0)
                        totalWater = totalWater + math.max(descriptor.waterAmount or 0, 0)
                    end

                    if descriptor and descriptor.fluidType and (descriptor.waterAmount or 0) > 0 then
                        totalByFluidType[descriptor.fluidType] = (totalByFluidType[descriptor.fluidType] or 0) + descriptor.waterAmount
                    end
                end
            end
        end

        for fluidTypeName in pairs(totalByFluidType) do
            fluidTypeCount = fluidTypeCount + 1
            networkFluidType = fluidTypeName
        end

        if fluidTypeCount <= 1 and #containers > 1 and totalCapacity > 0 then
            -- Gravity settle: water pools to the lowest floors first. A single-floor component reduces to the
            -- classic per-pool equalization, so one floor is unchanged.
            GravityFlow.settle(containers, totalWater, networkFluidType)
        elseif fluidTypeCount > 1 then
            Logger.warn("Skipping mixed-fluid network with " .. tostring(fluidTypeCount) .. " fluid types")
        end
    end
end

-- No purifier on the tile: one-way passthrough of the IN network's single fluid into the OUT network.
-- `dt` is the elapsed in-game minutes for this sub-step; rates are per-minute and scaled by it.
local function processPassthroughRouter(inSquare, outSquare, dt)
    local avail, fluidType = NetworkAccess.availableToPull(inSquare)
    if not fluidType or avail <= 0 then
        return
    end
    local headroom = NetworkAccess.availableToPush(outSquare, fluidType)
    if headroom <= 0 then
        return
    end
    local transfer = math.min(Constants.ROUTER_TRANSFER_RATE * dt, avail, headroom)
    if transfer <= 0 then
        return
    end
    local drawn = NetworkAccess.drawFluidAtSquare(inSquare, fluidType, transfer)
    if drawn and drawn > 0 then
        NetworkAccess.fillFluidAtSquare(outSquare, fluidType, drawn)
    end
end

-- Purifier on the tile: IN network -> IN buffer -> convert -> OUT buffer -> OUT network. Intake pulls
-- ONLY TAINTED water and ONLY from the IN network; output pushes clean water ONLY into the OUT network.
-- Intake happens with or without power; only converting needs power and filter life.
-- Step order is OUTPUT -> CONVERT -> INTAKE on purpose: draining the output first and refilling the
-- intake last leaves water resident in both buffers between ticks, so the tanks hold a real level
-- instead of being cycled to 0 every tick. Water just takes one extra tick to traverse.
-- `dt` is the elapsed in-game minutes for this sub-step; the per-minute rates are scaled by it.
local function processPurifierRouter(purifier, inSquare, outSquare, dt)
    -- Set by whichever step actually moves fluid. A tank sitting full while it pushes clean water out IS
    -- busy, and the readout used to call that "Stopped" purely because the levels looked static.
    local processed = false

    -- 1. Output: even the OUT buffer out with the rest of the clean network.
    -- It used to PUSH -- read the buffer, ask the network for headroom, fill it, subtract what was taken --
    -- which is exactly wrong now that the buffer IS one of that network's containers: the fill rebalances
    -- water back into the buffer and the subtraction removes it a second time. Settling moves nothing in or
    -- out, it only lets the level equalise; with no barrels it is a no-op and a tap can still reach it.
    local outAmount = Purifier.getOutAmount(purifier)
    if outAmount > 0 then
        local settled = NetworkAccess.settleAtSquare(outSquare)
        if settled > 0 and Purifier.getOutAmount(purifier) ~= outAmount then
            processed = true
        end
    end

    -- 2. Convert: move IN -> OUT. Tainted needs power AND filter life; clean water always passes.
    local inAmount = Purifier.getInAmount(purifier)
    if inAmount > 0 then
        local outHeadroom = Constants.PURIFIER_BUFFER_CAPACITY - Purifier.getOutAmount(purifier)
        if outHeadroom > 0 then
            local move = math.min(Constants.PURIFIER_CONVERT_RATE * dt, inAmount, outHeadroom)
            if Purifier.isInTainted(purifier) then
                -- Cleaning tainted water needs power AND a filter with life left. Every unit converted wears the
                -- filter; at 0 condition it stops and the water waits in IN until the player repairs it.
                if Purifier.canFilter(purifier) then
                    local before = Purifier.getInAmount(purifier)
                    Purifier.moveInToOut(purifier, move)   -- lands in the OUT buffer as clean Water
                    local converted = before - Purifier.getInAmount(purifier)
                    Purifier.wearFilter(purifier, converted)
                    processed = processed or converted > 0
                end
                -- tainted + not powered / clogged filter: stays in the IN buffer until it can be cleaned
            else
                local before = Purifier.getInAmount(purifier)
                Purifier.moveInToOut(purifier, move)       -- clean water always passes through
                processed = processed or Purifier.getInAmount(purifier) < before
            end
        end
    end

    -- 3. Intake: pull ONLY TAINTED water, and ONLY from the router's IN side. The purifier never draws
    -- clean water and never pulls anything back off the OUT side. Runs with or without power; only
    -- converting it later needs power and filter life.
    local avail, fluidType = NetworkAccess.availableToPull(inSquare)
    if fluidType == "TaintedWater" and avail > 0 then
        local curIn = Purifier.getInAmount(purifier)
        -- Pull into an empty buffer or one already holding tainted water (it is always tainted now).
        if curIn <= 0 or Purifier.isInTainted(purifier) then
            local headroom = Constants.PURIFIER_BUFFER_CAPACITY - curIn
            local pull = math.min(Constants.PURIFIER_INTAKE_RATE * dt, avail, headroom)
            if pull > 0 then
                local drawn = NetworkAccess.drawFluidAtSquare(inSquare, "TaintedWater", pull)
                if drawn and drawn > 0 then
                    Purifier.addIn(purifier, drawn, true)
                    processed = true
                end
            end
        end
    end

    -- Record what actually happened, so the readout reports it instead of guessing from the levels.
    Purifier.setProcessing(purifier, processed)
end

-- Fluid routers actively move fluid across their boundary in the OUT direction each server tick. A
-- purifier-container on the tile purifies in transit; otherwise it is a plain one-way passthrough.
function System.processRouter(router, rx, ry, rz, dt)
    dt = dt or 1.0
    local out = Router.getOutOffset(router)
    if not out then
        return
    end

    local inSquare = getSquare(rx - out.dx, ry - out.dy, rz)
    local outSquare = getSquare(rx + out.dx, ry + out.dy, rz)
    if not inSquare or not outSquare then
        return
    end

    -- Scan the whole purifier footprint from the router tile: the tank's modData may live on a footprint
    -- tile other than the anchor. Missing it here would silently run a plain passthrough.
    local purifier = Purifier.findForRouterSquare(getSquare(rx, ry, rz))
    if purifier then
        processPurifierRouter(purifier, inSquare, outSquare, dt)
    else
        processPassthroughRouter(inSquare, outSquare, dt)
    end
end

-- `dt` = elapsed in-game minutes since routers were last processed (defaults to a 1-minute step).
function System.processRouters(dt)
    dt = dt or 1.0
    if dt <= 0 then
        return
    end
    local state = State.ensure()
    for _, pipeData in pairs(state.pipes) do
        if pipeData.metadata and pipeData.metadata.router == true then
            local square = getSquare(pipeData.x, pipeData.y, pipeData.z)
            local router = square and Router.findOnSquare(square)
            if router then
                System.processRouter(router, pipeData.x, pipeData.y, pipeData.z, dt)
            end
        end
    end
end

-- A powered pump next to a well or open water injects fluid into its network. It is NOT a container: a
-- well holds 10 000 L and open water is infinite, so letting either join as storage would leave
-- rebalanceSummary smearing them across every pipe and the network permanently full.

-- Which purifier, if any, this pump can feed: one on a router bordering the pump's own zone, approached
-- from the router's IN side. The OUT offset points at the clean side, so pushing raw lake water in
-- there would contaminate the clean run.
-- Driven by the REGISTRY rather than by searching the world -- a purifier cannot exist without a router
-- under it, and both appear and disappear by player action. The old walk probed six neighbours of every
-- tile of the pump's network, about 1 260 lookups per pump per minute, to return nil on a base with no
-- purifier at all. A registry entry is a claim, not a fact: one the world contradicts is dropped here.
local function findPurifierIntakeForPump(square)
    local purifiers = State.getPurifiers()
    local cell = getCell and getCell() or nil
    if not purifiers or not cell then
        return nil
    end

    -- Built on first use, so an empty registry never pays for it.
    local networkKeys = nil
    local stale = nil

    local function routerFeedsNetwork(routerSquare)
        local router = Router.findOnSquare(routerSquare)
        local out = router and Router.getOutOffset(router)
        if not out then
            return false
        end

        local rx, ry, rz = routerSquare:getX(), routerSquare:getY(), routerSquare:getZ()
        for _, offset in ipairs(Constants.NETWORK_NEIGHBOR_OFFSETS) do
            local tx, ty, tz = rx + offset.x, ry + offset.y, rz + offset.z
            -- The OUT tile is the clean side; feeding the intake from there would push purified water
            -- back through the filter. Every other side is the dirty side, which is what a pump wants.
            local isOutSide = tx == rx + out.dx and ty == ry + out.dy and tz == rz
            if not isOutSide and networkKeys[State.squareKey(tx, ty, tz)] then
                return true
            end
        end
        return false
    end

    for _, coord in pairs(purifiers) do
        local purifierSquare = getSquare(coord.x, coord.y, coord.z)
        -- An unloaded square is not a contradiction: it says nothing either way, so the claim stands.
        if purifierSquare then
            if not Purifier.findOnSquare(purifierSquare) then
                stale = stale or {}
                stale[#stale + 1] = coord
            else
                if not networkKeys then
                    networkKeys = {}
                    for _, pipeSquare in ipairs(NetworkAccess.getNetworkSquares(square) or {}) do
                        networkKeys[State.squareKey(pipeSquare:getX(), pipeSquare:getY(),
                            pipeSquare:getZ())] = true
                    end
                end

                -- The purifier sits on its router or beside it, so both are candidates.
                local found = nil
                if Purifier.findForRouterSquare(purifierSquare)
                    and routerFeedsNetwork(purifierSquare) then
                    found = Purifier.findForRouterSquare(purifierSquare)
                end
                if not found then
                    for _, offset in ipairs(Constants.NETWORK_NEIGHBOR_OFFSETS) do
                        local routerSquare = cell:getGridSquare(coord.x + offset.x,
                            coord.y + offset.y, coord.z + offset.z)
                        if routerSquare and Router.hasRouterOnSquare(routerSquare) then
                            local purifier = Purifier.findForRouterSquare(routerSquare)
                            if purifier and routerFeedsNetwork(routerSquare) then
                                found = purifier
                                break
                            end
                        end
                    end
                end

                if found then
                    for _, gone in ipairs(stale or {}) do
                        State.unregisterPurifier(gone.x, gone.y, gone.z)
                    end
                    return found
                end
            end
        end
    end

    for _, gone in ipairs(stale or {}) do
        State.unregisterPurifier(gone.x, gone.y, gone.z)
    end
    return nil
end

function System.processPump(pump, square, dt)
    local source = Profiler.time("pump/source", Pump.findSource, pump)
    if not source then
        return   -- booster only: nothing to draw from, but it still adds head to its zone
    end

    -- Ask what can take water FIRST, so we never pull it out of a well and lose it.
    -- Two destinations, not one: a fill query stops dead at a router and a purifier sits on a router, so a
    -- pump feeding one with storage only on the clean side was told "no room" and drew nothing at all.
    local tainted = source.fluidType == "TaintedWater"
    local headroom = Profiler.time("pump/headroom", NetworkAccess.availableToPush,
        square, source.fluidType)
    local purifier = Profiler.time("pump/purifier", findPurifierIntakeForPump, square)
    local purifierRoom = purifier and Purifier.intakeHeadroom(purifier, tainted) or 0

    local wanted = math.min(Pump.intakeFor(dt), headroom + purifierRoom)
    if wanted <= 0 then
        return
    end

    local taken = Profiler.time("pump/draw", Pump.drawFromSource, source, wanted)
    if taken <= 0 then
        return
    end

    -- Network first: it is the destination the player can actually see filling up.
    local added = 0
    if headroom > 0 then
        added = Profiler.time("pump/fill", NetworkAccess.fillFluidAtSquare,
            square, source.fluidType, math.min(taken, headroom))
    end

    local leftover = taken - added
    if leftover > 0 and purifierRoom > 0 and purifier then
        local intoTank = math.min(leftover, purifierRoom)
        Purifier.addIn(purifier, intoTank, tainted)
        added = added + intoTank
    end

    if added < taken then
        -- Less was taken than we drew (a race with another consumer, or a mixed-fluid refusal). Put the
        -- remainder back rather than quietly destroying it.
        Pump.refundToSource(source, taken - added)
    end
end

function System.processPumps(dt)
    dt = dt or 1.0
    if dt <= 0 then
        return
    end
    local state = State.ensure()
    for _, pipeData in pairs(state.pipes) do
        -- Skip only what we KNOW is not a pump. An entry without `kinds` predates the registry recording it, so
        -- it is still probed rather than silently switched off in an existing save.
        local metadata = pipeData.metadata
        if not (metadata and metadata.kinds and not metadata.pump) then
            local square = getSquare(pipeData.x, pipeData.y, pipeData.z)
            local pump = square and Pump.findOnSquare(square)
            if pump and Pump.isPowered(pump) then
                System.processPump(pump, square, dt)
            end
        end
    end
end

-- A plumbed fixture that still has town water behind it fills the network. Simpler than the pump: the
-- mains is not a container we can overdraw, so there is nothing to draw first and nothing to refund.
function System.processMains(square, dt)
    local wanted = math.min(Mains.intakeFor(dt),
        NetworkAccess.availableToPush(square, "Water"))
    if wanted <= 0 then
        return
    end
    NetworkAccess.fillFluidAtSquare(square, "Water", wanted)
end

function System.processAllMains(dt)
    dt = dt or 1.0
    if dt <= 0 or not Mains.isEnabled() then
        return
    end
    local state = State.ensure()
    for _, pipeData in pairs(state.pipes) do
        local square = getSquare(pipeData.x, pipeData.y, pipeData.z)
        if square and Mains.findOnSquare(square) then
            System.processMains(square, dt)
        end
    end
end

-- An OPEN hydrant gushes at its flow rate: whatever the network on its tile can take is fed in, the
-- rest spills onto the street and is wasted. While the town service runs its reserve is held full and
-- the waste costs nothing; once the water is cut, the whole flow comes out of the fixed reserve.
function System.processHydrant(hydrant, square, dt)
    local mainsFed = Hydrant.isMainsFed()
    if mainsFed then
        Hydrant.setReserve(hydrant, Hydrant.capacity())   -- topped while the main has water
    end

    local reserve = Hydrant.reserve(hydrant)
    local flow = mainsFed and Hydrant.flowFor(dt) or math.min(Hydrant.flowFor(dt), reserve)
    if flow <= 0 then
        return
    end

    -- The network takes what it can and the remainder is spilled: the reserve loses the whole flow whether
    -- or not anything was connected.
    NetworkAccess.fillFluidAtSquare(square, "Water", flow)
    if not mainsFed then
        Hydrant.setReserve(hydrant, reserve - flow)
    end

    -- The spilled water lands somewhere: the gush waters the hydrant's own 3x3 like a sprinkler. Free
    -- litres -- they are already leaving through the open cap.
    Irrigation.waterHydrantSurroundings(square, dt / 60)
end

-- Driven by the open-hydrant registry rather than the pipe list, so a hydrant opened with no pipe on its
-- tile still wastes water. Self-cleaning: an entry whose hydrant is gone or closed is dropped here.
function System.processHydrants(dt)
    dt = dt or 1.0
    if dt <= 0 then
        return
    end
    for key, coord in pairs(State.getOpenHydrants()) do
        local square = getSquare(coord.x, coord.y, coord.z)
        if square then
            local hydrant = Hydrant.findOnSquare(square)
            if hydrant and Hydrant.isOpen(hydrant) then
                System.processHydrant(hydrant, square, dt)
            else
                State.setHydrantOpen(coord.x, coord.y, coord.z, false)
            end
        end
    end
end

-- ===== Water stagnation =====

-- The live water vessels of one network component: descriptor + its square + its FluidContainer,
-- gathered the same way redistributeWater does. Only actual containers holding fluid are returned.
local function collectComponentVessels(component)
    local vessels = {}
    for _, node in pairs(component.nodes) do
        if node.kind == Constants.NODE_KIND_CONTAINER then
            local square = getSquare(node.x, node.y, node.z)
            if square then
                local descriptor = Adapter.collectSquareContainers(square)[node.key]
                if descriptor and descriptor.object then
                    vessels[#vessels + 1] = { descriptor = descriptor, square = square,
                        object = descriptor.object }
                end
            end
        end
    end
    return vessels
end

local function fluidContainerOf(object)
    if not object or not object.getFluidContainer then
        return nil
    end
    local ok, fc = pcall(object.getFluidContainer, object)
    return ok and fc or nil
end

-- A component taints as one body of water, so this acts per component: the first vessel that says yes
-- taints the whole network through it. Fresh clean vessels are stamped now, so their clock starts from
-- first sight rather than turning the instant the feature is switched on.
local function taintComponentsWhere(predicate)
    for _, component in ipairs(State.getComponents()) do
        local vessels = collectComponentVessels(component)
        local taint = false
        for _, vessel in ipairs(vessels) do
            local d = vessel.descriptor
            if (d.waterAmount or 0) > 0 and d.fluidType == "Water" then
                if predicate(vessel) then
                    taint = true
                    break
                end
            end
        end
        if taint and vessels[1] then
            local turned = NetworkAccess.taintNetworkAt(vessels[1].square)
            if turned > 0 then
                Logger.log(string.format("[stagnation] tainted %.0f L across a network", turned))
            end
        end
    end
end

-- Hourly: water that has sat still past its limit turns. Open vessels (rain-catchers) spoil faster
-- than sealed ones; a network that is being drawn from keeps stamping itself and never gets here.
function System.processStagnation()
    if not Stagnation.isEnabled() then
        return
    end
    local nowHours = Stagnation.nowHours()
    if not nowHours then
        return
    end
    taintComponentsWhere(function(vessel)
        local open = Stagnation.isOpenContainer(fluidContainerOf(vessel.object))
        local stamp = Stagnation.readStamp(vessel.object)
        if not stamp then
            -- First time we have seen it: start its clock, do not taint yet.
            Stagnation.stamp(vessel.object, nowHours)
            return false
        end
        return Stagnation.hasStagnated(stamp, open, nowHours)
    end)
end

-- Every ten minutes while it rains: an OPEN vessel that is also OUTSIDE contaminates its whole network.
-- The same gamble vanilla already takes with its rain barrels, extended to the plumbed system.
function System.processRainTaint()
    if not Stagnation.isEnabled() or not Stagnation.rainTaints() then
        return
    end
    if not RainManager or not RainManager.isRaining or not RainManager.isRaining() then
        return
    end
    taintComponentsWhere(function(vessel)
        if not Stagnation.isOpenContainer(fluidContainerOf(vessel.object)) then
            return false
        end
        local square = vessel.square
        if not square.isOutside then
            return false
        end
        local ok, outside = pcall(square.isOutside, square)
        return ok and outside or false
    end)
end

-- Every pipe tile and its six neighbours, DEDUPLICATED.
-- A pipe contributes itself plus six neighbours, and on a dense grid almost every one of those is
-- another pipe: a 192-tile farm produced 1 344 positions covering barely 250 distinct tiles, and each
-- pass turned every one into a getGridSquare and a full object scan. The passes' own `visited` sets
-- spared only the ENDPOINT work -- the lookup and the scan had already been paid.
local function collectPipeNeighbourhood(state)
    local seen = {}
    local coordinates = {}

    local function add(x, y, z)
        local key = tostring(x) .. ":" .. tostring(y) .. ":" .. tostring(z)
        if seen[key] then
            return
        end
        seen[key] = true
        coordinates[#coordinates + 1] = { x = x, y = y, z = z }
    end

    for _, pipeData in pairs(state.pipes) do
        add(pipeData.x, pipeData.y, pipeData.z)
        for _, offset in ipairs(Constants.NETWORK_NEIGHBOR_OFFSETS) do
            add(pipeData.x + offset.x, pipeData.y + offset.y, pipeData.z + offset.z)
        end
    end

    return coordinates
end

-- Rebuild the endpoint index from the world, and say what it found that nobody had recorded.
-- The old per-minute behaviour, kept as a ten-minute BACKSTOP rather than the working path, and made to
-- report: a tile it discovers that the registry did not claim means a fixture became plumbed without
-- EndpointPlumbing.plumb hearing about it. A silent backstop could never answer that; if this one stays
-- quiet across enough sessions it can be deleted.
function System.reindexEndpoints()
    local coordinates = collectPipeNeighbourhood(State.ensure())
    local known = State.getEndpoints()
    local discovered = 0

    -- The FIRST index of a save is a migration, not a finding: a save made before the registry existed has
    -- every plumbed fixture unrecorded, and reporting each as an escape would bury the real case.
    local migrating = not State.endpointsIndexed()

    for _, position in ipairs(coordinates) do
        local square = getSquare(position.x, position.y, position.z)
        if square then
            local plumbed = false
            for _, endpointObject in ipairs(EndpointObjects.collectOnSquare(square)) do
                if EndpointPlumbing.isPlumbed(endpointObject) then
                    plumbed = true
                    break
                end
            end
            if not plumbed and square.getObjects then
                local objects = square:getObjects()
                for i = 0, objects:size() - 1 do
                    local worldObject = objects:get(i)
                    if GeneratorFuel.isGenerator(worldObject)
                        and GeneratorFuel.isPlumbed(worldObject) then
                        plumbed = true
                        break
                    end
                end
            end
            if plumbed and not known[State.squareKey(position.x, position.y, position.z)] then
                discovered = discovered + 1
                if not migrating then
                    Logger.warn(string.format(
                        "ENDPOINT NOT INDEXED: a plumbed fixture at %d:%d:%d was found by the sweep, "
                        .. "not by an event. The per-minute refresh would have missed it.",
                        position.x, position.y, position.z))
                end
                State.registerEndpoint(position.x, position.y, position.z)
            end
        end
    end

    if migrating then
        Logger.log(string.format(
            "Endpoint index built for this save: %d plumbed tile(s) recorded. From here they are "
            .. "recorded as they are plumbed, and this sweep is only a backstop.", discovered))
    end

    State.markEndpointsIndexed()
    return discovered
end

-- The per-minute refresh, reading the index instead of searching for its work.
-- Each entry is a CLAIM, settled here: a tile whose square is loaded and holds nothing plumbed is
-- dropped, while a tile whose square is NOT loaded is left alone -- walking away from your base must
-- not erase its plumbing.
function System.refreshPlumbedEndpoints()
    -- A save made before the index existed has plumbed fixtures and no record of them. Find them once, on
    -- the first pass after loading, and never again.
    if not State.endpointsIndexed() then
        System.reindexEndpoints()
    end

    local stale = nil

    for key, position in pairs(State.getEndpoints()) do
        local square = getSquare(position.x, position.y, position.z)
        if square then
            local found = 0

            for _, endpointObject in ipairs(EndpointObjects.collectOnSquare(square)) do
                if EndpointPlumbing.isPlumbed(endpointObject) then
                    found = found + 1
                    EndpointPlumbing.refreshEndpointSource(endpointObject)
                end
            end

            if square.getObjects then
                local objects = square:getObjects()
                for i = 0, objects:size() - 1 do
                    local worldObject = objects:get(i)
                    if GeneratorFuel.isGenerator(worldObject)
                        and GeneratorFuel.isPlumbed(worldObject) then
                        found = found + 1
                        GeneratorFuel.refresh(worldObject)
                    end
                end
            end

            if found == 0 then
                stale = stale or {}
                stale[#stale + 1] = key
            end
        end
    end

    for _, key in ipairs(stale or {}) do
        State.getEndpoints()[key] = nil
    end
end

-- `afterLayoutChange` defaults to true: a build or a removal really has changed the shape.
-- The ten-minute pass passes FALSE. It calls this to re-read containers and rebuild the graph, not
-- because anything changed, and dropping the head field on that timer cost a full cold solve -- 141 ms,
-- arriving every seven real seconds at x3 speed -- for a shape that was almost always identical.
-- Nothing is lost by not dropping: every way the layout can actually change fires an object event that
-- drops by tile, and the one path known to fire none (fire) is caught by verifyCachesAgainstTheWorld,
-- which reports the drift AND falls back to the wholesale drop. Dropping because something IS wrong,
-- rather than in case it might be.
function System.rebuild(afterLayoutChange)
    if afterLayoutChange ~= false then
        -- Both caches invalidate by tile on object events, but a build and the rebuild it triggers happen in the
        -- same frame -- so without this the refresh that follows would still see the pre-build shape.
        PipeObjectUtils.invalidateScanCache()
        NetworkAccess.invalidateTraversalCache()
    end

    System.scanContainersAroundPipes()
    State.rebuildGraph()
end

function System.tick()
    local ok, err = pcall(function()
        -- Broken out because 10min measured 26 ms a pass and nothing said which third that was. A rebuild drops
        -- the traversal cache and the head field, so it is also what makes the NEXT cold solve happen.
        Profiler.time("10min/rebuild", System.rebuild, false)
        Profiler.time("10min/redist", System.redistributeWater)
        Profiler.time("10min/endpoints", System.refreshPlumbedEndpoints)
    end)

    if not ok then
        Logger.error("Tick failed: " .. tostring(err))
    end
end

function System.registerPipeAt(x, y, z, metadata)
    State.registerPipe(x, y, z, metadata)
    System.rebuild()
    System.refreshPlumbedEndpoints()
    if isSinglePlayer() then
        PipeAutotile.refreshAround(x, y, z)
    end
end

function System.unregisterPipeAt(x, y, z)
    local coordinates = {
        { x = x, y = y, z = z },
    }

    for _, offset in ipairs(Constants.NETWORK_NEIGHBOR_OFFSETS) do
        coordinates[#coordinates + 1] = {
            x = x + offset.x,
            y = y + offset.y,
            z = z + offset.z,
        }
    end

    releasePlumbedEndpointReservationsNearCoordinates(coordinates)
    State.unregisterPipe(x, y, z)
    System.rebuild()

    -- Catch the object that just lost the pipe on its OWN square (it is no longer adjacent to any
    -- remaining pipe, so the full scan below would miss it)...
    refreshPlumbedEndpointsNearCoordinates(coordinates)
    refreshPlumbedGeneratorsNearCoordinates(coordinates)
    -- ...and immediately refresh every object still attached anywhere in the (now smaller) network,
    -- so a break far down a long pipe chain is reflected at once (no stale "phantom water").
    System.refreshPlumbedEndpoints()
    if isSinglePlayer() then
        PipeAutotile.refreshAround(x, y, z)
    end
end

function System.forceGlobalWaterShutoff()
    local sandboxOptions = getSandboxOptions and getSandboxOptions() or nil
    if sandboxOptions and sandboxOptions.set then
        sandboxOptions:set("WaterShut", 1)
        sandboxOptions:set("WaterShutModifier", 0)
        if sandboxOptions.toLua then
            sandboxOptions:toLua()
        end
    end

    if SandboxVars then
        SandboxVars.WaterShut = 1
        SandboxVars.WaterShutModifier = 0
    end

    Logger.warn("Debug forced global water shutoff")
end

local function onInitGlobalModData()
    State.ensure()
    System.rebuild()
    System.refreshPlumbedEndpoints()
    Logger.log("Server state initialized")
end

-- Pipe removal is processed ONE TICK later: some removal events (notably OnObjectAboutToBeRemoved, used
-- by the moveable pickup) fire BEFORE the object leaves the square, so a synchronous re-check would
-- still see the pipe. The next-tick guard also covers multi-pipe squares and cancelled removals.
local pendingPipeRemovals = {}
local pendingMaterialDrops = {}
local pendingRemovalScheduled = false

-- Chance a dismantled pipe hands its build material back. The scrap table cannot know what the pipe was
-- built FROM; this code can (see WaterPipeScrap.lua).
local DISMANTLE_RETURN_CHANCE = 90

-- Diagnostics for the build-material stamp, logged once per outcome (see schedulePipeRemoval).
local loggedDismantleMaterial = { [true] = false, [false] = false }

-- Every key a pipe's modData carries, sorted: a pipe that lost all its modData is a different bug from
-- one that only lost the material stamp.
local function describeModDataKeys(modData)
    if not modData then
        return "<no modData>"
    end
    local keys = {}
    local ok = pcall(function()
        for key in pairs(modData) do
            keys[#keys + 1] = tostring(key)
        end
    end)
    if not ok then
        return "<unreadable>"
    end
    table.sort(keys)
    return "{" .. table.concat(keys, ",") .. "}"
end

local function processPendingPipeRemovals()
    pendingRemovalScheduled = false
    if Events and Events.OnTick then
        Events.OnTick.Remove(processPendingPipeRemovals)
    end

    local toProcess = pendingPipeRemovals
    pendingPipeRemovals = {}
    local drops = pendingMaterialDrops
    pendingMaterialDrops = {}

    -- Material returns first, one per dismantled OBJECT: a cancelled removal drops nothing, and a
    -- multi-pipe square pays for exactly the pipe that was taken down.
    for _, drop in ipairs(drops) do
        local square = getSquare(drop.x, drop.y, drop.z)
        if square and square.getObjects then
            local stillThere = false
            local objects = square:getObjects()
            for index = 0, objects:size() - 1 do
                if objects:get(index) == drop.object then
                    stillThere = true
                    break
                end
            end
            if not stillThere and ZombRand and ZombRand(100) < DISMANTLE_RETURN_CHANCE then
                pcall(square.AddWorldInventoryItem, square, drop.itemType, 0.5, 0.5, 0.0)
            end
        end
    end

    for _, position in pairs(toProcess) do
        local square = getSquare(position.x, position.y, position.z)
        -- Only unregister once the square is loaded and no pipe remains there.
        if square and PipeObjectUtils.getPipeOnSquare(square) == nil then
            System.unregisterPipeAt(position.x, position.y, position.z)
        end
    end
end

local function schedulePipeRemoval(object, returnsMaterial)
    if not object or not PipeObjectUtils.isPipeObject(object) then
        return
    end

    local square = object.getSquare and object:getSquare() or nil
    if not square then
        return
    end

    local x, y, z = square:getX(), square:getY(), square:getZ()
    pendingPipeRemovals[tostring(x) .. ":" .. tostring(y) .. ":" .. tostring(z)] = { x = x, y = y, z = z }

    -- The material has to be read NOW: by the time the removal is confirmed next tick the object and its
    -- modData are gone.
    -- CLAY GIVES NOTHING BACK. A fired clay segment cannot be unfired, so it is spent the moment it is
    -- laid. That is the trade against metal: clay is cheap and needs no forge, but it is one-way, while a
    -- metal pipe is salvage. Without this, clay would be strictly better and nobody would forge one.
    if returnsMaterial then
        local clay, source = PipeObjectUtils.isClayBuilt(object)

        -- Once per outcome per session. The build side logs what it stamped; this logs what the other end
        -- concluded, which is the only way to tell "never stamped" from "stamped and lost".
        if not loggedDismantleMaterial[clay] then
            loggedDismantleMaterial[clay] = true
            local okMod, modData = pcall(object.getModData, object)
            Logger.log(string.format(
                "dismantle at %d:%d:%d -> %s (via %s, modData keys=%s)",
                x, y, z, clay and "CLAY, returns nothing" or "metal, returns a pipe",
                source, describeModDataKeys(okMod and modData or nil)))
        end

        if not clay then
            pendingMaterialDrops[#pendingMaterialDrops + 1] = {
                x = x, y = y, z = z, object = object,
                itemType = "Base.MetalPipe",
            }
        end
    end

    if not pendingRemovalScheduled and Events and Events.OnTick then
        pendingRemovalScheduled = true
        Events.OnTick.Add(processPendingPipeRemovals)
    elseif not (Events and Events.OnTick) then
        -- Fallback (no OnTick): process immediately.
        processPendingPipeRemovals()
    end
end

local function onDestroyIsoThumpable(thump, player)
    -- Sledgehammer: destruction, not dismantling -- nothing comes back, as before.
    schedulePipeRemoval(thump, false)
end

-- Fires for moveable "Pick Up" and other lua-driven removals; without it a removed pipe would stay
-- registered and its endpoints would still read as connected. Dismantling comes through here, so this
-- path hands the build material back.
local function onObjectAboutToBeRemoved(object)
    schedulePipeRemoval(object, true)
end

-- Rotates through state.pipes a few tiles at a time, so every tile is checked eventually and no
-- single pass costs anything measurable.
local verifyCursor = 0
local VERIFY_TILES_PER_PASS = 12

local function verifyCachesAgainstTheWorld()
    local state = State.ensure()

    local coords = {}
    for _, pipeData in pairs(state.pipes) do
        coords[#coords + 1] = pipeData
    end
    if #coords == 0 then
        return
    end

    local disagreed = 0
    for step = 1, math.min(VERIFY_TILES_PER_PASS, #coords) do
        verifyCursor = (verifyCursor % #coords) + 1
        local pipeData = coords[verifyCursor]
        local square = getSquare(pipeData.x, pipeData.y, pipeData.z)
        if square then
            if Adapter.verifySquareVessels and not Adapter.verifySquareVessels(square) then
                disagreed = disagreed + 1
                Logger.warn(string.format(
                    "CACHE DRIFT: vessel classification at %d:%d:%d disagreed with the world. An "
                        .. "object left that tile without OnObjectAboutToBeRemoved firing. This is the "
                        .. "case docs/removal-events.md is waiting for -- please report what was there.",
                    pipeData.x, pipeData.y, pipeData.z))
            end
            if PipeObjectUtils.verifySquareScan and not PipeObjectUtils.verifySquareScan(square) then
                disagreed = disagreed + 1
                Logger.warn(string.format(
                    "CACHE DRIFT: pipe scan at %d:%d:%d disagreed with the world. See "
                        .. "docs/removal-events.md.",
                    pipeData.x, pipeData.y, pipeData.z))
            end
        end
    end

    -- A disagreement means something else may be stale too, and the verifier only repaired the tiles it
    -- looked at. Falling back to the wholesale drop is the safe response to being wrong about the premise.
    if disagreed > 0 then
        Adapter.invalidateVesselCache()
        PipeObjectUtils.invalidateScanCache()
        if Hydraulics and Hydraulics.invalidate then
            Hydraulics.invalidate()
        end
    end
end

-- Emitters are charged on a multiple of the ten-minute tick (Constants.IRRIGATION_STEP_MINUTES).
-- `dtHours` is the time that ACTUALLY elapsed since the last pass, so the water delivered per game-hour
-- is the same whatever the step -- six passes of 1/6 h spend exactly what one pass of 1 h does.
-- Only the queueing happens here; the emitters drain a few per frame under a millisecond budget.
local minutesSinceIrrigation = 0

local function stepIrrigation()
    minutesSinceIrrigation = minutesSinceIrrigation + 10
    if minutesSinceIrrigation < math.max(Constants.IRRIGATION_STEP_MINUTES or 60, 10) then
        return
    end

    local dtHours = minutesSinceIrrigation / 60
    minutesSinceIrrigation = 0

    Profiler.count("irrigation: passes started", 1)
    local ok, err = pcall(Irrigation.beginPass, dtHours)
    if not ok then
        Logger.error("Irrigation pass failed: " .. tostring(err))
    end
end

local function onEveryTenMinutes()
    System.tick()

    -- Rain contaminates uncovered water at the same ten-minute cadence the vanilla rain barrel fills
    -- on, so a passing shower is caught within one step.
    local okRain, errRain = pcall(System.processRainTaint)
    if not okRain then
        Logger.error("Rain contamination pass failed: " .. tostring(errRain))
    end

    stepIrrigation()
end

-- The endpoint index's backstop, deliberately NOT on the same frame as the pass above: it costs 13.5 ms
-- and System.tick costs 26, and landing both together made a 40 ms frame for no reason. It is a
-- backstop for a case that has never fired, so it runs every third ten-minute pass on a frame of its
-- own. If it ever does report something, that is the moment to make it more frequent.
local REINDEX_EVERY = 3
local reindexCountdown = 1
local reindexDue = false

-- Asked for on the ten-minute boundary, RUN on a later frame. The countdown is decided here so the
-- cadence stays tied to game time rather than to how many frames happen to pass.
local function requestEndpointReindex()
    reindexCountdown = reindexCountdown - 1
    if reindexCountdown > 0 then
        return
    end
    reindexCountdown = REINDEX_EVERY
    reindexDue = true
end

-- One flag, checked per frame: on a frame with nothing due the cost is a nil test. Work with a deadline
-- measured in minutes has no business insisting on a particular frame.
local function drainEndpointReindex()
    if not reindexDue then
        return
    end
    reindexDue = false

    local okIndex, errIndex = pcall(Profiler.time, "10min/reindex", System.reindexEndpoints)
    if not okIndex then
        Logger.error("Endpoint re-index failed: " .. tostring(errIndex))
    end
end

-- The last input to the head field with no event behind it: whether a pump has power. That is
-- square:haveElectricity(), which changes when a generator starts, stops or runs dry, and the game
-- announces none of it. So it is WATCHED rather than assumed stale -- one lookup per pump, against a
-- full re-solve every minute on the chance that it moved.
-- The first pass after a load finds no remembered state and invalidates once, which is correct: the
-- field was solved before any of this was known.
local pumpPowerState = {}

local function checkPumpPower()
    local state = State.ensure()
    local changed = false


    for key, pipeData in pairs(state.pipes) do
        local metadata = pipeData.metadata
        if not (metadata and metadata.kinds and not metadata.pump) then
            local square = getSquare(pipeData.x, pipeData.y, pipeData.z)
            local pump = square and Pump.findOnSquare(square)
            if pump then
                local powered = Pump.isPowered(pump) and true or false
                if pumpPowerState[key] ~= powered then
                    pumpPowerState[key] = powered
                    changed = true
                end
            elseif pumpPowerState[key] ~= nil then
                pumpPowerState[key] = nil        -- the pump left; the layout event already fired
            end
        end
    end

    return changed
end

-- The two watchers, and ONE drop between them. Both used to invalidate on their own, and both
-- invalidate on their first look of a session, so loading a game cost two full re-solves back to back.
-- They still want DIFFERENT drops, which is why this is not simply an `or`: pump power feeds the head
-- field and nothing else, while the mains shutoff is baked into a cached walk's supply floor.
local function checkWatchedInputs()
    -- Both, before either drop: a watcher skipped because an earlier one already decided to invalidate
    -- would never record its own state, and would then report a change every single minute.
    local pumpChanged = checkPumpPower()
    local supplyChanged = NetworkAccess.supplyClockChanged()

    if supplyChanged then
        NetworkAccess.invalidateTraversalCache()      -- the walks, and the field with them
    elseif pumpChanged and Hydraulics and Hydraulics.invalidate then
        Hydraulics.invalidate()                       -- the field only
    end
end

local function onEveryOneMinute()
    -- The head field is no longer dropped per frame, so this is what bounds how stale it can get. A minute
    -- is the cadence the water itself moves on, so the field is never reasoning about a supply that has
    -- since run dry, at one solve a minute instead of one a frame.
    -- The other un-evented input is the day the town water is cut: it is read live inside Mains.isLiveAt,
    -- so a cached walk would keep counting a dead main as a supply floor.
    Profiler.time("1min/invalidate", checkWatchedInputs)

    -- The vessel classification and the pipe-object scan used to be dropped here too, wholesale: measured at
    -- ~190 ms of client work in the frame that followed, protecting against nothing anyone has observed.
    -- Both are invalidated by tile on object add/remove and on LoadGridsquare, and pipes cannot be
    -- destroyed by anything but a player. What is left of the doubt is a VERIFICATION on the ten-minute
    -- pass, which is cheap and says out loud when it disagrees.

    -- Routers process once per in-game minute (rates are per-minute; dt defaults to 1.0). This is the
    -- cheap cadence -- no per-frame OnTick work -- at the cost of the readout updating once a minute.
    local okRouters, errRouters = pcall(Profiler.time, "1min/routers", System.processRouters)
    if not okRouters then
        Logger.error("Router processing failed: " .. tostring(errRouters))
    end

    local okPumps, errPumps = pcall(Profiler.time, "1min/pumps", System.processPumps)
    if not okPumps then
        Logger.error("Pump processing failed: " .. tostring(errPumps))
    end

    local okMains, errMains = pcall(Profiler.time, "1min/mains", System.processAllMains)
    if not okMains then
        Logger.error("Mains supply processing failed: " .. tostring(errMains))
    end

    local okHydrants, errHydrants = pcall(Profiler.time, "1min/hydrants", System.processHydrants)
    if not okHydrants then
        Logger.error("Hydrant processing failed: " .. tostring(errHydrants))
    end

    local ok, err = pcall(Profiler.time, "1min/endpoints", System.refreshPlumbedEndpoints)
    if not ok then
        Logger.error("Endpoint plumbing refresh failed: " .. tostring(err))
    end
end

-- Irrigation moved to stepIrrigation, on the ten-minute tick. What is left here is stagnation, which is
-- a days-scale process and has no reason to run faster.
local function onEveryHours()
    -- Stagnation is a days-scale process, so the hourly cadence keeps its network walk off the hot path.
    local okStag, errStag = pcall(System.processStagnation)
    if not okStag then
        Logger.error("Stagnation pass failed: " .. tostring(errStag))
    end
end

-- The only per-frame work the system does, and it costs one nil check on the frames where there is
-- no pass draining -- which is all but a handful an hour.
local function drainIrrigationPass()
    if not Irrigation.hasPendingPass() then
        return
    end

    -- Timed, because it was not and that hid a quarter of everything the mod does: the bucket table adds up
    -- only its TOP-LEVEL rows, and solve/search was happening underneath an untimed pass.
    local ok, err = pcall(Profiler.time, "irrigation/step",
        Irrigation.stepPass, Constants.IRRIGATION_EMITTERS_PER_TICK)
    if not ok then
        Logger.error("Irrigation step failed: " .. tostring(err))
        -- Drop the pass rather than retry the same failing emitter every frame from here to eternity.
        pcall(Irrigation.cancelPass)
    end
end

local function onWaterAmountChange(object, prevAmount)
    -- Before the suppression guard, deliberately. The head field cares only whether a vessel holds water,
    -- and it has to hear about that crossing whoever caused it. The guard below stops endpoint
    -- reconciliation and stagnation clocks re-entering on our own writes; neither applies to an
    -- invalidation, which is idempotent.
    if object and Adapter.noteEmptinessCrossing then
        local ok, amount = pcall(Adapter.readWorldFluidAmount, object)
        pcall(Adapter.noteEmptinessCrossing, object, prevAmount, ok and amount or 0)
    end

    -- Ignore the echo of our OWN network writes. writeWorldFluidAmount fires OnWaterAmountChange purely so
    -- external mods refresh; processing it here would reset stagnation clocks and risk re-entrancy.
    if WaterPipes._suppressWaterEvent then
        return
    end

    if not object then
        return
    end

    -- Legacy hidden adapter objects from older saves (handled until cleaned up).
    if AdapterSource.isAdapterObject(object) then
        local ok, err = pcall(AdapterSource.onAdapterWaterAmountChange, object, prevAmount)
        if not ok then
            Logger.error("Adapter water change handler failed: " .. tostring(err))
        end
        return
    end

    -- A plumbed endpoint's own FluidContainer changed: reconcile consumption to the network.
    if EndpointPlumbing.isPlumbed(object) then
        local ok, err = pcall(FluidSource.onEndpointWaterAmountChange, object, prevAmount)
        if not ok then
            Logger.error("Endpoint water change handler failed: " .. tostring(err))
        end
    end

    -- Any change to a water vessel counts as movement and resets its stagnation clock. Reading the fluid
    -- type off the object leaves tainted water untouched, so tainting a vessel never resets its own clock.
    if Stagnation.isEnabled() and object.getModData then
        local ok, fluidType = pcall(function()
            local descriptors = Adapter.collectSquareContainers(object:getSquare())
            for _, descriptor in pairs(descriptors) do
                if descriptor.object == object then
                    return descriptor.fluidType
                end
            end
            return nil
        end)
        if ok and fluidType then
            Stagnation.noteMovement(object, fluidType)
        end
    end
end

local function findGeneratorOnSquare(square)
    if not square or not square.getObjects then
        return nil
    end
    local objects = square:getObjects()
    for index = 0, objects:size() - 1 do
        local candidate = objects:get(index)
        if GeneratorFuel.isGenerator(candidate) then
            return candidate
        end
    end
    return nil
end

local function resolveCommandSquare(args)
    if not args or args.x == nil or args.y == nil or args.z == nil then
        return nil
    end
    return getSquare(args.x, args.y, args.z)
end

local function onClientCommand(module, command, player, args)
    if module ~= "WaterPipes" then
        return
    end

    -- Endpoint plumb/unplumb runs authoritatively on the server (clients only request it).
    if command == "plumbEndpoint" or command == "unplumbEndpoint" then
        local square = resolveCommandSquare(args)
        local endpoint = square and EndpointObjects.findOnSquare(square)
        if not endpoint then
            Logger.warn("Endpoint plumb command: no endpoint at "
                .. tostring(args and args.x) .. ":" .. tostring(args and args.y) .. ":" .. tostring(args and args.z))
            return
        end
        if command == "plumbEndpoint" then
            EndpointPlumbing.plumb(endpoint)
        else
            EndpointPlumbing.unplumb(endpoint)
        end
        return
    end

    -- Generator plumb/unplumb runs authoritatively on the server as well.
    if command == "plumbGenerator" or command == "unplumbGenerator" then
        local square = resolveCommandSquare(args)
        local generator = square and findGeneratorOnSquare(square)
        if not generator then
            Logger.warn("Generator plumb command: no generator at "
                .. tostring(args and args.x) .. ":" .. tostring(args and args.y) .. ":" .. tostring(args and args.z))
            return
        end
        if command == "plumbGenerator" then
            GeneratorFuel.plumb(generator)
        else
            GeneratorFuel.unplumb(generator)
        end
        return
    end

    -- Filter repair: the client's timed action has already consumed the repair kit from its inventory;
    -- the server just resets the (authoritative) filter condition on the purifier and re-syncs it.
    if command == "repairPurifier" then
        local square = resolveCommandSquare(args)
        local purifier = square and Purifier.findOnSquare(square)
        if not purifier then
            Logger.warn("Repair purifier command: no purifier at "
                .. tostring(args and args.x) .. ":" .. tostring(args and args.y) .. ":" .. tostring(args and args.z))
            return
        end
        Purifier.repairFilter(purifier)
        return
    end

    -- Same contract as repairPurifier: the client already spent the kit, the server owns the state.
    if command == "repairDrip" then
        local square = resolveCommandSquare(args)
        local drip = square and Irrigation.findDripOnSquare(square)
        if not drip then
            Logger.warn("Repair drip command: no drip emitter at "
                .. tostring(args and args.x) .. ":" .. tostring(args and args.y) .. ":" .. tostring(args and args.z))
            return
        end
        Irrigation.repairDrip(drip)
        return
    end

    -- Router pressure ceiling: server-authoritative so every client sees the same regulated zone.
    if command == "setRouterPressure" then
        local square = resolveCommandSquare(args)
        local router = square and Router.findOnSquare(square)
        if not router then
            Logger.warn("Set router pressure command: no router at "
                .. tostring(args and args.x) .. ":" .. tostring(args and args.y) .. ":" .. tostring(args and args.z))
            return
        end
        Router.setPressureCeiling(router, args and args.pressure)
        return
    end

    -- Hydrant open/close: server-authoritative so every client agrees on which hydrants are flowing.
    if command == "setHydrantOpen" then
        local square = resolveCommandSquare(args)
        local hydrant = square and Hydrant.findOnSquare(square)
        if not hydrant then
            Logger.warn("Set hydrant command: no hydrant at "
                .. tostring(args and args.x) .. ":" .. tostring(args and args.y) .. ":" .. tostring(args and args.z))
            return
        end
        Hydrant.setOpen(hydrant, args and args.open)
        return
    end

    -- Pump switch: server-authoritative so every client agrees on which pumps are running. A switched-off
    -- pump reads as unpowered everywhere, so it stops both boosting pressure and drawing from its source.
    if command == "setPumpEnabled" then
        local square = resolveCommandSquare(args)
        local pump = square and Pump.findOnSquare(square)
        if not pump then
            Logger.warn("Set pump command: no pump at "
                .. tostring(args and args.x) .. ":" .. tostring(args and args.y) .. ":" .. tostring(args and args.z))
            return
        end
        Pump.setEnabled(pump, args and args.enabled)
        return
    end

    -- Debug: run a pass and balance the books (see System.checkIrrigationConservation). The result
    -- goes back to the caller so it can be read in-game, and to console.txt either way.
    if command == "checkIrrigationConservation" then
        local dt = args and tonumber(args.dt) or 1.0
        local ok, report = pcall(System.checkIrrigationConservation, dt)
        if not ok then
            Logger.error("Conservation check failed: " .. tostring(report))
            return
        end
        if player and sendServerCommand then
            sendServerCommand(player, "WaterPipes", "debugIrrigationConservation", report)
        end
        return
    end

    -- Debug: force an irrigation pass immediately, so a tester can watch crops fill without waiting
    -- for the hourly tick. dt comes from the client (hours of watering to apply in one shot).
    if command == "runIrrigation" then
        local dt = args and tonumber(args.dt) or 1.0
        local ok, err = pcall(Irrigation.run, dt)
        if not ok then
            Logger.error("Manual irrigation pass failed: " .. tostring(err))
        end
        return
    end

    if command == "forceGlobalWaterShutoff" then
        System.forceGlobalWaterShutoff()
        System.tick()
        sendServerCommand(player, "WaterPipes", "debugWaterShutoffApplied", {})
        return
    end

    if command == "forceNetworkTick" then
        System.tick()
        sendServerCommand(player, "WaterPipes", "debugNetworkTickApplied", {})
    end
end

if Events then
    if Events.OnInitGlobalModData then
        Events.OnInitGlobalModData.Add(onInitGlobalModData)
    end

    if Events.EveryTenMinutes then
        Events.EveryTenMinutes.Add(function()
            WaterPipes.Profiler.time("system/10min", onEveryTenMinutes)
            WaterPipes.Profiler.time("10min/verify", verifyCachesAgainstTheWorld)
            requestEndpointReindex()
        end)
    end

    if Events.EveryOneMinute then
        Events.EveryOneMinute.Add(function()
            WaterPipes.Profiler.time("system/1min", onEveryOneMinute)
        end)
    end

    if Events.EveryHours then
        Events.EveryHours.Add(function()
            WaterPipes.Profiler.time("system/1h", onEveryHours)
        end)
    end

    if Events.OnTick then
        Events.OnTick.Add(drainIrrigationPass)
        Events.OnTick.Add(drainEndpointReindex)
    end

    if Events.OnDestroyIsoThumpable then
        Events.OnDestroyIsoThumpable.Add(onDestroyIsoThumpable)
    end

    if Events.OnObjectAboutToBeRemoved then
        Events.OnObjectAboutToBeRemoved.Add(onObjectAboutToBeRemoved)
    end

    if Events.OnWaterAmountChange then
        Events.OnWaterAmountChange.Add(onWaterAmountChange)
    end

    if Events.OnClientCommand then
        Events.OnClientCommand.Add(onClientCommand)
    end
end
