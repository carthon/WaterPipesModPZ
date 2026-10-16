-- The client's half of the humidity sensor: what the server says back, the LED drawn from the state the
-- modData carries, and the "Open sensor" option.

require "ISUI/ISWorldObjectContextMenu"
require "WaterPipes/Signals"
require "WaterPipes/World"
require "WaterPipes/WaterPipesSensorWindow"
require "WaterPipes/WaterPipesSignalLinkCursor"
require "WaterPipes/ISOpenHumiditySensor"

WaterPipes = WaterPipes or {}

local Signals = WaterPipes.Signals
local World = WaterPipes.World

-- ===== What the server says =====

local handlers = Signals.clientHandlers

function handlers.sensorState(args)
    local square = World.squareAt(args.x, args.y, args.z)
    local sensor = square and Signals.findSensorOnSquare(square, true) or nil
    if sensor then
        sensor:getModData()[Signals.SENSOR_STATE_KEY] = args.state
        Signals.applySensorSprite(sensor)
    end
end

function handlers.sensorChanged(args)
    WaterPipesSensorWindow.onSensorChanged(args)
end

function handlers.snapshot(args)
    WaterPipesSensorWindow.onSnapshot(args)
end

function handlers.refused(args)
    local playerObj = getPlayer()
    local reason = args and args.reason
    if playerObj and HaloTextHelper and reason then
        HaloTextHelper.addBadText(playerObj, getText("IGUI_WaterPipesSignalRefused_" .. tostring(reason)))
    end
end

local function onServerCommand(module, command, args)
    if module ~= Signals.MODULE then
        return
    end
    local handler = handlers[command]
    if handler then
        handler(args or {})
    end
end

-- ===== The LED =====
-- Sprites do not travel with the object, so a client draws the LED from the state in modData. Deferred
-- a tick after a load or an add: the objects arrive before their modData does.

local pending = {}
local MAX_WAIT_TICKS = 120

local function queue(square)
    pending[#pending + 1] = { x = square:getX(), y = square:getY(), z = square:getZ(), ticks = 0 }
end

local function onLoadGridsquare(square)
    local specials = square and square:getSpecialObjects()
    for i = 0, (specials and specials:size() or 0) - 1 do
        if Signals.hasSensorSprite(specials:get(i)) then
            queue(square)
            return
        end
    end
end

local function onObjectAdded(object)
    if Signals.hasSensorSprite(object) and object:getSquare() then
        queue(object:getSquare())
    end
end

local function onTick()
    if #pending == 0 then
        return
    end
    local list = pending
    pending = {}
    for _, entry in ipairs(list) do
        local square = World.squareAt(entry.x, entry.y, entry.z)
        local sensor = square and Signals.findSensorOnSquare(square) or nil
        if sensor then
            Signals.applySensorSprite(sensor)
        elseif square and entry.ticks < MAX_WAIT_TICKS and Signals.findSensorOnSquare(square, true) then
            entry.ticks = entry.ticks + 1
            pending[#pending + 1] = entry
        end
    end
end

-- ===== Opening it =====

local function openSensor(playerObj, sensor)
    if luautils.walkAdjObject(playerObj, sensor, true) then
        ISTimedActionQueue.add(ISOpenHumiditySensor:new(playerObj, sensor))
    end
end

local function findSensor(worldobjects)
    for _, object in ipairs(worldobjects or {}) do
        if Signals.isSensor(object) then
            return object
        end
    end
    for _, object in ipairs(worldobjects or {}) do
        local square = object and object.getSquare and object:getSquare() or nil
        local sensor = square and Signals.findSensorOnSquare(square) or nil
        if sensor then
            return sensor
        end
    end
    return nil
end

local function onFillWorldObjectContextMenu(player, context, worldobjects, test)
    local playerObj = getSpecificPlayer(player)
    if not playerObj or playerObj:getVehicle() then
        return
    end
    local sensor = findSensor(worldobjects)
    if not sensor then
        return
    end
    if test then
        return ISWorldObjectContextMenu.setTest()
    end
    local name = Signals.sensorName(sensor)
    local label = getText("ContextMenu_WaterPipesOpenSensor")
    context:addOption(name and (label .. " (" .. name .. ")") or label, playerObj, openSensor, sensor)
end

if Events then
    Events.OnServerCommand.Add(onServerCommand)
    Events.LoadGridsquare.Add(onLoadGridsquare)
    Events.OnObjectAdded.Add(onObjectAdded)
    Events.OnTick.Add(onTick)
    Events.OnFillWorldObjectContextMenu.Add(onFillWorldObjectContextMenu)
end
