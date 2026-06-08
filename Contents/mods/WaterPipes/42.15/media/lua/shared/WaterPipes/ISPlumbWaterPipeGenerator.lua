require "TimedActions/ISBaseTimedAction"
require "WaterPipes/GeneratorFuel"

ISPlumbWaterPipeGenerator = ISBaseTimedAction:derive("ISPlumbWaterPipeGenerator")

function ISPlumbWaterPipeGenerator:isValid()
    return self.character:isEquipped(self.wrench)
        and self.generator
        and self.generator:getSquare() ~= nil
end

function ISPlumbWaterPipeGenerator:update()
    self.character:faceThisObject(self.generator)
    self.character:setMetabolicTarget(Metabolics.MediumWork)
end

function ISPlumbWaterPipeGenerator:start()
    self.sound = self.character:playSound("RepairWithWrench")
end

function ISPlumbWaterPipeGenerator:stop()
    self.character:stopOrTriggerSound(self.sound)
    ISBaseTimedAction.stop(self)
end

function ISPlumbWaterPipeGenerator:perform()
    self.character:stopOrTriggerSound(self.sound)

    local square = self.generator and self.generator.getSquare and self.generator:getSquare()
    if isClient() and square then
        -- MP: mutate the generator authoritatively on the server (avoids client/server desync).
        sendClientCommand(self.character, "WaterPipes",
            self.shouldPlumb and "plumbGenerator" or "unplumbGenerator",
            { x = square:getX(), y = square:getY(), z = square:getZ() })
    elseif self.shouldPlumb then
        WaterPipes.GeneratorFuel.plumb(self.generator)
    else
        WaterPipes.GeneratorFuel.unplumb(self.generator)
    end

    ISBaseTimedAction.perform(self)
end

function ISPlumbWaterPipeGenerator:new(character, generator, wrench, shouldPlumb)
    local o = ISBaseTimedAction.new(self, character)
    o.character = character
    o.generator = generator
    o.wrench = wrench
    o.shouldPlumb = shouldPlumb ~= false
    o.maxTime = character:isTimedActionInstant() and 1 or 100
    return o
end
