WaterPipes = WaterPipes or {}
WaterPipes.Sledgehammer = WaterPipes.Sledgehammer or {}

require "TimedActions/ISDestroyStuffAction"

local Sledgehammer = WaterPipes.Sledgehammer

-- Vanilla's sledgehammer raises only OnObjectAboutToBeRemoved, like Disassemble (OnDestroyIsoThumpable is for
-- zombies and weapons, and never fires on a non-thumpable pipe), so only its action can tell the two apart.
-- The event fires inside complete().

local swinging = false

function Sledgehammer.isSwinging()
    return swinging
end

-- The same wrapping twice would chain. Exposed so a game that loads the action late still gets it.
function Sledgehammer.install()
    if Sledgehammer.installed or not ISDestroyStuffAction then
        return false
    end
    Sledgehammer.installed = true
    local original = ISDestroyStuffAction.complete
    ISDestroyStuffAction.complete = function(self)
        swinging = true
        local ok, result = pcall(original, self)
        swinging = false
        if not ok then
            error(result)
        end
        return result
    end
    return true
end

if not Sledgehammer.install() and Events and Events.OnGameBoot then
    Events.OnGameBoot.Add(Sledgehammer.install)
end

return Sledgehammer
