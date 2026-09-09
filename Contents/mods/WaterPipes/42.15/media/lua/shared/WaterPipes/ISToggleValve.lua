require "TimedActions/ISBaseTimedAction"
require "WaterPipes/Constants"
require "WaterPipes/Valve"

-- Opening or closing a shut-off valve: the character walks to it, works the wrench, and only then does
-- the valve turn. Same shape as ISToggleHydrant -- the world state is flipped authoritatively on the
-- server via a client command (direct in single-player).
--
-- The duration is not decoration. Closing a valve splits the network, which costs a graph rebuild and
-- an endpoint refresh; inside a timed action that lands where the player is already waiting.

ISToggleValve = ISBaseTimedAction:derive("ISToggleValve")

local Valve = WaterPipes.Valve

function ISToggleValve:isValid()
    if not self.valve or not self.valve:getSquare() then
        return false
    end
    if not Valve.isValve(self.valve) then
        return false
    end
    if self.wrench and not self.character:isEquipped(self.wrench) then
        return false
    end
    return true
end

function ISToggleValve:update()
    self.character:faceThisObject(self.valve)
    self.character:setMetabolicTarget(Metabolics.LightWork)
end

function ISToggleValve:start()
    self:setActionAnim("VehicleWorkOnMid")
    self.sound = self.character:playSound("RepairWithWrench")
end

function ISToggleValve:stop()
    self.character:stopOrTriggerSound(self.sound)
    ISBaseTimedAction.stop(self)
end

function ISToggleValve:perform()
    self.character:stopOrTriggerSound(self.sound)

    local square = self.valve:getSquare()
    if isClient() and square then
        sendClientCommand(self.character, "WaterPipes", "setValveOpen",
            { x = square:getX(), y = square:getY(), z = square:getZ(), open = self.open })
    else
        Valve.setOpen(self.valve, self.open)
    end

    ISBaseTimedAction.perform(self)
end

function ISToggleValve:new(character, valve, wrench, open)
    local o = ISBaseTimedAction.new(self, character)
    o.character = character
    o.valve = valve
    o.wrench = wrench
    o.open = open and true or false
    o.stopOnWalk = true
    o.stopOnRun = true
    o.maxTime = character:isTimedActionInstant() and 1 or 60
    return o
end

return ISToggleValve
