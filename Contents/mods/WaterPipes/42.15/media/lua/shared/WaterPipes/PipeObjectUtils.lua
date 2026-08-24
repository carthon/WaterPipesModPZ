require "WaterPipes/Constants"

WaterPipes = WaterPipes or {}
WaterPipes.PipeObjectUtils = WaterPipes.PipeObjectUtils or {}

local Constants = WaterPipes.Constants
local PipeObjectUtils = WaterPipes.PipeObjectUtils

local function getPipeModData(worldObject)
    if not worldObject or not worldObject.getModData then
        return nil
    end

    return worldObject:getModData()
end

function PipeObjectUtils.isPipeObject(worldObject)
    if not worldObject or not instanceof or not instanceof(worldObject, "IsoThumpable") then
        return false
    end

    local modData = getPipeModData(worldObject)
    if modData and modData[Constants.PIPE_MODDATA_KEY] then
        return true
    end

    return worldObject.getName and worldObject:getName() == Constants.PIPE_OBJECT_NAME
end

function PipeObjectUtils.getPipePlacement(worldObject)
    local modData = getPipeModData(worldObject) or {}
    local axis = modData[Constants.PIPE_AXIS_MODDATA_KEY]
    if not axis then
        axis = worldObject and worldObject.getNorth and worldObject:getNorth()
            and Constants.PIPE_AXIS_NS
            or Constants.PIPE_AXIS_EW
    end

    return {
        surface = modData[Constants.PIPE_SURFACE_MODDATA_KEY] or Constants.PIPE_SURFACE_FLOOR,
        axis = axis,
    }
end

function PipeObjectUtils.isWallCover(worldObject)
    if not PipeObjectUtils.isPipeObject(worldObject) then
        return false
    end
    local modData = getPipeModData(worldObject)
    return modData and modData[Constants.PIPE_RISER_MODDATA_KEY] == true or false
end

-- A vertical pipe (wall cover) on the square authorises a vertical network link upward.
function PipeObjectUtils.hasWallCoverOnSquare(square)
    if not square or not square.getObjects then
        return false
    end

    local objects = square:getObjects()
    for index = 0, objects:size() - 1 do
        if PipeObjectUtils.isWallCover(objects:get(index)) then
            return true
        end
    end

    return false
end

-- What a pipe was built from: Constants.PIPE_MATERIAL_CLAY or nil for the metal default. Also
-- returns a short string naming where the answer came from, for the dismantle log.
--
-- The stamp WaterPipesBuild writes at build time is the only source, and a pipe without one reads as
-- metal. That is not a gap worth closing: the clay recipe has never shipped, so the only pipes in
-- existence that predate the stamp are the ones on a developer's own test save, and rebuilding those
-- takes seconds.
--
-- A fallback did live here, reading the item the IsoThumpable was built from -- the save file does
-- carry "Base.MetalPipe" / "Base.ClayPipeSegment" right beside the thump sound, so the record exists.
-- getFullType() is not how you reach it: in game it returned nothing usable and every pre-stamp pipe
-- came back "unknown, assuming metal". It is gone rather than left in place, because a fallback that
-- silently does not work is worse than no fallback -- it makes the log claim a source it never used.
-- The modData read is pcall'd here specifically, unlike everywhere else in this file. This one runs
-- against an object the engine is in the middle of REMOVING, which is the one moment a world object
-- is least likely to answer normally -- and the cost of it throwing is a dismantle that errors out
-- instead of handing the player their pipe back.
function PipeObjectUtils.getBuildMaterial(worldObject)
    if not worldObject then
        return nil, "no object"
    end

    local ok, modData = pcall(getPipeModData, worldObject)
    local stamped = ok and modData and modData[Constants.PIPE_MATERIAL_MODDATA_KEY] or nil
    if stamped then
        return stamped, "modData=" .. tostring(stamped)
    end

    return nil, "no material stamp (built before the stamp existed), assuming metal"
end

