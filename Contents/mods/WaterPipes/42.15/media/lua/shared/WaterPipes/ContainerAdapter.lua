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

-- Water appliances (washing machines) hold a FluidContainer inherited from IsoObject, so the
-- duck-typed detection below would adopt them as network STORAGE and rebalanceSummary would overwrite
-- their water every tick -- so they could never reach the level they need to run. They are consumers,
-- not vessels: EndpointObjects recognises the same class list as plumbable endpoints instead. Here we
-- just keep them out of the storage path. Constants.WATER_APPLIANCE_CLASSES is the shared source.
local function isExcludedAppliance(worldObject)
    if not worldObject or not instanceof then
        return false
    end
    for _, className in ipairs(Constants.WATER_APPLIANCE_CLASSES) do
        local ok, isInstance = pcall(instanceof, worldObject, className)
        if ok and isInstance then
            return true
        end
    end
    return false
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

-- Tainted water in this game is (usually) the plain "Water" fluid carrying a tainted flag -- it is set
-- via setTaintedWater() -- so getFluidTypeString() reports "Water" and the taint is invisible unless we
-- ALSO read the flag. The flag can live on the world object, its FluidContainer, or the primary fluid.
local function isTaintedFlagSet(worldObject, fluidContainer, primaryFluid)
    if readBoolean(worldObject, "isTaintedWater") == true then return true end
    if readBoolean(fluidContainer, "isTaintedWater") == true then return true end
    if readBoolean(primaryFluid, "isTaintedWater") == true then return true end
    if readBoolean(primaryFluid, "isTainted") == true then return true end
    return false
end

-- Normalise a fluid type string so tainted water always resolves to "TaintedWater", whether it is a
-- distinct "TaintedWater" fluid or "Water" + a tainted flag. Returns the (possibly corrected) type.
local function normalizeFluidType(typeString, worldObject, fluidContainer, primaryFluid)
    if type(typeString) == "string" and typeString ~= "" then
        if string.find(string.lower(typeString), "tainted") then
            return "TaintedWater"
        end
        if typeString == "Water" and isTaintedFlagSet(worldObject, fluidContainer, primaryFluid) then
            return "TaintedWater"
        end
        return typeString
    end
    if isTaintedFlagSet(worldObject, fluidContainer, primaryFluid) then
        return "TaintedWater"
    end
    return nil
end

local function readRawWorldFluidType(worldObject)
    local fluidContainer = getWorldFluidContainer(worldObject)
    local typeString, primaryFluid = nil, nil
    if fluidContainer and fluidContainer.getPrimaryFluid then
        local ok, pf = pcall(fluidContainer.getPrimaryFluid, fluidContainer)
        if ok and pf then
            primaryFluid = pf
            if pf.getFluidTypeString then
                local okType, fts = pcall(pf.getFluidTypeString, pf)
                if okType and type(fts) == "string" then
                    typeString = fts
                end
            end
        end
    end

    local normalized = normalizeFluidType(typeString, worldObject, fluidContainer, primaryFluid)
    if normalized then
        return normalized
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

    if isExcludedAppliance(worldObject) then
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

    if isExcludedAppliance(worldObject) then
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
    local typeString, primaryFluid = nil, nil
    if fluidContainer and fluidContainer.getPrimaryFluid then
        local ok, pf = pcall(fluidContainer.getPrimaryFluid, fluidContainer)
        if ok and pf then
            primaryFluid = pf
            if pf.getFluidTypeString then
                local okType, fts = pcall(pf.getFluidTypeString, pf)
                if okType and type(fts) == "string" then
                    typeString = fts
                end
            end
        end
    end

    local normalized = normalizeFluidType(typeString, worldObject, fluidContainer, primaryFluid)
    if normalized then
        return normalized
    end

    if Adapter.readWorldFluidAmount(worldObject) > 0 and readBoolean(worldObject, "hasWater") then
        return "Water"
    end

    return nil
end

