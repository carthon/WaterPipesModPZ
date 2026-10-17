-- The signal bus: the server's half of WaterPipes.Signals. Every ten minutes it reads each loaded sensor,
-- then sets every linked valve to `switch AND (no sensors OR any sensor active)`. It also owns the
-- commands the sensor window sends (link, configure, battery) and the clean-up when a sensor or a valve
-- is taken down.
--
-- lua/server runs on MP clients too: everything that changes the world returns early there.

require "WaterPipes/Signals"
require "WaterPipes/Valve"
require "WaterPipes/Logger"
require "WaterPipes/World"

WaterPipes = WaterPipes or {}
WaterPipes.SignalBus = WaterPipes.SignalBus or {}

local Bus = WaterPipes.SignalBus
local Signals = WaterPipes.Signals
local Valve = WaterPipes.Valve
local Logger = WaterPipes.Logger
local World = WaterPipes.World

local STEP_HOURS = Signals.STEP_MINUTES / 60

local function authoritative()
    return not (isClient and isClient())
end

local function coordsOf(object)
    local square = object and object.getSquare and object:getSquare() or nil
    if not square then
        return nil
    end
    return square:getX(), square:getY(), square:getZ()
end

local function transmit(object)
    if object and object.transmitModData then
        object:transmitModData()
    end
end

-- ===== Registry entries =====

local function emitterEntry(registry, x, y, z, create)
    local key = Signals.key(x, y, z)
    local entry = registry.emitters[key]
    if not entry and create then
        entry = { x = x, y = y, z = z, kind = "humidity", links = {}, active = false }
        registry.emitters[key] = entry
    end
    return entry, key
end

local function anySensorActive(registry, receiver)
    for sensorKey in pairs(receiver.sensors) do
        local emitter = registry.emitters[sensorKey]
        if emitter and emitter.active then
            return true
        end
    end
    return false
end

function Bus.effectiveFor(registry, receiver)
    if receiver.switchOn == false then
        return false
    end
    if Signals.isEmpty(receiver.sensors) then
        return true
    end
    return anySensorActive(registry, receiver)
end

local function findValveAt(x, y, z)
    local square = World.squareAt(x, y, z)
    return square and Valve.findOnSquare(square) or nil, square
end

-- Write what the client draws from onto the valve: its switch, its name and how many sensors drive it.
local function stampValve(valve, receiver)
    local modData = Signals.modDataOf(valve)
    if not modData then
        return
    end
    if receiver then
        modData[Signals.VALVE_SWITCH_KEY] = receiver.switchOn == false and "off" or "on"
        modData[Signals.VALVE_LINKS_KEY] = Signals.count(receiver.sensors)
        modData[Signals.VALVE_NAME_KEY] = receiver.name
    else
        modData[Signals.VALVE_SWITCH_KEY] = nil
        modData[Signals.VALVE_LINKS_KEY] = nil
    end
    transmit(valve)
end

-- Valves decided while their tile was away: a linked one (`pending`) or one released then (`stale` with its
-- switch). The registry already splits the network there, and the valve itself is turned the moment its
-- tile loads. Counted lazily; nil = count again.
local pendingCount = nil

local function countPending(registry)
    local n = 0
    for _, receiver in pairs(registry.receivers) do
        if receiver.pending then
            n = n + 1
        end
    end
    for key, entry in pairs(registry.stale) do
        if entry.on ~= nil and not registry.receivers[key] then
            n = n + 1
        end
    end
    return n
end

-- What the bus decided for a valve whose tile was away, or nil. The container scan asks it, so a rebuild
-- that runs before the valve is turned does not read the old state back.
function Bus.pendingValveOpen(x, y, z)
    if pendingCount == 0 then
        return nil
    end
    local registry = Signals.registry()
    if pendingCount == nil then
        pendingCount = countPending(registry)
        if pendingCount == 0 then
            return nil
        end
    end
    local key = Signals.key(x, y, z)
    local receiver = registry.receivers[key]
    if receiver then
        if receiver.pending then
            return receiver.applied
        end
        return nil
    end
    local entry = registry.stale[key]
    if entry and entry.on ~= nil then
        return entry.on
    end
    return nil