function PipeObjectUtils.isClayBuilt(worldObject)
    local material, source = PipeObjectUtils.getBuildMaterial(worldObject)
    return material == Constants.PIPE_MATERIAL_CLAY, source
end

-- ===== Per-frame scan memo =====
--
-- getPipeObjectsOnSquare is the most-called world accessor in the mod by a wide margin: a single
-- network walk asks it about thirteen times per pipe tile -- the router check on the way in, then the
-- pipe check and the router check again inside tryAdd, then the pump lookup, and all of that again
-- from each of the four neighbours the tile is reached from. Every one of those calls walks the
-- square's entire object list and allocates a fresh table.
--
-- The answer cannot change unless an object is added to or removed from the square, or streaming
-- rebuilds the square itself. All three raise events, so it is memoised and dropped on those events --
-- by TILE, not wholesale.
--
-- It used to be dropped once per frame as well, and that clear undid the invalidation above it: this
-- scan is what classify() calls for every one of the 1,681 tiles the client registry sweeps, and
-- rebuilding it sixty times a second to get the same answer is the same mistake the head field and
-- the vessel classification both shipped with.
local scanMemo = {}

local function memoKey(square)
    return tostring(square:getX()) .. ":" .. tostring(square:getY()) .. ":" .. tostring(square:getZ())
end

function PipeObjectUtils.invalidateScanCache()
    scanMemo = {}
end

-- Recompute ONE tile and compare it against what was remembered. True when they agree.
--
-- This replaces the periodic wholesale drop, and the difference is the point. The drop assumed the
-- memo was wrong and paid to rebuild every tile of every network -- measured at ~190 ms of client
-- work per in-game minute, landing in one frame. This assumes the memo is RIGHT, checks a few tiles
-- to see, and says so when it is not.
--
-- The memo is left holding the fresh answer either way, so a disagreement is also a repair.
--
-- A disagreement means an object left a tile without OnObjectAboutToBeRemoved firing, which is the
-- one thing that could justify the old drop and which nobody has ever observed. If this never fires
-- across enough play, the check goes away and takes the last periodic rescan with it. If it does
-- fire, the log names the tile and the path can be hooked properly. Either way it is evidence
-- instead of nerve -- see docs/removal-events.md.
function PipeObjectUtils.verifySquareScan(square)
    if not square or not square.getObjects then
        return true
    end

    local key = memoKey(square)
    local remembered = scanMemo[key]
    if not remembered then
        return true
    end

    scanMemo[key] = nil
    local fresh = PipeObjectUtils.getPipeObjectsOnSquare(square)

    if #fresh ~= #remembered then
        return false
    end
    for index = 1, #fresh do
        if fresh[index] ~= remembered[index] then
            return false
        end
    end
    return true
end

function PipeObjectUtils.invalidateSquareScan(square)
    if square and square.getX then
        scanMemo[memoKey(square)] = nil
    end
end

