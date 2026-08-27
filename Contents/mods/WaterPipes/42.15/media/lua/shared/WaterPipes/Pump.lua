WaterPipes = WaterPipes or {}
WaterPipes.Pump = WaterPipes.Pump or {}

require "WaterPipes/Invalidate"
require "WaterPipes/Constants"
require "WaterPipes/PipeObjectUtils"
require "WaterPipes/Pressure"
require "WaterPipes/World"
require "WaterPipes/State"
require "WaterPipes/Router"
require "WaterPipes/Purifier"
require "WaterPipes/Logger"

local Invalidate = WaterPipes.Invalidate
local Constants = WaterPipes.Constants
local PipeObjectUtils = WaterPipes.PipeObjectUtils
local Pressure = WaterPipes.Pressure
local Pump = WaterPipes.Pump

-- A water pump is a floor pipe flagged in modData that needs power. It does two jobs, and which one
-- it does falls out of where the player puts it (see the pump block in Constants.lua):
--   * head   -- every powered pump raises the pressure of the zone it sits in.
--   * intake -- a pump next to a well or open water also injects fluid into the network.
-- Both are gated on power: cut the electricity and the pump contributes nothing, so the network
-- silently falls back to plain gravity.

local function getModData(worldObject)
    if not worldObject or not worldObject.getModData then
        return nil
    end
    local ok, modData = pcall(worldObject.getModData, worldObject)
    return ok and modData or nil
end

function Pump.isPump(worldObject)
    local modData = getModData(worldObject)
    return modData and modData[Constants.PUMP_MODDATA_KEY] == true or false
end

function Pump.findOnSquare(square)
    if not square then
        return nil
    end
    for _, worldObject in ipairs(PipeObjectUtils.getPipeObjectsOnSquare(square)) do
        if Pump.isPump(worldObject) then
            return worldObject
        end
    end
    return nil
end

function Pump.hasPumpOnSquare(square)
    return Pump.findOnSquare(square) ~= nil
end

-- Sprite is picked by axis, like a straight pipe: the pump never autotiles into corners.
function Pump.spriteFor(worldObject)
    local modData = getModData(worldObject)
    local axis = modData and modData[Constants.PIPE_AXIS_MODDATA_KEY]
    if axis == Constants.PIPE_AXIS_NS then
        return Constants.PUMP_SPRITE_NS
    end
    return Constants.PUMP_SPRITE_EW
end

-- ===== Power =====

local function squareHasPower(square)
    if not square or not square.haveElectricity then
        return false
    end
    local ok, powered = pcall(square.haveElectricity, square)
    return ok and powered or false
end

-- A pump runs only with BOTH gates up: mains power on its tile, and the player's switch left on.
-- Everything downstream (head, intake, the pressure report) asks isPowered and nothing else, so
-- combining the two there is enough -- no call site needs to know the switch exists.
function Pump.hasPower(worldObject)
    if not Pump.isPump(worldObject) then
        return false
    end
    local square = worldObject.getSquare and worldObject:getSquare() or nil
    return squareHasPower(square)
end

-- Absent key means ON -- see PUMP_ENABLED_KEY. Every pump that predates the switch keeps working.
function Pump.isEnabled(worldObject)
    local modData = getModData(worldObject)
    return not modData or modData[Constants.PUMP_ENABLED_KEY] ~= false
end

-- Server-authoritative in MP: clients request the flip, the server lands here (see ISTogglePump).
function Pump.setEnabled(worldObject, enabled)
    local modData = getModData(worldObject)
    if not modData then
        return
    end
    modData[Constants.PUMP_ENABLED_KEY] = enabled and true or false
    if worldObject.transmitModData then
        pcall(worldObject.transmitModData, worldObject)
    end

    -- A pump is half the head in most zones, so flipping it invalidates the solved field. Resolved off
    -- the WaterPipes table rather than required at the top: Hydraulics already requires this module.
    local Hydraulics = WaterPipes.Hydraulics
    Invalidate.pumpStateChanged()
end

function Pump.isPowered(worldObject)
    return Pump.hasPower(worldObject) and Pump.isEnabled(worldObject)
end

-- ===== Head =====

