-- Where the interesting tiles are (client-only).
--
-- Four presentational modules -- the spray FX, the wetness check, the two ambient sound loops and the
-- irrigation overlay -- all ask the same thing: "which emitters / hydrants / purifiers are near the
-- player right now?". Each answered it by sweeping a square area and scanning every tile's object list,
-- several times a second, whether or not one of those objects existed anywhere in the save.
--
-- Filled two ways, and the split is the whole design:
--   * OnObjectAdded, immediately -- so an emitter the player just built sprays at once.
--   * a full sweep on a SLOW timer -- which is what actually finds everything else.
--
-- The slow sweep is load-bearing, not belt-and-braces. Populating from LoadGridsquare looks right and
-- does not work: at the moment it fires the objects are on the square but their modData is not attached
-- yet, and every emitter/hydrant/purifier check in this mod reads modData. Sweeping later, off a timer,
-- asks the question when the answer exists.
--
-- Purely an index, and client-side: it owns no state the simulation reads, so being briefly wrong costs
-- a few seconds of a missing spray, never a wrong water level.

require "WaterPipes/Constants"
require "WaterPipes/Hydrant"
require "WaterPipes/Irrigation"
require "WaterPipes/PipeObjectUtils"
require "WaterPipes/Profiler"
require "WaterPipes/Purifier"
require "WaterPipes/World"

WaterPipes = WaterPipes or {}
WaterPipes.TileRegistry = WaterPipes.TileRegistry or {}

local Hydrant = WaterPipes.Hydrant
local Irrigation = WaterPipes.Irrigation
local PipeObjectUtils = WaterPipes.PipeObjectUtils
local Profiler = WaterPipes.Profiler
local Purifier = WaterPipes.Purifier
local Registry = WaterPipes.TileRegistry

-- How long an emitter's computed status is reused. The values behind it -- network pressure, whether the
-- line still holds water -- only move when the server runs its minute pass, but this is kept well under
-- a minute anyway so a network running dry still shows up promptly.
local STATUS_TTL_MS = 3000

-- The sweep that actually populates the registry. Radius covers the widest reader (the spray FX at 18)
-- with margin; the interval is what keeps it cheap -- the sweeps this replaced ran at 0.75 s, 1 s and
-- 0.25 s, three of them, every second of play.
-- Milliseconds, not ticks: a tick count measures how fast the machine is, not how much time has passed.
-- "300 ticks, ~5 s at 60 fps" is 2.4 s at 127, so this swept twice as often on a better PC.
local SWEEP_INTERVAL_MS = 5000
local SWEEP_RADIUS = 20
-- Rows of the sweep done per tick. Spreading it stops the rebuild landing as one visible spike -- the
-- same total work, just not all at once. The full sweep is ~69 500 bridge calls over 1 681 tiles, so 8
-- rows puts ~13 100 in one frame where 2 puts ~3 300 over 21 frames. The sweep then takes ~0.35 s
-- instead of ~0.10 s, which is invisible on a five-second cadence; only the worst frame moves.
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

local getCellSquare = WaterPipes.World.squareAt

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

-- Declared up here because entryFor's callers and forgetResolved both close over it: a local declared
-- after them would leave those closures bound to a nil global instead, silently.
local pendingSweep = nil

-- A remembered tile, with the square and object already resolved. Registry.near used to re-resolve BOTH
-- on every read -- a getGridSquare and a full object scan, per remembered tile, per caller, with five
-- modules calling several times a second.
-- Both references are dropped by forgetResolved when the tile changes underneath them, which is what
-- keeps this from being a stale-object bug.
local function entryFor(square, x, y, z, object)
    return { x = x, y = y, z = z, square = square, object = object }
end

-- Drop what a tile resolved to, keeping the tile itself remembered: forgetting the tile outright would
-- blank the registry every time the player walks past a chunk boundary.
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
-- It writes into the in-progress sweep too: a sweep swaps in a freshly built set when it finishes, and
-- without that an emitter placed mid-sweep would be recorded and then thrown away seconds later.
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
-- Rebuilt rather than merged: the registry describes the player's surroundings, so tiles left behind are
-- forgotten instead of accumulating for the whole session. Built into a separate set and swapped in at
-- the end, so a half-finished sweep never leaves the readers looking at a registry missing things.
local sweep = nil            -- in-progress sweep, nil when idle
local sweepCountdown = 0
-- Declared HERE, beside the state it belongs to: Registry.requestSweep below writes it, and a write to a
-- name whose `local` comes later in the file is a write to a GLOBAL. It compiles, it runs, and the local
-- it was meant for never changes.
local nextSweepAtMs = nil

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
    nextSweepAtMs = nil
end

-- ===== Reads =====

local FINDERS = {
    emitters = function(square)
        return Irrigation.findSprinklerOnSquare(square) or Irrigation.findDripOnSquare(square)
    end,
    hydrants = function(square) return Hydrant.findOnSquare(square) end,
    purifiers = function(square) return Purifier.findOnSquare(square) end,
}