end

-- Put one valve where its switch and sensors say.
function Bus.applyReceiver(registry, receiver)
    local want = Bus.effectiveFor(registry, receiver)
    local valve, square = findValveAt(receiver.x, receiver.y, receiver.z)
    if valve then
        Signals.ValveReceiver:new(valve):apply(want)
        receiver.applied = want
        if receiver.pending then
            receiver.pending = nil
            pendingCount = nil
        end
    elseif not square and receiver.applied ~= want then
        if Signals.ValveReceiver.applyAt(receiver.x, receiver.y, receiver.z, want) then
            receiver.applied = want
            receiver.pending = true
            pendingCount = nil
        end
    end
end

-- A valve no sensor drives any more goes back to its own switch.
local function releaseReceiver(registry, receiverKey)
    local receiver = registry.receivers[receiverKey]
    if not receiver then
        return
    end
    registry.receivers[receiverKey] = nil
    pendingCount = nil
    local valve, square = findValveAt(receiver.x, receiver.y, receiver.z)
    local on = receiver.switchOn ~= false
    if valve then
        stampValve(valve, nil)
        Signals.ValveReceiver:new(valve):apply(on)
    elseif not square then
        Signals.ValveReceiver.applyAt(receiver.x, receiver.y, receiver.z, on)
        -- its modData still says what the sensor last made it: the switch rides along for when it loads
        registry.stale[receiverKey] = { x = receiver.x, y = receiver.y, z = receiver.z, on = on }
    elseif Signals.squareMayHoldValve(square) then
        -- loaded, but the valve did not answer: settled by clearStale once it does
        registry.stale[receiverKey] = { x = receiver.x, y = receiver.y, z = receiver.z, on = on }
    end
end

local function unlink(registry, sensorKey, receiverKey)
    local emitter = registry.emitters[sensorKey]
    local receiver = registry.receivers[receiverKey]
    if emitter then
        emitter.links[receiverKey] = nil
    end
    if not receiver then
        return
    end
    receiver.sensors[sensorKey] = nil
    if Signals.isEmpty(receiver.sensors) then
        releaseReceiver(registry, receiverKey)
        return
    end
    local valve = findValveAt(receiver.x, receiver.y, receiver.z)
    if valve then
        stampValve(valve, receiver)
    end
    Bus.applyReceiver(registry, receiver)
end

