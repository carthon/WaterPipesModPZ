WaterPipes = WaterPipes or {}
WaterPipes.Hydrant = WaterPipes.Hydrant or {}

require "WaterPipes/Invalidate"
require "WaterPipes/Constants"
require "WaterPipes/Mains"
require "WaterPipes/PipeObjectUtils"
require "WaterPipes/State"
require "WaterPipes/World"

local Invalidate = WaterPipes.Invalidate
local Constants = WaterPipes.Constants
local Mains = WaterPipes.Mains
local PipeObjectUtils = WaterPipes.PipeObjectUtils
local State = WaterPipes.State
local World = WaterPipes.World
local Hydrant = WaterPipes.Hydrant

-- A fire hydrant is a plain vanilla street object (Mov_FireHydrant) with no water of its own. This
-- module gives it one: opened with a pipe wrench it feeds the pipe network laid on its tile, mains-fed
-- and bottomless while the town service runs, and holding only a fixed local reserve once it is cut.
-- The identity, the open flag and the reserve live here; the injection pass lives in WaterPipeSystem.

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

    -- An open, mains-fed hydrant is a pressure floor the network walk records as it passes, so a
    -- cached walk still reflects the old valve position. Resolved off the WaterPipes table:
    -- NetworkAccess requires this module, so requiring it back would be a recursive require.
    local NetworkAccess = WaterPipes.NetworkAccess
    Invalidate.flowPathChanged()
end

-- Client: the server opened or closed a hydrant. Written here too, since the modData may arrive after this.
function Hydrant.onServerCommand(module, command, args)
    if module ~= "WaterPipes" or command ~= "hydrantOpenChanged" or not args then
        return
    end
    local square = World.squareAt(args.x, args.y, args.z)
    local modData = getModData(square and Hydrant.findOnSquare(square))
    if modData then
        modData[Constants.HYDRANT_OPEN_KEY] = args.open == true
    end
    Invalidate.flowPathChanged()
end

if Events and Events.OnServerCommand then
    Events.OnServerCommand.Add(Hydrant.onServerCommand)
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
-- holding some reserve. A cut hydrant whose reserve has run dry is open but gives nothing.
function Hydrant.isFlowing(hydrant)
    if not Hydrant.isOpen(hydrant) then
        return false
    end
    return Hydrant.isMainsFed() or Hydrant.reserve(hydrant) > 0
end

-- A pipe on its tile takes the flow: a connected hydrant spills nothing.
function Hydrant.isConnected(square)
    return square ~= nil and PipeObjectUtils.getPipeOnSquare(square) ~= nil
end

-- Flowing onto the street: open, with water, and no pipe on its tile. Drives the gush, its sound and
-- the wetting.
function Hydrant.isGushing(hydrant)
    if not Hydrant.isFlowing(hydrant) then
        return false
    end
    return not Hydrant.isConnected(hydrant.getSquare and hydrant:getSquare() or nil)
end

-- An OPEN hydrant connected to a network feeds it what it can take and keeps the rest in the main.
-- One with no pipe on its tile gushes at its flow rate onto the street: the water is lost and waters
-- the hydrant's 3x3. While the town service runs its reserve is held full; once the water is cut, what
-- leaves comes out of the fixed reserve.
-- ===== The per-tick step =====
-- Moved here from WaterPipeSystem. Which hydrants run comes off the open-hydrant registry in
-- the tick; what an open one does with a minute is this.
function Hydrant.step(hydrant, square, dt)
    -- Resolved off the WaterPipes table rather than required: NetworkAccess requires this
    -- module, and Irrigation requires NetworkAccess, so either require would close a cycle.
    local NetworkAccess = WaterPipes.NetworkAccess
    local Irrigation = WaterPipes.Irrigation
    if not NetworkAccess or (dt or 0) <= 0 then
        return
    end

    local mainsFed = Hydrant.isMainsFed()
    if mainsFed then
        Hydrant.setReserve(hydrant, Hydrant.capacity())   -- topped while the main has water
    end

    local reserve = Hydrant.reserve(hydrant)
    local flow = mainsFed and Hydrant.flowFor(dt) or math.min(Hydrant.flowFor(dt), reserve)
    if flow <= 0 then
        return
    end

    if Hydrant.isConnected(square) then
        local added = NetworkAccess.fillFluidAtSquare(square, "Water", flow) or 0
        if not mainsFed and added > 0 then
            Hydrant.setReserve(hydrant, reserve - added)
        end
        return
    end

    if not mainsFed then
        Hydrant.setReserve(hydrant, reserve - flow)
    end
    -- The gush waters the hydrant's own 3x3 like a sprinkler.
    if Irrigation then
        Irrigation.waterHydrantSurroundings(square, dt / 60)
    end
end

return Hydrant
