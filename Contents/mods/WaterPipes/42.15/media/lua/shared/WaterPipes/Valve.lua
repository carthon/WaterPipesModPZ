WaterPipes = WaterPipes or {}
WaterPipes.Valve = WaterPipes.Valve or {}

require "WaterPipes/Constants"
require "WaterPipes/Invalidate"
require "WaterPipes/State"
require "WaterPipes/Logger"

local Constants = WaterPipes.Constants
local Invalidate = WaterPipes.Invalidate
local State = WaterPipes.State
local Logger = WaterPipes.Logger
local Valve = WaterPipes.Valve

-- An inline shut-off valve: a non-pipe device fitted onto an existing floor pipe. Open, it does nothing.
-- Closed, every topology walk treats its tile as a wall in both directions, so the network splits.

local function getModData(worldObject)
    if not worldObject or not worldObject.getModData then
        return nil
    end
    local ok, modData = pcall(worldObject.getModData, worldObject)
    return ok and modData or nil
end

function Valve.isValve(worldObject)
    local modData = getModData(worldObject)
    return modData and modData[Constants.VALVE_MODDATA_KEY] == true or false
end

-- ABSENT MEANS OPEN. A valve built before this key was written, or one whose modData has not arrived
-- yet in MP, must read as open: a missing key that read as "closed" would cut a base in two.
function Valve.isOpen(worldObject)
    local modData = getModData(worldObject)
    return not (modData and modData[Constants.VALVE_CLOSED_KEY] == true)
end

function Valve.spriteFor(worldObject)
    return Valve.isOpen(worldObject) and Constants.VALVE_SPRITE_OPEN or Constants.VALVE_SPRITE_CLOSED
end

-- The valve is not a pipe, so it is not in getPipeObjectsOnSquare; scan the square's objects, the
-- same way Build.squareHasGauge does.
function Valve.findOnSquare(square)
    if not square or not square.getObjects then
        return nil
    end
    local ok, objects = pcall(square.getObjects, square)
    if not ok or not objects then
        return nil
    end
    for i = 0, objects:size() - 1 do
        local worldObject = objects:get(i)
        if Valve.isValve(worldObject) then
            return worldObject
        end
    end
    return nil
end

function Valve.hasValveOnSquare(square)
    return Valve.findOnSquare(square) ~= nil
end

-- The one predicate every topology walk asks. A square with no valve, or with an open one, conducts.
function Valve.isClosedOnSquare(square)
    local valve = Valve.findOnSquare(square)
    return valve ~= nil and not Valve.isOpen(valve)
end

-- Put the open/closed sprite on the valve. Split out because BOTH ends need it: the server, which owns
-- the flip, and the client that asked for it -- a sprite set on the server does not travel to clients
-- with the modData, so the valve kept looking the way it did when the client loaded the tile.
function Valve.applySprite(worldObject, open)
    local spriteName = open and Constants.VALVE_SPRITE_OPEN or Constants.VALVE_SPRITE_CLOSED
    local sprite = getSprite and getSprite(spriteName) or nil
    if not sprite or not worldObject or not worldObject.setSprite then
        Logger.warn("Valve sprite " .. tostring(spriteName) .. " did not resolve -- the valve is "
            .. (open and "open" or "CLOSED") .. " but will not look it. Restart the game fully: "
            .. "tilesets load only at boot, so a pack added this session is not there yet.")
        return
    end
    pcall(worldObject.setSprite, worldObject, sprite)
    if worldObject.transmitCompleteItemToClients then
        pcall(worldObject.transmitCompleteItemToClients, worldObject)
    end
end

-- Flip it, authoritatively. Every toggle path lands here (the server command handler and the
-- single-player direct call both do), so this is the only place that has to keep the registry, the
-- sprite and the caches in step.
function Valve.setOpen(worldObject, open)
    local modData = getModData(worldObject)
    if not modData then
        return
    end
    modData[Constants.VALVE_CLOSED_KEY] = (not open) and true or nil
    if worldObject.transmitModData then
        pcall(worldObject.transmitModData, worldObject)
    end

    Valve.applySprite(worldObject, open)


    local square = worldObject.getSquare and worldObject:getSquare() or nil
    if square then
        -- State.rebuildGraph decides where a network ENDS from the registry, not from the world, so the
        -- flag has to be there before the rebuild runs -- exactly as `metadata.router` does.
        local recorded = State.setPipeValveClosed(square:getX(), square:getY(), square:getZ(), not open)
        Logger.log(string.format("Valve at %d:%d:%d is now %s",
            square:getX(), square:getY(), square:getZ(), open and "open" or "closed"))
        -- The registry is what State.rebuildGraph reads to decide where a network ends. If the tile has
        -- no entry the walks would cut while the graph did not, which is a split only half the mod can
        -- see. scanContainersAroundPipes re-derives it within the minute, but say so.
        if not recorded then
            Logger.warn(string.format(
                "Valve at %d:%d:%d has no pipe in the registry: the graph will not agree with the walks "
                .. "until the next container scan re-derives it.",
                square:getX(), square:getY(), square:getZ()))
        end
    end

    -- Closing a valve changes the SHAPE of the network, not just what a walk costs, so this is a
    -- layout change: the graph, the walks and the head field all have to be rebuilt.
    Invalidate.layoutChanged()
    local System = WaterPipes.System
    if System and System.rebuild then
        System.rebuild()
        if System.refreshPlumbedEndpoints then
            System.refreshPlumbedEndpoints()
        end
    end
end

return Valve
