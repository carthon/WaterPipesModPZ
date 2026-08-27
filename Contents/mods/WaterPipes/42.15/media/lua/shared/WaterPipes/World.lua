WaterPipes = WaterPipes or {}
WaterPipes.World = WaterPipes.World or {}

local World = WaterPipes.World

-- The mod's one reach into the cell.
--
-- This body was copied into ten files -- Hydraulics, NetworkAccess, Irrigation, Pump, TileRegistry,
-- WaterPipeSystem, EndpointAdapterSource, PipeAutotile, PipeObjectUtils and PurifierWindow -- under
-- four different names, plus two more copies that were never called at all. Nine were identical; the
-- tenth had a guard the others lacked. That guard is kept here, so every caller now has it.
--
-- REQUIRES NOTHING, deliberately. It can be the first line of any module's require block, it cannot
-- take part in a cycle, and it loads under every shim in tools/conservation.
--
-- Three things a caller has to know:
--
--   1. `getCell` is resolved AND called on every invocation, never captured at load. Some callers run
--      before the world exists, and the test suite runs with no world at all -- four of its files
--      never define `getCell` and six define it returning nil. A load-time capture or an assert here
--      would take all of them out at once.
--   2. It NEVER memoises. Two calls for the same coordinates return whatever the cell returns, which
--      may be two different handles. Hydraulics keys its zone cache off square coordinates and its
--      test asserts solution-table identity precisely because squares are not stable; a memo here
--      would make those assertions pass for the wrong reason.
--   3. It returns nil and never throws. No world, no cell, a cell that cannot answer, a nil
--      coordinate, a square already detached from the map -- all the same answer, because to every
--      caller they mean the same thing: there is nothing there to work with.
--
-- Square LOOKUP only. Reading what stands on a square belongs to PipeObjectUtils or to the appliance
-- that cares. Nothing here should grow a `hasPipeAt`.

-- The square at these coordinates, or nil.
function World.squareAt(x, y, z)
    if x == nil or y == nil or z == nil or not getCell then
        return nil
    end

    local cell = getCell()
    if not cell or not cell.getGridSquare then
        return nil
    end

    return cell:getGridSquare(x, y, z)
end

-- x, y, z of a square, or nil. Guarded because this runs against squares handed over by removal
-- events, which may already be detached.
function World.coordsOf(square)
    if not square or not square.getX then
        return nil
    end

    local okX, x = pcall(square.getX, square)
    local okY, y = pcall(square.getY, square)
    local okZ, z = pcall(square.getZ, square)
    if not okX or not okY or not okZ or x == nil or y == nil or z == nil then
        return nil
    end

    return x, y, z
end

-- The square an object stands on, or nil. Same reason for the guard.
function World.squareOf(worldObject)
    if not worldObject or not worldObject.getSquare then
        return nil
    end

    local ok, square = pcall(worldObject.getSquare, worldObject)
    return ok and square or nil
end

-- The square one level up, or nil.
function World.above(square)
    local x, y, z = World.coordsOf(square)
    if not x then
        return nil
    end

    return World.squareAt(x, y, z + 1)
end

return World
