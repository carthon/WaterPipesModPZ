-- The humidity sensor in vanilla's moveables and destroy actions. Every hook below hands any other
-- object straight to vanilla, untouched: only the sensor's tiles (89-104) are moveable at all.
--
-- Picked up: its battery goes back to the player with its charge, its links go (the bus releases their
-- valves), and its settings travel on the item. Placed: on plantable soil only, one per tile; settings
-- restored and the bus reads it at once. Rotated in place: the same object, so battery and links stay.
-- Dismantled or destroyed: the action says who did it, so parts and battery reach that player.

require "Moveables/ISMoveableSpriteProps"
require "TimedActions/ISDestroyStuffAction"
require "WaterPipes/Signals"

WaterPipes = WaterPipes or {}
WaterPipes.SignalsMoveables = WaterPipes.SignalsMoveables or {}

local Signals = WaterPipes.Signals
local Moveables = WaterPipes.SignalsMoveables

local CARRIED = "waterpipesSensorCarried"       -- the settings riding in movableData

-- Whatever vanilla copied across from the old object; none of it means anything on a sensor.
local LEFTOVERS = { "name", "health", "maxHealth", "thumpSound", "color", "lightSource",
                    "canBeLockedByPadlock", "lockedByKeyId", "lockedByCode", "modData", "movableData" }
local SENSOR_KEYS = { Signals.SENSOR_KEY, Signals.SENSOR_NAME_KEY, Signals.SENSOR_MIN_KEY, Signals.SENSOR_MAX_KEY,
                      Signals.SENSOR_INVERT_KEY, Signals.SENSOR_BATTERY_KEY, Signals.SENSOR_STATE_KEY,
                      Signals.SENSOR_REASON_KEY, Signals.SENSOR_READING_KEY, Signals.SENSOR_SOURCE_KEY,
                      Signals.SENSOR_FACING_KEY, Signals.SENSOR_EDGE_KEY }

local function authoritative()
    return not (isClient and isClient())
end

local function bus()
    return WaterPipes.SignalBus
end

local function isSensorSprite(name)
    return name ~= nil and Signals.faceOfSprite(name) ~= nil
end

local function isSensorObject(object)
    return object ~= nil and (Signals.isSensor(object) or Signals.hasSensorSprite(object))
end

local function settingsOf(object)
    local modData = object:getModData()
    return {
        name = Signals.cleanName(modData[Signals.SENSOR_NAME_KEY]),
        min = tonumber(modData[Signals.SENSOR_MIN_KEY]),
        max = tonumber(modData[Signals.SENSOR_MAX_KEY]),
        invert = modData[Signals.SENSOR_INVERT_KEY] == true,
    }
end

-- The settings a placed sensor came with, wherever vanilla put them: movableData (an IsoObject), or the
-- copy of the whole modData it keeps for an IsoThumpable.
local function carriedSettings(modData)
    local found = type(modData.movableData) == "table" and modData.movableData[CARRIED]
    if type(found) ~= "table" and type(modData.modData) == "table" then
        local inner = modData.modData
        found = type(inner.movableData) == "table" and inner.movableData[CARRIED] or nil
    end
    return type(found) == "table" and found or {}
end