-- Notify EXTERNAL listeners that a world container we wrote to changed its amount, so mods keying off
-- OnWaterAmountChange refresh (e.g. Useful Barrels' fill-level sprite, vanilla rain collectors). The
-- vanilla FluidContainer write does not raise this event, so without it those mods never see our
-- network moving their water. Guarded by WaterPipes._suppressWaterEvent: our OWN handler early-returns
-- on the echo, so this resets no stagnation clock and re-reconciles no endpoint -- it is purely an
-- outward signal. Save/restore (not true/false) stays correct if a listener re-enters; pcall keeps the
-- flag clean if one errors. Fired only on a real change, and only for a real IsoObject.
local function fireExternalWaterChange(worldObject, prevAmount)
    if not worldObject or not worldObject.getModData then
        return
    end
    if not LuaEventManager or not LuaEventManager.triggerEvent then
        return
    end
    local now = Adapter.readWorldFluidAmount(worldObject) or 0
    if math.abs(now - (prevAmount or 0)) <= 0.001 then
        return
    end
    WaterPipes = WaterPipes or {}
    local saved = WaterPipes._suppressWaterEvent
    WaterPipes._suppressWaterEvent = true
    pcall(LuaEventManager.triggerEvent, "OnWaterAmountChange", worldObject, prevAmount or 0)
    WaterPipes._suppressWaterEvent = saved
end

function Adapter.writeWorldFluidAmount(worldObject, fluidAmount, fluidTypeName)
    if not worldObject then
        return false
    end

    worldObject = resolveFluidTarget(worldObject)
    local prevAmount = Adapter.readWorldFluidAmount(worldObject) or 0

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

        fireExternalWaterChange(worldObject, prevAmount)
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

    fireExternalWaterChange(worldObject, prevAmount)
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

-- The purifier's clean OUT buffer, written as an ordinary network container (see
-- addPurifierOutletDescriptors in NetworkAccess). It is a modData number rather than a
-- FluidContainer, so it is written by hand here.
--
-- Only ever holds clean Water: the outlet descriptor is left out of any network that already carries
-- tainted water, so a rebalance can never arrive here with anything else. Refusing loudly rather than
-- silently storing it, because a wrong answer at this point is water conjured or destroyed.
local function writePurifierOutAmount(purifierObject, fluidAmount, fluidTypeName)
    if not purifierObject or not purifierObject.getModData then
        return false
    end
    if fluidAmount > 0 and fluidTypeName and fluidTypeName ~= "Water" then
        return false
    end

    local ok, modData = pcall(purifierObject.getModData, purifierObject)
    if not ok or not modData then
        return false
    end

    modData[Constants.PURIFIER_OUT_AMOUNT_KEY] =
        math.min(math.max(fluidAmount or 0, 0), Constants.PURIFIER_BUFFER_CAPACITY)

    if purifierObject.transmitModData then
        pcall(purifierObject.transmitModData, purifierObject)
    end
    return true
end

function Adapter.writeDescriptorWaterAmount(descriptor, fluidAmount, fluidTypeName)
    if not descriptor then
        return false
    end

    if descriptor.fluidMode == "purifierOut" then
        return writePurifierOutAmount(descriptor.object, fluidAmount, fluidTypeName)
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

-- Compat (Take A Bath And Shower): its "TubFluidContainer" is a special fluid container the network
-- must NEVER manage -- doing so causes unstable behaviour. Matched by getName() on the object or on
-- the fluid container, per the mod author. No-op for everything else.
local EXCLUDED_CONTAINER_NAMES = { TubFluidContainer = true }

local function isExcludedByName(namedThing)
    if namedThing and namedThing.getName then
        local ok, name = pcall(namedThing.getName, namedThing)
        if ok and name and EXCLUDED_CONTAINER_NAMES[name] then
            return true
        end
    end
    return false
end

function Adapter.isWaterCandidate(container)
    if not container then
        return false
    end

    if isExcludedByName(container) then
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
        if not EndpointObjects.isEndpointCandidate(worldObject) and not isExcludedByName(worldObject) then
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
