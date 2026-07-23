WaterPipes = WaterPipes or {}
WaterPipes.Hydrant = WaterPipes.Hydrant or {}

require "WaterPipes/Constants"
require "WaterPipes/Mains"
require "WaterPipes/State"

local Constants = WaterPipes.Constants
local Mains = WaterPipes.Mains
local State = WaterPipes.State
local Hydrant = WaterPipes.Hydrant

-- A fire hydrant is a plain vanilla street object (the Mov_FireHydrant decoration) with no water of
-- its own -- its tiledef is empty. This module gives it one: opened with a pipe wrench it feeds the
-- pipe network laid on its tile, mains-fed and bottomless while the town service runs, and holding
-- only a fixed local reserve once the water is cut. See the hydrant block in Constants.lua.
--
-- The identity, the open/closed flag and the reserve live here; the injection pass that actually
-- moves water lives in WaterPipeSystem, next to the pump and mains passes it mirrors.

local function getModData(worldObject)
    if not worldObject or not worldObject.getModData then
        return nil
    end
    local ok, modData = pcall(worldObject.getModData, worldObject)
    return ok and modData or nil
end

local function spriteName(worldObject)
    if not worldObject or not worldObject.getSprite then
        return nil
    end
    local ok, sprite = pcall(worldObject.getSprite, worldObject)
    if not ok or not sprite or not sprite.getName then
        return nil
    end
    local okName, name = pcall(sprite.getName, sprite)
    return okName and name or nil
end

function Hydrant.isHydrant(worldObject)
    return spriteName(worldObject) == Constants.HYDRANT_SPRITE
end

function Hydrant.findOnSquare(square)
    if not square or not square.getObjects then
        return nil
    end
    local ok, objects = pcall(square.getObjects, square)
    if not ok or not objects then
        return nil
    end
    for i = 0, objects:size() - 1 do
        local worldObject = objects:get(i)
        if Hydrant.isHydrant(worldObject) then
            return worldObject
        end
    end
    return nil
end

-- ===== Open / closed =====

function Hydrant.isOpen(worldObject)
    local modData = getModData(worldObject)
    return modData and modData[Constants.HYDRANT_OPEN_KEY] == true or false
end

function Hydrant.setOpen(worldObject, open)
    local modData = getModData(worldObject)
    if not modData then
        return
    end
    modData[Constants.HYDRANT_OPEN_KEY] = open and true or false
    if worldObject.transmitModData then
        pcall(worldObject.transmitModData, worldObject)
    end

    -- Keep the open-hydrant registry in step. Every toggle path runs through here (the server command
    -- handler and the single-player direct call both land on setOpen), so this one spot is enough.
    local square = worldObject.getSquare and worldObject:getSquare() or nil
    if square then
        State.setHydrantOpen(square:getX(), square:getY(), square:getZ(), open and true or false)
    end
end

-- ===== Reserve =====

-- Litres a cut-off hydrant still holds in its local main. Sandbox-tunable; 0 leaves a hydrant with no
-- reserve at all, so it runs dry the instant the town service stops.
function Hydrant.capacity()
    local sv = SandboxVars and SandboxVars.WaterPipes
    local v = sv and sv.HydrantReserve
    if type(v) == "number" then
        return math.max(v, 0)
    end
    return Constants.HYDRANT_RESERVE
end

-- Reserve remaining. A hydrant that has never been touched reads as full.
function Hydrant.reserve(worldObject)
    local modData = getModData(worldObject)
    local v = modData and modData[Constants.HYDRANT_RESERVE_KEY]
    if type(v) == "number" then
        return math.max(v, 0)
    end
    return Hydrant.capacity()
end

function Hydrant.setReserve(worldObject, litres)
    local modData = getModData(worldObject)
    if not modData then
        return
    end
    modData[Constants.HYDRANT_RESERVE_KEY] = math.max(litres or 0, 0)
    if worldObject.transmitModData then
        pcall(worldObject.transmitModData, worldObject)
    end
end

-- ===== Supply =====

-- Mains-fed while the town service runs: the reserve is held topped, so the hydrant is effectively
-- bottomless until the shutoff, then it is exactly full and drains from there.
function Hydrant.isMainsFed()
    return Mains.serviceLive()
end

-- Pressure an open, mains-fed hydrant holds its network at. A hydrant is a high-flow tap on the town
-- main, so it runs higher than a household supply (Mains.head). Real hydrants sit around 3-4 bar;
-- stored in tenths so an integer sandbox slider can say 40.0.
function Hydrant.head()
    local sv = SandboxVars and SandboxVars.WaterPipes
    local v = sv and sv.HydrantHead
    if type(v) == "number" then
        return math.max(v, 0) / 10
    end
    return Constants.HYDRANT_HEAD
end

-- Does this hydrant put pressure into the network right now? Only while OPEN and still mains-fed --
-- the pressure is the town main's, so once the water is cut an open hydrant still yields its reserve
-- but with no pressure behind it, exactly as a real standpipe would drain by gravity.
function Hydrant.pressureActive(hydrant)
    return Hydrant.isOpen(hydrant) and Hydrant.isMainsFed()
end

-- Litres an open hydrant may deliver in `dt` in-game minutes.
function Hydrant.flowFor(dt)
    return math.max(Constants.HYDRANT_FLOW_RATE, 0) * math.max(dt or 0, 0)
end

-- Is water actually coming out right now? Open, and with something to give -- mains-fed, or still
-- holding some reserve. A cut hydrant whose reserve has run dry is open but silent. Drives the sound.
function Hydrant.isFlowing(hydrant)
    if not Hydrant.isOpen(hydrant) then
        return false
    end
    return Hydrant.isMainsFed() or Hydrant.reserve(hydrant) > 0
end

return Hydrant
