WaterPipes = WaterPipes or {}
WaterPipes.Invalidate = WaterPipes.Invalidate or {}

require "WaterPipes/World"
require "WaterPipes/Profiler"

local Invalidate = WaterPipes.Invalidate
local World = WaterPipes.World
local Profiler = WaterPipes.Profiler

-- Who drops what, in one file.
--
-- Four caches are kept correct by events rather than by rescanning: the vessel classification
-- (ContainerAdapter), the pipe-object scan (PipeObjectUtils), the network walks (NetworkAccess) and
-- the head field (Hydraulics). Between them they exposed eleven invalidation verbs, and every site
-- that changed the world had to know which caches existed, which verb reached which, and which of them
-- cascade -- NetworkAccess.invalidateTraversalCache drops the head field too, and nothing else does.
-- Predictably, no two sites chose the same subset, and it was impossible to tell the deliberate
-- differences from the accidental ones because they were scattered across six files.
--
-- So the verbs below are named after WHAT HAPPENED, and each one names the caches it drops. The sets
-- are exactly the ones the scattered call sites used: this is a vocabulary, not a simplification. Two
-- of them differ in ways that look like oversights and are not, and they say so where they are
-- defined; correcting either is a behaviour change and belongs in its own commit, with its own
-- reasoning and its own before/after counter table.
--
-- Every cache is resolved LAZILY off the WaterPipes table and every call is guarded. That is not
-- defensiveness for its own sake: NetworkAccess and Hydraulics require the modules this one talks to,
-- so requiring them back would be a cycle, and the test harness loads some of these modules without
-- the others. A verb whose target is absent does nothing, which is what the call sites already did by
-- hand with `if Hydraulics and Hydraulics.invalidate then`.
--
-- What this does NOT replace: docs/removal-events.md established in game that FIRE destroys objects
-- without raising either removal event. No event-driven seam can see that, so the periodic drift
-- verifier stays. This gives its findings somewhere to be reported from, not a reason to delete it.

local function adapter() return WaterPipes.ContainerAdapter end
local function pipes() return WaterPipes.State end
local function scans() return WaterPipes.PipeObjectUtils end
local function field() return WaterPipes.Hydraulics end
local function walks() return WaterPipes.NetworkAccess end
local function tileRegistry() return WaterPipes.TileRegistry end   -- client-only; absent on a server

local function call(module, name, ...)
    if module and module[name] then
        module[name](...)
    end
end

-- ===== World events =====
-- Registered once, here, instead of four times in four modules. Each of those derived the object's
-- square for itself, which was three pcall(getSquare) on an event that fires around 230 times a second
-- as the world streams in; now it is one.
--
-- The order below is load order, and it does not matter: the four caches are independent and none of
-- them reads another. It is fixed only so that a future reader is not left wondering.

-- Counters, resolved off the global table like everything else here: a whole-map mark arriving often
-- on a quiet base means a watcher is chattering, and the marks would then be worth less than a sweep.
local function countPhase(name, amount)
    local Profiler = WaterPipes.Profiler
    if Profiler and Profiler.count then
        Profiler.count(name, amount or 1)
    end
end

-- Only a tile the mod has a pipe on can change what a fixture is served. Without this filter the set
-- would fill with furniture: the object events fire hundreds of times a second while the world streams.
local function markIfPiped(square)
    local State = pipes()
    if not State or not State.ensure or not square or not square.getX then
        return
    end
    local key = State.squareKey(square:getX(), square:getY(), square:getZ())
    if State.ensure().pipes[key] then
        Invalidate.waterMovedAt(key, square:getX(), square:getY(), square:getZ())
    end
end

-- An object was added to the world, or is about to leave it.
function Invalidate.objectChanged(worldObject)
    local square = World.squareOf(worldObject)
    if not square then
        -- No square to scope by. Every cache drops wholesale, which is what each of the four did on
        -- its own when it could not find one.
        Invalidate.layoutChanged()
        return
    end
    Invalidate.squareChanged(square)
end

