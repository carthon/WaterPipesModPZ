-- Purifier ambient sound (client-only). While an electric purifier is powered it emits a looping
-- machine hum (the vanilla running-generator loop) from its tile. FMOD handles distance attenuation;
-- we just start the loop when a powered purifier is near the player and stop it when it powers off,
-- is removed, or leaves range. Purely presentational -> lives entirely on the client.

require "WaterPipes/Constants"
require "WaterPipes/Purifier"

WaterPipes = WaterPipes or {}
WaterPipes.PurifierSound = WaterPipes.PurifierSound or {}

local Purifier = WaterPipes.Purifier
local Sound = WaterPipes.PurifierSound

-- Tunables. Switch SOUND_NAME to "OldGeneratorLoop" for a rougher, older-motor hum.
local SOUND_NAME = "GeneratorLoop"
local DEFAULT_VOLUME = 55     -- 0..100; slider default and fallback
local SCAN_RADIUS = 14        -- tiles around the player we manage emitters within
local INTERVAL_TICKS = 60     -- ~1s at 60fps between rescans (cheap; the hum is local)

-- THE single entry point for all of the mod's audio: client-side, per-player, runtime mod options
-- (in-game Options -> Mods), persisted in ModOptions.ini. No sandbox / no restart needed. Every future
-- sound must gate on soundEnabled() and use soundVolume() (see the sound-entry-point project memory).
if PZAPI and PZAPI.ModOptions and not PZAPI.ModOptions:getOptions("WaterPipes") then
    local opts = PZAPI.ModOptions:create("WaterPipes", "IGUI_WaterPipes_Options")
    opts:addTickBox("SoundEnabled", "IGUI_WaterPipes_SoundEnabled", true, "IGUI_WaterPipes_SoundEnabled_tooltip")
    opts:addSlider("SoundVolume", "IGUI_WaterPipes_SoundVolume", 0, 100, 5, DEFAULT_VOLUME, "IGUI_WaterPipes_SoundVolume_tooltip")
    opts:addTickBox("EffectsEnabled", "IGUI_WaterPipes_EffectsEnabled", true, "IGUI_WaterPipes_EffectsEnabled_tooltip")
end

local function modOption(id)
    local group = PZAPI and PZAPI.ModOptions and PZAPI.ModOptions:getOptions("WaterPipes")
    return group and group:getOption(id) or nil
end

-- Read live so a change in the options menu takes effect on the next rescan. Safe defaults if the
-- options are not registered yet (enabled, 55%).
local function soundEnabled()
    local o = modOption("SoundEnabled")
    return not o or o:getValue() ~= false
end

local function soundVolume()
    local o = modOption("SoundVolume")
    local v = o and o:getValue() or DEFAULT_VOLUME
    return math.min(math.max(v, 0), 100) / 100
end

Sound.active = Sound.active or {}   -- key "x:y:z" -> { emitter = , channel = }

local function keyFor(sq)
    return sq:getX() .. ":" .. sq:getY() .. ":" .. sq:getZ()
end

-- Play the machine hum on a WORLD free emitter at the purifier tile. We deliberately do NOT take
-- ownership: the engine's WorldSoundManager then ticks the pooled emitter for us. (An OWNED emitter --
-- and, in practice on this build, an object's own getEmitter() loop -- must be tick()'d by hand every
-- frame or it stays silent; that was the original no-sound bug.) A looping sound keeps the pooled
-- emitter busy so it is not recycled; we re-arm each rescan if it ever stops and re-apply the volume.
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

    local seen = {}
    for dx = -SCAN_RADIUS, SCAN_RADIUS do
        for dy = -SCAN_RADIUS, SCAN_RADIUS do
            local sq = cell:getGridSquare(px + dx, py + dy, pz)
            if sq then
                local purifier = Purifier.findOnSquare(sq)
                if purifier and Purifier.isWorking(purifier) then
                    local k = keyFor(sq)
                    seen[k] = true
                    ensureLoop(sq, k)   -- (re)start the loop + refresh volume on a world free emitter
                end
            end
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
