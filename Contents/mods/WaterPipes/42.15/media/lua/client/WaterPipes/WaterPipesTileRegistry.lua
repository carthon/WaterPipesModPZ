-- Where the interesting tiles are (client-only).
--
-- Four presentational modules -- the spray FX, the wetness check, the two ambient sound loops and
-- the irrigation overlay -- all need the same thing: "which emitters / hydrants / purifiers are near
-- the player right now?". Each of them answered it by sweeping a square area around the player and
-- scanning every tile's object list: 1369 tiles for the FX, 841 for each sound module, 961 for the
-- overlay, several times a second, whether or not a single one of those objects existed anywhere in
-- the save. That sweep cost more than everything it was looking for.
--
-- A registry answers the same question by remembering, so the readers pay for the handful of tiles
-- that matter instead of the thousand that do not.
--
-- It is filled two ways, and the split is the whole design:
--
--   * OnObjectAdded, immediately -- so an emitter the player just built sprays at once.
--   * a full sweep on a SLOW timer -- which is what actually finds everything else.
--
-- The slow sweep is not belt-and-braces, it is load-bearing, and the first version of this file was
-- wrong for leaving it out. Populating from LoadGridsquare looks right and does not work: at the
-- moment that event fires the objects are on the square but their modData is not attached yet, and
-- every emitter/hydrant/purifier check in this mod reads modData. The classification silently found
-- nothing and the registry stayed empty, so no spray was ever drawn. (PipeObjectUtils.isPipeObject
-- already carries a getName() fallback for exactly this reason -- that fallback is the fossil of the
-- same bug.) Sweeping later, off a timer, asks the question when the answer exists.
--
-- Five seconds of latency on a decorative spray is not worth a cleverer mechanism, and the sweep at
-- this cadence still costs a fraction of what the per-module sweeps it replaced did.
--
-- Deliberately client-side and purely an index: it owns no state the simulation reads, so being
-- briefly wrong costs a few seconds of a missing spray, never a wrong water level.

require "WaterPipes/Constants"
require "WaterPipes/Hydrant"
require "WaterPipes/Irrigation"
require "WaterPipes/PipeObjectUtils"
require "WaterPipes/Purifier"

WaterPipes = WaterPipes or {}
WaterPipes.TileRegistry = WaterPipes.TileRegistry or {}

local Hydrant = WaterPipes.Hydrant
local Irrigation = WaterPipes.Irrigation
local PipeObjectUtils = WaterPipes.PipeObjectUtils
local Purifier = WaterPipes.Purifier
local Registry = WaterPipes.TileRegistry

-- How long an emitter's computed status is reused. The values behind it (network pressure, whether
-- the line still holds water) only move when the server runs its minute pass, so anything below that
-- is asking a question whose answer cannot have changed. Kept well under a minute anyway so a network
-- running dry still shows up promptly.
local STATUS_TTL_MS = 3000

-- The sweep that actually populates the registry. Radius covers the widest reader (the spray FX at
-- 18) with margin; the interval is what keeps it cheap -- the sweeps this replaced ran at 0.75 s,
-- 1 s and 0.25 s, three of them, every second of play.
local SWEEP_INTERVAL_TICKS = 300   -- ~5 s at 60 fps
local SWEEP_RADIUS = 20
-- Rows of the sweep done per tick. Spreading it stops the rebuild from landing as one visible spike
-- in a single frame -- it is the same total work, just not all at once.
local SWEEP_ROWS_PER_TICK = 8

Registry.emitters = Registry.emitters or {}     -- ["x:y:z"] = { x, y, z }
Registry.hydrants = Registry.hydrants or {}
Registry.purifiers = Registry.purifiers or {}

local statusCache = {}                          -- ["x:y:z"] = { stamp, status }

local function keyOf(x, y, z)
    return tostring(x) .. ":" .. tostring(y) .. ":" .. tostring(z)
end

local function nowMs()
    if not getTimestampMs then
        return nil
    end
    local ok, ms = pcall(getTimestampMs)
    return ok and type(ms) == "number" and ms or nil
end

local function getCellSquare(x, y, z)
    if not getCell then
        return nil
    end
    local cell = getCell()
    return cell and cell.getGridSquare and cell:getGridSquare(x, y, z) or nil
end

-- ===== Population =====