-- Total head a zone's pumps add. `pumps` comes from the network walk, which already had each
-- square's pipe objects in hand. Unpowered pumps contribute nothing, so cutting the electricity
-- silently drops the whole network back to plain gravity.
function Pump.headForPumps(pumps)
    if not pumps then
        return 0
    end

    local perPump = Pressure.pumpHead()
    local total = 0
    for _, pump in ipairs(pumps) do
        if Pump.isPowered(pump) then
            total = total + perPump
        end
    end
    return total
end

-- ===== Source detection (extractor mode) =====

local getCellSquare = WaterPipes.World.squareAt
local World = WaterPipes.World
local State = WaterPipes.State
local Router = WaterPipes.Router
local Purifier = WaterPipes.Purifier
local Logger = WaterPipes.Logger

-- Server admins can switch off pumping from rivers and lakes without losing wells or the rest of
-- the pressure model: it is the one source that is genuinely infinite.
local function waterBodiesAllowed()
    local sv = SandboxVars and SandboxVars.WaterPipes
    local v = sv and sv.PumpFromWaterBodies
    if type(v) == "boolean" then
        return v
    end
    return true
end

-- Open water, identified the way vanilla's own isValidWaterSquare does it: the floor tile carries
-- the `water` property. Infinite, and always TaintedWater.
local function isOpenWaterSquare(square)
    if not square or not square.getFloor then
        return false
    end
    local ok, floor = pcall(square.getFloor, square)
    if not ok or not floor or not floor.hasProperty then
        return false
    end
    local okProp, hasWater = pcall(floor.hasProperty, floor, IsoFlagType.water)
    return okProp and hasWater or false
end

-- The name of the entity script behind a world object, or nil for a plain scenery tile.
-- getEntityScript() is the accessor that answers on a B42 entity object; getScriptName() is the vehicle
-- one and returns the literal string "none" here, which is why asking it alone never matched a well.
local function entityNameOf(worldObject)
    if not worldObject then
        return nil
    end

    if worldObject.getEntityScript then
        local ok, script = pcall(worldObject.getEntityScript, worldObject)
        if ok and script and script.getName then
            local okName, name = pcall(script.getName, script)
            if okName and name and name ~= "" then
                return name
            end
        end
    end

    if worldObject.getScriptName then
        local ok, name = pcall(worldObject.getScriptName, worldObject)
        if ok and name and name ~= "" and name ~= "none" then
            return name
        end
    end

    return nil
end
Pump.entityNameOf = entityNameOf

function Pump.isWell(worldObject)
    local name = entityNameOf(worldObject)
    return name == Constants.WELL_ENTITY_NAME or name == Constants.WELL_SCRIPT_NAME
end

-- A well is an entity object carrying a FluidContainer of clean water. It is deliberately NOT an
-- ordinary network container (its capacity is above MAX_FINITE_FLUID_CAPACITY), so the pump is the
-- only way its water reaches the pipes.
local function findWellOnSquare(square)
    if not square or not square.getObjects then
        return nil
    end
    local ok, objects = pcall(square.getObjects, square)
    if not ok or not objects then
        return nil
    end
    for i = 0, objects:size() - 1 do
        local worldObject = objects:get(i)
        if Pump.isWell(worldObject) then
            return worldObject
        end
    end
    return nil
end

-- Can a pump at pumpZ still lift a source sitting at sourceZ? Suction is capped by atmospheric
-- pressure, not by the motor, so a source more than ~2 floors down simply will not prime.
function Pump.canLiftFrom(pumpZ, sourceZ)
    local drop = (pumpZ or 0) - (sourceZ or 0)
    if drop <= 0 then
        return true   -- source level with the pump or above it: gravity feeds the inlet
    end
    return drop * Pressure.levelHead() <= Pressure.suctionLimit()
end

