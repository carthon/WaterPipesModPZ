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

-- The body matches the shape the pipe under it is drawn in. PipeAutotile is read off the WaterPipes
-- table, not required: its requires lead back to this module.
local function wantedSprite(worldObject, open)
    local square = worldObject and worldObject.getSquare and worldObject:getSquare() or nil
    local autotile = WaterPipes.PipeAutotile
    local shape = nil
    if square and autotile and autotile.floorShapeAt then
        shape = autotile.floorShapeAt(square:getX(), square:getY(), square:getZ())
    end
    local pair = shape and Constants.VALVE_SPRITES[shape] or nil
    if pair then
        return open and pair.open or pair.closed
    end
    return open and Constants.VALVE_SPRITE_OPEN or Constants.VALVE_SPRITE_CLOSED
end

function Valve.spriteFor(worldObject)
    return wantedSprite(worldObject, Valve.isOpen(worldObject))
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
-- PipeObjectUtils' scan memo already knows the tiles with no valve, so those cost nothing. Read off the
-- table: it is not required here. A valve it missed reads as open, which a new valve is.
function Valve.isClosedOnSquare(square)
    local Utils = WaterPipes.PipeObjectUtils
    if Utils and Utils.squareHasNoValve and Utils.squareHasNoValve(square) then
        return false
    end
    local valve = Valve.findOnSquare(square)
    return valve ~= nil and not Valve.isOpen(valve)
end

-- Put the open/closed sprite on the valve, and NOTHING else. A sprite set on the server does not
-- travel with the modData, so each side draws its own from the state that does -- see
-- Valve.reconcileOnSquare.
--
-- What is deliberately not here is transmitCompleteItemToClients. Sending the whole object to a client
-- that already has this one ADDS a second copy instead of replacing it: two valves on the tile, an
-- open handle drawn over a closed one, and a menu that reads whichever comes first in the object list.
-- That copy never hears about a flip again, so the valve could be closed and never reopened.
-- Valves already warned about, by object: the sweep redraws every few seconds.
local warnedSprite = {}

function Valve.applySprite(worldObject, open)
    local spriteName = wantedSprite(worldObject, open)
    local sprite = getSprite and getSprite(spriteName) or nil
    if not sprite or not worldObject or not worldObject.setSprite then
        local key = tostring(worldObject)
        if not warnedSprite[key] then
            warnedSprite[key] = true
            Logger.warn("Valve sprite " .. tostring(spriteName) .. " did not resolve -- the valve is "
                .. (open and "open" or "CLOSED") .. " but will not look it. Restart the game fully: "
                .. "tilesets load only at boot, so a pack added this session is not there yet.")
        end
        return
    end
    pcall(worldObject.setSprite, worldObject, sprite)

    -- The dismantle cursor finds its object by sprite name: a repaint under it must drop its cache.
    local autotile = WaterPipes.PipeAutotile
    if autotile and autotile.invalidateMoveableCursorCache then
        autotile.invalidateMoveableCursorCache()
    end
end

local function spriteNameOf(worldObject)
    if not worldObject or not worldObject.getSpriteName then
        return nil
    end
    local ok, name = pcall(worldObject.getSpriteName, worldObject)
    return ok and name or nil
end

-- Optimistic local flip, for the side that asked. The state is written here so the menu agrees with
-- the handle at once; the owner's modData follows and confirms it. Nothing is sent from here.
function Valve.setLocalState(worldObject, open)
    local modData = getModData(worldObject)
    if modData then
        modData[Constants.VALVE_CLOSED_KEY] = (not open) and true or nil
    end
    Valve.applySprite(worldObject, open)
    -- This side's walks and head field were priced on the old state.
    local square = worldObject and worldObject.getSquare and worldObject:getSquare() or nil
    if square then
        Invalidate.squareChanged(square)
    end
end

-- Every valve on the tile drawn the way its own state says. This is how a flip made elsewhere reaches
-- a client: the modData replicates, the sprite does not, so it is derived where it is drawn.
-- Returns how many it had to correct.
function Valve.reconcileOnSquare(square)
    if not square or not square.getObjects then
        return 0
    end
    local ok, objects = pcall(square.getObjects, square)
    if not ok or not objects then
        return 0
    end

    local corrected, found = 0, 0
    for i = 0, objects:size() - 1 do
        local worldObject = objects:get(i)
        if Valve.isValve(worldObject) then
            found = found + 1
            local open = Valve.isOpen(worldObject)
            local wanted = wantedSprite(worldObject, open)
            if spriteNameOf(worldObject) ~= wanted then
                Valve.applySprite(worldObject, open)
                corrected = corrected + 1
            end
        end
    end

    -- One tile, one valve. More than one means a copy was put there rather than the original updated,
    -- and the menu would be reading whichever the object list happens to hand over first.
    if found > 1 then
        Logger.warn(string.format("%d valves on the tile at %d:%d:%d -- only one of them can be the "
            .. "real one. Reconnecting rebuilds the tile from the server.",
            found, square:getX(), square:getY(), square:getZ()))
    end

    -- A redrawn handle is a state this side's caches never heard of; so is a valve the scan memo
    -- missed (its modData arrived after the object did).
    local Utils = WaterPipes.PipeObjectUtils
    if corrected > 0 or (found > 0 and Utils and Utils.squareHasNoValve
        and Utils.squareHasNoValve(square, true)) then
        Invalidate.squareChanged(square)
    end
    return corrected
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
        -- see. scanContainersAroundPipes re-derives it at the next ten-minute scan, but say so.
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
