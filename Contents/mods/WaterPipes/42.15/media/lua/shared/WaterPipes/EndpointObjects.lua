WaterPipes = WaterPipes or {}
WaterPipes.EndpointObjects = WaterPipes.EndpointObjects or {}

require "WaterPipes/Constants"
require "WaterPipes/PipeObjectUtils"

local EndpointObjects = WaterPipes.EndpointObjects
local PipeObjectUtils = WaterPipes.PipeObjectUtils

local function readBoolean(methodOwner, methodName)
    if not methodOwner or not methodOwner[methodName] then
        return nil
    end

    local ok, value = pcall(methodOwner[methodName], methodOwner)
    if ok and type(value) == "boolean" then
        return value
    end

    return nil
end

local function getSpriteProperties(worldObject)
    if not worldObject or not worldObject.getSprite then
        return nil
    end

    local sprite = worldObject:getSprite()
    if not sprite or not sprite.getProperties then
        return nil
    end

    return sprite:getProperties()
end

local function hasWaterPipedFlag(worldObject)
    local props = getSpriteProperties(worldObject)
    if not props then
        return false
    end

    if IsoFlagType and props.has and props:has(IsoFlagType.waterPiped) then
        return true
    end

    if props.Is and props:Is("waterPiped") then
        return true
    end

    return false
end

local function hasEndpointModData(worldObject)
    if not worldObject or not worldObject.getModData then
        return false
    end

    local modData = worldObject:getModData()
    if not modData then
        return false
    end

    if modData.canBeWaterPiped ~= nil then
        return true
    end

    if modData.usesExternalWaterSource == true then
        return true
    end

    return false
end

function EndpointObjects.isEndpointCandidate(worldObject)
    if not worldObject then
        return false
    end

    if PipeObjectUtils.isPipeObject(worldObject) then
        return false
    end

    if instanceof and instanceof(worldObject, "IsoWorldInventoryObject") then
        return false
    end

    if not worldObject.getSquare or not worldObject:getSquare() then
        return false
    end

    if hasWaterPipedFlag(worldObject) then
        return true
    end

    if hasEndpointModData(worldObject) then
        return true
    end

    local usesExternalWaterSource = readBoolean(worldObject, "isUsesExternalWaterSource")
        or readBoolean(worldObject, "getUsesExternalWaterSource")
    if usesExternalWaterSource then
        return true
    end

    return false
end

function EndpointObjects.findOnSquare(square)
    local endpoints = EndpointObjects.collectOnSquare(square)
    return endpoints[1]
end

function EndpointObjects.collectOnSquare(square)
    if not square or not square.getObjects then
        return {}
    end

    local results = {}
    local objects = square:getObjects()
    for index = 0, objects:size() - 1 do
        local worldObject = objects:get(index)
        if EndpointObjects.isEndpointCandidate(worldObject) then
            results[#results + 1] = worldObject
        end
    end

    return results
end

function EndpointObjects.findInWorldObjects(worldobjects)
    if not worldobjects then
        return nil
    end

    for _, worldObject in ipairs(worldobjects) do
        if EndpointObjects.isEndpointCandidate(worldObject) then
            return worldObject
        end
    end

    local square = PipeObjectUtils.getSquareFromWorldObjects(worldobjects)
    if square then
        return EndpointObjects.findOnSquare(square)
    end

    return nil
end
