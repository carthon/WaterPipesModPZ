require "TimedActions/ISBaseTimedAction"
require "WaterPipes/Constants"
require "WaterPipes/Hydrant"

-- Opening or closing a fire hydrant: the character walks to it, works the wrench, and only then does
-- the valve turn. Same shape as ISRepairWaterDrip -- the world state is flipped authoritatively on the
-- server via a client command (direct in single-player).

ISToggleHydrant = ISBaseTimedAction:derive("ISToggleHydrant")

local Constants = WaterPipes.Constants
local Hydrant = WaterPipes.Hydrant

function ISToggleHydrant:isValid()
    if not self.hydrant or not self.hydrant:getSquare() then
        return false
    end
    if not Hydrant.isHydrant(self.hydrant) then
        return false
    end
    if self.wrench and not self.character:isEquipped(self.wrench) then
        return false
    end
    return true
end

function ISToggleHydrant:update()
    self.character:faceThisObject(self.hydrant)
    self.character:setMetabolicTarget(Metabolics.LightWork)
end

function ISToggleHydrant:start()
    self:setActionAnim("VehicleWorkOnMid")
    self.sound = self.character:playSound("RepairWithWrench")
end

function ISToggleHydrant:stop()
    self.character:stopOrTriggerSound(self.sound)
    ISBaseTimedAction.stop(self)
end

function ISToggleHydrant:perform()
    self.character:stopOrTriggerSound(self.sound)

    local square = self.hydrant:getSquare()
    if isClient() and square then
        sendClientCommand(self.character, "WaterPipes", "setHydrantOpen",
            { x = square:getX(), y = square:getY(), z = square:getZ(), open = self.open })
    else
        Hydrant.setOpen(self.hydrant, self.open)
    end

    ISBaseTimedAction.perform(self)
end

function ISToggleHydrant:new(character, hydrant, wrench, open)
    local o = ISBaseTimedAction.new(self, character)
    o.character = character
    o.hydrant = hydrant
    o.wrench = wrench
    o.open = open and true or false
    o.stopOnWalk = true
    o.stopOnRun = true
    o.maxTime = character:isTimedActionInstant() and 1 or 80
    return o
end

return ISToggleHydrant
