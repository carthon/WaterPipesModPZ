-- WaterPipes/RemovalAudit.lua
--
-- Says out loud, once per removal, what left the world and whether this mod's tables were told.
--
-- Several caches and registries in this mod are kept correct by object-lifecycle events rather than
-- by periodic rescanning, and each one carries a periodic "backstop" that exists solely because
-- nobody could prove the events fire in every case. Those backstops are the most expensive thing the
-- mod does -- the drop they force was measured at ~190 ms of client work per in-game minute -- and
-- they are being paid for a doubt, not for a known failure.
--
-- This turns the doubt into an experiment. Destroy things by every means you can arrange -- fire,
-- zombies, a sledgehammer, an explosion, another mod, a chunk being unloaded under you -- and read
-- the log. Every removal this mod NOTICES prints a line. A removal that produces no line is a hole,
-- and the line it failed to print names exactly what would have gone stale.
--
-- See docs/removal-events.md for what has been established so far and what remains to be proven.
--
-- Off by default. Turn it on from the pipe Debug menu; it prints one line per relevant removal and
-- nothing at all for the corpses, bags and litter that make up almost every removal in a real game.

require "WaterPipes/Logger"
require "WaterPipes/PipeObjectUtils"

WaterPipes = WaterPipes or {}
WaterPipes.RemovalAudit = WaterPipes.RemovalAudit or {}

local Audit = WaterPipes.RemovalAudit
local Logger = WaterPipes.Logger
local PipeObjectUtils = WaterPipes.PipeObjectUtils

local enabled = false

-- Tallies, so a session can be summarised without reading every line. Also surfaced by the profiler.
Audit.counts = { seen = 0, relevant = 0, ignored = 0 }

function Audit.isEnabled()
    return enabled
end

function Audit.setEnabled(value)
    enabled = value and true or false
    Audit.counts = { seen = 0, relevant = 0, ignored = 0 }
    Logger.log("removal audit " .. (enabled and "ON" or "OFF"))
end

function Audit.toggle()
    Audit.setEnabled(not enabled)
    return enabled
end

-- What this object is, in the terms the mod's tables are keyed by. Resolved lazily off the global
-- table so this module can load before any of them and needs no require cycle.
local function classify(object)
    local kinds = {}
    local WP = WaterPipes

    local function note(label, ok)
        if ok then
            kinds[#kinds + 1] = label
        end
    end

    local function safe(fn, ...)
        if not fn then
            return false
        end
        local ok, result = pcall(fn, ...)
        return ok and result and true or false
    end

    note("pipe", safe(PipeObjectUtils.isPipeObject, object))
    note("router", WP.Router and safe(WP.Router.isRouter, object))
    note("pump", WP.Pump and safe(WP.Pump.isPump, object))
    note("well", WP.Pump and safe(WP.Pump.isWell, object))
    note("sprinkler", WP.Irrigation and safe(WP.Irrigation.isSprinkler, object))
    note("drip", WP.Irrigation and safe(WP.Irrigation.isDrip, object))
    note("hydrant", WP.Hydrant and safe(WP.Hydrant.isHydrant, object))
    note("purifier", WP.Purifier and safe(WP.Purifier.isPurifier, object))

    -- Anything holding fluid matters to the vessel classification even when it is none of the above.
    if object and object.getFluidContainer then
        local ok, container = pcall(object.getFluidContainer, object)
        note("vessel", ok and container ~= nil)
    end

    return kinds
end

-- Which of the mod's own tables claim this tile. If a removal is not followed by these going false,
-- the table did not hear about it -- which is the whole question this module exists to answer.
local function registryClaims(x, y, z)
    local claims = {}
    local State = WaterPipes.State
    if not State or not State.ensure then
        return claims
    end

    local ok, state = pcall(State.ensure)
    if not ok or not state then
        return claims
    end

    local key = State.squareKey(x, y, z)
    if state.pipes and state.pipes[key] then claims[#claims + 1] = "state.pipes" end
    if state.purifiers and state.purifiers[key] then claims[#claims + 1] = "state.purifiers" end
    if state.openHydrants and state.openHydrants[key] then claims[#claims + 1] = "state.openHydrants" end
    return claims
end

local function join(list, empty)
    if #list == 0 then
        return empty
    end
    return table.concat(list, "+")
end

-- `cause` is the event that fired, which is the point: a removal seen through only one of them, or
-- through neither, is the finding.
function Audit.note(object, cause)
    if not enabled or not object then
        return
    end

    Audit.counts.seen = Audit.counts.seen + 1

    local kinds = classify(object)
    if #kinds == 0 then
        -- A corpse, a dropped bag, a piece of furniture. Nothing in this mod is keyed by it.
        Audit.counts.ignored = Audit.counts.ignored + 1
        return
    end

    Audit.counts.relevant = Audit.counts.relevant + 1

    local x, y, z = "?", "?", "?"
    local square = nil
    if object.getSquare then
        local ok, found = pcall(object.getSquare, object)
        square = ok and found or nil
    end
    if square and square.getX then
        x, y, z = square:getX(), square:getY(), square:getZ()
    end

    local name = "?"
    if object.getName then
        local ok, found = pcall(object.getName, object)
        if ok and found then name = tostring(found) end
    end

    Logger.log(string.format(
        "REMOVAL via %s: %s at %s:%s:%s (name=%s) claimed by [%s]",
        cause, join(kinds, "none"), tostring(x), tostring(y), tostring(z), name,
        join(registryClaims(x, y, z), "nothing")))
end

function Audit.report()
    local c = Audit.counts
    return string.format(
        "removal audit: %d removals seen, %d relevant to this mod, %d ignored",
        c.seen, c.relevant, c.ignored)
end

-- Both events, separately labelled. The mod already listens to both for pipe bookkeeping, and whether
-- a given kind of destruction raises one, the other, or neither is exactly what needs establishing.
if Events then
    if Events.OnObjectAboutToBeRemoved then
        Events.OnObjectAboutToBeRemoved.Add(function(object)
            pcall(Audit.note, object, "OnObjectAboutToBeRemoved")
        end)
    end
    if Events.OnDestroyIsoThumpable then
        Events.OnDestroyIsoThumpable.Add(function(object)
            pcall(Audit.note, object, "OnDestroyIsoThumpable")
        end)
    end
end

return Audit
