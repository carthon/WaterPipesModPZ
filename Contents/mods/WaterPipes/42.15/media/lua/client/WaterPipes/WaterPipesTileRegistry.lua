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
require "WaterPipes/Profiler"
require "WaterPipes/Purifier"

WaterPipes = WaterPipes or {}
WaterPipes.TileRegistry = WaterPipes.TileRegistry or {}

local Hydrant = WaterPipes.Hydrant
local Irrigation = WaterPipes.Irrigation
local PipeObjectUtils = WaterPipes.PipeObjectUtils
local Profiler = WaterPipes.Profiler
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
--
-- Measured on the medium bench scenario: the full sweep is ~69,500 bridge calls over 1,681 tiles,
-- about 1,700 per row. At 8 rows that is ~13,100 landing in one frame; at 2 it is ~3,300 spread
-- over 21 frames. The sweep then takes ~0.35 s instead of ~0.10 s, which costs nothing that
-- matters -- the registry feeds decorative FX on a five-second cadence, so a third of a second of
-- extra latency is invisible. The total is identical either way; only the worst frame moves.
local SWEEP_ROWS_PER_TICK = 2

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

-- The sweep in progress, if any; assigned by the sweep block below. Declared up here because both
-- entryFor's callers and forgetResolved close over it, and a local declared after them would leave
-- those closures bound to a nil global instead -- silently, which is the worst way to be wrong.
local pendingSweep = nil

-- A remembered tile, with the square and object already resolved.
--
-- Registry.near used to re-resolve BOTH on every read -- a getGridSquare and a full object scan, per
-- remembered tile, per caller, and five modules call it several times a second. Measured in game at
-- ~12 ms per spray-FX rebuild, on every rebuild, warm status cache or not.
--
-- Both references are dropped by forgetResolved when the tile changes underneath them, which is what
-- keeps this from being a stale-object bug: see the two events it is wired to.
local function entryFor(square, x, y, z, object)
    return { x = x, y = y, z = z, square = square, object = object }
end

-- Drop what a tile resolved to, keeping the tile itself remembered. Forgetting the tile outright
-- would blank the registry every time the player walks past a chunk boundary; forgetting only the
-- references costs one lookup on the next read.
local RESOLVED_KINDS = { "emitters", "hydrants", "purifiers" }

function Registry.forgetResolved(square)
    if not square or not square.getX then
        return
    end

    local key = keyOf(square:getX(), square:getY(), square:getZ())
    for _, kind in ipairs(RESOLVED_KINDS) do
        local entry = Registry[kind][key]
        if entry then
            entry.square = nil
            entry.object = nil
        end
        entry = pendingSweep and pendingSweep[kind][key] or nil
        if entry then
            entry.square = nil
            entry.object = nil
        end
    end
end