-- The natural source a pump can draw from, searched over its own tile and the cardinal neighbours,
-- across the floors its suction can still reach. Returns a descriptor or nil.
function Pump.findSource(pumpObject)
    local square = pumpObject and pumpObject.getSquare and pumpObject:getSquare() or nil
    if not square then
        return nil
    end

    local px, py, pz = square:getX(), square:getY(), square:getZ()
    -- How many floors down suction still reaches (0 = same floor only).
    local levelHead = Pressure.levelHead()
    local maxDrop = levelHead > 0 and math.floor(Pressure.suctionLimit() / levelHead) or 0

    local offsets = { { x = 0, y = 0 } }
    for _, offset in ipairs(Constants.CARDINAL_OFFSETS) do
        offsets[#offsets + 1] = { x = offset.x, y = offset.y }
    end

    for drop = 0, maxDrop do
        local z = pz - drop
        for _, offset in ipairs(offsets) do
            local candidate = getCellSquare(px + offset.x, py + offset.y, z)
            if candidate then
                local well = findWellOnSquare(candidate)
                if well then
                    return { kind = "well", object = well, square = candidate, fluidType = "Water" }
                end
                if waterBodiesAllowed() and isOpenWaterSquare(candidate) then
                    -- Rivers and lakes are infinite and dirty: this is what feeds the purifier.
                    return { kind = "water", square = candidate, fluidType = "TaintedWater" }
                end
            end
        end
    end

    return nil
end

-- How much a pump may move in `dt` in-game minutes.
function Pump.intakeFor(dt)
    local sv = SandboxVars and SandboxVars.WaterPipes
    local rate = sv and sv.PumpIntakeRate
    if type(rate) ~= "number" then
        rate = Constants.PUMP_INTAKE_RATE
    end
    return math.max(rate, 0) * math.max(dt or 0, 0)
end

-- Draw up to `amount` out of a source descriptor. A well has a real FluidContainer to drain; open
-- water is infinite, so nothing is deducted. Returns how much was actually taken.
function Pump.drawFromSource(source, amount)
    if not source or (amount or 0) <= 0 then
        return 0
    end

    if source.kind == "water" then
        return amount   -- a river does not run dry
    end

    local container = source.object and source.object.getFluidContainer
        and source.object:getFluidContainer() or nil
    if not container or not container.getAmount then
        return 0
    end

    local okAmount, available = pcall(container.getAmount, container)
    if not okAmount or (available or 0) <= 0 then
        return 0
    end

    local taken = math.min(amount, available)
    if taken <= 0 then
        return 0
    end

    -- adjustAmount is an absolute set, not a delta -- see ISWaterPlantAction for vanilla's usage.
    local okSet = pcall(container.adjustAmount, container, available - taken)
    if not okSet then
        return 0
    end
    return taken
end

-- Hand back fluid the network turned out not to be able to take. Open water needs no refund (we
-- never actually removed anything), but a well would otherwise quietly lose the difference.
function Pump.refundToSource(source, amount)
    if not source or (amount or 0) <= 0 or source.kind == "water" then
        return
    end

    local container = source.object and source.object.getFluidContainer
        and source.object:getFluidContainer() or nil
    if not container or not container.getAmount then
        return
    end

    local okAmount, current = pcall(container.getAmount, container)
    if not okAmount then
        return
    end

    local capacity = container.getCapacity and container:getCapacity() or nil
    local restored = current + amount
    if capacity then
        restored = math.min(restored, capacity)
    end
    pcall(container.adjustAmount, container, restored)
end

-- ===== Readout =====

-- Everything the status dialog and the context menu need, in one call.
-- NetworkAccess is deliberately NOT required at the top of this file: it already requires Pump, and
-- closing that loop would make the pair a recursive require.
function Pump.getStatus(pumpObject)
    if not Pump.isPump(pumpObject) then
        return nil
    end
    local square = pumpObject.getSquare and pumpObject:getSquare() or nil
    if not square then
        return nil
    end

    local status = {
        enabled = Pump.isEnabled(pumpObject),
        hasPower = Pump.hasPower(pumpObject),
    }
    status.running = status.enabled and status.hasPower

    -- Intake side. Finding a source is about WHERE the pump stands, so it answers even while the pump
    -- is off -- "there is a well right here, you just have it switched off" is the useful answer.
    local source = Pump.findSource(pumpObject)
    status.sourceKind = source and source.kind or nil     -- "well" | "water" | nil
    status.drawing = status.running and source ~= nil

    -- Pressure side. `outlet` is what the line holds at this tile right now; `inlet` is what it would hold
    -- WITHOUT this pump. A zone's lift is max(pump head, municipal supply floor), so a pump on a mains-fed
    -- run can be adding nothing at all -- which is exactly what the player is trying to find out. Taking
    -- the difference says so honestly, where subtracting a nominal 25.0 would invent a contribution.
    local NetworkAccess = WaterPipes.NetworkAccess
    local report = NetworkAccess and NetworkAccess.getPressureReport(square) or nil
    if report then
        status.pressureEnabled = report.enabled

        local own = Pressure.pumpHead()
        local supply = report.supplyHead or 0
        -- headForPumps only counts POWERED pumps, so this already excludes us while we are off.
        local others = report.pumpHead or 0
        if status.running then
            others = math.max(others - own, 0)
        end
        local delta = math.max(others + own, supply) - math.max(others, supply)

        local tap = report.kinds and report.kinds[Constants.PRESSURE_KIND_TAP] or nil
        local outlet = tap and tap.head or nil
        status.outlet = outlet
        if outlet then
            status.inlet = status.running and math.max(outlet - delta, 0) or outlet
        end
        -- What flipping the switch would buy, so an idle pump can justify itself.
        status.wouldGain = (not status.running) and delta or 0
    end

    return status
end

-- ===== The per-tick step =====
-- Moved here from WaterPipeSystem. The tick still decides WHICH pumps run -- that reads the registry
-- and is scheduling -- but what one pump does with a minute belongs to the pump.

-- Timed through the profiler when there is one and called straight through when there is not: this
-- module loads in the test harness without a profiler, and pump/headroom is a bucket the perf notes
-- name, so the measurement is worth carrying across.
local function timed(name, fn, ...)
    local Profiler = WaterPipes.Profiler
    if Profiler and Profiler.time then
        return timed(name, fn, ...)
    end
    return fn(...)
end

-- Which purifier, if any, this pump can feed: one on a router bordering the pump's own zone, approached
-- from the router's IN side. The OUT offset points at the clean side, so pushing raw lake water in
-- there would contaminate the clean run.
-- Driven by the REGISTRY rather than by searching the world -- a purifier cannot exist without a router
-- under it, and both appear and disappear by player action. The old walk probed six neighbours of every
-- tile of the pump's network, about 1 260 lookups per pump per minute, to return nil on a base with no
-- purifier at all. A registry entry is a claim, not a fact: one the world contradicts is dropped here.
local function findPurifierIntakeForPump(square)
    local purifiers = State.getPurifiers()
    if not purifiers then
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
        local purifierSquare = World.squareAt(coord.x, coord.y, coord.z)
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
                        local routerSquare = World.squareAt(coord.x + offset.x,
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

function Pump.step(pump, square, dt)
    if not pump or (dt or 0) <= 0 then
        return
    end
    -- Resolved off the WaterPipes table rather than required: NetworkAccess requires this
    -- module, so closing the loop would be a recursive require.
    local NetworkAccess = WaterPipes.NetworkAccess

    local source = timed("pump/source", Pump.findSource, pump)
    if not source then
        return   -- booster only: nothing to draw from, but it still adds head to its zone
    end

    -- Ask what can take water FIRST, so we never pull it out of a well and lose it.
    -- Two destinations, not one: a fill query stops dead at a router and a purifier sits on a router, so a
    -- pump feeding one with storage only on the clean side was told "no room" and drew nothing at all.
    local tainted = source.fluidType == "TaintedWater"
    local headroom = timed("pump/headroom", NetworkAccess.availableToPush,
        square, source.fluidType)
    local purifier = timed("pump/purifier", findPurifierIntakeForPump, square)
    local purifierRoom = purifier and Purifier.intakeHeadroom(purifier, tainted) or 0

    local wanted = math.min(Pump.intakeFor(dt), headroom + purifierRoom)
    if wanted <= 0 then
        return
    end

    local taken = timed("pump/draw", Pump.drawFromSource, source, wanted)
    if taken <= 0 then
        return
    end

    -- Network first: it is the destination the player can actually see filling up.
    local added = 0
    if headroom > 0 then
        added = timed("pump/fill", NetworkAccess.fillFluidAtSquare,
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

return Pump
