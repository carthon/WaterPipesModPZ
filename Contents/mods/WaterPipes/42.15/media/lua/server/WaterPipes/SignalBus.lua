-- The signal bus: the server's half of WaterPipes.Signals. Every ten minutes it reads each loaded sensor,
-- then sets every linked receiver to `switch AND (no sensors OR any sensor active)`. It also owns the
-- commands the sensor window sends (link, configure, battery) and the clean-up when a sensor or a
-- receiver is taken down. Receivers are reached only through their class (Signals.SignalReceiver).
--
-- lua/server runs on MP clients too: everything that changes the world returns early there.

require "WaterPipes/Signals"
require "WaterPipes/Logger"
require "WaterPipes/World"

WaterPipes = WaterPipes or {}
WaterPipes.SignalBus = WaterPipes.SignalBus or {}

local Bus = WaterPipes.SignalBus
local Signals = WaterPipes.Signals
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
        entry = { x = x, y = y, z = z, kind = Signals.DEFAULT_EMITTER, links = {}, active = false }
        registry.emitters[key] = entry
    end
    return entry, key
end

local function anySensorActive(registry, record)
    for sensorKey in pairs(record.sensors) do
        local emitter = registry.emitters[sensorKey]
        if emitter and emitter.active then
            return true
        end
    end
    return false
end

-- Registry records are plain tables: { x, y, z, kind, sensors, switchOn, name, applied, pending }.
function Bus.effectiveFor(registry, record)
    if record.switchOn == false then
        return false
    end
    if Signals.isEmpty(record.sensors) then
        return true
    end
    return anySensorActive(registry, record)
end

-- The receiver a record names, wrapped, or nil; with its square when loaded, and its class.
local function receiverOf(record)
    return Signals.receiverAt(record.kind, record.x, record.y, record.z)
end

-- Receivers decided while their tile was away: a linked one (`pending`) or one released then (`stale`
-- with its switch). Its class already acted on what it could (applyUnloaded), and the receiver itself
-- is switched the tick after its tile loads. Counted lazily; nil = count again.
local pendingCount = nil

local function countPending(registry)
    local n = 0
    for _, record in pairs(registry.receivers) do
        if record.pending then
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

-- What the bus decided for a receiver whose tile was away, or nil. The water network's container scan
-- asks it for valves, so a rebuild that runs before the valve is turned does not read the old state back.
function Bus.pendingState(kind, x, y, z)
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
    local key = Signals.receiverKey(kind, x, y, z)
    local record = registry.receivers[key]
    if record then
        if record.pending then
            return record.applied
        end
        return nil
    end
    local entry = registry.stale[key]
    if entry and entry.on ~= nil then
        return entry.on
    end
    return nil
end

-- Tell one receiver what its switch and sensors say.
function Bus.applyReceiver(registry, record)
    local want = Bus.effectiveFor(registry, record)
    local receiver, square, class = receiverOf(record)
    if receiver then
        receiver:onSignal(want)
        record.applied = want
        if record.pending then
            record.pending = nil
            pendingCount = nil
        end
    elseif not square and class and record.applied ~= want then
        if class:applyUnloaded(record.x, record.y, record.z, want) then
            record.applied = want
            record.pending = true
            pendingCount = nil
        end
    end
end

-- A receiver no sensor drives any more goes back to its own switch.
local function releaseReceiver(registry, receiverKey)
    local record = registry.receivers[receiverKey]
    if not record then
        return
    end
    registry.receivers[receiverKey] = nil
    pendingCount = nil
    local receiver, square, class = receiverOf(record)
    local on = record.switchOn ~= false
    local stale = { x = record.x, y = record.y, z = record.z, kind = record.kind, on = on }
    if receiver then
        receiver:mark(nil)
        receiver:onSignal(on)
    elseif not square then
        if class then
            class:applyUnloaded(record.x, record.y, record.z, on)
        end
        -- its modData still says what the sensor last made it: the switch rides along for when it loads
        registry.stale[receiverKey] = stale
    elseif class and class:mayStandOn(square) then
        -- loaded, but the receiver did not answer: settled by clearStale once it does
        registry.stale[receiverKey] = stale
    end
end

local function unlink(registry, sensorKey, receiverKey)
    local emitter = registry.emitters[sensorKey]
    local record = registry.receivers[receiverKey]
    if emitter then
        emitter.links[receiverKey] = nil
    end
    if not record then
        return
    end
    record.sensors[sensorKey] = nil
    if Signals.isEmpty(record.sensors) then
        releaseReceiver(registry, receiverKey)
        return
    end
    local receiver = receiverOf(record)
    if receiver then
        receiver:mark(record)
    end
    Bus.applyReceiver(registry, record)
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
    Logger.log("Sensor removed at " .. sensorKey)
