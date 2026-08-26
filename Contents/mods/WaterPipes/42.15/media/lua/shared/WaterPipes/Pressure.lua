WaterPipes = WaterPipes or {}
WaterPipes.Pressure = WaterPipes.Pressure or {}

require "WaterPipes/Constants"

local Constants = WaterPipes.Constants
local Pressure = WaterPipes.Pressure

-- Hydraulic head, in metres of water column (m.c.a.). See the pressure block in Constants.lua for
-- the model and why the unit is real. This module owns the arithmetic and the per-save tunables;
-- the traversal that supplies (z, hops) lives in NetworkAccess.
--
-- Everything here is pure: no world access, no caching. NetworkAccess already re-floods the network
-- per query, and pressure rides along on that same BFS rather than adding a pass of its own.

-- ===== Per-save tunables (Sandbox Options), all falling back to the constants =====

-- Tenths, so integer sandbox sliders can express 3.0 as 30 without a float option type.
local function sandboxTenths(name, fallback)
    local sv = SandboxVars and SandboxVars.WaterPipes
    local v = sv and sv[name]
    if type(v) == "number" then
        return math.max(v, 0) / 10
    end
    return fallback
end

local function sandboxPercent(name, fallback)
    local sv = SandboxVars and SandboxVars.WaterPipes
    local v = sv and sv[name]
    if type(v) == "number" then
        return math.max(v, 0) / 100
    end
    return fallback
end

-- Which model this save runs. Defaults to REALISTIC when the sandbox var is absent.
function Pressure.model()
    local sv = SandboxVars and SandboxVars.WaterPipes
    local v = sv and sv.PressureModel
    if type(v) == "number"
        and v >= Constants.PRESSURE_MODEL_REALISTIC
        and v <= Constants.PRESSURE_MODEL_OFF then
        return v
    end
    return Constants.PRESSURE_MODEL_REALISTIC
end

function Pressure.isEnabled()
    return Pressure.model() ~= Constants.PRESSURE_MODEL_OFF
end

function Pressure.levelHead()
    return sandboxTenths("PressurePerLevel", Constants.PRESSURE_PER_LEVEL)
end

function Pressure.containerBase()
    return sandboxTenths("PressureContainerBase", Constants.CONTAINER_BASE_PRESSURE)
end

-- Friction per pipe tile for a given consumer kind, scaled by WaterPipes.PressureFrictionScale
-- (a percentage: 100 = default, 0 = distance never costs anything).
-- SIMPLE model = height only, so friction is zero whatever the scale says.
function Pressure.frictionFor(kind)
    if Pressure.model() == Constants.PRESSURE_MODEL_SIMPLE then
        return 0
    end

    local base = Constants.PRESSURE_FRICTION_TAP
    if kind == Constants.PRESSURE_KIND_DRIP then
        base = Constants.PRESSURE_FRICTION_DRIP
    elseif kind == Constants.PRESSURE_KIND_SPRINKLER then
        base = Constants.PRESSURE_FRICTION_SPRINKLER
    end

    return base * sandboxPercent("PressureFrictionScale", 1)
end

-- Head at which a throttled transfer reaches its full rate.
function Pressure.flowReference()
    return sandboxTenths("PressureFlowReference", Constants.HYDRAULIC_FLOW_REFERENCE_PRESSURE)
end

-- Fraction of its maximum rate a transfer runs at, given the head (m.c.a.) reaching the consumer's tile.
--
-- Q proportional to sqrt(dP) is orifice flow, and the curve is the whole reason to prefer it over a
-- linear one: at half the reference head a transfer still moves 71%, so an ordinary barrel on the same
-- floor keeps working instead of crawling. Linear would have cut that same barrel to a third, which is
-- the opposite of what a player asking for faster transfers wants.
--
-- Capped at 1: head above the reference buys nothing. A pump makes a starved line work, it does not
-- make a healthy one overspeed.
--
-- Returns 1 whole when the pressure model is off, so a save with pressure disabled transfers exactly as
-- it did before this existed -- without it, applyPressureGate's container-base fallback would have
-- throttled those saves to 58% for no reason the player could see.
function Pressure.flowFactor(head)
    if not Pressure.isEnabled() then
        return 1.0
    end
    local reference = Pressure.flowReference()
    if reference <= 0 then
        return 1.0
    end
    local available = math.max(head or 0, 0)
    if available >= reference then
        return 1.0
    end
    return math.sqrt(available / reference)
