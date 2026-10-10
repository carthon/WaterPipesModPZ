require "TimedActions/ISBaseTimedAction"
require "WaterPipes/Constants"
require "WaterPipes/BuildingPlumbing"
require "WaterPipes/Logger"
require "WaterPipes/SoundOptions"

-- Plumbing a whole building: pipes are laid as the work proceeds, root outward, so an interrupted pass
-- leaves a connected tree. Paced per frame by a millisecond budget, or by time in multiplayer. The pipe
-- is paid for by FIXTURE when the pass opens, and a fixture the pass never reaches is refunded.

ISPlumbBuilding = ISBaseTimedAction:derive("ISPlumbBuilding")

local Constants = WaterPipes.Constants
local BuildingPlumbing = WaterPipes.BuildingPlumbing
local Logger = WaterPipes.Logger

-- Materials are checked again as the work starts, so a pass never begins without the pipe to finish it.
function ISPlumbBuilding:isValidStart()
    local needed = self.plan.pipes or 0
    local held = BuildingPlumbing.countPipes(self.character:getInventory())
    if held < needed then
        if HaloTextHelper and HaloTextHelper.addBadText then
            HaloTextHelper.addBadText(self.character,
                getText("IGUI_WaterPipesPlumbBuildingNeedPipes", tostring(needed), tostring(held)))
        end
        return false
    end
    return true
end

function ISPlumbBuilding:isValid()
    return BuildingPlumbing.hasWork(self.plan)
end

