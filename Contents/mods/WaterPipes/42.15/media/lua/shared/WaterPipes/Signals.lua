-- Signals: emitters that raise an on/off signal and receivers that act on it. Today one of each: the
-- humidity sensor and the shut-off valve. Kept apart from the water network so it can move to a shared
-- library mod later; the only reach into WaterPipes is the valve adapter (ValveReceiver).
--
-- The server owns every decision (WaterPipes.SignalBus, lua/server). This file holds what both sides
-- read: the keys, the registry, the classes and the helpers the client UI draws from.

require "ISBaseObject"
require "WaterPipes/Logger"
require "WaterPipes/World"
require "WaterPipes/Constants"
require "WaterPipes/Valve"

WaterPipes = WaterPipes or {}
WaterPipes.Signals = WaterPipes.Signals or {}

local Signals = WaterPipes.Signals
local Logger = WaterPipes.Logger
local World = WaterPipes.World
local Constants = WaterPipes.Constants
local Valve = WaterPipes.Valve

-- ===== Keys and defaults =====

Signals.MODULE = "WaterPipesSignals"            -- client/server command module
Signals.REGISTRY_KEY = "WaterPipesSignals"      -- server global mod data

Signals.SENSOR_KEY = "waterpipesSensor"
Signals.SENSOR_NAME_KEY = "waterpipesSensorName"
Signals.SENSOR_MIN_KEY = "waterpipesSensorMin"
Signals.SENSOR_MAX_KEY = "waterpipesSensorMax"
Signals.SENSOR_INVERT_KEY = "waterpipesSensorInvert"
Signals.SENSOR_BATTERY_KEY = "waterpipesSensorBattery"   -- charge 0..1; absent = no battery fitted
Signals.SENSOR_STATE_KEY = "waterpipesSensorState"       -- "on" | "off" | "dead"
Signals.SENSOR_REASON_KEY = "waterpipesSensorReason"
Signals.SENSOR_READING_KEY = "waterpipesSensorReading"
Signals.SENSOR_SOURCE_KEY = "waterpipesSensorSource"     -- "grid" | "battery" | "flat" | "none"
Signals.SENSOR_EDGE_KEY = "waterpipesSensorEdge"         -- "min" | "max": the last end of the range reached

-- The valve's own switch, the one turned by hand. Absent means the valve follows its own open/closed
-- state, which is every valve that was never linked: old saves keep behaving exactly as before.
Signals.VALVE_SWITCH_KEY = "waterpipesValveSwitch"       -- "on" | "off"
Signals.VALVE_NAME_KEY = "waterpipesValveName"
Signals.VALVE_LINKS_KEY = "waterpipesValveLinks"         -- how many sensors drive it

Signals.SENSOR_FACING_KEY = "waterpipesSensorFacing"   -- "W" | "N" | "E" | "S": the corner it stands in

-- One set per entity face, the stake near that corner of the tile; ghost = the face (build cursor).
local function sensorSet(first)
    return {
        on = "waterpipes_01_" .. first,
        off = "waterpipes_01_" .. (first + 1),
        dead = "waterpipes_01_" .. (first + 2),
        ghost = "waterpipes_01_" .. (first + 3),
    }
end
Signals.SENSOR_FACES = { W = sensorSet(89), N = sensorSet(93), E = sensorSet(97), S = sensorSet(101) }
Signals.SENSOR_SPRITES = Signals.SENSOR_FACES.W
Signals.SENSOR_GHOST_SPRITE = Signals.SENSOR_FACES.W.ghost

