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

-- A vertical pipe occupies a whole tile and links the floor network to the tile above it.
function PipeObjectUtils.isVertical(worldObject)
    if not PipeObjectUtils.isPipeObject(worldObject) then
        return false
    end
    local modData = getPipeModData(worldObject)
    return modData and modData[Constants.PIPE_RISER_MODDATA_KEY] == true or false
end

-- Back-compat alias (old name).
function PipeObjectUtils.isWallCover(worldObject)
    return PipeObjectUtils.isVertical(worldObject)
end

-- A vertical pipe on the square authorises a vertical network link upward.
function PipeObjectUtils.hasVerticalOnSquare(square)
    if not square or not square.getObjects then
        return false
    end

    local objects = square:getObjects()
    for index = 0, objects:size() - 1 do
        if PipeObjectUtils.isVertical(objects:get(index)) then
            return true
        end
    end

    return false
end
PipeObjectUtils.hasWallCoverOnSquare = PipeObjectUtils.hasVerticalOnSquare

function PipeObjectUtils.getPipeObjectsOnSquare(square, excludeObject)
    if not square or not square.getObjects then
        return {}
    end

    local results = {}
    local objects = square:getObjects()
    for index = 0, objects:size() - 1 do
        local worldObject = objects:get(index)
        if worldObject ~= excludeObject and PipeObjectUtils.isPipeObject(worldObject) then
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

-- A vertical pipe on (x,y,z) links the floor network to the tile directly above it. The reverse
-- link (from the tile above back down into the vertical) is the SAME edge -- added bidirectionally
-- when the graph connects the two nodes -- so we only emit the upward coordinate here.
function PipeObjectUtils.getRiserVerticalNeighborCoords(x, y, z)
    local coords = {}
    if PipeObjectUtils.hasVerticalOnSquare(squareAt(x, y, z)) then
        coords[#coords + 1] = { x = x, y = y, z = z + 1 }
    end
    return coords
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