end

local function dropReceiver(registry, receiverKey)
    local record = registry.receivers[receiverKey]
    if not record then
        return
    end
    for sensorKey in pairs(record.sensors) do
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
    local x, y, z = coordsOf(sensor)
    local registry = Signals.registry()
    local known = x and emitterEntry(registry, x, y, z, false) or nil
    local class = Signals.emitterClass(known and known.kind)
    local result = class and class:new(sensor):evaluate(dtHours or 0) or nil
    if not result then
        return nil
    end
    writeResult(sensor, result)
    local emitter = emitterEntry(registry, x, y, z, true)
    emitter.active = result.active
    return result
end

local function applyLinkedReceivers(registry, emitter)
    for receiverKey in pairs(emitter.links) do
        local record = registry.receivers[receiverKey]
        if record then
            Bus.applyReceiver(registry, record)
        end
    end
end

-- Read a sensor and act on its receivers at once: after a build, a change in the window or a battery.
local function refreshSensor(sensor)
    Bus.evaluateSensor(sensor, 0)
    local registry = Signals.registry()
    local emitter = emitterEntry(registry, coordsOf(sensor))
    if emitter then
        Signals.batchReceivers(applyLinkedReceivers, registry, emitter)
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

-- Receivers released while their chunk was away still carry their link marks; clear them once loaded.
-- A loaded tile whose receiver never answers is given up after STALE_STEPS steps.
local STALE_STEPS = 6

-- One released receiver whose tile is loaded: its marks cleared and its switch applied. True when settled.
local function settleStale(registry, key, entry, square)
    local class = Signals.receiverClass(entry.kind)
    local object = class and class:findOnSquare(square) or nil
    if object and not registry.receivers[key] then
        local receiver = class:new(object)
        local on = entry.on
        if on == nil then
            on = receiver:isSwitchOn()   -- read before the marks go
        end
        receiver:mark(nil)
        receiver:onSignal(on)
    end
    return object ~= nil or (class ~= nil and not class:mayStandOn(square))
end

