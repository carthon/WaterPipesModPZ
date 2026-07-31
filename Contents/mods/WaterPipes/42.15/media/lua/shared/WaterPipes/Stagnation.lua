WaterPipes = WaterPipes or {}
WaterPipes.Stagnation = WaterPipes.Stagnation or {}

require "WaterPipes/Constants"

local Constants = WaterPipes.Constants
local Stagnation = WaterPipes.Stagnation

-- The policy half of water stagnation: the clock, the per-vessel timestamp, and the two decisions
-- "should this go bad?" and "should the rain ruin this?". The server-side passes that walk the
-- network and actually taint the water live in WaterPipeSystem; this module holds nothing that needs
-- the world, so it stays pure and testable. See the stagnation block in Constants.lua for the model.

-- ===== Per-save tunables (Sandbox Options) =====

function Stagnation.isEnabled()
    local sv = SandboxVars and SandboxVars.WaterPipes
    local v = sv and sv.WaterStagnation
    if type(v) == "boolean" then
        return v
    end
    return true   -- on by default
end

local function sandboxDays(name, fallback)
    local sv = SandboxVars and SandboxVars.WaterPipes
    local v = sv and sv[name]
    if type(v) == "number" then
        return math.max(v, 0)
    end
    return fallback
end

-- Days a closed / open vessel may sit still before its water turns. 0 means "never" for that class.
function Stagnation.daysClosed()
    return sandboxDays("StagnationDaysClosed", Constants.STAGNATION_DAYS_CLOSED)
end

function Stagnation.daysOpen()
    return sandboxDays("StagnationDaysOpen", Constants.STAGNATION_DAYS_OPEN)
end

function Stagnation.rainTaints()
    local sv = SandboxVars and SandboxVars.WaterPipes
    local v = sv and sv.RainTaintsOpenWater
    if type(v) == "boolean" then
        return v
    end
    return true
end

-- ===== The clock =====

-- World age in hours: monotonic, save-persistent, and the very clock the engine's own water shutoff
-- runs on. nil if it cannot be read (never taint on a missing clock).
function Stagnation.nowHours()
    if not getGameTime then
        return nil
    end
    local gt = getGameTime()
    if not gt or not gt.getWorldAgeHours then
        return nil
    end
    local ok, hours = pcall(gt.getWorldAgeHours, gt)
    return ok and hours or nil
end

-- ===== Per-vessel timestamp =====

local function getModData(worldObject)
    if not worldObject or not worldObject.getModData then
        return nil
    end
    local ok, modData = pcall(worldObject.getModData, worldObject)
    return ok and modData or nil
end

function Stagnation.readStamp(worldObject)
    local modData = getModData(worldObject)
    local v = modData and modData[Constants.STAGNATION_STAMP_KEY]
    return type(v) == "number" and v or nil
end

function Stagnation.stamp(worldObject, hours)
    local modData = getModData(worldObject)
    if not modData then
        return
    end
    modData[Constants.STAGNATION_STAMP_KEY] = hours
    if worldObject.transmitModData then
        pcall(worldObject.transmitModData, worldObject)
    end
end

-- Movement resets the clock. Called from OnWaterAmountChange for a container that still holds CLEAN
-- water -- tainted water has nothing left to protect, so we do not bother stamping it, which also
-- means the act of tainting a vessel never refreshes its own stamp.
function Stagnation.noteMovement(worldObject, fluidTypeName, hours)
    if not Stagnation.isEnabled() or fluidTypeName ~= "Water" then
        return
    end
    hours = hours or Stagnation.nowHours()
    if hours then
        Stagnation.stamp(worldObject, hours)
    end
end

-- ===== Decisions =====

-- Open = collects rain = exposed to the air. Read off the vessel's rain-catcher factor, so it covers
-- any modded container without us keeping a list: a rain barrel and an open amphora report > 0, a
-- sealed tank and a lidded amphora report 0.
function Stagnation.isOpenContainer(fluidContainer)
    if not fluidContainer or not fluidContainer.getRainCatcher then
        return false
    end
    local ok, factor = pcall(fluidContainer.getRainCatcher, fluidContainer)
    return ok and type(factor) == "number" and factor > 0 or false
end

-- Hours a vessel of this kind may sit still, or nil when that class is switched off (days = 0).
function Stagnation.limitHours(isOpen)
    local days = isOpen and Stagnation.daysOpen() or Stagnation.daysClosed()
    if days <= 0 then
        return nil
    end
    return days * 24
end

-- Has a vessel last touched at `stamp` sat still long enough to turn? A nil stamp is "just seen":
-- not stagnant yet, but the caller should record now() so the limit starts counting.
function Stagnation.hasStagnated(stamp, isOpen, nowHours)
    local limit = Stagnation.limitHours(isOpen)
    if not limit or not stamp or not nowHours then
        return false
    end
    return (nowHours - stamp) >= limit
end

return Stagnation
