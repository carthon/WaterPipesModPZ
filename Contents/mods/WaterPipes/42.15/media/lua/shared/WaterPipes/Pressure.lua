WaterPipes = WaterPipes or {}
WaterPipes.Pressure = WaterPipes.Pressure or {}

require "WaterPipes/Constants"

local Constants = WaterPipes.Constants
local Pressure = WaterPipes.Pressure

-- Hydraulic head, in metres of water column (m.c.a.). See the pressure block in Constants.lua for
-- the model and why the unit is real.
--
-- Per-save tunables, the flow curve and the lift gate. The head itself is solved in Hydraulics.
-- Everything here is pure: no world access, no caching.

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

-- Share of the inlet head a purifier passes to its clean side. 1 = transparent, 0 = none.
function Pressure.purifierHeadTransfer()
    return sandboxPercent("PurifierHeadTransfer", Constants.PURIFIER_HEAD_TRANSFER)
end

-- How far below itself a pump can still lift a source. Atmospheric pressure is the real cap here,
-- not motor power -- which is why this number is so much smaller than pumpHead().
function Pressure.suctionLimit()
    return sandboxTenths("PumpSuctionLimit", Constants.PUMP_SUCTION_LIMIT)
end

-- ===== The lift gate =====

-- Whether a head goes on a dial as a number. At or below zero the tile stands above the water with
-- nothing lifting it, and the player is told there is no pressure rather than shown a negative figure.
function Pressure.onDial(head)
    return head ~= nil and head > 0
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
