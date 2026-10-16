require "TimedActions/ISBaseTimedAction"
require "WaterPipes/Constants"
require "WaterPipes/Valve"
require "WaterPipes/Signals"
require "WaterPipes/SoundOptions"

-- Opening or closing a shut-off valve: walk to it, turn the handwheel by hand, then flip it on the server
-- (direct in single player). The duration covers the graph rebuild the change costs.

ISToggleValve = ISBaseTimedAction:derive("ISToggleValve")

local Valve = WaterPipes.Valve

function ISToggleValve:isValid()
    if not self.valve or not self.valve:getSquare() then
        return false
    end
    if not Valve.isValve(self.valve) then
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
    local Signals = WaterPipes.Signals
    local linked = Signals and Signals.valveLinkCount(self.valve) > 0
    if isClient() and square then
        sendClientCommand(self.character, "WaterPipes", "setValveOpen",
            { x = square:getX(), y = square:getY(), z = square:getZ(), open = self.open })
        -- Shown here too, state and all. The server owns the flip and refuses only when the valve is
        -- gone, which isValid has just ruled out; waiting for its answer leaves the handle wrong and
        -- the menu offering the flip that is already on its way.
        -- A linked valve only moves its switch: whether it opens is the sensors' call, on the server.
        if linked then
            self.valve:getModData()[Signals.VALVE_SWITCH_KEY] = self.open and "on" or "off"
        else
            Valve.setLocalState(self.valve, self.open)
        end
    elseif WaterPipes.SignalBus and WaterPipes.SignalBus.setValveSwitch then
        WaterPipes.SignalBus.setValveSwitch(self.valve, self.open)
    else
        Valve.setOpen(self.valve, self.open)
    end

    ISBaseTimedAction.perform(self)
end

function ISToggleValve:new(character, valve, open)
    local o = ISBaseTimedAction.new(self, character)
    o.character = character
    o.valve = valve
    o.open = open and true or false
    o.stopOnWalk = true
    o.stopOnRun = true
    o.maxTime = character:isTimedActionInstant() and 1 or 60
    return o
end

return ISToggleValve
