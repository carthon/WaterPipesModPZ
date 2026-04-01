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
