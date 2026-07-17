require "TimedActions/ISBaseTimedAction"
require "WaterPipes/Constants"
require "WaterPipes/Irrigation"

-- Repairs a drip emitter that overpressure blew out: consumes the repair kit from the character's
-- inventory and restores it to full. Same shape as ISRepairWaterPurifier -- world state is mutated
-- authoritatively on the server via a client command, the inventory is spent on the acting client.

ISRepairWaterDrip = ISBaseTimedAction:derive("ISRepairWaterDrip")

local Constants = WaterPipes.Constants
local Irrigation = WaterPipes.Irrigation

function ISRepairWaterDrip.hasRepairKit(inventory)
    if not inventory then
        return false
    end
    for _, entry in ipairs(Constants.DRIP_REPAIR_ITEMS) do
        if inventory:getCountTypeRecurse(entry.type) < (entry.count or 1) then
            return false
        end
    end
    return true
end

local function consumeRepairKit(inventory)
    for _, entry in ipairs(Constants.DRIP_REPAIR_ITEMS) do
        for _ = 1, (entry.count or 1) do
            local item = inventory:getFirstTypeRecurse(entry.type)
            if not item then
                return false
            end
            local container = item:getContainer() or inventory
            container:DoRemoveItem(item)
        end
    end
    return true
end

function ISRepairWaterDrip:isValid()
    if not self.drip or not self.drip:getSquare() then
        return false
    end
    if not Irrigation.isDrip(self.drip) then
        return false
    end
    if self.wrench and not self.character:isEquipped(self.wrench) then
        return false
    end
    return ISRepairWaterDrip.hasRepairKit(self.character:getInventory())
end

function ISRepairWaterDrip:update()
    self.character:faceThisObject(self.drip)
    self.character:setMetabolicTarget(Metabolics.LightWork)
end

function ISRepairWaterDrip:start()
    self:setActionAnim("VehicleWorkOnMid")
    self.sound = self.character:playSound("RepairWithWrench")
end

function ISRepairWaterDrip:stop()
    self.character:stopOrTriggerSound(self.sound)
    ISBaseTimedAction.stop(self)
end

function ISRepairWaterDrip:perform()
    self.character:stopOrTriggerSound(self.sound)

    local inventory = self.character:getInventory()
    if consumeRepairKit(inventory) then
        local square = self.drip:getSquare()
        if isClient() and square then
            sendClientCommand(self.character, "WaterPipes", "repairDrip",
                { x = square:getX(), y = square:getY(), z = square:getZ() })
        else
            Irrigation.repairDrip(self.drip)
        end
    end

    ISBaseTimedAction.perform(self)
end

function ISRepairWaterDrip:new(character, drip, wrench)
    local o = ISBaseTimedAction.new(self, character)
    o.character = character
    o.drip = drip
    o.wrench = wrench
    o.stopOnWalk = true
    o.stopOnRun = true
    o.maxTime = character:isTimedActionInstant() and 1 or Constants.DRIP_REPAIR_TIME
    return o
end

return ISRepairWaterDrip