Signals.DEFAULT_MIN = 80                         -- no vanilla crop needs more than 80
Signals.DEFAULT_MAX = 95
Signals.DEFAULT_BATTERY_DAYS = 30
Signals.BATTERY_ITEM = "Base.Battery"
Signals.STEP_MINUTES = 10
Signals.NAME_MAX = 32
Signals.CONFIG_REACH = 3                         -- tiles from the sensor a player may configure it from
Signals.LINK_REACH = 30                          -- tiles from the player a valve may be linked from (cursor scan)
-- What a dismantled sensor hands back, rolled per item. Destroying it returns only its battery.
Signals.DISMANTLE_RETURNS = {
    { itemType = "Base.ElectronicsScrap", count = 2, chance = 75 },
    { itemType = "Base.MotionSensor", count = 1, chance = 90 },
    { itemType = "Base.Receiver", count = 1, chance = 90 },
    { itemType = "Base.ElectricWire", count = 1, chance = 90 },
}
Signals.SCRAP_MATERIAL = "WaterPipesSensorScrap"  -- must match tools/texturepack/edit_tiles.py

-- ===== Small helpers =====

function Signals.key(x, y, z)
    return tostring(x) .. ":" .. tostring(y) .. ":" .. tostring(z)
end

local function modDataOf(object)
    if not object or not object.getModData then
        return nil
    end
    return object:getModData()
end
Signals.modDataOf = modDataOf

local function spriteNameOf(object)
    if not object or not object.getSprite then
        return nil
    end
    local sprite = object:getSprite()
    return sprite and sprite.getName and sprite:getName() or nil
end

local function clamp(value, lo, hi)
    return math.max(lo, math.min(hi, value))
end

function Signals.cleanName(text)
    if type(text) ~= "string" then
        return nil
    end
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then
        return nil
    end
    return text:sub(1, Signals.NAME_MAX)
end

-- ===== Sandbox =====

local function sandbox()
    return SandboxVars and SandboxVars.WaterPipes or nil
end

function Signals.batteryDays()
    local v = sandbox() and sandbox().SensorBatteryDays
    if type(v) == "number" and v > 0 then
        return v
    end
    return Signals.DEFAULT_BATTERY_DAYS
end

-- 0 = no limit.
function Signals.linkRange()
    local v = sandbox() and sandbox().SensorLinkRange
    if type(v) == "number" and v > 0 then
        return v
    end
    return 0
end

-- ===== Registry (server) =====

local fallbackRegistry = nil
local checkedRegistry = nil

function Signals.registry()
    local raw
    if ModData and ModData.getOrCreate then
        raw = ModData.getOrCreate(Signals.REGISTRY_KEY)
    else
        fallbackRegistry = fallbackRegistry or {}
        raw = fallbackRegistry
    end
    if raw ~= checkedRegistry then
        Signals.sanitizeRegistry(raw)
        checkedRegistry = raw
    end
    return raw
end

local function isCoord(v)
    return type(v) == "number" and v == math.floor(v)
end

local function placed(entry)
    return type(entry) == "table" and isCoord(entry.x) and isCoord(entry.y) and isCoord(entry.z)
end