local function clearStale(registry)
    local done = {}
    for key, entry in pairs(registry.stale) do
        local square = World.squareAt(entry.x, entry.y, entry.z)
        -- a kind nobody registered (its mod is off) waits, as its records do
        if square and Signals.receiverClass(entry.kind) then
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
    for receiverKey, record in pairs(registry.receivers) do
        local class = Signals.receiverClass(record.kind)
        local square = World.squareAt(record.x, record.y, record.z)
        if class and square and not class:mayStandOn(square) then
            missing[#missing + 1] = receiverKey
        elseif class then
            Bus.applyReceiver(registry, record)
        end
        -- a kind nobody registered (its mod is off): left as it was
    end
    for _, receiverKey in ipairs(missing) do
        dropReceiver(registry, receiverKey)
    end
    clearStale(registry)
end

-- Whatever the step switches is settled once, together (one network rebuild for all its valves).
function Bus.tick(dtHours)
    if not authoritative() then
        return
    end
    Signals.batchReceivers(tickNow, dtHours)
end

-- ===== Tiles coming back =====
-- A pending receiver is switched the tick after its tile loads, when its objects are all there.

local loadedPending = {}

local function onLoadGridsquare(square)
    if pendingCount == 0 or not square or not authoritative() then
        return
    end
    local x, y, z = square:getX(), square:getY(), square:getZ()
    for _, class in ipairs(Signals.receiverClasses()) do
        if Bus.pendingState(class.kind, x, y, z) ~= nil then
            loadedPending[#loadedPending + 1] = Signals.receiverKey(class.kind, x, y, z)
        end
    end
end

local function applyLoadedPending()
    local list = loadedPending
    loadedPending = {}
    local registry = Signals.registry()
    for _, key in ipairs(list) do
        local record = registry.receivers[key]
        local entry = registry.stale[key]
        if record and record.pending then
            Bus.applyReceiver(registry, record)
        elseif not record and entry then
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
        Signals.batchReceivers(applyLoadedPending)
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
        local record = registry.receivers[receiverKey]
        if record then
            local receiver = receiverOf(record)
            local on = record.applied
            if receiver then
                on = receiver:isOn()
            end
            links[#links + 1] = {
                x = record.x, y = record.y, z = record.z, kind = record.kind or Signals.DEFAULT_RECEIVER,
                name = record.name,
                on = on,
                switchOn = record.switchOn ~= false,
                loaded = receiver ~= nil,
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

-- The receiver class a request names; none named = the default kind.
local function requestedClass(args)
    if args.kind ~= nil and type(args.kind) ~= "string" then
        return nil
    end
    return Signals.receiverClass(args.kind)
end

function handlers.link(player, args)
    local class = requestedClass(args)
    if not class or not isTile(args.vx, args.vy, args.vz) then
        return
    end
    local sensor, why = sensorFor(player, args)
    if not sensor then
        refuseSensor(player, args, why)
        return
    end
    local receiver, receiverSquare = Signals.receiverAt(class.kind, args.vx, args.vy, args.vz)
    if not receiver then
        refuse(player, class.MISSING_REASON)
        return
    end
    -- the cursor only offers receivers around the player; a request for one further off is not from it
    if not near(player, args.vx, args.vy, Signals.LINK_REACH) then
        refuse(player, "outOfRange")
        return
    end
    local range = Signals.linkRange()
    if range > 0 and (math.abs(args.vx - args.x) > range or math.abs(args.vy - args.y) > range) then
        refuse(player, "outOfRange")
        return
    end
    if not Bus.mayTouch(player, receiverSquare) then
        refuse(player, "safehouse")
        return
    end

    -- what it reads now, not what it read at the last step
    Bus.evaluateSensor(sensor, 0)
    local registry = Signals.registry()
    local emitter, sensorKey = emitterEntry(registry, args.x, args.y, args.z, true)
    local receiverKey = Signals.receiverKey(class.kind, args.vx, args.vy, args.vz)
    local record = registry.receivers[receiverKey]
    if not record then
        record = {
            x = args.vx, y = args.vy, z = args.vz, kind = class.kind, sensors = {},
            switchOn = receiver:isSwitchOn(), name = receiver:savedName(),
        }
        registry.receivers[receiverKey] = record
        registry.stale[receiverKey] = nil
        pendingCount = nil
    end
    record.name = Signals.cleanName(args.name) or record.name
    record.sensors[sensorKey] = true
    emitter.links[receiverKey] = true
    receiver:mark(record)
    Bus.applyReceiver(registry, record)
    Logger.log(string.format("Receiver %s linked to sensor %s", receiverKey, sensorKey))
    Signals.notifyClients("sensorChanged", { x = args.x, y = args.y, z = args.z })
    Signals.notifyPlayer(player, "snapshot", Bus.snapshot(sensor))
end

-- Unlinking only needs the key: a link to a kind whose mod is gone can still be taken off the sensor.
function handlers.unlink(player, args)
    if (args.kind ~= nil and type(args.kind) ~= "string") or not isTile(args.vx, args.vy, args.vz) then
        return
    end
    local sensor, why = sensorFor(player, args)
    if not sensor then
        refuseSensor(player, args, why)
        return
    end
    local receiverKey = Signals.receiverKey(args.kind, args.vx, args.vy, args.vz)
    local receiverSquare = World.squareAt(args.vx, args.vy, args.vz)
    if receiverSquare and not Bus.mayTouch(player, receiverSquare) then
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

-- A hand on a receiver (wrapped). A linked one only moves its switch and lets the sensors decide; an
-- unlinked one is switched as it always was.
function Bus.setReceiverSwitch(receiver, on)
    local x, y, z = coordsOf(receiver.object)
    local registry = Signals.registry()
    local record = x and registry.receivers[Signals.receiverKey(receiver.kind, x, y, z)] or nil
    if not record then
        if receiver:hasSwitchMark() then
            receiver:mark(nil, true)   -- sent with the switch below
        end
        receiver:turnByHand(on)
        return
    end
    record.switchOn = on and true or false
    receiver:mark(record)
    Bus.applyReceiver(registry, record)
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
            if entry.sensor then
                dropEmitter(registry, Signals.key(entry.x, entry.y, entry.z))
                payOut(square, entry)
            else
                dropReceiver(registry, Signals.receiverKey(entry.kind, entry.x, entry.y, entry.z))
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
    Signals.batchReceivers(settleRemovals, list)
end

local function noteRemoval(object, mode, player)
    if not authoritative() or not object then
        return
    end
    local sensor = Signals.isSensor(object) or Signals.hasSensorSprite(object)
    local class = not sensor and Signals.receiverClassOf(object) or nil
    if not sensor and not class then
        return
    end
    local x, y, z = coordsOf(object)
    if not x then
        return
    end
    -- a receiver and a sensor can share a tile and go in the same tick
    local key = Signals.key(x, y, z) .. "#" .. (sensor and "sensor" or class.kind)
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
        x = x, y = y, z = z, object = object, sensor = sensor, kind = class and class.kind or nil,
        mode = mode, player = player,
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