-- What, if anything, on this square is worth remembering. One object-list scan serves all three
-- lookups; the emitter check reuses the pipe scan the other two do not need.
local function classify(square)
    local emitter, hydrant, purifier = nil, nil, nil

    for _, worldObject in ipairs(PipeObjectUtils.getPipeObjectsOnSquare(square)) do
        if not emitter and (Irrigation.isSprinkler(worldObject) or Irrigation.isDrip(worldObject)) then
            emitter = worldObject
        end
    end

    hydrant = Hydrant.findOnSquare(square)
    purifier = Purifier.findOnSquare(square)

    return emitter, hydrant, purifier
end

-- Classify one square now and record the answer. Driven by OnObjectAdded, where modData is already
-- attached -- unlike LoadGridsquare, where it is not (see the header).
--
-- Declared before the sweep block so it can be defined here, but it writes into the in-progress
-- sweep too: a sweep swaps in a freshly built set when it finishes, and without that an emitter
-- placed mid-sweep would be recorded and then thrown away seconds later.
local pendingSweep = nil        -- assigned by the sweep block below

function Registry.noteSquare(square)
    if not square or not square.getX then
        return
    end

    local x, y, z = square:getX(), square:getY(), square:getZ()
    local key = keyOf(x, y, z)
    local emitter, hydrant, purifier = classify(square)
    local entry = { x = x, y = y, z = z }

    local targets = { Registry }
    if pendingSweep then
        targets[#targets + 1] = pendingSweep
    end
    for _, t in ipairs(targets) do
        t.emitters[key] = emitter and entry or nil
        t.hydrants[key] = hydrant and entry or nil
        t.purifiers[key] = purifier and entry or nil
    end

    if not emitter then
        statusCache[key] = nil
    end
end

function Registry.noteObject(worldObject)
    local square = worldObject and worldObject.getSquare and worldObject:getSquare() or nil
    if square then
        Registry.noteSquare(square)
    end
end

function Registry.clear()
    Registry.emitters = {}
    Registry.hydrants = {}
    Registry.purifiers = {}
    statusCache = {}
end

-- ===== The sweep =====
--
-- Rebuilt rather than merged: the registry is meant to describe the player's surroundings, so tiles
-- left behind should be forgotten instead of accumulating for the whole session. Built into a
-- separate set and swapped in at the end, so a half-finished sweep never leaves the readers looking
-- at a registry that is missing things.
local sweep = nil            -- in-progress sweep, nil when idle
local sweepCountdown = 0

local function beginSweep()
    local player = getPlayer and getPlayer() or nil
    if not player then
        return
    end
    sweep = {
        px = math.floor(player:getX()),
        py = math.floor(player:getY()),
        pz = math.floor(player:getZ()),
        row = -SWEEP_RADIUS,
        emitters = {},
        hydrants = {},
        purifiers = {},
    }
    pendingSweep = sweep       -- so noteSquare writes into it too
end

local function stepSweep()
    if not sweep then
        return
    end

    local rows = 0
    while sweep.row <= SWEEP_RADIUS and rows < SWEEP_ROWS_PER_TICK do
        for dx = -SWEEP_RADIUS, SWEEP_RADIUS do
            local square = getCellSquare(sweep.px + dx, sweep.py + sweep.row, sweep.pz)
            if square then
                local emitter, hydrant, purifier = classify(square)
                if emitter or hydrant or purifier then
                    local key = keyOf(square:getX(), square:getY(), square:getZ())
                    local entry = { x = square:getX(), y = square:getY(), z = square:getZ() }
                    if emitter then sweep.emitters[key] = entry end
                    if hydrant then sweep.hydrants[key] = entry end
                    if purifier then sweep.purifiers[key] = entry end
                end
            end
        end
        sweep.row = sweep.row + 1
        rows = rows + 1
    end

    if sweep.row > SWEEP_RADIUS then
        Registry.emitters = sweep.emitters
        Registry.hydrants = sweep.hydrants
        Registry.purifiers = sweep.purifiers
        sweep = nil
        pendingSweep = nil
    end
end

-- Force a full rebuild on the next tick. For the cases where waiting out the timer would read as a
-- bug (the player just placed or removed something that changes what is on a tile).
function Registry.requestSweep()
    sweepCountdown = 0
end

-- ===== Reads =====

local FINDERS = {
    emitters = function(square)
        return Irrigation.findSprinklerOnSquare(square) or Irrigation.findDripOnSquare(square)
    end,
    hydrants = function(square) return Hydrant.findOnSquare(square) end,
    purifiers = function(square) return Purifier.findOnSquare(square) end,
}

-- Every remembered tile of `kind` within `radius` of (px, py, pz), as { square, object } pairs.
--
-- Each candidate is re-checked here rather than trusted. That is what lets the registry survive the
-- cases PZ gives us no event for -- a chunk unloading, a save loaded with tiles already streamed in --
-- and it is affordable precisely because the list is short: a handful of remembered tiles instead of
-- the thousand-tile sweep this replaces. A candidate that no longer holds what it promised is dropped.
function Registry.near(kind, px, py, pz, radius)
    local table_ = Registry[kind]
    local finder = FINDERS[kind]
    if not table_ or not finder then
        return {}
    end

    local results = {}
    local stale = nil

    for key, entry in pairs(table_) do
        if entry.z == pz
            and math.abs(entry.x - px) <= radius
            and math.abs(entry.y - py) <= radius then
            local square = getCellSquare(entry.x, entry.y, entry.z)
            local object = square and finder(square) or nil
            if object then
                results[#results + 1] = { square = square, object = object }
            elseif square then
                -- The square is loaded and the thing is gone: forget it. A square that is merely
                -- unloaded (nil) is left alone, so walking out of range does not erase the registry.
                stale = stale or {}
                stale[#stale + 1] = key
            end
        end
    end

    for _, key in ipairs(stale or {}) do
        table_[key] = nil
        statusCache[key] = nil
    end

    return results
end

-- Irrigation.getEmitterStatus walks the whole network twice (pressure, then available fluid). The
-- presentational callers ask it several times a second, per emitter, for an answer that only changes
-- when the server's minute pass runs -- so it is cached per tile for STATUS_TTL_MS.
function Registry.emitterStatus(emitter, square)
    if not emitter or not square then
        return nil
    end

    local key = keyOf(square:getX(), square:getY(), square:getZ())
    local stamp = nowMs()
    local cached = statusCache[key]
    if cached and stamp and (stamp - cached.stamp) < STATUS_TTL_MS then
        return cached.status
    end

    local status = Irrigation.getEmitterStatus(emitter, square)
    if stamp then
        statusCache[key] = { stamp = stamp, status = status }
    end
    return status
end

-- Drop a tile's cached status so the next read recomputes it. For the moments the player expects an
-- immediate answer (opening the pump switch, toggling a hydrant) rather than up to a TTL of lag.
function Registry.invalidate(x, y, z)
    statusCache[keyOf(x, y, z)] = nil
end

function Registry.invalidateAll()
    statusCache = {}
end

-- ===== Wiring =====
--
-- Note what is NOT here: LoadGridsquare. It fires too early to classify anything (see the header),
-- and hooking it would only pay for a scan of every streamed tile to learn nothing.

local function onTick()
    if sweep then
        stepSweep()
        return
    end
    sweepCountdown = sweepCountdown - 1
    if sweepCountdown <= 0 then
        sweepCountdown = SWEEP_INTERVAL_TICKS
        beginSweep()
    end
end

if Events then
    if Events.OnTick then
        Events.OnTick.Add(function() pcall(onTick) end)
    end
    if Events.OnObjectAdded then
        -- Immediate, so a freshly built emitter does not wait out the sweep timer. modData IS
        -- attached by the time this fires for a player-built object.
        Events.OnObjectAdded.Add(function(object) pcall(Registry.noteObject, object) end)
    end
    if Events.OnObjectAboutToBeRemoved then
        -- The object is still on the square here, so re-classifying now would re-add it. The lazy
        -- re-check in Registry.near drops it on the next read instead.
        Events.OnObjectAboutToBeRemoved.Add(function(object)
            local square = object and object.getSquare and object:getSquare() or nil
            if square then
                Registry.invalidate(square:getX(), square:getY(), square:getZ())
            end
        end)
    end
    if Events.OnGameStop then
        Events.OnGameStop.Add(function()
            Registry.clear()
            sweep = nil
            pendingSweep = nil
            sweepCountdown = 0
        end)
    end
end

return Registry
