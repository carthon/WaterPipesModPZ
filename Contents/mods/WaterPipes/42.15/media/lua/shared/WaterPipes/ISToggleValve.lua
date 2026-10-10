require "TimedActions/ISBaseTimedAction"
require "WaterPipes/Constants"
require "WaterPipes/Valve"
require "WaterPipes/SoundOptions"

-- Opening or closing a shut-off valve: walk to it, work the wrench, then flip it on the server (direct in
-- single player). The duration covers the graph rebuild the change costs.

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
    self.sound = WaterPipes.SoundOptions.playOnCharacter(self.character, "RepairWithWrench")
end

function ISToggleValve:stop()
    WaterPipes.SoundOptions.stopOnCharacter(self.character, self.sound)
    ISBaseTimedAction.stop(self)
end

function ISToggleValve:perform()
    WaterPipes.SoundOptions.stopOnCharacter(self.character, self.sound)

    local square = self.valve:getSquare()
    if isClient() and square then
        sendClientCommand(self.character, "WaterPipes", "setValveOpen",
            { x = square:getX(), y = square:getY(), z = square:getZ(), open = self.open })
        -- Shown here too, state and all. The server owns the flip and refuses only when the valve is
        -- gone, which isValid has just ruled out; waiting for its answer leaves the handle wrong and
        -- the menu offering the flip that is already on its way.
        Valve.setLocalState(self.valve, self.open)
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
