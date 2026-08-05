require "TimedActions/ISBaseTimedAction"
require "WaterPipes/Constants"
require "WaterPipes/Purifier"

-- Repairs a purifier's worn filter: consumes the repair kit (charcoal + RippedSheets) from the
-- character's inventory and restores the filter condition to full. World state (the condition modData)
-- is mutated authoritatively on the server via a client command, mirroring the plumb timed actions;
-- the inventory consumption happens locally on the acting client.

ISRepairWaterPurifier = ISBaseTimedAction:derive("ISRepairWaterPurifier")

local Constants = WaterPipes.Constants
local Purifier = WaterPipes.Purifier

-- Inventory type queries below use the FULL type ("Base.RippedSheets"), matching the mod's proven
-- containsTypeRecurse("Base.PipeWrench") usage (PZ's *TypeRecurse helpers match full or short type).

-- Counting and taking both live in Constants, so this and the drip repair cannot drift apart: an
-- entry may list interchangeable types (the two charcoals) and name a tag, and both paths have to
-- agree on what counts or the tooltip ends up promising something the action cannot deliver.

-- Does the inventory hold the full repair kit?
function ISRepairWaterPurifier.hasRepairKit(inventory)
    if not inventory then
        return false
    end
    for _, entry in ipairs(Constants.PURIFIER_REPAIR_ITEMS) do
        if Constants.countRepairItems(inventory, entry) < (entry.count or 1) then
            return false
        end
    end
    return true
end

local function consumeRepairKit(inventory)
    for _, entry in ipairs(Constants.PURIFIER_REPAIR_ITEMS) do
        for _ = 1, (entry.count or 1) do
            local item = Constants.takeRepairItem(inventory, entry)
            if not item then
                return false
            end
            local container = item:getContainer() or inventory
            container:DoRemoveItem(item)
        end
    end
    return true
end

function ISRepairWaterPurifier:isValid()
    if not self.purifier or not self.purifier:getSquare() then
        return false
    end
    if not Purifier.isPurifier(self.purifier) then
        return false
    end
    if self.wrench and not self.character:isEquipped(self.wrench) then
        return false
    end
    return ISRepairWaterPurifier.hasRepairKit(self.character:getInventory())
end

function ISRepairWaterPurifier:update()
    self.character:faceThisObject(self.purifier)
    self.character:setMetabolicTarget(Metabolics.MediumWork)
end

function ISRepairWaterPurifier:start()
    self:setActionAnim("VehicleWorkOnMid")
    self.sound = self.character:playSound("RepairWithWrench")
end

function ISRepairWaterPurifier:stop()
    self.character:stopOrTriggerSound(self.sound)
    ISBaseTimedAction.stop(self)
end

function ISRepairWaterPurifier:perform()
    self.character:stopOrTriggerSound(self.sound)

    local inventory = self.character:getInventory()
    if consumeRepairKit(inventory) then
        local square = self.purifier:getSquare()
        if isClient() and square then
            -- MP: mutate the purifier authoritatively on the server so all clients converge.
            sendClientCommand(self.character, "WaterPipes", "repairPurifier",
                { x = square:getX(), y = square:getY(), z = square:getZ() })
        else
            Purifier.repairFilter(self.purifier)
        end
    end

    ISBaseTimedAction.perform(self)
end

function ISRepairWaterPurifier:new(character, purifier, wrench)
    local o = ISBaseTimedAction.new(self, character)
    o.character = character
    o.purifier = purifier
    o.wrench = wrench
    o.stopOnWalk = true
    o.stopOnRun = true
    o.maxTime = character:isTimedActionInstant() and 1 or Constants.PURIFIER_REPAIR_TIME
    return o
end

return ISRepairWaterPurifier
