WaterPipes = WaterPipes or {}
WaterPipes.ContainerAdapter = WaterPipes.ContainerAdapter or {}

require "WaterPipes/Constants"
require "WaterPipes/EndpointObjects"
require "WaterPipes/State"

local Constants = WaterPipes.Constants
local Adapter = WaterPipes.ContainerAdapter
local EndpointObjects = WaterPipes.EndpointObjects
local State = WaterPipes.State

local function readNumber(methodOwner, methodName)
    if not methodOwner or not methodOwner[methodName] then
        return nil
    end

    local ok, value = pcall(methodOwner[methodName], methodOwner)
    if ok and type(value) == "number" then
        return value
    end

    return nil
end

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

local function getSpriteName(worldObject)
    if not worldObject then
        return nil
    end

    if worldObject.getSprite and worldObject:getSprite() and worldObject:getSprite().getName then
        return worldObject:getSprite():getName()
    end

    if worldObject.getSpriteName then
        local ok, spriteName = pcall(worldObject.getSpriteName, worldObject)
        if ok and type(spriteName) == "string" then
            return spriteName
        end
    end

    return nil
end

local function getWorldFluidContainer(worldObject)
    if not worldObject or not worldObject.getFluidContainer then
        return nil
    end

    local ok, fluidContainer = pcall(worldObject.getFluidContainer, worldObject)
    if ok then
        return fluidContainer
    end

    return nil
end

local function isExcludedWorldObject(worldObject)
    if not worldObject or not worldObject.getModData then
        return false
    end

    local modData = worldObject:getModData()
    return modData and modData[Constants.ADAPTER_SOURCE_MODDATA_KEY] == true or false
end