-- Everything that knows about one tile forgets it.
function Invalidate.squareChanged(square)
    call(adapter(), "invalidateSquareVessels", square)
    call(scans(), "invalidateSquareScan", square)
    call(field(), "invalidateAroundSquare", square)
    call(walks(), "invalidateAroundSquare", square)
    markIfPiped(square)
end

-- A square the engine rebuilt while streaming: its objects were never announced one by one, and every
-- cache holding the OLD square object -- the head field included -- would go on reading the dead one.
-- Fires for every square streamed in, so the square is read and its key built ONCE for all four caches
-- and the client's tile registry; each used to read the coordinates and build the same "x:y:z" key.
function Invalidate.squareStreamedIn(square)
    if not square then
        return
    end
    local x, y, z = square:getX(), square:getY(), square:getZ()
    local key = tostring(x) .. ":" .. tostring(y) .. ":" .. tostring(z)
    call(adapter(), "invalidateVesselsAtKey", key)
    call(scans(), "invalidateScanAtKey", key)
    call(walks(), "invalidateAroundKey", key)
    call(field(), "invalidateAroundCoords", x, y, z, key)
    call(tileRegistry(), "forgetResolvedAtKey", key)
end

-- ===== What changed, in the mod's own words =====

-- A vessel crossed empty, or stopped being empty. Only the head field cares: the walks do not cache
-- amounts, and the vessel memo caches which objects are containers rather than what is in them.
function Invalidate.supplyChangedAt(square)
    if not square then
        return
    end
    local hydraulics = field()
    if not hydraulics then
        return
    end
    local drop = hydraulics.invalidateSupplyAroundSquare or hydraulics.invalidateAroundSquare
    if drop then
        drop(square)
    end
end

-- The head field around one tile, without touching anything else. Plumbing a fixture changes what the
-- zone is asked for, and nothing about its shape or its containers.
function Invalidate.headAroundSquare(square)
    if not square then
        return
    end
    call(field(), "invalidateAroundSquare", square)
end

-- Pipe was built or dismantled, or the world was read cold: everything goes.
function Invalidate.layoutChanged()
    Invalidate.everythingChanged()
    call(adapter(), "invalidateVesselCache")
    call(scans(), "invalidateScanCache")
    -- The walks drop the head field with them, which is why Hydraulics is not called separately here.
    call(walks(), "invalidateTraversalCache")
    if not walks() then
        call(field(), "invalidate")
    end
end

-- The registry was rebuilt from the world. The vessel memo is DELIBERATELY not dropped: the rebuild
-- re-reads the containers itself, and the memo remembers which objects are containers rather than
-- what they hold.
function Invalidate.registryRebuilt()
    Invalidate.everythingChanged()
    call(scans(), "invalidateScanCache")
    call(walks(), "invalidateTraversalCache")
end

-- The periodic audit found a cache disagreeing with the world, so the premise that the events are
-- sufficient is wrong somewhere and the safe response is to drop wholesale.
-- The walks are DELIBERATELY not dropped: re-walking every network costs a visible stutter once a
-- minute, and the verifier's own finding is about tile contents rather than about shape.
function Invalidate.worldVerified()
    Invalidate.everythingChanged()
    call(adapter(), "invalidateVesselCache")
    call(scans(), "invalidateScanCache")
    call(field(), "invalidate")
end

-- A valve or a hydrant moved: the walks are priced on it, and they take the field with them.
function Invalidate.flowPathChanged()
    Invalidate.everythingChanged()
    call(walks(), "invalidateTraversalCache")
end

-- A pump was switched, or lost power. Only the field is priced on that.
function Invalidate.pumpStateChanged()
    Invalidate.everythingChanged()
    call(field(), "invalidate")
end

-- ===== What moved since the last pass =====
-- Which tiles had water, shape or contents change. What reads them refreshes the fixtures of those
-- networks instead of every plumbed fixture on the map; the ten-minute sweep stays underneath as the
-- net that catches whatever raised no event at all.
--
-- Square keys, never zone ids: a zone id lives as long as one solve and does not survive an
-- invalidation, so it is a memo within a pass and useless as a stored mark. The set is a module local
-- and never State, which is persisted to ModData.

