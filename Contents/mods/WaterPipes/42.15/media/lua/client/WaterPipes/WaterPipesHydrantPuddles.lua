-- Open-hydrant puddle decal (client-only). While a hydrant is open and flowing, a shallow-water
-- overlay is painted on the 3x3 around it, so the spill is visible. When it closes, runs dry, is
-- removed, or leaves range, the puddles clear.
--
-- Purely presentational, so it never becomes world state: each client paints its own puddles from the
-- synced open/reserve state and removes them locally (AddTileObject + removeFromSquare, no transmit).
-- Nothing is sent, nothing needs to persist -- and because the manager reconciles the whole scan area
-- every pass, any decal that a chunk happened to save is swept the first time the area is scanned.
--
-- Same scan shape and radius as WaterPipesHydrantSound; the two are independent (sound is audio,
-- this is visual).

require "WaterPipes/Constants"
require "WaterPipes/Hydrant"

WaterPipes = WaterPipes or {}
WaterPipes.HydrantPuddles = WaterPipes.HydrantPuddles or {}

local Constants = WaterPipes.Constants
local Hydrant = WaterPipes.Hydrant
local Puddles = WaterPipes.HydrantPuddles

local SCAN_RADIUS = 14        -- tiles around the player we manage decals within (matches the sound)
local INTERVAL_TICKS = 60     -- ~1s between rescans

local function keyFor(x, y, z)
    return x .. ":" .. y .. ":" .. z
end

-- The puddle decal on a square, if any. Ours are flagged in modData so we only ever touch our own.
local function puddleOn(sq)
    local objects = sq:getObjects()
    for i = 0, objects:size() - 1 do
        local o = objects:get(i)
        local md = o.getModData and o:getModData() or nil
        if md and md[Constants.HYDRANT_PUDDLE_MODDATA_KEY] then
            return o
        end
    end
    return nil
end

local function addPuddle(sq)
    if puddleOn(sq) then
        return
    end
    local ok, obj = pcall(IsoObject.new, sq, Constants.HYDRANT_PUDDLE_SPRITE)
    if not ok or not obj then
        return
    end
    local md = obj.getModData and obj:getModData() or nil
    if md then
        md[Constants.HYDRANT_PUDDLE_MODDATA_KEY] = true
    end
    pcall(function() sq:AddTileObject(obj) end)   -- local add only; never transmitted
end

local function removePuddle(sq)
    local obj = puddleOn(sq)
    if obj then
        pcall(function() obj:removeFromSquare() end)   -- local remove only
    end
end

-- Reconcile the whole scan area: paint the 3x3 of every flowing hydrant, clear every other puddle.
function Puddles.update()
    local player = getPlayer and getPlayer() or nil
    local cell = getCell and getCell() or nil
    if not player or not cell then
        return
    end

    local px = math.floor(player:getX())
    local py = math.floor(player:getY())
    local pz = math.floor(player:getZ())

    -- Squares that SHOULD be wet: the 3x3 around each flowing open hydrant in range.
    local wanted = {}
    for dx = -SCAN_RADIUS, SCAN_RADIUS do
        for dy = -SCAN_RADIUS, SCAN_RADIUS do
            local sq = cell:getGridSquare(px + dx, py + dy, pz)
            if sq then
                local hydrant = Hydrant.findOnSquare(sq)
                if hydrant and Hydrant.isFlowing(hydrant) then
                    local hx, hy, hz = sq:getX(), sq:getY(), sq:getZ()
                    for ox = -1, 1 do
                        for oy = -1, 1 do
                            wanted[keyFor(hx + ox, hy + oy, hz)] = true
                        end
                    end
                end
            end
        end
    end

    -- Add where wanted and missing; clear where present and not wanted (closed hydrants + orphans).
    for dx = -SCAN_RADIUS, SCAN_RADIUS do
        for dy = -SCAN_RADIUS, SCAN_RADIUS do
            local sq = cell:getGridSquare(px + dx, py + dy, pz)
            if sq then
                local should = wanted[keyFor(sq:getX(), sq:getY(), sq:getZ())]
                if should then
                    addPuddle(sq)
                elseif puddleOn(sq) then
                    removePuddle(sq)
                end
            end
        end
    end
end

-- Clear every puddle we can currently see. Used on teardown so none linger past a session.
function Puddles.clearAll()
    local player = getPlayer and getPlayer() or nil
    local cell = getCell and getCell() or nil
    if not player or not cell then
        return
    end
    local px, py, pz = math.floor(player:getX()), math.floor(player:getY()), math.floor(player:getZ())
    for dx = -SCAN_RADIUS, SCAN_RADIUS do
        for dy = -SCAN_RADIUS, SCAN_RADIUS do
            local sq = cell:getGridSquare(px + dx, py + dy, pz)
            if sq then
                removePuddle(sq)
            end
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
    pcall(Puddles.update)
end

if Events and Events.OnTick then
    Events.OnTick.Add(onTick)
end

if Events and Events.OnGameStop then
    Events.OnGameStop.Add(function() pcall(Puddles.clearAll) end)
end

return Puddles
