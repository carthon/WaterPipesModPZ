require "TimedActions/ISBaseTimedAction"
require "WaterPipes/Constants"
require "WaterPipes/BuildingPlumbing"
require "WaterPipes/Logger"

-- Plumbing a whole building: the character works, and the pipes go in as the work proceeds.
--
-- The pass is spread over frames by a MILLISECOND BUDGET rather than a tile count, the same way
-- Irrigation.beginPass is: a count is a proxy for cost and it drifts the moment anything underneath
-- changes. At least one tile is laid per tick so a pass always advances, and after that the clock
-- decides.
--
-- The plan lays tiles ROOT OUTWARD, so an interrupted pass leaves a connected tree rather than
-- islands -- whatever is on the ground when the player walks away actually works.
--
-- Materials are spent per tile as it is laid, not up front: interrupt the pass and you have paid for
-- the pipe that is in the floor and nothing more.

ISPlumbBuilding = ISBaseTimedAction:derive("ISPlumbBuilding")

local Constants = WaterPipes.Constants
local BuildingPlumbing = WaterPipes.BuildingPlumbing
local Logger = WaterPipes.Logger

-- Pipes owed per tile laid. Scaled per-save by WaterPipes.BuildingPlumbCostScale (percent); 100 is one
-- pipe per pipe, exactly what laying them by hand costs, which is what keeps dismantling from turning
-- a plumbed house into a metal-pipe printer.
function ISPlumbBuilding.costPerTile()
    local sv = SandboxVars and SandboxVars.WaterPipes
    local scale = sv and sv.BuildingPlumbCostScale
    if type(scale) ~= "number" then
        scale = 100
    end
    return math.max(scale, 0) / 100
end

function ISPlumbBuilding.pipesFor(tiles)
    return math.ceil((tiles or 0) * ISPlumbBuilding.costPerTile() - 0.000001)
end

function ISPlumbBuilding.countPipes(inventory)
    if not inventory or not inventory.getCountTypeRecurse then
        return 0
    end
    local ok, count = pcall(inventory.getCountTypeRecurse, inventory, Constants.PIPE_ITEM_TYPE)
    return ok and count or 0
end

local function takePipe(inventory)
    if not inventory or not inventory.getFirstTypeRecurse then
        return false
    end
    local ok, item = pcall(inventory.getFirstTypeRecurse, inventory, Constants.PIPE_ITEM_TYPE)
    if not ok or not item then
        return false
    end
    local container = item:getContainer() or inventory
    container:DoRemoveItem(item)
    return true
end

function ISPlumbBuilding:isValid()
    return self.plan ~= nil and #self.plan.placements > 0
end

function ISPlumbBuilding:update()
    self.character:setMetabolicTarget(Metabolics.HeavyWork)

    local budget = Constants.BUILDING_PLUMB_MS_PER_TICK
    local started = getTimestampMs and getTimestampMs() or 0
    local laidThisTick = 0

    while self.next <= #self.plan.placements do
        -- At least one tile a tick, so a pass always advances however expensive one turns out to be.
        if laidThisTick > 0 and getTimestampMs and (getTimestampMs() - started) >= budget then
            break
        end

        local placement = self.plan.placements[self.next]

        -- Pay as we lay. The debt carries the fractional part, so a scale that is not a whole number
        -- of pipes per tile still charges exactly what it should over the run.
        self.debt = self.debt + ISPlumbBuilding.costPerTile()
        while self.debt >= 1 do
            if not takePipe(self.character:getInventory()) then
                self.outOfPipes = true
                break
            end
            self.debt = self.debt - 1
        end
        if self.outOfPipes then
            break
        end

        local object, reason = BuildingPlumbing.place(placement, self.character)
        if object then
            self.laid[#self.laid + 1] = placement
        else
            self.failed = self.failed + 1
            if reason and not self.reportedReasons[reason] then
                self.reportedReasons[reason] = true
                Logger.warn(string.format("Building plumbing could not lay %s at %d:%d:%d (%s)",
                    placement.kind, placement.x, placement.y, placement.z, tostring(reason)))
            end
        end

        self.next = self.next + 1
        laidThisTick = laidThisTick + 1
    end

    if self.outOfPipes or self.next > #self.plan.placements then
        self:forceComplete()
    end
end

function ISPlumbBuilding:getJobDelta()
    local total = #self.plan.placements
    if total == 0 then
        return 1
    end
    return math.min((self.next - 1) / total, 1)
end

function ISPlumbBuilding:start()
    self:setActionAnim("VehicleWorkOnMid")
    self.sound = self.character:playSound("RepairWithWrench")
end

function ISPlumbBuilding:stop()
    self.character:stopOrTriggerSound(self.sound)
    -- Whatever went in is a connected tree, so it is owed the same settling as a completed pass.
    BuildingPlumbing.finish(self.laid, self.character)
    ISBaseTimedAction.stop(self)
end

function ISPlumbBuilding:perform()
    self.character:stopOrTriggerSound(self.sound)
    BuildingPlumbing.finish(self.laid, self.character)
    if self.onFinished then
        self.onFinished(self)
    end
    ISBaseTimedAction.perform(self)
end

function ISPlumbBuilding:new(character, plan, onFinished)
    local o = ISBaseTimedAction.new(self, character)
    o.character = character
    o.plan = plan
    o.onFinished = onFinished
    o.next = 1
    o.laid = {}
    o.debt = 0
    o.failed = 0
    o.outOfPipes = false
    o.reportedReasons = {}
    o.stopOnWalk = true
    o.stopOnRun = true
    -- Long enough to read as real work; the pass itself ends the action the moment the last tile is in,
    -- so this is a ceiling rather than a duration.
    o.maxTime = character:isTimedActionInstant() and 1 or (60 + 6 * #plan.placements)
    return o
end

return ISPlumbBuilding