-- Classify one square now and record the answer. Driven by OnObjectAdded, where modData is already
-- attached -- unlike LoadGridsquare, where it is not (see the header).
--
-- Declared before the sweep block so it can be defined here, but it writes into the in-progress
-- sweep too: a sweep swaps in a freshly built set when it finishes, and without that an emitter
-- placed mid-sweep would be recorded and then thrown away seconds later.
function Registry.noteSquare(square)
    if not square or not square.getX then
        return
    end

    local x, y, z = square:getX(), square:getY(), square:getZ()
    local key = keyOf(x, y, z)
    local emitter, hydrant, purifier = classify(square)

    local targets = { Registry }
    if pendingSweep then
        targets[#targets + 1] = pendingSweep
    end
    for _, t in ipairs(targets) do
        -- A separate entry per kind, never one shared between them: each caches the object it stands
        -- for, and a tile may legally carry an emitter and a hydrant at once.
        t.emitters[key] = emitter and entryFor(square, x, y, z, emitter) or nil
        t.hydrants[key] = hydrant and entryFor(square, x, y, z, hydrant) or nil
        t.purifiers[key] = purifier and entryFor(square, x, y, z, purifier) or nil
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
                    local x, y, z = square:getX(), square:getY(), square:getZ()
                    local key = keyOf(x, y, z)
                    if emitter then sweep.emitters[key] = entryFor(square, x, y, z, emitter) end
                    if hydrant then sweep.hydrants[key] = entryFor(square, x, y, z, hydrant) end
                    if purifier then sweep.purifiers[key] = entryFor(square, x, y, z, purifier) end
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
            -- Resolved once and remembered. A miss here is a tile whose references were dropped
            -- because something changed on it, so the lookup that follows is the re-check that
            -- decides whether it still belongs in the registry at all.
            local square, object = entry.square, entry.object
            if not object then
                square = getCellSquare(entry.x, entry.y, entry.z)
                object = square and finder(square) or nil
                entry.square = square
                entry.object = object
            end
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

-- How far into the TTL window a tile's first stamp is backdated, so that emitters do not all expire
-- together. Deterministic from the tile: stable across sessions, and it needs no stored state.
--
-- The multipliers are large on purpose. A farm row is consecutive x, so a small multiplier -- the
-- (x * 7 + y * 13) used for the animation phase, where the modulus is a frame count -- would put
-- neighbours a few milliseconds apart and spread forty-seven emitters over a fraction of the window.
-- These put adjacent tiles most of a second apart instead.
local function statusPhase(x, y, z)
    return (x * 1103 + y * 2749 + z * 4111) % STATUS_TTL_MS
end

-- Irrigation.getEmitterStatus walks the whole network (once: pressure and available fluid are two
-- readings off one summary). The presentational callers ask it several times a second, per emitter,
-- for an answer that only changes when the server's minute pass runs -- so it is cached per tile
-- for STATUS_TTL_MS.
--
-- The first stamp is PHASED, and that is what stops the cost arriving in one frame. Every emitter
-- near the player is first read in the same rebuild, so without this they are all stamped together,
-- all expire together, and stay locked in step for the rest of the session. Measured in game: a
-- rebuild averaged 13.4 ms and its worst was 186 -- a factor of fourteen -- because roughly one
-- rebuild in nine recomputed all forty-seven emitters at once while the other eight were nearly free.
--
-- Backdating the first stamp by a per-tile amount breaks the convoy. It is the same total work over
-- the same three seconds; it just stops being a spike. Note this cannot show up in tools/perf, which
-- counts calls made and not when they land -- the profiler is the instrument for it.
function Registry.emitterStatus(emitter, square)
    if not emitter or not square then
        return nil
    end

    local x, y, z = square:getX(), square:getY(), square:getZ()
    local key = keyOf(x, y, z)
    local stamp = nowMs()
    local cached = statusCache[key]
    if cached and stamp and (stamp - cached.stamp) < STATUS_TTL_MS then
        return cached.status
    end

    -- A miss is where the cost is: everything else in a rebuild is table reads.
    Profiler.count("sprayfx: status recomputed", 1)
    local status = Irrigation.getEmitterStatus(emitter, square)
    if stamp then
        -- Only the FIRST sighting is phased. Afterwards the tile re-stamps at its own expiry, which
        -- is already offset from its neighbours', so the spread maintains itself.
        --
        -- Registry.invalidate clears the entry, which makes the next read a first sighting again. That
        -- is correct for what it is for: the recompute still happens immediately on that read -- a
        -- cleared entry is a miss -- and only the tile's next expiry is re-phased.
        statusCache[key] = {
            stamp = cached and stamp or (stamp - statusPhase(x, y, z)),
            status = status,
        }
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
        Profiler.time("registry/sweep", stepSweep)
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
        -- re-check in Registry.near drops it on the next read instead -- which is exactly why the
        -- resolved references have to go with it. Leaving them would hand every later read the object
        -- that is being removed, and that re-check would never run.
        Events.OnObjectAboutToBeRemoved.Add(function(object)
            local square = object and object.getSquare and object:getSquare() or nil
            if square then
                Registry.forgetResolved(square)
                Registry.invalidate(square:getX(), square:getY(), square:getZ())
            end
        end)
    end
    if Events.LoadGridsquare then
        -- Streaming rebuilds a square, which leaves any reference we hold pointing at a grid square
        -- that no longer exists. Too early to CLASSIFY here (see the header) -- but never too early to
        -- forget, which is all this does.
        Events.LoadGridsquare.Add(function(square) pcall(Registry.forgetResolved, square) end)
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