local dirtyTiles = {}
local dirtyCount = 0
local everythingDirty = false

-- Past this many tiles, walking them one at a time costs more than the sweep they stand in for.
local DIRTY_TILE_LIMIT = 64

local function coordinatesFromKey(key)
    local x, y, z = tostring(key):match("^(-?%d+):(-?%d+):(-?%d+)$")
    if not x then
        return nil
    end
    return tonumber(x), tonumber(y), tonumber(z)
end

-- Water moved on a tile. `squareKey` is the prebuilt one where the caller has it, so the hottest path
-- in the mod pays no concatenation; the coordinates are read back off the key when it does not.
function Invalidate.waterMovedAt(squareKey, x, y, z)
    if everythingDirty then
        return
    end

    local key = squareKey
    if key == nil and x and y and z then
        key = tostring(x) .. ":" .. tostring(y) .. ":" .. tostring(z)
    end
    if key == nil then
        -- Something moved and there is no saying where: the whole map is the honest answer.
        Invalidate.everythingChanged()
        return
    end
    if dirtyTiles[key] then
        return
    end
    if not (x and y and z) then
        x, y, z = coordinatesFromKey(key)
        if not x then
            Invalidate.everythingChanged()
            return
        end
    end

    if dirtyCount >= DIRTY_TILE_LIMIT then
        Invalidate.everythingChanged()
        return
    end
    dirtyTiles[key] = { x = x, y = y, z = z }
    dirtyCount = dirtyCount + 1
    countPhase("dirty: tiles marked")
end

-- A vessel's water moved without the mod moving it: a player drinking from it or pouring into it.
-- Only the marks care -- the caches remember which objects are containers, never what they hold.
function Invalidate.vesselWaterChanged(square)
    markIfPiped(square)
end

-- Too much changed to name tiles, or something changed that has no tile. Overrides the marks already
-- held: they are a subset of what the full sweep will cover anyway.
function Invalidate.everythingChanged()
    if not everythingDirty then
        countPhase("dirty: whole map marked")
    end
    everythingDirty = true
    dirtyTiles = {}
    dirtyCount = 0
end

function Invalidate.isEverythingDirty()
    return everythingDirty
end

function Invalidate.dirtyTileCount()
    return dirtyCount
end

-- Handed over and cleared in one step. The pass that consumes these moves water itself, so marks its
-- own writes raise belong to the next pass rather than to the one in progress.
function Invalidate.takeDirtyTiles()
    local taken, global = dirtyTiles, everythingDirty
    dirtyTiles = {}
    dirtyCount = 0
    everythingDirty = false
    return taken, global
end

-- ===== The supply hold =====
-- One irrigation pass is one instant of simulated time, so the field it drinks from is priced once
-- rather than once per emitter. Delegated rather than reimplemented; the counting lives in Hydraulics.

function Invalidate.holdSupply()
    call(field(), "holdSupplyInvalidation")
end

function Invalidate.releaseSupply()
    call(field(), "releaseSupplyInvalidation")
end

function Invalidate.isSupplyHeld()
    local hydraulics = field()
    return hydraulics and hydraulics.isSupplyHeld and hydraulics.isSupplyHeld() or false
end

-- Did the town supply go on or off since the last look? Reports rather than drops, because the caller
-- pairs it with another watcher and both must record their state before either acts.
function Invalidate.supplyClockChanged()
    local network = walks()
    return network and network.supplyClockChanged and network.supplyClockChanged() or false
end

if Events then
    if Events.OnObjectAdded then
        Events.OnObjectAdded.Add(Invalidate.objectChanged)
    end
    if Events.OnObjectAboutToBeRemoved then
        Events.OnObjectAboutToBeRemoved.Add(Invalidate.objectChanged)
    end
    if Events.LoadGridsquare then
        -- Timed per square at ms resolution: one call reads 0 or 1 ms, the bucket total is what counts.
        Events.LoadGridsquare.Add(function(square)
            Profiler.time("load/invalidate", Invalidate.squareStreamedIn, square)
        end)
    end
end

return Invalidate