local function addUniqueObject(results, seen, worldObject)
    if not worldObject then
        return
    end

    local key = tostring(worldObject)
    if seen[key] then
        return
    end

    seen[key] = true
    results[#results + 1] = worldObject
end

local function collectRelatedWorldObjects(worldObject)
    local results = {}
    local seen = {}

    addUniqueObject(results, seen, worldObject)

    if worldObject and worldObject.getSpriteGridObjectsIncludingSelf and ArrayList and ArrayList.new then
        local objects = ArrayList.new()
        local ok = pcall(worldObject.getSpriteGridObjectsIncludingSelf, worldObject, objects)
        if ok and objects and objects.size then
            for index = 0, objects:size() - 1 do
                addUniqueObject(results, seen, objects:get(index))
            end
        end
    end

    return results
end

local function getRawWorldFluidCapacity(worldObject)
    return readNumber(worldObject, "getFluidCapacity")
        or readNumber(worldObject, "getReserveWaterMax")
        or readNumber(getWorldFluidContainer(worldObject), "getCapacity")
end

local function getRawWorldFluidAmount(worldObject)
    return readNumber(worldObject, "getFluidAmount")
        or readNumber(worldObject, "getReserveWaterAmount")
        or readNumber(getWorldFluidContainer(worldObject), "getAmount")
        or 0
end

local function readRawWorldFluidType(worldObject)
    local fluidContainer = getWorldFluidContainer(worldObject)
    if fluidContainer and fluidContainer.getPrimaryFluid then
        local ok, primaryFluid = pcall(fluidContainer.getPrimaryFluid, fluidContainer)
        if ok and primaryFluid and primaryFluid.getFluidTypeString then
            local okType, fluidTypeString = pcall(primaryFluid.getFluidTypeString, primaryFluid)
            if okType and type(fluidTypeString) == "string" then
                return fluidTypeString
            end
        end
    end

    local tainted = readBoolean(worldObject, "isTaintedWater")
    if tainted ~= nil and tainted then
        return "TaintedWater"
    end

    if getRawWorldFluidAmount(worldObject) > 0 and readBoolean(worldObject, "hasWater") then
        return "Water"
    end

    return nil
end

local function getDirectWorldFluidKind(worldObject)
    if not worldObject then
        return false
    end

    if isExcludedWorldObject(worldObject) then
        return false
    end

    if instanceof and instanceof(worldObject, "IsoWorldInventoryObject") then
        return false
    end

    local fluidContainer = getWorldFluidContainer(worldObject)
    local hasReserveWater = worldObject.getReserveWaterMax or worldObject.getReserveWaterAmount or worldObject.setReserveWaterAmount
    if not fluidContainer and not hasReserveWater then
        return false
    end

    local capacity = getRawWorldFluidCapacity(worldObject)
    if not capacity or capacity <= 0 or capacity >= Constants.MAX_FINITE_FLUID_CAPACITY then
        return false
    end

    if fluidContainer or hasReserveWater then
        return "worldFluid"
    end

    return false
end

local function resolveFluidTarget(worldObject)
    if isExcludedWorldObject(worldObject) then
        return worldObject
    end

    local bestObject = nil
    local bestCapacity = -1

    for _, candidate in ipairs(collectRelatedWorldObjects(worldObject)) do
        local capacity = getRawWorldFluidCapacity(candidate)
        if capacity and capacity > bestCapacity then
            bestObject = candidate
            bestCapacity = capacity
        elseif not bestObject then
            local hasFluidContainer = getWorldFluidContainer(candidate) ~= nil
            local hasFluidMethod = candidate.getFluidCapacity or candidate.getReserveWaterMax or candidate.setReserveWaterAmount
            if hasFluidContainer or hasFluidMethod then
                bestObject = candidate
            end
        end
    end

    return bestObject or worldObject
end

local function getObjectContainerAt(worldObject, containerIndex)
    if worldObject.getContainerByIndex then
        local ok, container = pcall(worldObject.getContainerByIndex, worldObject, containerIndex)
        if ok then
            return container
        end
    end

    if containerIndex == 0 and worldObject.getContainer then
        local ok, container = pcall(worldObject.getContainer, worldObject)
        if ok then
            return container
        end
    end

    return nil
end

local function getObjectContainerCount(worldObject)
    if worldObject.getContainerCount then
        local ok, count = pcall(worldObject.getContainerCount, worldObject)
        if ok and type(count) == "number" then
            return count
        end
    end

    if worldObject.getContainer then
        local container = getObjectContainerAt(worldObject, 0)
        if container then
            return 1
        end
    end

    return 0
end

function Adapter.getWorldFluidKind(worldObject)
    if not worldObject then
        return false
    end

    worldObject = resolveFluidTarget(worldObject)

    if isExcludedWorldObject(worldObject) then
        return false
    end

    if instanceof and instanceof(worldObject, "IsoWorldInventoryObject") then
        return false
    end

    if not getWorldFluidContainer(worldObject) and not worldObject.getFluidCapacity then
        return false
    end

    local capacity = Adapter.readWorldFluidCapacity(worldObject)
    if not capacity or capacity <= 0 or capacity >= Constants.MAX_FINITE_FLUID_CAPACITY then
        return false
    end

    local spriteName = getSpriteName(worldObject)
    local props = worldObject.getSprite and worldObject:getSprite() and worldObject:getSprite():getProperties() or nil

    if props and (props:has("CustomName") or props:has("GroupName") or props:has("IsMoveAble")) then
        return "worldFluid"
    end

    if spriteName then
        return "worldFluid"
    end

    if worldObject.getName and worldObject:getName() then
        return "worldFluid"
    end

    if worldObject.getFluidUiName then
        return "worldFluid"
    end

    return false
end

function Adapter.readWorldFluidCapacity(worldObject)
    worldObject = resolveFluidTarget(worldObject)
    return getRawWorldFluidCapacity(worldObject)
end

function Adapter.readWorldFluidAmount(worldObject)
    worldObject = resolveFluidTarget(worldObject)
    return getRawWorldFluidAmount(worldObject)
end

function Adapter.readWorldFluidType(worldObject)
    worldObject = resolveFluidTarget(worldObject)
    local fluidContainer = getWorldFluidContainer(worldObject)
    if fluidContainer and fluidContainer.getPrimaryFluid then
        local ok, primaryFluid = pcall(fluidContainer.getPrimaryFluid, fluidContainer)
        if ok and primaryFluid and primaryFluid.getFluidTypeString then
            local okType, fluidTypeString = pcall(primaryFluid.getFluidTypeString, primaryFluid)
            if okType and type(fluidTypeString) == "string" then
                return fluidTypeString
            end
        end
    end

    local tainted = readBoolean(worldObject, "isTaintedWater")
    if tainted ~= nil and tainted then
        return "TaintedWater"
    end

    if Adapter.readWorldFluidAmount(worldObject) > 0 and readBoolean(worldObject, "hasWater") then
        return "Water"
    end

    return nil
end

function Adapter.writeWorldFluidAmount(worldObject, fluidAmount, fluidTypeName)
    if not worldObject then
        return false
    end

    worldObject = resolveFluidTarget(worldObject)

    if worldObject.setReserveWaterAmount or worldObject.getReserveWaterMax then
        local reserveCapacity = readNumber(worldObject, "getReserveWaterMax") or 0
        local clampedAmount = math.max(math.min(fluidAmount or 0, reserveCapacity > 0 and reserveCapacity or (fluidAmount or 0)), 0)

        if worldObject.setReserveWaterAmount then
            local ok = pcall(worldObject.setReserveWaterAmount, worldObject, clampedAmount)
            if not ok then
                return false
            end
        else
            return false
        end

        if worldObject.setTaintedWater then
            pcall(worldObject.setTaintedWater, worldObject, clampedAmount > 0 and fluidTypeName == "TaintedWater")
        end

        if worldObject.sync then
            pcall(worldObject.sync, worldObject)
        end

        if worldObject.transmitModData then
            pcall(worldObject.transmitModData, worldObject)
        end

        return true
    end

    local fluidContainer = getWorldFluidContainer(worldObject)
    local cleared = false

    if worldObject.emptyFluid then
        cleared = pcall(worldObject.emptyFluid, worldObject)
    elseif fluidContainer and fluidContainer.removeFluid then
        cleared = pcall(fluidContainer.removeFluid, fluidContainer)
    end

    if not cleared then
        return false
    end

    if fluidAmount > 0 and fluidTypeName then
        local fluidType = nil
        if fluidTypeName == "Water" then
            fluidType = (FluidType and FluidType.Water) or (Fluid and Fluid.Water)
        elseif fluidTypeName == "TaintedWater" then
            fluidType = (FluidType and FluidType.TaintedWater) or (Fluid and Fluid.TaintedWater)
        elseif FluidType.FromNameLower then
            fluidType = FluidType.FromNameLower(string.lower(fluidTypeName))
        elseif Fluid and Fluid.FromNameLower then
            fluidType = Fluid.FromNameLower(string.lower(fluidTypeName))
        end

        if not fluidType then
            return false
        end

        local ok = false
        if worldObject.addFluid then
            ok = pcall(worldObject.addFluid, worldObject, fluidType, fluidAmount)
        elseif fluidContainer and fluidContainer.addFluid then
            ok = pcall(fluidContainer.addFluid, fluidContainer, fluidType, fluidAmount)
        end

        if not ok then
            return false
        end
    end

    if worldObject.sync then
        pcall(worldObject.sync, worldObject)
    end

    if worldObject.transmitModData then
        pcall(worldObject.transmitModData, worldObject)
    end

    return true
end

function Adapter.readCapacity(container)
    return readNumber(container, "getCapacity")
        or readNumber(container, "getMaxCapacity")
end

function Adapter.readWaterAmount(container)
    return readNumber(container, "getWaterAmount")
        or readNumber(container, "getFluidAmount")
        or 0
end

function Adapter.writeWaterAmount(container, waterAmount)
    if container.setWaterAmount then
        local ok = pcall(container.setWaterAmount, container, waterAmount)
        if ok then
            return true
        end
    end

    if container.setFluidAmount then
        local ok = pcall(container.setFluidAmount, container, waterAmount)
        if ok then
            return true
        end
    end

    return false
end

function Adapter.writeDescriptorWaterAmount(descriptor, fluidAmount, fluidTypeName)
    if not descriptor then
        return false
    end

    if descriptor.fluidMode == "worldObject" then
        return Adapter.writeWorldFluidAmount(descriptor.object, fluidAmount, fluidTypeName)
    end

    if descriptor.container then
        local ok = Adapter.writeWaterAmount(descriptor.container, fluidAmount)
        if ok and descriptor.container.setTaintedWater then
            pcall(descriptor.container.setTaintedWater, descriptor.container, fluidTypeName == "TaintedWater")
        end
        return ok
    end

    return false
end

function Adapter.isWaterCandidate(container)
    if not container then
        return false
    end

    local capacity = Adapter.readCapacity(container)
    if not capacity or capacity <= 0 then
        return false
    end

    if container.isWaterSource then
        local ok, isWaterSource = pcall(container.isWaterSource, container)
        if ok and isWaterSource then
            return true
        end
    end

    if container.getType then
        local ok, containerType = pcall(container.getType, container)
        if ok and type(containerType) == "string" then
            local lowered = string.lower(containerType)
            if string.find(lowered, "water", 1, true) then
                return true
            end
        end
    end

    return Adapter.readWaterAmount(container) >= 0
end

function Adapter.collectSquareContainers(square)
    local result = {}

    if not square or not square.getObjects then
        return result
    end

    local objects = square:getObjects()
    if not objects or not objects.size then
        return result
    end

    local x = square:getX()
    local y = square:getY()
    local z = square:getZ()
    local squareKey = State.squareKey(x, y, z)

    for objectIndex = 0, objects:size() - 1 do
        local worldObject = objects:get(objectIndex)
        if not EndpointObjects.isEndpointCandidate(worldObject) then
            local fluidKind = getDirectWorldFluidKind(worldObject)

            if fluidKind then
                local capacity = getRawWorldFluidCapacity(worldObject)
                if capacity and capacity > 0 then
                    local key = squareKey .. ":" .. tostring(objectIndex) .. ":fluid"
                    result[key] = {
                        key = key,
                        squareKey = squareKey,
                        x = x,
                        y = y,
                        z = z,
                        objectIndex = objectIndex,
                        containerIndex = -1,
                        capacity = capacity,
                        waterAmount = getRawWorldFluidAmount(worldObject) or 0,
                        fluidType = readRawWorldFluidType(worldObject),
                        kind = "worldFluid",
                        fluidMode = "worldObject",
                        object = worldObject,
                    }
                end
            end
        end
    end

    return result
end
