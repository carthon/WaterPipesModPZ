-- Open-hydrant water sound (client-only). While a hydrant is open and flowing it emits a looping
-- water-on-the-ground sound from its tile. FMOD handles distance attenuation; the loop starts when a
-- flowing hydrant is near the player and stops when it closes, runs dry, is removed or leaves range.
-- Same shape and audio budget as WaterPipesPurifierSound, which owns the ModOptions group this reads.

require "WaterPipes/Hydrant"
require "WaterPipes/WaterPipesTileRegistry"

WaterPipes = WaterPipes or {}
WaterPipes.HydrantSound = WaterPipes.HydrantSound or {}

local Hydrant = WaterPipes.Hydrant
local Registry = WaterPipes.TileRegistry
local Sound = WaterPipes.HydrantSound

-- Placeholder like the sprite: the vanilla "liquid on the ground" pour, looped, reads as a hydrant
-- gushing onto the street. Swap for a dedicated loop later.
local SOUND_NAME = "PourLiquidOnGround"
local DEFAULT_VOLUME = 55     -- fallback only; the real value is the shared SoundVolume slider
local SCAN_RADIUS = 14        -- tiles around the player we manage emitters within
local INTERVAL_TICKS = 60     -- ~1s between rescans

local function modOption(id)
    local group = PZAPI and PZAPI.ModOptions and PZAPI.ModOptions:getOptions("WaterPipes")
    return group and group:getOption(id) or nil
end

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

-- Start (or re-arm) the loop on a WORLD free emitter at the hydrant tile, and re-apply the volume.
-- We do NOT own the emitter: the engine's WorldSoundManager ticks the pooled emitter for us, and the
-- loop keeps it from being recycled. (An owned emitter must be tick()'d by hand or it stays silent --
-- the original purifier no-sound bug.)
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

-- Rescan the area around the player: loop for each flowing open hydrant in range, stop the rest.
function Sound.update()
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

    -- Driven by the tile registry rather than a (2*SCAN_RADIUS+1)^2 sweep: the old scan walked 841
    -- tiles once a second scanning every object list, to manage a loop for the handful of hydrants
    -- that actually exist. See WaterPipesTileRegistry.
    local seen = {}
    for _, found in ipairs(Registry.near("hydrants", px, py, pz, SCAN_RADIUS)) do
        if Hydrant.isFlowing(found.object) then
            local sq = found.square
            local k = keyFor(sq)
            seen[k] = true
            ensureLoop(sq, k)
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

if Events and Events.OnPlayerDeath then
    Events.OnPlayerDeath.Add(function() Sound.stopAll() end)
end
if Events and Events.OnGameStop then
    Events.OnGameStop.Add(function() Sound.stopAll() end)
end

return Sound
