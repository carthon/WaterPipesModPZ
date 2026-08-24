-- Standing under running water gets you wet (client-only).
--
-- A sprinkler waters the 3x3 around it and an open hydrant dumps its main over the same footprint, so
-- walking through either should soak you the way rain does -- and until now you could stand in the
-- middle of a running sprinkler indefinitely and stay bone dry.
--
-- Paced off REAL elapsed milliseconds rather than a tick count, so the rate does not ride on the
-- player's framerate: roughly a minute from dry to soaked standing still, which means crossing a
-- sprinkler at a walk leaves you damp rather than drenched.
--
-- Only ever RAISES wetness, never lowers it, so it cannot fight the engine's own drying: whichever of
-- the two wants a higher number wins, and once you step out of the water the normal drying takes over.
--
-- Client-side and local-player only, like the spray FX: your own body damage is yours to write.

require "WaterPipes/Constants"
require "WaterPipes/Hydrant"
require "WaterPipes/Irrigation"
require "WaterPipes/WaterPipesTileRegistry"

WaterPipes = WaterPipes or {}
WaterPipes.Wetness = WaterPipes.Wetness or {}

local Constants = WaterPipes.Constants
local Hydrant = WaterPipes.Hydrant
local Irrigation = WaterPipes.Irrigation
local Registry = WaterPipes.TileRegistry
local Wetness = WaterPipes.Wetness

-- ===== Tunables =====
local SOAK_MS = 60000        -- real milliseconds from bone dry to fully soaked, standing in it
local CHECK_TICKS = 15       -- ~4 checks a second: responsive enough, costs nothing
local CLOTHING_MAX = 100     -- InventoryItem wetness runs 0..100

local lastMs = nil
local tickCounter = 0

local function maxWetness()
    if CharacterStat and CharacterStat.WETNESS and CharacterStat.WETNESS.getMaximumValue then
        local ok, v = pcall(CharacterStat.WETNESS.getMaximumValue, CharacterStat.WETNESS)
        if ok and type(v) == "number" and v > 0 then
            return v
        end
    end
    return 100
end

-- The player is in the water when a running emitter sits within its own watering radius of them --
-- the emitter covers the 3x3 around itself, so being within one tile of one is being under it.
--
-- This runs four times a second, so what it asks matters. It used to scan the 3x3 for objects and
-- then ask Irrigation.getEmitterStatus, which walks the whole network -- meaning standing next
-- to a sprinkler cost a full network traversal several times a second for a yes/no. It now reads the tile
-- registry (which remembers where emitters are) and its cached status. See WaterPipesTileRegistry.
local function playerIsInSpray(player)
    local px = math.floor(player:getX())
    local py = math.floor(player:getY())
    local pz = math.floor(player:getZ())
    local r = Constants.SPRINKLER_RADIUS or 1

    for _, found in ipairs(Registry.near("hydrants", px, py, pz, r)) do
        if Hydrant.isFlowing(found.object) then
            return true
        end
    end

    -- Only the sprinkler: a drip emitter waters the soil of its own tile and would not wet a person
    -- standing on it.
    local stamp = Registry.stamp()
    for _, found in ipairs(Registry.near("emitters", px, py, pz, r)) do
        if Irrigation.isSprinkler(found.object) then
            local status = Registry.statusFor(found, stamp)
            if status and status.active then
                return true
            end
        end
    end

    return false
end

local function wetBody(player, add)
    local bd = player.getBodyDamage and player:getBodyDamage() or nil
    local parts = bd and bd.getBodyParts and bd:getBodyParts() or nil
    if not parts then
        return
    end
    local cap = maxWetness()
    for i = 0, parts:size() - 1 do
        local part = parts:get(i)
        if part and part.getWetness and part.setWetness then
            local current = part:getWetness() or 0
            if current < cap then
                part:setWetness(math.min(cap, current + add))
            end
        end
    end

    -- The aggregate stat drives the moodle; vanilla's own soak path sets both (AReallyCDDAy.lua:74).
    local stats = player.getStats and player:getStats() or nil
    if stats and CharacterStat and CharacterStat.WETNESS then
        local ok, current = pcall(stats.get, stats, CharacterStat.WETNESS)
        if ok and type(current) == "number" and current < cap then
            pcall(stats.set, stats, CharacterStat.WETNESS, math.min(cap, current + add))
        end
    end
end

local function wetClothing(player, add)
    local worn = player.getWornItems and player:getWornItems() or nil
    if not worn then
        return
    end
    for i = 0, worn:size() - 1 do
        local entry = worn:get(i)
        local item = entry and entry.getItem and entry:getItem() or nil
        if item and item.getWetness and item.setWetness then
            local current = item:getWetness() or 0
            if current < CLOTHING_MAX then
                item:setWetness(math.min(CLOTHING_MAX, current + add))
            end
        end
    end
end

function Wetness.update()
    if not isIngameState or not isIngameState() then
        lastMs = nil
        return
    end
    local player = getPlayer and getPlayer() or nil
    if not player or (player.isDead and player:isDead()) then
        lastMs = nil
        return
    end

    local now = getTimestampMs and getTimestampMs() or nil
    if not now then
        return
    end
    local previous = lastMs
    lastMs = now
    if not previous then
        return          -- first pass after a load: no interval to charge for yet
    end

    local elapsed = now - previous
    -- A paused or stuttering game can hand back a huge interval; clamp it so a single frame cannot
    -- soak the player instantly.
    if elapsed <= 0 or elapsed > 2000 then
        return
    end

    if not playerIsInSpray(player) then
        return
    end

    wetBody(player, maxWetness() * elapsed / SOAK_MS)
    wetClothing(player, CLOTHING_MAX * elapsed / SOAK_MS)
end

local function onTick()
    tickCounter = tickCounter + 1
    if tickCounter < CHECK_TICKS then
        return
    end
    tickCounter = 0
    pcall(Wetness.update)
end

if Events and Events.OnTick then
    Events.OnTick.Add(onTick)
end
if Events and Events.OnGameStop then
    Events.OnGameStop.Add(function() lastMs = nil end)
end

return Wetness
