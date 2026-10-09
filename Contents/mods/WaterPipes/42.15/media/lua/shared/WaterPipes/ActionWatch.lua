WaterPipes = WaterPipes or {}
WaterPipes.ActionWatch = WaterPipes.ActionWatch or {}

require "WaterPipes/World"
require "WaterPipes/PipeObjectUtils"
require "WaterPipes/Logger"

local World = WaterPipes.World
local PipeObjectUtils = WaterPipes.PipeObjectUtils
local Logger = WaterPipes.Logger
local ActionWatch = WaterPipes.ActionWatch

-- A timed action can turn an object into a vessel without any event: cutting a barrel's lid open can add
-- the FluidContainer to the barrel itself. So when any action finishes, the piped tiles it worked on are
-- re-read. Those tiles come from the action's own fields, never from where the character stands: with
-- cheats an action reaches as far as the player clicks.

-- Re-read at once, and again a moment later: on a client the server's change arrives after the action.
local RECHECK_AFTER_TICKS = { 1, 90 }
-- Fields looked at per action, nested tables included. An action is a handful of fields; this only stops
-- one holding a UI or a large table from costing more than it is worth.
local FIELD_BUDGET = 64

local tick = 0
local pending = {}          -- ["x:y:z"] = { x, y, z, due = { ticks... } }
local pendingCount = 0

local function squareOfValue(value)
    if value == nil or type(value) == "number" or type(value) == "string" or not instanceof then
        return nil
    end
    if instanceof(value, "IsoGridSquare") then
        return value
    end
    if instanceof(value, "IsoObject") and not instanceof(value, "IsoGameCharacter") and value.getSquare then
        local ok, square = pcall(value.getSquare, value)
        return ok and square or nil
    end
    return nil
end

local function collectSquares(action)
    local found = {}
    local seen = {}
    local budget = FIELD_BUDGET

    local function add(square)
        if square and square.getX then
            found[#found + 1] = square
        end
    end

    local function visit(value, depth)
        if budget <= 0 then
            return
        end
        budget = budget - 1
        local square = squareOfValue(value)
        if square then
            add(square)
            return
        end
        if depth > 0 and type(value) == "table" and not seen[value] then
            seen[value] = true
            for key, nested in pairs(value) do
                -- The character is where the action was done FROM; `action` is the engine's handle.
                if key ~= "character" and key ~= "action" then
                    visit(nested, depth - 1)
                end
            end
        end
    end

    visit(action, 2)

    if type(action.x) == "number" and type(action.y) == "number" then
        add(World.squareAt(action.x, action.y, type(action.z) == "number" and action.z or 0))
    end
    return found
end

function ActionWatch.noteFinished(action)
    if type(action) ~= "table" then
        return
    end
    for _, square in ipairs(collectSquares(action)) do
        if PipeObjectUtils.getPipeOnSquare(square) then
            local x, y, z = square:getX(), square:getY(), square:getZ()
            local key = tostring(x) .. ":" .. tostring(y) .. ":" .. tostring(z)
            if not pending[key] then
                pendingCount = pendingCount + 1
            end
            local due = {}
            for _, after in ipairs(RECHECK_AFTER_TICKS) do
                due[#due + 1] = tick + after
            end
            pending[key] = { x = x, y = y, z = z, due = due }
        end
    end
end

local function onTick()
    tick = tick + 1
    if pendingCount == 0 then
        return
    end
    local System = WaterPipes.System
    for key, entry in pairs(pending) do
        if entry.due[1] <= tick then
            table.remove(entry.due, 1)
            local square = World.squareAt(entry.x, entry.y, entry.z)
            if square and System and System.recheckVesselsAt then
                local ok, err = pcall(System.recheckVesselsAt, square)
                if not ok then
                    Logger.error("Vessel recheck after an action failed: " .. tostring(err))
                end
            end
            if #entry.due == 0 then
                pending[key] = nil
                pendingCount = pendingCount - 1
            end
        end
    end
end

-- ===== Wrapping =====
-- On the class, never on the instance: a networked action's fields are sent to the server, and a
-- function among them is not something to put on the wire.

local wrappers = {}
local wrappedClasses = {}

local function wrapMethod(class, name)
    local original = rawget(class, name)
    if type(original) ~= "function" or wrappers[original] then
        return
    end
    local function wrapper(self, ...)
        local a, b, c = original(self, ...)
        pcall(ActionWatch.noteFinished, self)
        return a, b, c
    end
    wrappers[wrapper] = true
    class[name] = wrapper
end

-- complete() is where B42 actions change the world (server and single player); perform() runs on the
-- client. Each class up the chain, stopping at the base, which subclasses call for the queue only.
local function wrapClass(class)
    while type(class) == "table" and class ~= ISBaseTimedAction and not wrappedClasses[class] do
        wrappedClasses[class] = true
        wrapMethod(class, "complete")
        wrapMethod(class, "perform")
        class = getmetatable(class)
    end
end

local function derivesFromBase(value)
    local class = getmetatable(value)
    local steps = 0
    while type(class) == "table" and steps < 16 do
        if class == ISBaseTimedAction then
            return true
        end
        class = getmetatable(class)
        steps = steps + 1
    end
    return false
end

-- Every action class defined by now, the mod's own and everyone else's.
local function wrapAllKnown()
    for _, value in pairs(_G) do
        if type(value) == "table" and value ~= ISBaseTimedAction and derivesFromBase(value) then
            pcall(wrapClass, value)
        end
    end
end

local installed = false
function ActionWatch.install()
    if type(ISBaseTimedAction) ~= "table" or type(ISBaseTimedAction.new) ~= "function" then
        return
    end
    if not installed then
        installed = true
        -- A class first used after the sweep is wrapped when its first instance is made.
        local originalNew = ISBaseTimedAction.new
        ISBaseTimedAction.new = function(self, ...)
            if self ~= ISBaseTimedAction then
                pcall(wrapClass, self)
            end
            return originalNew(self, ...)
        end
    end
    wrapAllKnown()
end

ActionWatch.install()

if Events then
    if Events.OnTick then
        Events.OnTick.Add(onTick)
    end
    -- Again once every mod has loaded, on whichever side this is: their classes exist by then.
    if Events.OnGameBoot then
        Events.OnGameBoot.Add(ActionWatch.install)
    end
    if Events.OnServerStarted then
        Events.OnServerStarted.Add(ActionWatch.install)
    end
    if Events.OnGameStart then
        Events.OnGameStart.Add(ActionWatch.install)
    end
end

return ActionWatch
