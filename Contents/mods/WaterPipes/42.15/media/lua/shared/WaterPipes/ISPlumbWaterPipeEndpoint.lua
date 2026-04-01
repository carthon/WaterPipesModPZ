require "TimedActions/ISBaseTimedAction"
require "WaterPipes/EndpointPlumbing"

ISPlumbWaterPipeEndpoint = ISBaseTimedAction:derive("ISPlumbWaterPipeEndpoint")

function ISPlumbWaterPipeEndpoint:isValid()
    return self.character:isEquipped(self.wrench)
        and self.endpointObject
        and self.endpointObject:getSquare() ~= nil
end

function ISPlumbWaterPipeEndpoint:update()
    self.character:faceThisObject(self.endpointObject)
    self.character:setMetabolicTarget(Metabolics.MediumWork)
end

function ISPlumbWaterPipeEndpoint:start()
    self.sound = self.character:playSound("RepairWithWrench")
end

function ISPlumbWaterPipeEndpoint:stop()
    self.character:stopOrTriggerSound(self.sound)
    ISBaseTimedAction.stop(self)
end

function ISPlumbWaterPipeEndpoint:perform()
    self.character:stopOrTriggerSound(self.sound)

    if self.shouldPlumb then
        WaterPipes.EndpointPlumbing.plumb(self.endpointObject)
    else
        WaterPipes.EndpointPlumbing.unplumb(self.endpointObject)
    end

    ISBaseTimedAction.perform(self)
end

function ISPlumbWaterPipeEndpoint:new(character, endpointObject, wrench, shouldPlumb)
    local o = ISBaseTimedAction.new(self, character)
    o.character = character
    o.endpointObject = endpointObject
    o.wrench = wrench
    o.shouldPlumb = shouldPlumb ~= false
    o.maxTime = character:isTimedActionInstant() and 1 or 100
    return o
end
