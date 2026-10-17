require "TimedActions/ISBaseTimedAction"

-- Walk to the humidity sensor first, then open its window: queued after luautils.walkAdjObject, like
-- ISOpenWaterPump.

ISOpenHumiditySensor = ISBaseTimedAction:derive("ISOpenHumiditySensor")

function ISOpenHumiditySensor:isValid()
    return self.sensor ~= nil and self.sensor:getSquare() ~= nil
end

function ISOpenHumiditySensor:update()
    self.character:faceThisObject(self.sensor)
end

function ISOpenHumiditySensor:start()
end

function ISOpenHumiditySensor:stop()
    ISBaseTimedAction.stop(self)
end

function ISOpenHumiditySensor:perform()
    if WaterPipesSensorWindow then
        WaterPipesSensorWindow.openFor(self.sensor, self.character)
    end
    ISBaseTimedAction.perform(self)
end

function ISOpenHumiditySensor:new(character, sensor)
    local o = ISBaseTimedAction.new(self, character)
    o.character = character
    o.sensor = sensor
    o.stopOnWalk = false
    o.stopOnRun = false
    o.maxTime = character:isTimedActionInstant() and 1 or 8
    return o
end

return ISOpenHumiditySensor
