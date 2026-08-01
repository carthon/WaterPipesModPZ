require "TimedActions/ISBaseTimedAction"
require "WaterPipes/Pump"

-- Tiny timed action queued AFTER the walk-to so the pump status window opens once the character has
-- actually reached the machine, like inspecting a container. The walk itself is queued by
-- luautils.walkAdjObject in ContextMenu.openPump; this just pops the window on arrival. Same shape as
-- ISOpenWaterPurifier.

ISOpenWaterPump = ISBaseTimedAction:derive("ISOpenWaterPump")

function ISOpenWaterPump:isValid()
    return self.pump ~= nil and self.pump:getSquare() ~= nil
end

function ISOpenWaterPump:update()
    self.character:faceThisObject(self.pump)
end

function ISOpenWaterPump:start()
end

function ISOpenWaterPump:stop()
    ISBaseTimedAction.stop(self)
end

function ISOpenWaterPump:perform()
    if WaterPipesPumpWindow then
        WaterPipesPumpWindow.openFor(self.pump)
    end
    ISBaseTimedAction.perform(self)
end

function ISOpenWaterPump:new(character, pump)
    local o = ISBaseTimedAction.new(self, character)
    o.character = character
    o.pump = pump
    o.stopOnWalk = false
    o.stopOnRun = false
    o.maxTime = character:isTimedActionInstant() and 1 or 8   -- brief; the walk already positioned us
    return o
end

return ISOpenWaterPump
