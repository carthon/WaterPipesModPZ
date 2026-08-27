WaterPipes = WaterPipes or {}
WaterPipes.Invalidate = WaterPipes.Invalidate or {}

require "WaterPipes/World"

local Invalidate = WaterPipes.Invalidate
local World = WaterPipes.World

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
local function scans() return WaterPipes.PipeObjectUtils end
local function field() return WaterPipes.Hydraulics end
local function walks() return WaterPipes.NetworkAccess end

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
end

-- A square the engine rebuilt while streaming: its objects were never announced one by one.
-- Note what is NOT here: the head field. Hydraulics never listened to LoadGridsquare, on the grounds
-- that a streamed-in square cannot change a zone that was solved without it. Kept as it was.
function Invalidate.squareStreamedIn(square)
    if not square then
        return
    end
    call(adapter(), "invalidateSquareVessels", square)
    call(scans(), "invalidateSquareScan", square)
    call(walks(), "invalidateAroundSquare", square)
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
    call(scans(), "invalidateScanCache")
    call(walks(), "invalidateTraversalCache")
end

-- The periodic audit found a cache disagreeing with the world, so the premise that the events are
-- sufficient is wrong somewhere and the safe response is to drop wholesale.
-- The walks are DELIBERATELY not dropped: re-walking every network costs a visible stutter once a
-- minute, and the verifier's own finding is about tile contents rather than about shape.
function Invalidate.worldVerified()
    call(adapter(), "invalidateVesselCache")
    call(scans(), "invalidateScanCache")
    call(field(), "invalidate")
end

-- A valve or a hydrant moved: the walks are priced on it, and they take the field with them.
function Invalidate.flowPathChanged()
    call(walks(), "invalidateTraversalCache")
end

-- A pump was switched, or lost power. Only the field is priced on that.
function Invalidate.pumpStateChanged()
    call(field(), "invalidate")
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
        Events.LoadGridsquare.Add(Invalidate.squareStreamedIn)
    end
end

return Invalidate
