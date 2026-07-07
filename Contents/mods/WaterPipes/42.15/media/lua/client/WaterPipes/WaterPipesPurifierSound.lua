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
local VOLUME = 0.55           -- 0..1 multiplier; a background hum, not dominating
local SCAN_RADIUS = 14        -- tiles around the player we manage emitters within
local INTERVAL_TICKS = 60     -- ~1s at 60fps between rescans (cheap; the hum is local)

Sound.active = Sound.active or {}   -- key "x:y:z" -> { emitter = , channel = }

local function keyFor(sq)
    return sq:getX() .. ":" .. sq:getY() .. ":" .. sq:getZ()
end

local function startSound(sq)
    local k = keyFor(sq)
    if Sound.active[k] then
        return
    end
    local world = getWorld and getWorld() or nil
    if not world or not world.getFreeEmitter then
        return
    end
    local ok, emitter = pcall(function()
        return world:getFreeEmitter(sq:getX() + 0.5, sq:getY() + 0.5, sq:getZ())
    end)
    if not ok or not emitter then
        return
    end
    -- Own the emitter so the pool does not recycle it while our loop is playing.
    pcall(function() if world.takeOwnershipOfEmitter then world:takeOwnershipOfEmitter(emitter) end end)
    local okPlay, channel = pcall(function() return emitter:playSoundLooped(SOUND_NAME) end)
    if not okPlay or not channel or channel == 0 then
        pcall(function() if world.returnOwnershipOfEmitter then world:returnOwnershipOfEmitter(emitter) end end)
        return
    end
    pcall(function() emitter:setVolume(channel, VOLUME) end)
    Sound.active[k] = { emitter = emitter, channel = channel }
end

local function stopSound(k)
    local entry = Sound.active[k]
    if not entry then
        return
    end
    Sound.active[k] = nil
    local emitter, channel = entry.emitter, entry.channel
    if emitter then
        pcall(function()
            if channel and emitter.isPlaying and emitter:isPlaying(channel) then
                emitter:stopSound(channel)
            elseif emitter.stopAll then
                emitter:stopAll()
            end
        end)
        local world = getWorld and getWorld() or nil
        pcall(function() if world and world.returnOwnershipOfEmitter then world:returnOwnershipOfEmitter(emitter) end end)
    end
end

function Sound.stopAll()
    for k in pairs(Sound.active) do
        stopSound(k)
    end
end

-- Rescan the area around the player: start a loop for each powered purifier in range, stop the rest.
function Sound.update()
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
                    startSound(sq)
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
