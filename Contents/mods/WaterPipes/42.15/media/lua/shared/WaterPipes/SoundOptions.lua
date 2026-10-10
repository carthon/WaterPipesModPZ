WaterPipes = WaterPipes or {}
WaterPipes.SoundOptions = WaterPipes.SoundOptions or {}

local SoundOptions = WaterPipes.SoundOptions

-- The one gate every mod sound goes through: the per-player "WaterPipes" mod options (SoundEnabled,
-- SoundVolume). The group is registered client-side by WaterPipesPurifierSound, where PZAPI exists;
-- this reads it live and falls back to enabled at the default volume wherever it is absent.

SoundOptions.DEFAULT_VOLUME = 55   -- 0..100

local function option(id)
    local group = PZAPI and PZAPI.ModOptions and PZAPI.ModOptions:getOptions("WaterPipes")
    return group and group:getOption(id) or nil
end

function SoundOptions.enabled()
    local o = option("SoundEnabled")
    return not o or o:getValue() ~= false
end

-- 0..1
function SoundOptions.volume()
    local o = option("SoundVolume")
    local v = o and o:getValue() or SoundOptions.DEFAULT_VOLUME
    return math.min(math.max(v, 0), 100) / 100
end

-- Play `name` on a character, at the mod volume. Returns the sound id, or nil when sound is off.
function SoundOptions.playOnCharacter(character, name)
    if not character or not SoundOptions.enabled() then
        return nil
    end
    local id = character:playSound(name)
    if id and id ~= 0 then
        local volume = SoundOptions.volume()
        pcall(function() character:getEmitter():setVolume(id, volume) end)
    end
    return id
end

-- Stop a sound started by playOnCharacter; nil (sound was off) is a no-op.
function SoundOptions.stopOnCharacter(character, id)
    if character and id and id ~= 0 then
        character:stopOrTriggerSound(id)
    end
end

-- Play `name` once from a tile, at the mod volume.
function SoundOptions.playAtSquare(square, name)
    if not square or not SoundOptions.enabled() then
        return
    end
    local world = getWorld and getWorld()
    local emitter = world and world:getFreeEmitter(square:getX() + 0.5, square:getY() + 0.5, square:getZ())
    if not emitter then
        return
    end
    local id = emitter:playSound(name)
    if id and id ~= 0 then
        local volume = SoundOptions.volume()
        pcall(function() emitter:setVolume(id, volume) end)
    end
end

return SoundOptions