-- Every remembered tile of `kind` within `radius` of (px, py, pz).
-- Each result carries `x`, `y`, `z` and `key` as well as the square and the object, and that is the
-- point: the registry already stored the coordinates, and handing back only the square made every
-- caller ask the engine for them again -- nine bridge calls per emitter per spray-FX rebuild, 66 000 in
-- a sixty-second window, to re-derive what was never lost.
-- Each candidate is re-checked here rather than trusted, which is what lets the registry survive the
-- cases PZ gives no event for -- a chunk unloading, a save loaded with tiles already streamed in. It is
-- affordable because the list is short. A candidate that no longer holds what it promised is dropped.
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
            -- Resolved once and remembered. A miss here is a tile whose references were dropped because something
            -- changed on it, so the lookup that follows is the re-check.
            local square, object = entry.square, entry.object
            if not object then
                square = getCellSquare(entry.x, entry.y, entry.z)
                object = square and finder(square) or nil
                entry.square = square
                entry.object = object
            end
            if object then
                results[#results + 1] = {
                    square = square, object = object,
                    x = entry.x, y = entry.y, z = entry.z, key = key,
                }
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

-- How far into the TTL window a tile's first stamp is backdated, so emitters do not all expire together.
-- Deterministic from the tile: stable across sessions, and it needs no stored state.
-- The multipliers are large on purpose. A farm row is consecutive x, so a small one would put
-- neighbours a few milliseconds apart; these put adjacent tiles most of a second apart instead.
local function statusPhase(x, y, z)
    return (x * 1103 + y * 2749 + z * 4111) % STATUS_TTL_MS
end

-- Irrigation.getEmitterStatus walks the whole network. The presentational callers ask it several times a
-- second, per emitter, for an answer that only changes when the server's minute pass runs -- so it is
-- cached per tile for STATUS_TTL_MS.
-- The first stamp is PHASED, and that is what stops the cost arriving in one frame. Every emitter near
-- the player is first read in the same rebuild, so without it they stamp together, expire together and
-- stay in step for the session: a rebuild averaged 13.4 ms and its worst was 186, because one rebuild
-- in nine recomputed all forty-seven at once. Same total work over the same three seconds, minus the
-- spike. This cannot show up in tools/perf, which counts calls made and not when they land.

-- One clock read for a whole pass. The cached path through statusOf is otherwise a table lookup and a
-- subtraction, and it was spending a pcall and a bridge call per emitter to ask what time it was.
function Registry.stamp()
    return nowMs()
end

-- The core. `entry` is a Registry.near result: object, square, x, y, z, key, all in hand.
local function statusOf(entry, stampMs)
    local emitter, square = entry.object, entry.square
    if not emitter or not square then
        return nil
    end

    local x, y, z, key = entry.x, entry.y, entry.z, entry.key
    local stamp = stampMs or nowMs()
    local cached = statusCache[key]
    if cached and stamp and (stamp - cached.stamp) < STATUS_TTL_MS then
        return cached.status
    end

    -- A miss is where the cost is: everything else in a rebuild is table reads.
    Profiler.count("sprayfx: status recomputed", 1)
    local status = Irrigation.getEmitterStatus(emitter, square)
    if stamp then
        -- Only the FIRST sighting is phased; afterwards the tile re-stamps at its own expiry, which is already
        -- offset from its neighbours', so the spread maintains itself. Registry.invalidate clears the entry,
        -- which makes the next read a first sighting again -- correct, since the recompute still happens
        -- immediately on that read and only the tile's next expiry is re-phased.
        statusCache[key] = {
            stamp = cached and stamp or (stamp - statusPhase(x, y, z)),
            status = status,
        }
    end
    return status
end

-- The fast form: hand it a Registry.near entry and the pass's stamp.
function Registry.statusFor(entry, stampMs)
    if not entry then
        return nil
    end
    return statusOf(entry, stampMs)
end

-- There is deliberately NO square-only form. Every reader gets its tiles from Registry.near, so a
-- convenience wrapper for a caller that does not exist would be a public function with no caller -- an
-- untested function however green the suite looks. That is how Adapter.verifySquareVessels shipped
-- bound to a nil global. If a caller ever genuinely holds only a square, add it back WITH a test.

-- Drop a tile's cached status so the next read recomputes it. For the moments the player expects an
-- immediate answer (opening the pump switch, toggling a hydrant) rather than up to a TTL of lag.
function Registry.invalidate(x, y, z)
    statusCache[keyOf(x, y, z)] = nil
end

-- ===== Wiring =====
-- Note what is NOT here: LoadGridsquare. It fires too early to classify anything (see the header), and
-- hooking it would only pay for a scan of every streamed tile to learn nothing.

-- Rows per tick stays frame-based on purpose: that one is about not spiking a single frame, and a
-- frame is exactly what it is spreading the work across. Only the INTERVAL is a duration.
local function onTick()
    if sweep then
        Profiler.time("registry/sweep", stepSweep)
        return
    end

    local stamp = nowMs()
    if stamp then
        if nextSweepAtMs and stamp < nextSweepAtMs then
            return
        end
        nextSweepAtMs = stamp + SWEEP_INTERVAL_MS
        beginSweep()
        return
    end

    -- No clock in this build: fall back to the frame counter rather than sweeping every tick.
    sweepCountdown = sweepCountdown - 1
    if sweepCountdown <= 0 then
        sweepCountdown = 300
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
        -- The object is still on the square here, so re-classifying now would re-add it. The lazy re-check in
        -- Registry.near drops it on the next read instead -- which is why the resolved references have to go
        -- with it, or every later read would be handed the object that is being removed.
        Events.OnObjectAboutToBeRemoved.Add(function(object)
            local square = object and object.getSquare and object:getSquare() or nil
            if square then
                Registry.forgetResolved(square)
                Registry.invalidate(square:getX(), square:getY(), square:getZ())
            end
        end)
    end
    if Events.LoadGridsquare then
        -- Streaming rebuilds a square, leaving any reference we hold pointing at one that no longer exists. Too
        -- early to CLASSIFY here (see the header), but never too early to forget.
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
