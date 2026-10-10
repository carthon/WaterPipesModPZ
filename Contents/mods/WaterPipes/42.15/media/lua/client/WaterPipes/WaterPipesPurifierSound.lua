-- Purifier ambient sound (client-only). While an electric purifier is powered it emits a looping
-- machine hum (the vanilla running-generator loop) from its tile. FMOD handles distance attenuation;
-- we just start the loop when a powered purifier is near the player and stop it when it powers off,
-- is removed, or leaves range. Purely presentational -> lives entirely on the client.

require "WaterPipes/Constants"
require "WaterPipes/Purifier"
require "WaterPipes/WaterPipesTileRegistry"
require "WaterPipes/SoundOptions"

WaterPipes = WaterPipes or {}
WaterPipes.PurifierSound = WaterPipes.PurifierSound or {}

local Purifier = WaterPipes.Purifier
local SoundOptions = WaterPipes.SoundOptions
local Registry = WaterPipes.TileRegistry
local Sound = WaterPipes.PurifierSound

-- Tunables. Switch SOUND_NAME to "OldGeneratorLoop" for a rougher, older-motor hum.
local SOUND_NAME = "GeneratorLoop"
local SCAN_RADIUS = 14        -- tiles around the player we manage emitters within
local INTERVAL_TICKS = 60     -- ~1s at 60fps between rescans (cheap; the hum is local)

-- Registers the mod's options group; every sound reads it through WaterPipes.SoundOptions.
if PZAPI and PZAPI.ModOptions and not PZAPI.ModOptions:getOptions("WaterPipes") then
    local opts = PZAPI.ModOptions:create("WaterPipes", "IGUI_WaterPipes_Options")
    opts:addTickBox("SoundEnabled", "IGUI_WaterPipes_SoundEnabled", true, "IGUI_WaterPipes_SoundEnabled_tooltip")
    opts:addSlider("SoundVolume", "IGUI_WaterPipes_SoundVolume", 0, 100, 5, SoundOptions.DEFAULT_VOLUME, "IGUI_WaterPipes_SoundVolume_tooltip")
    opts:addTickBox("EffectsEnabled", "IGUI_WaterPipes_EffectsEnabled", true, "IGUI_WaterPipes_EffectsEnabled_tooltip")
end

local soundEnabled = SoundOptions.enabled
local soundVolume = SoundOptions.volume

Sound.active = Sound.active or {}   -- key "x:y:z" -> { emitter = , channel = }

local function keyFor(sq)
    return sq:getX() .. ":" .. sq:getY() .. ":" .. sq:getZ()
end

-- Play the machine hum on a WORLD free emitter at the purifier tile. We deliberately do NOT take
-- ownership: the engine's WorldSoundManager then ticks the pooled emitter for us, where an OWNED one
-- must be tick()'d by hand every frame or it stays silent. A looping sound keeps the pooled emitter
-- busy so it is not recycled; each rescan re-arms it if it stopped and re-applies the volume.
local function ensureLoop(sq, k)
    local entry = Sound.active[k]
    local playing = false
    if entry and entry.emitter and entry.channel and entry.channel ~= 0 then
        pcall(function() playing = entry.emitter:isPlaying(entry.channel) end)
    end
    if not playing then
        local world = getWorld and getWorld() or nil
        if not world or not world.getFreeEmitter then
            return
        end
        local emitter
        pcall(function()
            emitter = world:getFreeEmitter(sq:getX() + 0.5, sq:getY() + 0.5, sq:getZ())
        end)
        if not emitter then
            return
        end
        local channel = 0
        pcall(function() channel = emitter:playSoundLooped(SOUND_NAME) or 0 end)
        if channel == 0 then
            return
        end
        entry = { emitter = emitter, channel = channel }
        Sound.active[k] = entry
    end
    if entry.channel and entry.channel ~= 0 then
        pcall(function() entry.emitter:setVolume(entry.channel, soundVolume()) end)
    end
end

local function stopSound(k)
    local entry = Sound.active[k]
    if not entry then
        return
    end
    Sound.active[k] = nil
    local emitter = entry.emitter
    if emitter then
        pcall(function()
            if entry.channel and entry.channel ~= 0 and emitter.isPlaying and emitter:isPlaying(entry.channel) then
                emitter:stopSound(entry.channel)
            elseif emitter.stopSoundByName then
                emitter:stopSoundByName(SOUND_NAME)
            end
        end)
    end
end

function Sound.stopAll()
    for k in pairs(Sound.active) do
        stopSound(k)
    end
end

-- Rescan the area around the player: start a loop for each powered purifier in range, stop the rest.
function Sound.update()
    -- Sandbox toggle: total silence when disabled.
    if not soundEnabled() then
        Sound.stopAll()
        return
    end

    local player = getPlayer and getPlayer() or nil
    local cell = getCell and getCell() or nil
    if not player or not cell then
        Sound.stopAll()
        return
    end

    local px = math.floor(player:getX())
    local py = math.floor(player:getY())
    local pz = math.floor(player:getZ())

    -- Driven by the tile registry rather than a (2*SCAN_RADIUS+1)^2 sweep -- see the same change in
    -- WaterPipesHydrantSound, and WaterPipesTileRegistry for why.
    local seen = {}
    for _, found in ipairs(Registry.near("purifiers", px, py, pz, SCAN_RADIUS)) do
        if Purifier.isWorking(found.object) then
            local k = keyFor(found.square)
            seen[k] = true
            ensureLoop(found.square, k)   -- (re)start the loop + refresh volume on a world free emitter
        end
    end

    for k in pairs(Sound.active) do
        if not seen[k] then
            stopSound(k)
        end
    end
end

local tickCounter = 0
local function onTick()
    tickCounter = tickCounter + 1
    if tickCounter < INTERVAL_TICKS then
        return
    end
    tickCounter = 0
    pcall(Sound.update)
end

if Events and Events.OnTick then
    Events.OnTick.Add(onTick)
end

-- Clean up loops on teardown so none leak across a game session.
if Events and Events.OnPlayerDeath then
    Events.OnPlayerDeath.Add(function() Sound.stopAll() end)
end
if Events and Events.OnGameStop then
    Events.OnGameStop.Add(function() Sound.stopAll() end)
end

return Sound