local function dropEmitter(registry, sensorKey)
    local emitter = registry.emitters[sensorKey]
    if not emitter then
        return
    end
    local linked = {}
    for receiverKey in pairs(emitter.links) do
        linked[#linked + 1] = receiverKey
    end
    for _, receiverKey in ipairs(linked) do
        unlink(registry, sensorKey, receiverKey)
    end
    registry.emitters[sensorKey] = nil
    Logger.log("Humidity sensor removed at " .. sensorKey)
end

local function dropReceiver(registry, receiverKey)
    local receiver = registry.receivers[receiverKey]
    if not receiver then
        return
    end
    for sensorKey in pairs(receiver.sensors) do
        local emitter = registry.emitters[sensorKey]
        if emitter then
            emitter.links[receiverKey] = nil
        end
    end
    registry.receivers[receiverKey] = nil
    pendingCount = nil
end

-- ===== Reading sensors =====

-- Battery percent each sensor last sent to the clients, by tile.
local sentPercent = {}

local function writeResult(sensor, result)
    local modData = Signals.modDataOf(sensor)
    local before = modData[Signals.SENSOR_STATE_KEY]
    local changed = before ~= result.state
        or modData[Signals.SENSOR_REASON_KEY] ~= result.reason
        or modData[Signals.SENSOR_READING_KEY] ~= result.reading
        or modData[Signals.SENSOR_SOURCE_KEY] ~= result.source
        or (result.reading ~= nil and modData[Signals.SENSOR_EDGE_KEY] ~= result.edge)
    modData[Signals.SENSOR_STATE_KEY] = result.state
    modData[Signals.SENSOR_REASON_KEY] = result.reason
    modData[Signals.SENSOR_READING_KEY] = result.reading
    modData[Signals.SENSOR_SOURCE_KEY] = result.source
    -- kept through a power cut or an empty tile: only a reading moves it
    if result.reading ~= nil then
        modData[Signals.SENSOR_EDGE_KEY] = result.edge
    end
    -- the charge creeps down every step; clients only need it to the percent
    local charge = Signals.batteryCharge(sensor)
    local percent = charge and math.floor(charge * 100) or -1
    local key = Signals.key(coordsOf(sensor))
    if sentPercent[key] ~= percent then
        sentPercent[key] = percent
        changed = true
    end
    if changed then
        transmit(sensor)
    end
    Signals.applySensorSprite(sensor)
    if before ~= result.state then
        local x, y, z = coordsOf(sensor)
        Signals.notifyClients("sensorState", { x = x, y = y, z = z, state = result.state })
    end
end

-- Read one sensor now and record its signal. `dtHours` is battery time to spend (0 for a look).
function Bus.evaluateSensor(sensor, dtHours)
    local result = Signals.HumiditySensor:new(sensor):evaluate(dtHours or 0)
    if not result then
        return nil
    end
    writeResult(sensor, result)
    local x, y, z = coordsOf(sensor)
    local registry = Signals.registry()
    local emitter = emitterEntry(registry, x, y, z, true)
    emitter.active = result.active
    return result
end

local function applyLinkedReceivers(registry, emitter)
    for receiverKey in pairs(emitter.links) do
        local receiver = registry.receivers[receiverKey]
        if receiver then
            Bus.applyReceiver(registry, receiver)
        end
    end
end

-- Read a sensor and act on its valves at once: after a build, a change in the window or a battery.
local function refreshSensor(sensor)
    Bus.evaluateSensor(sensor, 0)
    local registry = Signals.registry()
    local emitter = emitterEntry(registry, coordsOf(sensor))
    if emitter then
        Valve.batch(applyLinkedReceivers, registry, emitter)
    end
end

-- Sensors built before they were on a square (OnCreate can run first): retried for a few ticks.
local unplaced = {}
local UNPLACED_TICKS = 60

local function registerPlaced(sensor)
    local x, y, z = coordsOf(sensor)
    if not x then
        return false
    end
    emitterEntry(Signals.registry(), x, y, z, true)
    Logger.log("Humidity sensor built at " .. Signals.key(x, y, z))
    refreshSensor(sensor)
    return true
end

local function retryUnplaced()
    local still = {}
    for _, entry in ipairs(unplaced) do
        entry.ticks = entry.ticks + 1
        if not registerPlaced(entry.sensor) and entry.ticks < UNPLACED_TICKS then
            still[#still + 1] = entry
        end
    end
    unplaced = still
    if #unplaced == 0 and Events and Events.OnTick then
        Events.OnTick.Remove(retryUnplaced)
    end
end

function Bus.sensorBuilt(sensor)
    if not authoritative() or not sensor then
        return
    end
    if registerPlaced(sensor) then
        return
    end
    if #unplaced == 0 and Events and Events.OnTick then
        Events.OnTick.Add(retryUnplaced)
    end
    unplaced[#unplaced + 1] = { sensor = sensor, ticks = 0 }
end

-- Exposed for tools/conservation.
Bus.retryUnplaced = retryUnplaced

-- Valves released while their chunk was away still carry their link marks; clear them once loaded.
-- A loaded tile whose valve never answers is given up after STALE_STEPS steps.
local STALE_STEPS = 6

-- One released valve whose tile is loaded: its marks cleared and its switch applied. True when settled.
local function settleStale(registry, key, entry, square)
    local valve = Valve.findOnSquare(square)
    if valve and not registry.receivers[key] then
        local on = entry.on
        if on == nil then
            on = Signals.valveSwitchOn(valve)   -- read before the marks go
        end
        stampValve(valve, nil)
        Signals.ValveReceiver:new(valve):apply(on)
    end
    return valve ~= nil or not Signals.squareMayHoldValve(square)
end

local function clearStale(registry)
    local done = {}
    for key, entry in pairs(registry.stale) do
        local square = World.squareAt(entry.x, entry.y, entry.z)
        if square then
            entry.steps = (entry.steps or 0) + 1
            if settleStale(registry, key, entry, square) or entry.steps > STALE_STEPS then
                done[#done + 1] = key
            end
        end
    end
    for _, key in ipairs(done) do
        registry.stale[key] = nil
    end
    if #done > 0 then
        pendingCount = nil
    end
end

local function tickNow(dtHours)
    local registry = Signals.registry()
    local gone = {}
    -- a snapshot: reading a sensor may add its own entry, and the table must not grow while it is walked
    local emitters = {}
    for sensorKey, emitter in pairs(registry.emitters) do
        emitters[#emitters + 1] = { key = sensorKey, entry = emitter }
    end
    for _, item in ipairs(emitters) do
        local sensorKey, emitter = item.key, item.entry
        local square = World.squareAt(emitter.x, emitter.y, emitter.z)
        if square then
            local sensor = Signals.findSensorOnSquare(square)
            if sensor then
                Bus.evaluateSensor(sensor, dtHours)
            elseif not Signals.findSensorOnSquare(square, true) then
                gone[#gone + 1] = sensorKey
            end
            -- a sensor whose modData has not arrived keeps its last signal this round
        end
        -- unloaded: frozen on its last signal
    end
    for _, sensorKey in ipairs(gone) do
        dropEmitter(registry, sensorKey)
    end

    local missing = {}
    for receiverKey, receiver in pairs(registry.receivers) do
        local square = World.squareAt(receiver.x, receiver.y, receiver.z)
        if square and not Signals.squareMayHoldValve(square) then
            missing[#missing + 1] = receiverKey
        else
            Bus.applyReceiver(registry, receiver)
        end
    end
    for _, receiverKey in ipairs(missing) do
        dropReceiver(registry, receiverKey)
    end
    clearStale(registry)
end

-- Every valve the step turns rebuilds the network once, together.
function Bus.tick(dtHours)
    if not authoritative() then
        return
    end
    Valve.batch(tickNow, dtHours)
end

-- ===== Tiles coming back =====
-- A pending valve is turned the tick after its tile loads, when its objects are all there.

local loadedPending = {}

local function onLoadGridsquare(square)
    if pendingCount == 0 or not square or not authoritative() then
        return
    end
    local x, y, z = square:getX(), square:getY(), square:getZ()
    if Bus.pendingValveOpen(x, y, z) ~= nil then
        loadedPending[#loadedPending + 1] = Signals.key(x, y, z)
    end
end

local function applyLoadedPending()
    local list = loadedPending
    loadedPending = {}
    local registry = Signals.registry()
    for _, key in ipairs(list) do
        local receiver = registry.receivers[key]
        local entry = registry.stale[key]
        if receiver and receiver.pending then
            Bus.applyReceiver(registry, receiver)
        elseif not receiver and entry then
            local square = World.squareAt(entry.x, entry.y, entry.z)
            if square and settleStale(registry, key, entry, square) then
                registry.stale[key] = nil
                pendingCount = nil
            end
        end
    end
end

local function onTickPending()
    if #loadedPending > 0 then
        Valve.batch(applyLoadedPending)
    end
end

-- Exposed for tools/conservation.
Bus.onLoadGridsquare = onLoadGridsquare
Bus.applyLoadedPending = onTickPending

-- ===== Permissions =====

-- A tile inside a safehouse belongs to its members (Signals.mayTouch, shared with the link cursor).
function Bus.mayTouch(player, square)
    return Signals.mayTouch(player, square)
end

local function near(player, x, y, reach)
    if not player or not player.getX then
        return true
    end
    return math.abs(player:getX() - x) <= reach + 1 and math.abs(player:getY() - y) <= reach + 1
end

-- The sensor a request names, or nil and why not.
local function sensorFor(player, args)
    if type(args) ~= "table" then
        return nil, "noSensor"
    end
    local square = World.squareAt(args.x, args.y, args.z)
    local sensor = square and Signals.findSensorOnSquare(square) or nil
    if not sensor or not near(player, args.x, args.y, Signals.CONFIG_REACH) then
        return nil, "noSensor"
    end
    if not Bus.mayTouch(player, square) then
        return nil, "sensorSafehouse"
    end
    return sensor, square
end

local function refuse(player, reason)
    Signals.notifyPlayer(player, "refused", { reason = reason })
end

-- Refused at the sensor itself: the client closes that sensor's window too.
local function refuseSensor(player, args, reason)
    Signals.notifyPlayer(player, "refused", { reason = reason, x = args.x, y = args.y, z = args.z, sensor = true })
end

-- ===== What the window shows =====

function Bus.snapshot(sensor)
    local x, y, z = coordsOf(sensor)
    local registry = Signals.registry()
    local emitter = emitterEntry(registry, x, y, z, false)
    local links = {}
    for receiverKey in pairs(emitter and emitter.links or {}) do
        local receiver = registry.receivers[receiverKey]
        if receiver then
            local valve = findValveAt(receiver.x, receiver.y, receiver.z)
            local open = receiver.applied
            if valve then
                open = Valve.isOpen(valve)
            end
            links[#links + 1] = {
                x = receiver.x, y = receiver.y, z = receiver.z,
                name = receiver.name,
                open = open,
                switchOn = receiver.switchOn ~= false,
                loaded = valve ~= nil,
            }
        end
    end
    table.sort(links, function(a, b)
        return (a.name or "~") < (b.name or "~")
    end)
    local lo, hi, invert = Signals.sensorRange(sensor)
    return {
        x = x, y = y, z = z, links = links,
        name = Signals.sensorName(sensor), min = lo, max = hi, invert = invert == true,
    }
end

-- ===== Commands =====

local handlers = {}

function handlers.snapshot(player, args)
    local sensor, why = sensorFor(player, args)
    if not sensor then
        refuseSensor(player, args, why)
        return
    end
    refreshSensor(sensor)
    Signals.notifyPlayer(player, "snapshot", Bus.snapshot(sensor))
end

function handlers.configure(player, args)
    local sensor, why = sensorFor(player, args)
    if not sensor then
        refuseSensor(player, args, why)
        return
    end
    local modData = Signals.modDataOf(sensor)
    local lo = math.max(0, math.min(100, math.floor(tonumber(args.min) or Signals.DEFAULT_MIN)))
    local hi = math.max(0, math.min(100, math.floor(tonumber(args.max) or Signals.DEFAULT_MAX)))
    if lo > hi then
        lo, hi = hi, lo
    end
    modData[Signals.SENSOR_MIN_KEY] = lo
    modData[Signals.SENSOR_MAX_KEY] = hi
    modData[Signals.SENSOR_INVERT_KEY] = args.invert == true
    modData[Signals.SENSOR_NAME_KEY] = Signals.cleanName(args.name)
    transmit(sensor)
    refreshSensor(sensor)
    Signals.notifyClients("sensorChanged", { x = args.x, y = args.y, z = args.z })
    Signals.notifyPlayer(player, "snapshot", Bus.snapshot(sensor))
end

-- The battery comes out of the player's inventory with its charge.
local function findBattery(inventory, itemId)
    if not inventory then
        return nil
    end
    local item = nil
    if itemId and inventory.getItemById then
        item = inventory:getItemById(itemId)
    end
    if not item and itemId and inventory.getItemWithIDRecursiv then
        item = inventory:getItemWithIDRecursiv(itemId)
    end
    if not item and inventory.getFirstTypeRecurse then
        item = inventory:getFirstTypeRecurse(Signals.BATTERY_ITEM)
    end
    if item and item:getFullType() == Signals.BATTERY_ITEM then
        return item
    end
    return nil
end

function handlers.insertBattery(player, args)
    local sensor, why = sensorFor(player, args)
    if not sensor then
        refuseSensor(player, args, why)
        return
    end
    if Signals.batteryCharge(sensor) ~= nil then
        return
    end
    local inventory = player and player.getInventory and player:getInventory() or nil
    local item = findBattery(inventory, args.itemId)
    if not item then
        refuse(player, "noBattery")
        return
    end
    local charge = item.getCurrentUsesFloat and item:getCurrentUsesFloat() or 1
    local container = item:getContainer() or inventory
    if sendRemoveItemFromContainer then
        sendRemoveItemFromContainer(container, item)
    end
    container:Remove(item)
    Signals.modDataOf(sensor)[Signals.SENSOR_BATTERY_KEY] = math.max(0, math.min(1, charge))
    transmit(sensor)
    refreshSensor(sensor)
    Signals.notifyClients("sensorChanged", { x = args.x, y = args.y, z = args.z })
    Signals.notifyPlayer(player, "snapshot", Bus.snapshot(sensor))
end

function handlers.removeBattery(player, args)
    local sensor, why = sensorFor(player, args)
    if not sensor then
        refuseSensor(player, args, why)
        return
    end
    local charge = Signals.batteryCharge(sensor)
    if not charge then
        return
    end
    local inventory = player and player.getInventory and player:getInventory() or nil
    if not inventory then
        return
    end
    Bus.giveItem(player, sensor:getSquare(), Bus.batteryItem(charge))
    Signals.modDataOf(sensor)[Signals.SENSOR_BATTERY_KEY] = nil
    transmit(sensor)
    refreshSensor(sensor)
    Signals.notifyClients("sensorChanged", { x = args.x, y = args.y, z = args.z })
    Signals.notifyPlayer(player, "snapshot", Bus.snapshot(sensor))
end

local function isTile(x, y, z)
    return type(x) == "number" and type(y) == "number" and type(z) == "number"
end

function handlers.link(player, args)
    if not isTile(args.vx, args.vy, args.vz) then
        return
    end
    local sensor, why = sensorFor(player, args)
    if not sensor then
        refuseSensor(player, args, why)
        return
    end
    local valve, valveSquare = findValveAt(args.vx, args.vy, args.vz)
    if not valve then
        refuse(player, "noValve")
        return
    end
    -- the cursor only offers valves around the player; a request for one further off is not from it
    if not near(player, args.vx, args.vy, Signals.LINK_REACH) then
        refuse(player, "outOfRange")
        return
    end
    local range = Signals.linkRange()
    if range > 0 and (math.abs(args.vx - args.x) > range or math.abs(args.vy - args.y) > range) then
        refuse(player, "outOfRange")
        return
    end
    if not Bus.mayTouch(player, valveSquare) then
        refuse(player, "safehouse")
        return
    end

    -- what it reads now, not what it read at the last step
    Bus.evaluateSensor(sensor, 0)
    local registry = Signals.registry()
    local emitter, sensorKey = emitterEntry(registry, args.x, args.y, args.z, true)
    local receiverKey = Signals.key(args.vx, args.vy, args.vz)
    local receiver = registry.receivers[receiverKey]
    if not receiver then
        receiver = {
            x = args.vx, y = args.vy, z = args.vz, kind = "valve", sensors = {},
            switchOn = Signals.valveSwitchOn(valve), name = Signals.valveName(valve),
        }
        registry.receivers[receiverKey] = receiver
        registry.stale[receiverKey] = nil
        pendingCount = nil
    end
    receiver.name = Signals.cleanName(args.name) or receiver.name
    receiver.sensors[sensorKey] = true
    emitter.links[receiverKey] = true
    stampValve(valve, receiver)
    Bus.applyReceiver(registry, receiver)
    Logger.log(string.format("Valve %s linked to humidity sensor %s", receiverKey, sensorKey))
    Signals.notifyClients("sensorChanged", { x = args.x, y = args.y, z = args.z })
    Signals.notifyPlayer(player, "snapshot", Bus.snapshot(sensor))
end

function handlers.unlink(player, args)
    if not isTile(args.vx, args.vy, args.vz) then
        return
    end
    local sensor, why = sensorFor(player, args)
    if not sensor then
        refuseSensor(player, args, why)
        return
    end
    local receiverKey = Signals.key(args.vx, args.vy, args.vz)
    local _, valveSquare = findValveAt(args.vx, args.vy, args.vz)
    if valveSquare and not Bus.mayTouch(player, valveSquare) then
        refuse(player, "safehouse")
        return
    end
    unlink(Signals.registry(), Signals.key(args.x, args.y, args.z), receiverKey)
    Signals.notifyClients("sensorChanged", { x = args.x, y = args.y, z = args.z })
    Signals.notifyPlayer(player, "snapshot", Bus.snapshot(sensor))
end

-- Tiles a client names are whole numbers or the request is dropped: every registry key is built from them.
local COORD_FIELDS = { "x", "y", "z", "vx", "vy", "vz" }

local function normalizeCoords(args)
    for _, name in ipairs(COORD_FIELDS) do
        local v = args[name]
        if v ~= nil then
            if type(v) ~= "number" or v ~= v or math.abs(v) > 1000000 then
                return false
            end
            args[name] = math.floor(v)
        end
    end
    return true
end

function Bus.handle(command, player, args)
    if not authoritative() then
        return
    end
    local handler = handlers[command]
    if not handler then
        return
    end
    args = type(args) == "table" and args or {}
    if normalizeCoords(args) then
        handler(player, args)
    end
end

-- A hand on a valve. A linked valve only moves its switch and lets the sensors decide; an unlinked
-- one opens or closes as it always did.
function Bus.setValveSwitch(valve, on)
    local x, y, z = coordsOf(valve)
    local registry = Signals.registry()
    local receiver = x and registry.receivers[Signals.key(x, y, z)] or nil
    if not receiver then
        local modData = Signals.modDataOf(valve)
        if modData and modData[Signals.VALVE_SWITCH_KEY] ~= nil then
            modData[Signals.VALVE_SWITCH_KEY] = nil
            modData[Signals.VALVE_LINKS_KEY] = nil
        end
        Valve.setOpen(valve, on)
        return
    end
    receiver.switchOn = on and true or false
    stampValve(valve, receiver)
    Bus.applyReceiver(registry, receiver)
end

-- ===== Removal =====
-- Confirmed a tick later, as WaterPipeSystem does for pipes: the event fires before the object leaves,
-- and a cancelled dismantle raises it too. How a sensor left (dismantled, destroyed, picked up) and by
-- whom is told beforehand by the action that removes it (SignalsMoveables.lua); a removal nobody
-- announced pays out as a dismantle with the battery on the floor, as it always did.

local pending = {}
local pendingScheduled = false
local removers = {}     -- sensor object -> { mode = "scrap" | "destroy" | "move", player = ..., at = ms }
local REMOVER_TTL_MS = 10000

local function nowMs()
    return getTimestampMs and getTimestampMs() or nil
end

-- A note whose object never left (the action stopped after its hook) is forgotten after a while.
local function pruneRemovers()
    local now = nowMs()
    if not now then
        return
    end
    local old = nil
    for object, note in pairs(removers) do
        if note.at and now - note.at > REMOVER_TTL_MS then
            old = old or {}
            old[#old + 1] = object
        end
    end
    for _, object in ipairs(old or {}) do
        removers[object] = nil
    end
end

function Bus.noteRemover(object, mode, player)
    if authoritative() and object then
        pruneRemovers()
        removers[object] = { mode = mode, player = player, at = nowMs() }
    end
end

local function stillOnSquare(square, object)
    if not square then
        return false
    end
    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do
        if objects:get(i) == object then
            return true
        end
    end
    return false
end

-- The battery as an item carrying its charge, made before anyone is told about it.
function Bus.batteryItem(charge)
    local item = instanceItem and instanceItem(Signals.BATTERY_ITEM) or nil
    if item and item.setCurrentUsesFloat then
        item:setCurrentUsesFloat(math.max(0, math.min(1, charge or 0)))
    end
    return item
end

-- Into the player's inventory when there is one with room, else onto the tile; synced either way.
function Bus.giveItem(player, square, item)
    if not item then
        return
    end
    local inventory = player and player.getInventory and player:getInventory() or nil
    if inventory and (not inventory.hasRoomFor or inventory:hasRoomFor(player, item)) then
        inventory:AddItem(item)
        if sendAddItemToContainer then
            sendAddItemToContainer(inventory, item)
        end
        return
    end
    if square then
        square:AddWorldInventoryItem(item, 0.5, 0.5, 0.0)
    end
end

local function payOut(square, entry)
    if entry.mode == "scrap" then
        for _, part in ipairs(Signals.DISMANTLE_RETURNS) do
            for _ = 1, part.count or 1 do
                if ZombRand(100) < (part.chance or 100) then
                    Bus.giveItem(entry.player, square, instanceItem and instanceItem(part.itemType) or nil)
                end
            end
        end
    end
    -- dismantled or destroyed, the battery comes back with its charge; a move handed it over already
    if entry.battery and entry.mode ~= "move" then
        Bus.giveItem(entry.player, square, Bus.batteryItem(entry.battery))
    end
end

local function settleRemovals(list)
    local registry = Signals.registry()
    for _, entry in pairs(list) do
        local square = World.squareAt(entry.x, entry.y, entry.z)
        if square and not stillOnSquare(square, entry.object) then
            local key = Signals.key(entry.x, entry.y, entry.z)
            if entry.sensor then
                dropEmitter(registry, key)
                payOut(square, entry)
            else
                dropReceiver(registry, key)
            end
        end
        removers[entry.object] = nil
    end
end

local function processPending()
    pendingScheduled = false
    if Events and Events.OnTick then
        Events.OnTick.Remove(processPending)
    end
    local list = pending
    pending = {}
    Valve.batch(settleRemovals, list)
end

local function noteRemoval(object, mode, player)
    if not authoritative() or not object then
        return
    end
    local sensor = Signals.isSensor(object) or Signals.hasSensorSprite(object)
    if not sensor and not Valve.isValve(object) then
        return
    end
    local x, y, z = coordsOf(object)
    if not x then
        return
    end
    -- a valve and a sensor can share a tile and go in the same tick
    local key = Signals.key(x, y, z) .. (sensor and "#sensor" or "#valve")
    local told = removers[object]
    mode = (told and told.mode) or mode
    player = (told and told.player) or player
    local existing = pending[key]
    if existing then
        -- a sledgehammer raises both events: destroyed wins
        if mode == "destroy" or existing.mode == "destroy" then
            existing.mode = "destroy"
        end
        existing.player = existing.player or player
        return
    end
    pending[key] = {
        x = x, y = y, z = z, object = object, sensor = sensor, mode = mode, player = player,
        battery = sensor and Signals.batteryCharge(object) or nil,
    }
    if not pendingScheduled and Events and Events.OnTick then
        pendingScheduled = true
        Events.OnTick.Add(processPending)
    end
end

-- Exposed for tools/conservation.
Bus.processPendingRemovals = processPending
Bus.noteRemoval = noteRemoval

-- ===== Events =====

local minutes = 0

local function onTenMinutes()
    minutes = minutes + 10
    if minutes < Signals.STEP_MINUTES then
        return
    end
    minutes = 0
    Bus.tick(STEP_HOURS)
end

local function onClientCommand(module, command, player, args)
    if module ~= Signals.MODULE then
        return
    end
    Bus.handle(command, player, args)
end

if Events then
    if Events.EveryTenMinutes then
        Events.EveryTenMinutes.Add(onTenMinutes)
    end
    if Events.OnClientCommand then
        Events.OnClientCommand.Add(onClientCommand)
    end
    if Events.OnObjectAboutToBeRemoved then
        Events.OnObjectAboutToBeRemoved.Add(function(object) noteRemoval(object, "scrap") end)
    end
    if Events.OnDestroyIsoThumpable then
        Events.OnDestroyIsoThumpable.Add(function(object, player) noteRemoval(object, "destroy", player) end)
    end
    if Events.LoadGridsquare then
        Events.LoadGridsquare.Add(onLoadGridsquare)
    end
    if Events.OnTick then
        Events.OnTick.Add(onTickPending)
    end
end

return Bus
