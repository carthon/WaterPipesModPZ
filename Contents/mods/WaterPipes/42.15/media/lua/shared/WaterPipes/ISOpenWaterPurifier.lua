require "TimedActions/ISBaseTimedAction"
require "WaterPipes/Purifier"

-- Tiny timed action queued AFTER the walk-to so the purifier readout window opens once the character
-- has actually reached the tank (like inspecting a container). The walk itself is queued by
-- luautils.walkAdjObject in ContextMenu.openPurifier; this just pops the window on arrival.

ISOpenWaterPurifier = ISBaseTimedAction:derive("ISOpenWaterPurifier")

function ISOpenWaterPurifier:isValid()
    return self.purifier and self.purifier:getSquare() ~= nil
end

function ISOpenWaterPurifier:update()
    self.character:faceThisObject(self.purifier)
end

function ISOpenWaterPurifier:start()
end

function ISOpenWaterPurifier:stop()
    ISBaseTimedAction.stop(self)
end

function ISOpenWaterPurifier:perform()
    if WaterPipesPurifierWindow then
        WaterPipesPurifierWindow.openFor(self.purifier, self.anchorSquare)
    end
    ISBaseTimedAction.perform(self)
end

function ISOpenWaterPurifier:new(character, purifier, anchorSquare)
    local o = ISBaseTimedAction.new(self, character)
    o.character = character
    o.purifier = purifier
    o.anchorSquare = anchorSquare
    o.stopOnWalk = false
    o.stopOnRun = false
    o.maxTime = character:isTimedActionInstant() and 1 or 8   -- brief; the walk already positioned us
    return o
end

return ISOpenWaterPurifier