-- Hooks vanilla once its classes are there; the same wrapping twice would chain. Exposed for tools/conservation.
function Moveables.install()
    if Moveables.installed or not ISMoveableSpriteProps or not ISDestroyStuffAction then
        return false
    end
    Moveables.installed = true

    -- ===== Pick up =====

    local pickUp = ISMoveableSpriteProps.pickUpMoveableInternal
    function ISMoveableSpriteProps:pickUpMoveableInternal(_character, _square, _object, _sprInstance, _spriteName,
                                                          _createItem, _rotating)
        if not isSensorObject(_object) or _sprInstance then
            return pickUp(self, _character, _square, _object, _sprInstance, _spriteName, _createItem, _rotating)
        end
        local modData = _object:getModData()
        if authoritative() then
            local charge = Signals.batteryCharge(_object)
            local Bus = bus()
            if charge and Bus then
                Bus.giveItem(_character, _square, Bus.batteryItem(charge))
            end
            modData[Signals.SENSOR_BATTERY_KEY] = nil
            if Bus then
                Bus.noteRemover(_object, "move", _character)
            end
        end
        modData.movableData = { [CARRIED] = settingsOf(_object) }
        return pickUp(self, _character, _square, _object, _sprInstance, _spriteName, _createItem, _rotating)
    end

    -- ===== Place =====

    local canPlace = ISMoveableSpriteProps.canPlaceMoveableInternal
    function ISMoveableSpriteProps:canPlaceMoveableInternal(_character, _square, _item, _forceTypeObject)
        local ok = canPlace(self, _character, _square, _item, _forceTypeObject)
        if not ok or not isSensorSprite(self.spriteName) then
            return ok
        end
        return Signals.isPlantable(_square) and Signals.findSensorOnSquare(_square, true) == nil
    end

    local place = ISMoveableSpriteProps.placeMoveableInternal
    function ISMoveableSpriteProps:placeMoveableInternal(_character, _square, _item, _spriteName)
        local obj = place(self, _character, _square, _item, _spriteName)
        if not obj or not isSensorSprite(_spriteName) or not authoritative() then
            return obj
        end
        local modData = obj:getModData()
        local settings = carriedSettings(modData)
        for _, key in ipairs(LEFTOVERS) do
            modData[key] = nil
        end
        for _, key in ipairs(SENSOR_KEYS) do
            modData[key] = nil
        end
        modData[Signals.SENSOR_KEY] = true
        modData[Signals.SENSOR_FACING_KEY] = Signals.faceOfSprite(_spriteName)
        modData[Signals.SENSOR_NAME_KEY] = Signals.cleanName(settings.name)
        modData[Signals.SENSOR_MIN_KEY] = tonumber(settings.min) or Signals.DEFAULT_MIN
        modData[Signals.SENSOR_MAX_KEY] = tonumber(settings.max) or Signals.DEFAULT_MAX
        modData[Signals.SENSOR_INVERT_KEY] = settings.invert == true
        modData[Signals.SENSOR_STATE_KEY] = "dead"
        modData[Signals.SENSOR_REASON_KEY] = "noPower"
        if obj.transmitModData then
            obj:transmitModData()
        end
        Signals.applySensorSprite(obj)
        local Bus = bus()
        if Bus and Bus.sensorBuilt then
            Bus.sensorBuilt(obj)
        end
        return obj
    end

    -- ===== Rotate in place =====
    -- Vanilla only swaps the sprite of the same object: the corner it stands in moves with it.

    local rotate = ISMoveableSpriteProps.rotateMoveableInternal
    function ISMoveableSpriteProps:rotateMoveableInternal(_character, _square, _origSpriteName)
        rotate(self, _character, _square, _origSpriteName)
        if not isSensorSprite(_origSpriteName) then
            return
        end
        local sensor = Signals.findSensorOnSquare(_square, true)
        local face = sensor and Signals.faceOfSprite(sensor:getSprite() and sensor:getSprite():getName())
        if not face then
            return
        end
        sensor:getModData()[Signals.SENSOR_FACING_KEY] = face
        Signals.applySensorSprite(sensor)
        if authoritative() and sensor.transmitModData then
            sensor:transmitModData()
        end
    end

    -- ===== Dismantle and destroy: who took it down =====

    local scrapInternal = ISMoveableSpriteProps.scrapObjectInternal
    function ISMoveableSpriteProps:scrapObjectInternal(_character, _scrapDef, _square, _object, ...)
        local Bus = bus()
        if Bus and isSensorObject(_object) then
            Bus.noteRemover(_object, "scrap", _character)
        end
        return scrapInternal(self, _character, _scrapDef, _square, _object, ...)
    end

    local destroyComplete = ISDestroyStuffAction.complete
    function ISDestroyStuffAction:complete()
        local Bus = bus()
        if Bus and isSensorObject(self.item) then
            Bus.noteRemover(self.item, "destroy", self.character)
        end
        return destroyComplete(self)
    end
    return true
end

if not Moveables.install() and Events and Events.OnGameBoot then
    Events.OnGameBoot.Add(Moveables.install)
end
