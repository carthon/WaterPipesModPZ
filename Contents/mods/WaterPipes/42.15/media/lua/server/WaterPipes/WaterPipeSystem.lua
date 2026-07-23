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
require "WaterPipes/Irrigation"
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
local PipeAutotile = WaterPipes.PipeAutotile
local Purifier = WaterPipes.Purifier
local GravityFlow = WaterPipes.GravityFlow
local Router = WaterPipes.Router
local NetworkAccess = WaterPipes.NetworkAccess
local Mains = WaterPipes.Mains
local Pump = WaterPipes.Pump
local Hydrant = WaterPipes.Hydrant
local Stagnation = WaterPipes.Stagnation
local Irrigation = WaterPipes.Irrigation
local State = WaterPipes.State
local System = WaterPipes.System

-- Single-player has no client/server split. PipeAutotile is otherwise driven by client-side events
-- (OnObjectAdded etc.), but those don't reliably fire on a freshly-built entity in SP, so the build
-- path repaints directly -- only in SP. A dedicated/host server must NEVER change & sync the sprite
-- (MP clients and the co-op host autotile locally via PipeAutotile's own events).
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
        end
    end

    State.replaceContainers(found)
    return found
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
            -- Gravity settle: water pools to the lowest floors first (relocation). A single-floor
            -- component reduces to the classic per-pool equalization, so one floor is unchanged.
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

-- Purifier-container on the tile: IN network -> IN buffer -> convert -> OUT buffer -> OUT network.
-- Water always flows one way, IN side -> OUT side. Intake pulls ONLY TAINTED water and ONLY from the
-- router's IN network; output pushes clean water ONLY into the OUT network. It never draws clean water
-- (no need to purify it) and never pulls anything back off the OUT side. Intake happens with or without
-- power (the tainted water still enters the buffer); only converting it to clean needs power + filter.
--
-- Step order is OUTPUT -> CONVERT -> INTAKE on purpose: draining the output side FIRST and refilling
-- the intake side LAST leaves water resident in both buffers between ticks, so the tanks actually hold
-- (and the readout shows) a real level instead of being fully cycled to 0 every tick; water just takes
-- one extra tick to traverse.
-- `dt` is the elapsed in-game minutes for this sub-step; the per-minute rates are scaled by it so the
-- purifier moves the same amount per game-minute no matter how often we tick.
local function processPurifierRouter(purifier, inSquare, outSquare, dt)
    -- 1. Output: push the (clean) OUT buffer into the OUT network.
    local outAmount = Purifier.getOutAmount(purifier)
    if outAmount > 0 then
        local pushHeadroom = NetworkAccess.availableToPush(outSquare, "Water")
        local push = math.min(Constants.PURIFIER_OUTPUT_RATE * dt, outAmount, pushHeadroom)
        if push > 0 then
            local filled = NetworkAccess.fillFluidAtSquare(outSquare, "Water", push)
            if filled and filled > 0 then
                Purifier.removeOut(purifier, filled)
            end
        end
    end

    -- 2. Convert: move IN -> OUT. Tainted needs power AND filter life; clean water always passes.
    local inAmount = Purifier.getInAmount(purifier)
    if inAmount > 0 then
        local outHeadroom = Constants.PURIFIER_BUFFER_CAPACITY - Purifier.getOutAmount(purifier)
        if outHeadroom > 0 then
            local move = math.min(Constants.PURIFIER_CONVERT_RATE * dt, inAmount, outHeadroom)
            if Purifier.isInTainted(purifier) then
                -- Cleaning tainted water needs power AND a filter with life left. Every unit converted
                -- wears the filter; at 0 condition it stops cleaning (the water waits in IN) until the
                -- player repairs it. moveInToOut clamps to what is actually in IN, so wear by that.
                if Purifier.canFilter(purifier) then
                    local before = Purifier.getInAmount(purifier)
                    Purifier.moveInToOut(purifier, move)   -- lands in the OUT buffer as clean Water
                    Purifier.wearFilter(purifier, before - Purifier.getInAmount(purifier))
                end
                -- tainted + not powered / clogged filter: stays in the IN buffer until it can be cleaned
            else
                Purifier.moveInToOut(purifier, move)       -- clean water always passes through
            end
        end
    end

    -- 3. Intake: pull ONLY TAINTED water, and ONLY from the router's IN network. The purifier exists to
    -- clean tainted water, so it never draws clean water (which needs no purifying) and never pulls
    -- anything off the OUT side -- inSquare is the IN side. This runs with or without power (the water
    -- still enters the buffer); only converting it to clean later needs power + filter life.
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
                end
            end
        end
    end
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

    -- Scan the whole purifier footprint from the router tile (the tank's modData may live on a footprint
    -- tile other than the router/anchor tile). Missing it here would silently run a plain passthrough.
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

-- A powered pump next to a well or open water injects fluid into its network. It is NOT a container:
-- a well holds 10 000 L and open water is infinite, so letting either join the network as storage
-- would leave rebalanceSummary smearing them across every pipe and the network permanently full.
-- Bounded injection is the same shape the purifier's intake step already uses.
function System.processPump(pump, square, dt)
    local source = Pump.findSource(pump)
    if not source then
        return   -- booster only: nothing to draw from, but it still adds head to its zone
    end

    -- Ask the network what it can take FIRST, so we never pull water out of a well and lose it.
    local headroom = NetworkAccess.availableToPush(square, source.fluidType)
    local wanted = math.min(Pump.intakeFor(dt), headroom)
    if wanted <= 0 then
        return
    end

    local taken = Pump.drawFromSource(source, wanted)
    if taken <= 0 then
        return
    end

    local added = NetworkAccess.fillFluidAtSquare(square, source.fluidType, taken)
    if added < taken then
        -- The network took less than we drew (a race with another consumer, or a mixed-fluid
        -- refusal). Put the remainder back rather than quietly destroying it.
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
        local square = getSquare(pipeData.x, pipeData.y, pipeData.z)
        local pump = square and Pump.findOnSquare(square)
        if pump and Pump.isPowered(pump) then
            System.processPump(pump, square, dt)
        end
    end
end

-- A plumbed fixture that still has town water behind it fills the network. Simpler than the pump:
-- the mains is not a container we can overdraw, so there is nothing to draw first and nothing to
-- refund -- we ask the network what it can take and hand it exactly that.
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

-- An OPEN hydrant gushes water at its flow rate. Whatever the pipe network on its tile can take is
-- fed in; the rest spills onto the street and is wasted -- so an open hydrant with nothing connected,
-- or with a full network, still loses water. While the town service runs it is mains-fed, so its
-- reserve is held full and the waste costs nothing; once the water is cut, the full flow (delivered
-- plus spilled) is drawn from the fixed reserve, which then runs dry. Closed hydrants are untouched.
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

    -- The network takes what it can; the remainder is spilled. Both come out of the flow, so the
    -- reserve loses the whole flow whether or not anything was connected.
    NetworkAccess.fillFluidAtSquare(square, "Water", flow)
    if not mainsFed then
        Hydrant.setReserve(hydrant, reserve - flow)
    end
end

-- Driven by the open-hydrant registry rather than the pipe list, so a hydrant opened with no pipe on
-- its tile still wastes water. The registry is self-cleaning: an entry whose hydrant is gone or has
-- been closed is dropped here.
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

-- A component taints as one body of water, so we act per component, not per vessel: decide with
-- `predicate`, and the first vessel that says yes taints the whole network through it. Fresh clean
-- vessels with no stamp yet are stamped now, so their clock starts from first sight rather than
-- turning them the instant the feature switches on.
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

-- Every ten minutes while it rains: an OPEN vessel that is also OUTSIDE contaminates its whole
-- network. Uncovered collection is a gamble whenever the weather turns -- which is what vanilla
-- already does to its rain barrels, extended here to the whole plumbed system.
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

function System.refreshPlumbedEndpoints()
    local state = State.ensure()
    local coordinates = {}

    for _, pipeData in pairs(state.pipes) do
        local pipeCoordinates = {
            { x = pipeData.x, y = pipeData.y, z = pipeData.z },
        }

        for _, offset in ipairs(Constants.NETWORK_NEIGHBOR_OFFSETS) do
            pipeCoordinates[#pipeCoordinates + 1] = {
                x = pipeData.x + offset.x,
                y = pipeData.y + offset.y,
                z = pipeData.z + offset.z,
            }
        end
        for _, position in ipairs(pipeCoordinates) do
            coordinates[#coordinates + 1] = position
        end
    end

    refreshPlumbedEndpointsNearCoordinates(coordinates)
    refreshPlumbedGeneratorsNearCoordinates(coordinates)
end

function System.rebuild()
    System.scanContainersAroundPipes()
    State.rebuildGraph()
end

function System.tick()
    local ok, err = pcall(function()
        System.rebuild()
        System.redistributeWater()
        System.refreshPlumbedEndpoints()
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

-- Pipe removal (sledgehammer destroy, moveable "Pick Up", erosion, etc.) is processed ONE TICK
-- later: some removal events (notably OnObjectAboutToBeRemoved, used by the moveable pickup) fire
-- BEFORE the object actually leaves the square, so a synchronous re-check would still "see" the
-- pipe. Deferring a frame lets us read the true post-removal world state. The next-tick guard
-- (no pipe left on the square) also handles multi-pipe squares and cancelled removals uniformly.
local pendingPipeRemovals = {}
local pendingRemovalScheduled = false

local function processPendingPipeRemovals()
    pendingRemovalScheduled = false
    if Events and Events.OnTick then
        Events.OnTick.Remove(processPendingPipeRemovals)
    end

    local toProcess = pendingPipeRemovals
    pendingPipeRemovals = {}

    for _, position in pairs(toProcess) do
        local square = getSquare(position.x, position.y, position.z)
        -- Only unregister once the square is loaded and no pipe remains there.
        if square and PipeObjectUtils.getPipeOnSquare(square) == nil then
            System.unregisterPipeAt(position.x, position.y, position.z)
        end
    end
end

local function schedulePipeRemoval(object)
    if not object or not PipeObjectUtils.isPipeObject(object) then
        return
    end

    local square = object.getSquare and object:getSquare() or nil
    if not square then
        return
    end

    local x, y, z = square:getX(), square:getY(), square:getZ()
    pendingPipeRemovals[tostring(x) .. ":" .. tostring(y) .. ":" .. tostring(z)] = { x = x, y = y, z = z }

    if not pendingRemovalScheduled and Events and Events.OnTick then
        pendingRemovalScheduled = true
        Events.OnTick.Add(processPendingPipeRemovals)
    elseif not (Events and Events.OnTick) then
        -- Fallback (no OnTick): process immediately.
        processPendingPipeRemovals()
    end
end

local function onDestroyIsoThumpable(thump, player)
    schedulePipeRemoval(thump)
end

-- Fires for moveable "Pick Up" and other lua-driven removals; without it a removed pipe would
-- stay registered and its endpoints would still read as connected.
local function onObjectAboutToBeRemoved(object)
    schedulePipeRemoval(object)
end

local function onEveryTenMinutes()
    System.tick()

    -- Rain contaminates uncovered water at the same ten-minute cadence the vanilla rain barrel fills
    -- on, so a passing shower is caught within one step.
    local okRain, errRain = pcall(System.processRainTaint)
    if not okRain then
        Logger.error("Rain contamination pass failed: " .. tostring(errRain))
    end
end

local function onEveryOneMinute()
    -- Routers process once per in-game minute (rates are per-minute; dt defaults to 1.0). This is the
    -- cheap cadence -- no per-frame OnTick work -- at the cost of the readout updating once a minute.
    local okRouters, errRouters = pcall(System.processRouters)
    if not okRouters then
        Logger.error("Router processing failed: " .. tostring(errRouters))
    end

    local okPumps, errPumps = pcall(System.processPumps)
    if not okPumps then
        Logger.error("Pump processing failed: " .. tostring(errPumps))
    end

    local okMains, errMains = pcall(System.processAllMains)
    if not okMains then
        Logger.error("Mains supply processing failed: " .. tostring(errMains))
    end

    local okHydrants, errHydrants = pcall(System.processHydrants)
    if not okHydrants then
        Logger.error("Hydrant processing failed: " .. tostring(errHydrants))
    end

    local ok, err = pcall(System.refreshPlumbedEndpoints)
    if not ok then
        Logger.error("Endpoint plumbing refresh failed: " .. tostring(err))
    end
end

-- Irrigation runs hourly, not per minute: crops drain 1 waterLvl every 5 in-game hours, so anything
-- faster would be pure overhead. It is also the only place pressure is computed for emitters, which
-- keeps that cost pinned to the slowest cadence in the mod.
local function onEveryHours()
    local ok, err = pcall(Irrigation.run, 1.0)
    if not ok then
        Logger.error("Irrigation pass failed: " .. tostring(err))
    end

    -- Stagnation is a days-scale process, so the hourly cadence is plenty and keeps its network walk
    -- off the hot path.
    local okStag, errStag = pcall(System.processStagnation)
    if not okStag then
        Logger.error("Stagnation pass failed: " .. tostring(errStag))
    end
end

local function onWaterAmountChange(object, prevAmount)
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

    -- Any change to a water vessel counts as movement, which resets its stagnation clock. Reading the
    -- fluid type off the object keeps clean water fresh while it is being used and leaves tainted water
    -- untouched -- so the very act of tainting a vessel never resets its own clock.
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
        Events.EveryTenMinutes.Add(onEveryTenMinutes)
    end

    if Events.EveryOneMinute then
        Events.EveryOneMinute.Add(onEveryOneMinute)
    end

    if Events.EveryHours then
        Events.EveryHours.Add(onEveryHours)
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