end

function Pressure.minimumFor(kind)
    if kind == Constants.PRESSURE_KIND_DRIP then
        return Constants.PRESSURE_MIN_DRIP
    elseif kind == Constants.PRESSURE_KIND_SPRINKLER then
        return Constants.PRESSURE_MIN_SPRINKLER
    end
    return Constants.PRESSURE_MIN_TAP
end

-- Head one powered pump adds. Real domestic pressure sets are ~2.5 bar; chaining them adds up,
-- which is what the player is buying when they build a second one.
function Pressure.pumpHead()
    return sandboxTenths("PumpHead", Constants.PUMP_HEAD)
end

-- How far below itself a pump can still lift a source. Atmospheric pressure is the real cap here,
-- not motor power -- which is why this number is so much smaller than pumpHead().
function Pressure.suctionLimit()
    return sandboxTenths("PumpSuctionLimit", Constants.PUMP_SUCTION_LIMIT)
end

-- ===== The model =====

-- Head delivered by a source sitting `hops` pipe tiles away at z = sourceZ, to a consumer at
-- z = consumerZ drawing at `kind`'s flow rate, with `pumpHead` m.c.a. of pumping in the zone.
-- Falling water gains head, climbing spends it, distance always costs, pumps add. May be negative,
-- which means the source cannot reach the consumer at all.
-- Pumps are counted PER ZONE, not per path: every powered pump between the same pair of routers lifts
-- the whole zone. Routers are already the only network boundary the mod has.
function Pressure.delivered(sourceZ, consumerZ, hops, kind, pumpHead)
    return Pressure.containerBase()
        + Pressure.levelHead() * ((sourceZ or 0) - (consumerZ or 0))
        - Pressure.frictionFor(kind) * math.max(hops or 0, 0)
        + math.max(pumpHead or 0, 0)
end

-- Head that a pressure-reducing valve set to `ceiling` lands with, `hops` tiles downstream of itself at
-- z = regulatorZ.
-- A regulator fixes the head at ITS OUTLET, not everywhere behind it: past the valve the water keeps
-- paying friction and height exactly as it does coming off a source, so the valve is priced as a fresh
-- source that happens to deliver `ceiling`. Capping the finished head instead made a whole regulated
-- branch sit at the setting no matter how long it was, which no real pipe does.
-- `pumpHead` is only the pumps BETWEEN the valve and the consumer. One upstream cannot push past it --
-- that is what a regulator is for -- but one downstream re-pressurises its own branch.
function Pressure.atRegulator(ceiling, regulatorZ, consumerZ, hops, kind, pumpHead)
    return (ceiling or 0)
        + Pressure.levelHead() * ((regulatorZ or 0) - (consumerZ or 0))
        - Pressure.frictionFor(kind) * math.max(hops or 0, 0)
        + math.max(pumpHead or 0, 0)
end

-- Can a source at (sourceZ, hops) drive a `kind` consumer at consumerZ?
-- With the model off every physically-connected source qualifies, which restores the behaviour from
-- before pressure existed.
function Pressure.canReach(sourceZ, consumerZ, hops, kind, pumpHead)
    if not Pressure.isEnabled() then
        return true
    end
    return Pressure.delivered(sourceZ, consumerZ, hops, kind, pumpHead) >= Pressure.minimumFor(kind)
end

-- The FILL side: can fluid entering the network at originZ reach a container at targetZ? Only lift is
-- priced, not distance -- filling is the network settling, not a consumer drawing.
-- With no pump this reproduces the old "down" traversal exactly: climbing needs lift > 0 and is
-- refused, the same floor costs 0 and passes, falling is negative and passes. Add a pump and the same
-- rule lets water climb pumpHead/3 floors.
function Pressure.canFillTo(originZ, targetZ, pumpHead)
    if not Pressure.isEnabled() then
        return true
    end
    local lift = Pressure.levelHead() * ((targetZ or 0) - (originZ or 0))
    return lift <= math.max(pumpHead or 0, 0)
end

return Pressure
