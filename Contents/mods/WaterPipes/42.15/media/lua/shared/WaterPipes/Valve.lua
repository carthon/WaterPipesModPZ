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

-- An inline shut-off valve: a NON-pipe device built onto a tile that already carries a floor pipe,
-- the same way the pressure gauge is (see Build.gaugeOnIsValid). It is not the pipe, which is what
-- lets it be fitted to a run that already exists without dismantling anything.
--
-- Open, it does nothing at all. Closed, its square stops conducting: every topology walk treats it as
-- a wall, so the network genuinely splits and the two sides stop sharing pressure, level, stagnation
-- and contamination. Unlike a router it has no crossing behaviour -- a closed valve is a hard stop in
-- both directions, and an open one is invisible.

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

    if worldObject.setSprite and getSprite then
        local sprite = getSprite(Valve.spriteFor(worldObject))
        if sprite then
            pcall(worldObject.setSprite, worldObject, sprite)
        end
    end

    local square = worldObject.getSquare and worldObject:getSquare() or nil
    if square then
        -- State.rebuildGraph decides where a network ENDS from the registry, not from the world, so the
        -- flag has to be there before the rebuild runs -- exactly as `metadata.router` does.
        State.setPipeValveClosed(square:getX(), square:getY(), square:getZ(), not open)
        Logger.log(string.format("Valve at %d:%d:%d is now %s",
            square:getX(), square:getY(), square:getZ(), open and "open" or "closed"))
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