-- Once per load: a damaged entry would otherwise throw in every ten-minute step.
function Signals.sanitizeRegistry(raw)
    for _, name in ipairs({ "emitters", "receivers", "stale" }) do
        if type(raw[name]) ~= "table" then
            raw[name] = {}
        end
    end
    for _, pair in ipairs({ { raw.emitters, "links" }, { raw.receivers, "sensors" } }) do
        local entries, field = pair[1], pair[2]
        local bad = {}
        for key, entry in pairs(entries) do
            if type(key) ~= "string" or not placed(entry) then
                bad[#bad + 1] = key
            elseif type(entry[field]) ~= "table" then
                entry[field] = {}
            end
        end
        for _, key in ipairs(bad) do
            entries[key] = nil
        end
    end
    local bad = {}
    for key, entry in pairs(raw.stale) do
        if not placed(entry) then
            bad[#bad + 1] = key
        end
    end
    for _, key in ipairs(bad) do
        raw.stale[key] = nil
    end
end

function Signals.isEmpty(t)
    for _ in pairs(t or {}) do
        return false
    end
    return true
end

function Signals.count(t)
    local n = 0
    for _ in pairs(t or {}) do
        n = n + 1
    end
    return n
end

-- ===== Sensor objects =====

local SENSOR_SPRITE_FACE = {}   -- sprite name -> face
for face, set in pairs(Signals.SENSOR_FACES) do
    for _, name in pairs(set) do
        SENSOR_SPRITE_FACE[name] = face
    end
end

-- The corner ("W", "N", "E", "S") a sensor sprite stands in, or nil for any other sprite.
function Signals.faceOfSprite(name)
    return name and SENSOR_SPRITE_FACE[name] or nil
end

function Signals.isSensor(object)
    local modData = modDataOf(object)
    return modData ~= nil and modData[Signals.SENSOR_KEY] == true
end

-- By sprite: true for a sensor whose modData has not arrived yet (chunk load, MP).
function Signals.hasSensorSprite(object)
    local name = spriteNameOf(object)
    return name ~= nil and SENSOR_SPRITE_FACE[name] ~= nil
end

-- The corner it was built facing: saved on create, else read off the sprite.
function Signals.sensorFacing(object)
    local modData = modDataOf(object)
    local face = modData and modData[Signals.SENSOR_FACING_KEY]
    if Signals.SENSOR_FACES[face] then
        return face
    end
    return SENSOR_SPRITE_FACE[spriteNameOf(object) or ""] or "W"
end

-- The sensor on a square. `bySprite` also accepts one whose modData is not there yet, which is what
-- placement and clean-up must ask: an absence read in that window is not an absence.
function Signals.findSensorOnSquare(square, bySprite)
    if not square or not square.getObjects then
        return nil
    end
    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do
        local object = objects:get(i)
        if Signals.isSensor(object) or (bySprite and Signals.hasSensorSprite(object)) then
            return object
        end
    end
    return nil
end

function Signals.sensorName(object)
    local modData = modDataOf(object)
    return modData and Signals.cleanName(modData[Signals.SENSOR_NAME_KEY]) or nil
end

function Signals.sensorRange(object)
    local modData = modDataOf(object) or {}
    local lo = clamp(tonumber(modData[Signals.SENSOR_MIN_KEY]) or Signals.DEFAULT_MIN, 0, 100)
    local hi = clamp(tonumber(modData[Signals.SENSOR_MAX_KEY]) or Signals.DEFAULT_MAX, 0, 100)
    if lo > hi then
        lo, hi = hi, lo
    end
    return lo, hi, modData[Signals.SENSOR_INVERT_KEY] == true
end

function Signals.sensorState(object)
    local modData = modDataOf(object)
    local state = modData and modData[Signals.SENSOR_STATE_KEY]
    return (state == "on" or state == "off") and state or "dead"
end

-- Battery charge 0..1, or nil with no battery fitted.
function Signals.batteryCharge(object)
    local modData = modDataOf(object)
    local v = modData and modData[Signals.SENSOR_BATTERY_KEY]
    return type(v) == "number" and clamp(v, 0, 1) or nil
end

-- Draw the LED from the state in modData. Sprites do not replicate, so each side draws its own.
function Signals.applySensorSprite(object)
    if not object or not object.setSprite then
        return false
    end
    local wanted = Signals.SENSOR_FACES[Signals.sensorFacing(object)][Signals.sensorState(object)]
    if spriteNameOf(object) == wanted then
        return false
    end
    local sprite = getSprite and getSprite(wanted) or nil
    if not sprite then
        return false
    end
    object:setSprite(sprite)
    -- The dismantle cursor finds its object by sprite name.
    local autotile = WaterPipes.PipeAutotile
    if autotile and autotile.invalidateMoveableCursorCache then
        autotile.invalidateMoveableCursorCache()
    end
    return true
end

-- ===== The world the sensor reads =====

-- Tile power as vanilla lamps read it: a generator or the grid reaches the tile, or the grid is on and
-- the tile is indoors.
function Signals.squareHasPower(square)
    if not square then
        return false
    end
    if square.haveElectricity and square:haveElectricity() then
        return true
    end
    if square.hasGridPower and square.getRoom and square:hasGridPower() and square:getRoom() then
        return true
    end
    return false
end

-- The farm plant on a square. The server's farming system where it runs, the client's mirror otherwise.
function Signals.cropOn(square)
    if not square then
        return nil
    end
    local system = (SFarmingSystem and SFarmingSystem.instance) or (CFarmingSystem and CFarmingSystem.instance)
    if not system or not system.getLuaObjectOnSquare then
        return nil
    end
    return system:getLuaObjectOnSquare(square)
end

-- The crop's water level 0..100, or nil and why not. Tilled soil with nothing sown and a dead plant have
-- nothing to measure.
function Signals.readCrop(square)
    local plant = Signals.cropOn(square)
    if not plant or plant.state == "plow" then
        return nil, "noCrop"
    end
    if plant.isAlive and not plant:isAlive() then
        return nil, "noCrop"
    end
    return clamp(tonumber(plant.waterLvl) or 0, 0, 100), nil
end

local function dirtAllowedOn(square)
    if square:getZ() == 0 then
        return true
    end
    local options = getSandboxOptions and getSandboxOptions() or nil
    local option = options and options.getOptionByName and options:getOptionByName("PlaceDirtAboveground") or nil
    return option ~= nil and option:getValue() == true
end

-- Where something can be planted: tilled soil or a crop already there, or bare dirt or grass on the
-- ground (vanilla's own test for digging a furrow).
function Signals.isPlantable(square)
    if not square then
        return false
    end
    if Signals.cropOn(square) then
        return true
    end
    if not dirtAllowedOn(square) then
        return false
    end
    local shovel = ISShovelGroundCursor and ISShovelGroundCursor.GetDirtGravelSand
    return shovel ~= nil and shovel(square) == "dirt"
end

-- ===== Valve tiles =====

-- A valve on a square, by modData or by its sprite (modData-missing window).
local VALVE_SPRITE_SET = {}
for _, pair in pairs(Constants.VALVE_SPRITES or {}) do
    VALVE_SPRITE_SET[pair.open] = true
    VALVE_SPRITE_SET[pair.closed] = true
end
VALVE_SPRITE_SET[Constants.VALVE_SPRITE_OPEN or ""] = true
VALVE_SPRITE_SET[Constants.VALVE_SPRITE_CLOSED or ""] = true
VALVE_SPRITE_SET["waterpipes_01_47"] = true

function Signals.squareMayHoldValve(square)
    if not square or not square.getObjects then
        return false
    end
    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do
        local object = objects:get(i)
        if Valve.isValve(object) or VALVE_SPRITE_SET[spriteNameOf(object) or ""] then
            return true
        end
    end
    return false
end

-- ===== Classes =====

local Base = ISBaseObject
if not Base then
    -- outside the game (tools/conservation): the same derive/new shape
    Base = { Type = "ISBaseObject" }
    function Base:derive(kind)
        local o = {}
        setmetatable(o, self)
        self.__index = self
        o.Type = kind
        o.SuperType = self
        return o
    end
    function Base:new()
        local o = {}
        setmetatable(o, self)
        self.__index = self
        return o
    end
end

local unpackArgs = unpack or table.unpack

-- Kinds by name, in the order they were registered. Registering a kind again replaces it. `required`
-- names the fields a class must set, checked when it registers rather than when a player first meets it.
local function kindRegistry(required)
    local byKind, ordered = {}, {}
    local function register(class)
        assert(type(class.kind) == "string", "a signal class needs a kind")
        for _, field in ipairs(required or {}) do
            assert(class[field] ~= nil, "signal kind " .. class.kind .. " needs " .. field)
        end
        if byKind[class.kind] then
            for i, known in ipairs(ordered) do
                if known.kind == class.kind then
                    ordered[i] = class
                end
            end
        else
            ordered[#ordered + 1] = class
        end
        byKind[class.kind] = class
        return class
    end
    return byKind, ordered, register
end

-- ---- Emitters ----

-- An emitter wraps one world object and turns what it measures into on/off. Subclasses implement
-- read() and decide(); power and the battery are common to all of them.
Signals.SignalEmitter = Base:derive("WaterPipesSignalEmitter")
local SignalEmitter = Signals.SignalEmitter

function SignalEmitter:new(object)
    local o = Base.new(self)
    o.object = object
    return o
end

function SignalEmitter:read(square)
    return nil, "noReading"
end

function SignalEmitter:decide(value)
    return false, "noReading"
end

-- Powered or not, and from what. Spends `dtHours` of battery when running on it.
function SignalEmitter:power(square, modData, dtHours)
    if Signals.squareHasPower(square) then
        return true, "grid"
    end
    local charge = modData[Signals.SENSOR_BATTERY_KEY]
    if type(charge) ~= "number" then
        return false, "none"
    end
    if dtHours and dtHours > 0 and charge > 0 then
        charge = math.max(0, charge - dtHours / (Signals.batteryDays() * 24))
        modData[Signals.SENSOR_BATTERY_KEY] = charge
    end
    if charge <= 0 then
        return false, "flat"
    end
    return true, "battery"
end

-- One reading. Unpowered or with nothing to read, the signal is always off: invert only flips the
-- range test.
function SignalEmitter:evaluate(dtHours)
    local object = self.object
    local square = object and object:getSquare() or nil
    local modData = modDataOf(object)
    if not square or not modData then
        return nil
    end
    local powered, source = self:power(square, modData, dtHours)
    if not powered then
        return { active = false, state = "dead", reason = "noPower", source = source }
    end
    local value, why = self:read(square)
    if value == nil then
        return { active = false, state = "off", reason = why or "noReading", source = source }
    end
    local active, reason, edge = self:decide(value)
    return { active = active, state = active and "on" or "off", reason = reason, reading = value, source = source,
             edge = edge }
end

Signals.DEFAULT_EMITTER = "humidity"   -- registry entries saved without a kind

local emitterKinds, _, registerEmitter = kindRegistry()
Signals.registerEmitter = registerEmitter

function Signals.emitterClass(kind)
    return emitterKinds[kind or Signals.DEFAULT_EMITTER]
end

Signals.HumiditySensor = SignalEmitter:derive("WaterPipesHumiditySensor")
local HumiditySensor = Signals.HumiditySensor
HumiditySensor.kind = "humidity"

function HumiditySensor:read(square)
    return Signals.readCrop(square)
end

-- Hysteresis: reaching the minimum switches the signal on, reaching the maximum switches it off, and in
-- between it holds. Invert swaps the two ends. Before either end is reached the signal stays off.
function HumiditySensor:decide(value)
    local lo, hi, invert = Signals.sensorRange(self.object)
    local modData = modDataOf(self.object) or {}
    local edge = modData[Signals.SENSOR_EDGE_KEY]
    local reason
    if value <= lo then
        edge, reason = "min", "atMin"
    elseif value >= hi then
        edge, reason = "max", "atMax"
    elseif edge == "min" then
        reason = "towardMax"
    elseif edge == "max" then
        reason = "towardMin"
    else
        edge, reason = nil, "noEdge"
    end
    local active = edge ~= nil and ((edge == "min") ~= invert)
    return active, reason, edge
end

registerEmitter(HumiditySensor)

-- ---- Receivers ----

-- A receiver wraps one world object a sensor can switch. Each kind is a subclass registered with
-- Signals.registerReceiver, and the bus only reaches it through this interface:
--   kind                         its name in the registry and in requests
--   SWITCH_KEY, LINKS_KEY,       modData keys for the hand switch ("on" | "off"), how many sensors drive
--   NAME_KEY                     it and its name
--   MISSING_REASON               refusal reason when a link names a tile without one
--   NAME_PROMPT                  getText key of the name box the link cursor opens
--   :findOnSquare(square)        the object on a loaded square, or nil
--   :mayStandOn(square)          one may be there even though its modData has not arrived
--   :isReceiver(object)          is this world object one (removal events)
--   :applyUnloaded(x, y, z, on)  act on it while its tile is away; false = could not, try again
--   :batch(fn, ...)              run fn with this kind's side effects settled once at the end
--   :onSignal(on)                the signal reached it: be on or off
--   :isOn()                      what it is now
--   :turnByHand(on)              a hand on it while no sensor drives it
Signals.SignalReceiver = Base:derive("WaterPipesSignalReceiver")
local SignalReceiver = Signals.SignalReceiver
SignalReceiver.MISSING_REASON = "noReceiver"

function SignalReceiver:new(object)
    local o = Base.new(self)
    o.object = object
    return o
end

function SignalReceiver:findOnSquare(square)
    return nil
end

function SignalReceiver:mayStandOn(square)
    return self:findOnSquare(square) ~= nil
end

function SignalReceiver:isReceiver(object)
    return false
end

-- Nothing to do away from its tile: the bus turns it the tick after the tile loads.
function SignalReceiver:applyUnloaded(x, y, z, on)
    return true
end

function SignalReceiver:batch(fn, ...)
    return fn(...)
end

function SignalReceiver:onSignal(on)
end

function SignalReceiver:isOn()
    return false
end

function SignalReceiver:turnByHand(on)
    self:onSignal(on)
end

-- How many sensors drive it, from its marks.
function SignalReceiver:linkCount()
    local modData = modDataOf(self.object)
    local v = modData and tonumber(modData[self.LINKS_KEY])
    return v and v > 0 and v or 0
end

-- The hand switch: what was last set by hand. Unlinked, it follows its own state; a switch mark left
-- without links (released while unloaded) does not count.
function SignalReceiver:isSwitchOn()
    local modData = modDataOf(self.object)
    local v = self:linkCount() > 0 and modData[self.SWITCH_KEY] or nil
    if v == "on" then
        return true
    elseif v == "off" then
        return false
    end
    return self:isOn()
end

function SignalReceiver:savedName()
    local modData = modDataOf(self.object)
    return modData and Signals.cleanName(modData[self.NAME_KEY]) or nil
end

function SignalReceiver:hasSwitchMark()
    local modData = modDataOf(self.object)
    return modData ~= nil and modData[self.SWITCH_KEY] ~= nil
end

-- Write what the client draws from: the switch, the name and how many sensors drive it. nil clears the
-- link marks (the name stays). `quiet` leaves sending to whatever changes the object next.
function SignalReceiver:mark(record, quiet)
    local modData = modDataOf(self.object)
    if not modData then
        return
    end
    if record then
        modData[self.SWITCH_KEY] = record.switchOn == false and "off" or "on"
        modData[self.LINKS_KEY] = Signals.count(record.sensors)
        modData[self.NAME_KEY] = record.name
    else
        modData[self.SWITCH_KEY] = nil
        modData[self.LINKS_KEY] = nil
    end
    if not quiet and self.object.transmitModData then
        self.object:transmitModData()
    end
end

Signals.DEFAULT_RECEIVER = "valve"   -- registry entries saved without a kind

local receiverKinds, receiverOrder, registerReceiver =
    kindRegistry({ "SWITCH_KEY", "LINKS_KEY", "NAME_KEY", "NAME_PROMPT" })
Signals.registerReceiver = registerReceiver

function Signals.receiverClass(kind)
    return receiverKinds[kind or Signals.DEFAULT_RECEIVER]
end

function Signals.receiverClasses()
    return receiverOrder
end

-- Registry key of one receiver. The default kind keeps the bare tile key, so saved registries load as
-- they were; any other kind on the same tile gets its own.
function Signals.receiverKey(kind, x, y, z)
    local key = Signals.key(x, y, z)
    if kind == nil or kind == Signals.DEFAULT_RECEIVER then
        return key
    end
    return key .. "#" .. kind
end

-- The receiver of `kind` at a tile, wrapped, or nil; with the square when it is loaded, and the class.
function Signals.receiverAt(kind, x, y, z)
    local class = Signals.receiverClass(kind)
    local square = World.squareAt(x, y, z)
    local object = class and square and class:findOnSquare(square) or nil
    return object and class:new(object) or nil, square, class
end

-- Every receiver on a square, one per kind, wrapped.
function Signals.receiversOnSquare(square)
    local found = {}
    for _, class in ipairs(receiverOrder) do
        local object = square and class:findOnSquare(square) or nil
        if object then
            found[#found + 1] = class:new(object)
        end
    end
    return found
end

-- The class a world object is a receiver of, or nil.
function Signals.receiverClassOf(object)
    for _, class in ipairs(receiverOrder) do
        if class:isReceiver(object) then
            return class
        end
    end
    return nil
end

-- Run fn inside every kind's batch: whatever one step switches is settled together.
function Signals.batchReceivers(fn, ...)
    local args, n = { ... }, select("#", ...)
    local function run(i)
        local class = receiverOrder[i]
        if not class then
            return fn(unpackArgs(args, 1, n))
        end
        return class:batch(run, i + 1)
    end
    return run(1)
end

-- ===== The valve as a receiver =====
-- The only reach into the water network.

Signals.ValveReceiver = SignalReceiver:derive("WaterPipesValveReceiver")
local ValveReceiver = Signals.ValveReceiver
ValveReceiver.kind = "valve"
ValveReceiver.SWITCH_KEY = Signals.VALVE_SWITCH_KEY
ValveReceiver.LINKS_KEY = Signals.VALVE_LINKS_KEY
ValveReceiver.NAME_KEY = Signals.VALVE_NAME_KEY
ValveReceiver.MISSING_REASON = "noValve"
ValveReceiver.NAME_PROMPT = "IGUI_WaterPipesSignalNameValve"

function ValveReceiver:findOnSquare(square)
    return Valve.findOnSquare(square)
end

function ValveReceiver:mayStandOn(square)
    return Signals.squareMayHoldValve(square)
end

function ValveReceiver:isReceiver(object)
    return Valve.isValve(object)
end

function ValveReceiver:isOn()
    return Valve.isOpen(self.object)
end

function ValveReceiver:onSignal(on)
    if Valve.isOpen(self.object) ~= on then
        Valve.setOpen(self.object, on)
    end
end

-- By hand it always goes through setOpen, which also puts sprite and registry right.
function ValveReceiver:turnByHand(on)
    Valve.setOpen(self.object, on)
end

-- Away from its tile the registry decides where the network splits; the bus turns the valve itself as
-- soon as its tile loads (SignalBus, pending receivers).
function ValveReceiver:applyUnloaded(x, y, z, on)
    local State = WaterPipes.State
    if not State or not State.setPipeValveClosed then
        return false
    end
    if not State.setPipeValveClosed(x, y, z, not on) then
        return false
    end
    Valve.layoutChanged()
    return true
end

-- Every valve turned in one go rebuilds the network once.
function ValveReceiver:batch(fn, ...)
    return Valve.batch(fn, ...)
end

registerReceiver(ValveReceiver)

function Signals.valveSwitchOn(valve)
    return ValveReceiver:new(valve):isSwitchOn()
end

function Signals.valveLinkCount(valve)
    return ValveReceiver:new(valve):linkCount()
end

function Signals.valveName(valve)
    return ValveReceiver:new(valve):savedName()
end

-- ===== Permissions =====

-- Admins, moderators and any role allowed into safehouses. getAccessLevel() is "user" for a plain player
-- on a server, so it cannot answer this.
function Signals.bypassesSafehouses(player)
    local role = player and player.getRole and player:getRole() or nil
    if not role or not role.hasCapability or not Capability or not Capability.CanGoInsideSafehouses then
        return false
    end
    return role:hasCapability(Capability.CanGoInsideSafehouses) == true
end

-- A tile inside a safehouse belongs to its members.
function Signals.mayTouch(player, square)
    if not player or not square or Signals.bypassesSafehouses(player) then
        return true
    end
    if not SafeHouse or not SafeHouse.isSafeHouse or not player.getUsername then
        return true
    end
    return SafeHouse.isSafeHouse(square, player:getUsername(), true) == nil
end

-- ===== Talking to the other side =====

-- Handlers the client registers. In single player there is no network: notifications go straight to them.
Signals.clientHandlers = Signals.clientHandlers or {}

local function deliverLocally(command, args)
    local handler = Signals.clientHandlers[command]
    if handler then
        handler(args)
    end
end

-- To every client.
function Signals.notifyClients(command, args)
    if isServer and isServer() then
        sendServerCommand(Signals.MODULE, command, args)
    elseif not (isClient and isClient()) then
        deliverLocally(command, args)
    end
end

-- To one player.
function Signals.notifyPlayer(player, command, args)
    if isServer and isServer() then
        if player then
            sendServerCommand(player, Signals.MODULE, command, args)
        end
    elseif not (isClient and isClient()) then
        deliverLocally(command, args)
    end
end

-- From a client to the server; handled in place in single player.
function Signals.request(player, command, args)
    if isClient and isClient() then
        sendClientCommand(player, Signals.MODULE, command, args)
        return
    end
    local Bus = WaterPipes.SignalBus
    if Bus and Bus.handle then
        Bus.handle(command, player, args)
    end
end

-- ===== Build hooks (entity WaterPipeHumiditySensor) =====

WaterPipesSignalsBuild = WaterPipesSignalsBuild or {}

-- On soil that can be planted, one sensor per tile; any WaterPipes piece may share the tile.
function WaterPipesSignalsBuild.sensorOnIsValid(params)
    local square = params and params.square
    return Signals.isPlantable(square) and Signals.findSensorOnSquare(square, true) == nil
end

-- Built with no battery and the default range; the server reads it at once.
function WaterPipesSignalsBuild.sensorOnCreate(params)
    local object = params and params.thumpable
    local modData = modDataOf(object)
    if not modData then
        return
    end
    modData[Signals.SENSOR_KEY] = true
    modData[Signals.SENSOR_FACING_KEY] = Signals.sensorFacing(object)
    modData[Signals.SENSOR_MIN_KEY] = Signals.DEFAULT_MIN
    modData[Signals.SENSOR_MAX_KEY] = Signals.DEFAULT_MAX
    modData[Signals.SENSOR_INVERT_KEY] = false
    modData[Signals.SENSOR_STATE_KEY] = "dead"
    modData[Signals.SENSOR_REASON_KEY] = "noPower"
    if object.transmitModData then
        object:transmitModData()
    end
    Signals.applySensorSprite(object)
    local Bus = WaterPipes.SignalBus
    if Bus and Bus.sensorBuilt then
        Bus.sensorBuilt(object)
    end
end

-- ===== Disassemble =====
-- Same scheme as WaterPipeScrap.lua: vanilla only offers Disassemble for a material with a return item,
-- so one is listed at a chance of zero and the real payout is SignalBus's removal hook (it has to hand
-- the battery back with its charge, which a scrap table cannot).
local function registerSensorScrap()
    local defs = moveableDefinitions
    if not defs and ISMoveableDefinitions and ISMoveableDefinitions.getInstance then
        defs = ISMoveableDefinitions:getInstance()
    end
    if not defs or not defs.addScrapDefinition or not defs.addScrapItem then
        return
    end
    defs.addScrapDefinition(Signals.SCRAP_MATERIAL, { "Base.Screwdriver" }, {}, Perks.Electricity, 1000,
        "Dismantle", true)
    defs.addScrapItem(Signals.SCRAP_MATERIAL, "Base.ElectronicsScrap", 1, 0)
end

if Events and Events.OnGameBoot then
    Events.OnGameBoot.Add(registerSensorScrap)
end

return Signals