function ISPlumbBuilding:update()
    -- Refused as it started (single player): stopped here rather than from inside start().
    if self.refused then
        if self.forceStop then
            self:forceStop()
        else
            self:stop()
        end
        return
    end
    self.character:setMetabolicTarget(Metabolics.HeavyWork)

    local budget = Constants.BUILDING_PLUMB_MS_PER_TICK
    local started = getTimestampMs and getTimestampMs() or 0
    local laidThisTick = 0
    local remote = isClient and isClient()

    while self.next <= #self.plan.placements do
        -- At least one tile a tick, so a pass always advances however expensive one turns out to be.
        if laidThisTick > 0 and getTimestampMs and (getTimestampMs() - started) >= budget then
            break
        end
        -- Multiplayer: pace the requests in time instead.
        if remote and getTimestampMs then
            local now = getTimestampMs()
            local interval = Constants.BUILDING_PLUMB_REMOTE_INTERVAL_MS
            -- Keep the average rate across frames, but never catch up more than one interval after a stall.
            local due = math.max(self.nextRequestAt or now, now - interval)
            if now < due then
                break
            end
            self.nextRequestAt = due + interval
        end

        local placement = self.plan.placements[self.next]
        local object, reason = BuildingPlumbing.place(placement, self.character)
        if object then
            self.laid[#self.laid + 1] = placement
        elseif reason and not self.reportedReasons[reason] then
            self.reportedReasons[reason] = true
            Logger.warn(string.format("Building plumbing could not lay %s at %d:%d:%d (%s)",
                placement.kind, placement.x, placement.y, placement.z, tostring(reason)))
        end

        self.next = self.next + 1
        laidThisTick = laidThisTick + 1
    end

    if self.next > #self.plan.placements then
        -- Multiplayer: nothing is connected before the server has answered the pass. Settling on a
        -- refusal still on its way connected fixtures and reported a plumbed house.
        if remote and not self.verdict then
            local waited = getTimestampMs and (getTimestampMs() - (self.askedAt or 0)) or 0
            if waited < Constants.BUILDING_PLUMB_VERDICT_TIMEOUT_MS then
                return
            end
            Logger.warn("Building plumbing: no answer from the server about the pass; finishing anyway.")
        end
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

-- The whole price, taken before a tile goes down. The fixtures are named so the server prices the pass
-- itself rather than believing a number the client sent it.
function ISPlumbBuilding:start()
    local fixtures = {}
    for _, fixture in ipairs(self.plan.connected or {}) do
        fixtures[#fixtures + 1] = { x = fixture.x, y = fixture.y, z = fixture.z }
    end
    if isClient and isClient() then
        -- The server answers a refusal with a command; this is the action it lands on.
        ISPlumbBuilding.current = self
        self.askedAt = getTimestampMs and getTimestampMs() or 0
        sendClientCommand(self.character, "WaterPipes", "beginBuildingPlumbing", { fixtures = fixtures })
    else
        local charged, reason = BuildingPlumbing.beginPaidPass({ fixtures = fixtures }, self.character)
        if not charged then
            ISPlumbBuilding.refuse(self, reason, true)
        end
    end

    self:setActionAnim("VehicleWorkOnMid")
    self.sound = WaterPipes.SoundOptions.playOnCharacter(self.character, "RepairWithWrench")
end

-- Settle the network, then connect what the pass reached. In that order, always: plumbing reads the
-- network, and until finish() has rebuilt it the new pipes do not exist as far as a fixture is
-- concerned.
-- ...and the pass closes AFTER the fixtures are connected, because what it refunds is the ones it paid
-- for and never reached.
function ISPlumbBuilding:settle()
    if self.settled then
        return
    end
    self.settled = true
    if ISPlumbBuilding.current == self then
        ISPlumbBuilding.current = nil
    end
    BuildingPlumbing.finish(self.laid, self.character)
    -- A refused pass laid nothing and paid for nothing, so there is nothing to connect.
    if not self.refused then
        self.plumbed = BuildingPlumbing.plumbFixtures(self.plan, self.character, self.laid)
    end
    if isClient and isClient() then
        sendClientCommand(self.character, "WaterPipes", "endBuildingPlumbing", {})
    else
        self.refunded = BuildingPlumbing.endPaidPass(self.character)
    end
end

function ISPlumbBuilding:stop()
    WaterPipes.SoundOptions.stopOnCharacter(self.character, self.sound)
    -- Whatever went in is a connected tree, so it is owed the same settling as a completed pass --
    -- including the fixtures it did reach.
    self:settle()
    ISBaseTimedAction.stop(self)
end

function ISPlumbBuilding:perform()
    WaterPipes.SoundOptions.stopOnCharacter(self.character, self.sound)
    self:settle()
    if self.onFinished then
        self.onFinished(self)
    end
    ISBaseTimedAction.perform(self)
end

-- The pass was refused: say why, connect nothing, stop. `later` leaves the stop to the next update.
function ISPlumbBuilding.refuse(action, reason, later)
    action.refused = reason or "?"
    if HaloTextHelper and HaloTextHelper.addBadText then
        local text = getTextOrNull
            and getTextOrNull("IGUI_WaterPipesPlumbBuildingRefusal_" .. tostring(reason))
            or tostring(reason)
        HaloTextHelper.addBadText(action.character, getText("IGUI_WaterPipesPlumbBuildingRefused", text))
    end
    Logger.warn("Building plumbing: the pass was refused (" .. tostring(reason) .. ")")
    if later then
        return
    end
    if action.forceStop then
        action:forceStop()
    else
        action:stop()
    end
end

-- The server's answer to the pass, or its refusal of one tile. Multiplayer only: the client sent
-- requests and counted them as laid, and this is how it learns otherwise.
function ISPlumbBuilding.onServerRefusal(command, args)
    local action = ISPlumbBuilding.current
    args = type(args) == "table" and args or {}
    if command == "buildingPlumbingAccepted" then
        if action and not action.settled then
            action.verdict = "accepted"
        end
    elseif command == "buildingPlumbingRefused" then
        if action and not action.settled then
            ISPlumbBuilding.refuse(action, args.reason)
        end
    elseif command == "buildingPipeRefused" and action and not action.settled then
        -- Only what was refused: a riser and a floor pipe can share a tile.
        for index = #action.laid, 1, -1 do
            local p = action.laid[index]
            if p.x == args.x and p.y == args.y and p.z == args.z
                and (args.kind == nil or (p.kind == args.kind and p.edge == args.edge)) then
                table.remove(action.laid, index)
            end
        end
    end
end

function ISPlumbBuilding:new(character, plan, onFinished)
    local o = ISBaseTimedAction.new(self, character)
    o.character = character
    o.plan = plan
    o.onFinished = onFinished
    o.next = 1
    o.laid = {}
    o.plumbed = 0
    o.reportedReasons = {}
    o.stopOnWalk = true
    o.stopOnRun = true
    -- No duration: the pass itself ends the action, the moment the last tile is laid or the pipe runs
    -- out. A timer here is a second authority on when the work is done, and it wins -- with instant
    -- actions it ended the pass after ONE tile and reported the whole plan as finished.
    o.maxTime = -1
    return o
end

return ISPlumbBuilding
