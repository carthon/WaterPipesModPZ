require "TimedActions/ISBaseTimedAction"
require "WaterPipes/Constants"
require "WaterPipes/Pump"

-- Flipping a water pump's switch. The character walks to the pump, reaches down to the panel and only
-- then does the state change -- same shape as ISToggleHydrant, except a switch needs no tool, so the
-- option shows with empty hands. The flip itself is server-authoritative (a client command in MP,
-- direct in single-player), so every client agrees on which pumps are running.
--
-- The animation and the LightSwitch sound follow vanilla's ISActivateCarBatteryChargerAction, which is
-- the same gesture on the same kind of machine.

ISTogglePump = ISBaseTimedAction:derive("ISTogglePump")

local Pump = WaterPipes.Pump

function ISTogglePump:isValid()
    if not self.pump or not self.pump:getSquare() then
        return false
    end
    if not Pump.isPump(self.pump) then
        return false
    end
    -- Someone else got there first: the switch is already where we wanted it.
    return Pump.isEnabled(self.pump) ~= self.enable
end

function ISTogglePump:waitToStart()
    self.character:faceThisObject(self.pump)
    return self.character:shouldBeTurning()
end

function ISTogglePump:start()
    self:setActionAnim("Loot")
    self.character:SetVariable("LootPosition", "Low")
end

function ISTogglePump:update()
    self.character:faceThisObject(self.pump)
    self.character:setMetabolicTarget(Metabolics.LightWork)
end

function ISTogglePump:stop()
    ISBaseTimedAction.stop(self)
end

function ISTogglePump:perform()
    local square = self.pump:getSquare()
    if square then
        square:playSound("LightSwitch")
    end

    if isClient() and square then
        sendClientCommand(self.character, "WaterPipes", "setPumpEnabled",
            { x = square:getX(), y = square:getY(), z = square:getZ(), enabled = self.enable })
    else
        Pump.setEnabled(self.pump, self.enable)
    end

    ISBaseTimedAction.perform(self)
end

function ISTogglePump:new(character, pump, enable)
    local o = ISBaseTimedAction.new(self, character)
    o.character = character
    o.pump = pump
    o.enable = enable and true or false
    o.stopOnWalk = true
    o.stopOnRun = true
    o.maxTime = character:isTimedActionInstant() and 1 or 50
    return o
end

return ISTogglePump