-- The returned table is SHARED between callers and must be treated as READ-ONLY. Not returning a
-- private copy is half the point: the allocation it avoids is as costly as the scan it avoids.
-- The excludeObject form is the one exception -- it has to filter, so it builds its own table.
function PipeObjectUtils.getPipeObjectsOnSquare(square, excludeObject)
    if not square or not square.getObjects then
        return {}
    end

    local key = memoKey(square)
    local cached = scanMemo[key]
    if not cached then
        cached = {}
        local objects = square:getObjects()
        for index = 0, objects:size() - 1 do
            local worldObject = objects:get(index)
            if PipeObjectUtils.isPipeObject(worldObject) then
                cached[#cached + 1] = worldObject
            end
        end
        scanMemo[key] = cached
    end

    if not excludeObject then
        return cached
    end

    local results = {}
    for _, worldObject in ipairs(cached) do
        if worldObject ~= excludeObject then
            results[#results + 1] = worldObject
        end
    end
    return results
end

function PipeObjectUtils.findPipeOnSquare(square, surface, axis, excludeObject)
    for _, worldObject in ipairs(PipeObjectUtils.getPipeObjectsOnSquare(square, excludeObject)) do
        local placement = PipeObjectUtils.getPipePlacement(worldObject)
        if placement.surface == surface and placement.axis == axis then
            return worldObject
        end
    end

    return nil
end

function PipeObjectUtils.getPipeOnSquare(square)
    return PipeObjectUtils.getPipeObjectsOnSquare(square)[1]
end

local function squareAt(x, y, z)
    if not getCell then
        return nil
    end
    local cell = getCell()
    return cell and cell.getGridSquare and cell:getGridSquare(x, y, z) or nil
end

-- Which wall edges have a riser (vertical pipe) on square (x,y,z).
local function riserEdgesAt(x, y, z)
    local edges = { N = false, W = false }
    local square = squareAt(x, y, z)
    if not square then
        return edges
    end
    for _, worldObject in ipairs(PipeObjectUtils.getPipeObjectsOnSquare(square)) do
        if PipeObjectUtils.isWallCover(worldObject) then
            local modData = getPipeModData(worldObject)
            local edge = modData and modData[Constants.PIPE_RISER_EDGE_MODDATA_KEY]
            if edge == "W" then
                edges.W = true
            else
                edges.N = true
            end
        end
    end
    return edges
end

-- Coordinates connected to (x,y,z) through a vertical pipe (wall riser). A riser sits on the LOWER
-- floor and climbs its wall to the floor above on BOTH sides of that wall:
--   N riser at (rx,ry,rz) links (rx,ry,rz) <-> (rx,ry,rz+1) and (rx,ry-1,rz+1)
--   W riser at (rx,ry,rz) links (rx,ry,rz) <-> (rx,ry,rz+1) and (rx-1,ry,rz+1)
-- Returns both the upward links (risers on this square) and the downward links (risers on the
-- floor below whose climb reaches this square), so traversal works in both directions.
function PipeObjectUtils.getRiserVerticalNeighborCoords(x, y, z)
    local coords = {}
    local function add(nx, ny, nz)
        coords[#coords + 1] = { x = nx, y = ny, z = nz }
    end

    local here = riserEdgesAt(x, y, z)
    if here.N then
        add(x, y, z + 1)
        add(x, y - 1, z + 1)
    end
    if here.W then
        add(x, y, z + 1)
        add(x - 1, y, z + 1)
    end

    if riserEdgesAt(x, y, z - 1).N or riserEdgesAt(x, y, z - 1).W then
        add(x, y, z - 1)
    end
    if riserEdgesAt(x, y + 1, z - 1).N then
        add(x, y + 1, z - 1)
    end
    if riserEdgesAt(x + 1, y, z - 1).W then
        add(x + 1, y, z - 1)
    end

    return coords
end

-- The scan memo's invalidation. Object add/remove clears the square it happened on; LoadGridsquare
-- clears a square the world has just rebuilt underneath us, which is the case the per-frame clear was
-- really guarding and the only one it caught that these do not. The per-minute pass drops the lot as a
-- backstop for anything not thought of here.
if Events then
    local function invalidateForObject(object)
        local square = object and object.getSquare and object:getSquare() or nil
        if square then
            PipeObjectUtils.invalidateSquareScan(square)
        else
            PipeObjectUtils.invalidateScanCache()
        end
    end

    if Events.OnObjectAdded then Events.OnObjectAdded.Add(invalidateForObject) end
    if Events.OnObjectAboutToBeRemoved then Events.OnObjectAboutToBeRemoved.Add(invalidateForObject) end
    if Events.LoadGridsquare then
        Events.LoadGridsquare.Add(function(square) pcall(PipeObjectUtils.invalidateSquareScan, square) end)
    end
end

function PipeObjectUtils.getSquareFromWorldObjects(worldobjects)
    if not worldobjects then
        return nil
    end

    for _, worldObject in ipairs(worldobjects) do
        if worldObject and worldObject.getSquare and worldObject:getSquare() then
            return worldObject:getSquare()
        end
    end

    return nil
end
