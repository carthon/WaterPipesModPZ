WaterPipes = WaterPipes or {}
WaterPipes.EndpointAdapterSource = WaterPipes.EndpointAdapterSource or {}

require "WaterPipes/Constants"
require "WaterPipes/ContainerAdapter"
require "WaterPipes/EndpointObjects"
require "WaterPipes/Logger"
require "WaterPipes/NetworkAccess"

local Adapter = WaterPipes.ContainerAdapter
local AdapterSource = WaterPipes.EndpointAdapterSource
local Constants = WaterPipes.Constants
local EndpointObjects = WaterPipes.EndpointObjects
local Logger = WaterPipes.Logger
local NetworkAccess = WaterPipes.NetworkAccess
local INTERNAL_SYNCING_KEY = "waterpipesAdapterSyncing"
local CONSUME_EPSILON = 0.001

-- LEGACY MIGRATION ONLY. Nothing here creates an adapter any more.
--
-- A plumbed fixture used to be fed by a hidden IsoThumpable stacked on the square above it, holding a
-- FluidContainer that mirrored the network. EndpointFluidSource replaced that: the fixture's OWN
-- container is written instead, so there is no second object to keep in step, prioritise on the tile,
-- or lose track of.
--
-- What survives is everything needed to get an OLD save back to a clean state: recognise an adapter,
-- find it, take it off the tile, and keep honouring draws made through one until it is gone. The
-- creation half -- createAdapterObject, syncForEndpoint, and the flag/priority/reconcile helpers only
-- they reached -- is deleted; it had no callers left and was 315 lines of ways to build a thing this
-- mod no longer builds.
--
-- So: do not add anything here. A fixture's water belongs to EndpointFluidSource.

local function isAuthoritative()
    if isServer and isServer() then
        return true
    end

    return not (isClient and isClient())
end

local function safeField(object, fieldName)
    if not object or not fieldName or type(object) ~= "table" then
        return nil
    end

    return object[fieldName]
end

local function isIsoObjectUserdata(object)
    if type(object) ~= "userdata" or not instanceof then
        return false
    end

    local ok, result = pcall(instanceof, object, "IsoObject")
    return ok and result or false
end

local function getModData(worldObject)
    if not isIsoObjectUserdata(worldObject) and type(worldObject) ~= "table" then
        return nil
    end

    local getModDataMethod = safeField(worldObject, "getModData")
        or (isIsoObjectUserdata(worldObject) and worldObject.getModData)
    if not getModDataMethod then
        return nil
    end

    local ok, modData = pcall(getModDataMethod, worldObject)
    return ok and modData or nil
end

local function getSpriteName(worldObject)
    if not isIsoObjectUserdata(worldObject) and type(worldObject) ~= "table" then
        return nil
    end

    local getSpriteMethod = safeField(worldObject, "getSprite")
        or (isIsoObjectUserdata(worldObject) and worldObject.getSprite)
    if not getSpriteMethod then
        return nil
    end

    local ok, sprite = pcall(getSpriteMethod, worldObject)
    local getNameMethod = ok and sprite and (safeField(sprite, "getName") or (type(sprite) == "userdata" and sprite.getName)) or nil
    if not getNameMethod then
        return nil
    end

    local okName, spriteName = pcall(getNameMethod, sprite)
    return okName and spriteName or nil
end

local function getSquare(x, y, z)
    if not getCell then
        return nil
    end

    local cell = getCell()
    if not cell or not cell.getGridSquare then
        return nil
    end

    return cell:getGridSquare(x, y, z)
end

local function describeObject(worldObject)
    if not worldObject then
        return "nil"
    end

    local name = worldObject.getName and worldObject:getName() or "?"
    local spriteName = (worldObject.getSprite and worldObject:getSprite() and worldObject:getSprite():getName()) or "?"
    local objectIndex = worldObject.getObjectIndex and worldObject:getObjectIndex() or "?"
    local square = worldObject.getSquare and worldObject:getSquare() or nil
    local squareText = square and (tostring(square:getX()) .. "," .. tostring(square:getY()) .. "," .. tostring(square:getZ())) or "?, ?, ?"
    return tostring(name) .. " sprite=" .. tostring(spriteName) .. " index=" .. tostring(objectIndex) .. " square=" .. squareText
end

local function getEndpointReference(worldObject)
    local square = worldObject and worldObject.getSquare and worldObject:getSquare() or nil
    if not square then
        return nil
    end

    return {
        x = square:getX(),
        y = square:getY(),
        z = square:getZ(),
        index = worldObject.getObjectIndex and worldObject:getObjectIndex() or -1,
    }
end

local function getAdapterSquare(endpointObject)
    local square = endpointObject and endpointObject.getSquare and endpointObject:getSquare() or nil
    if not square then
        return nil
    end

    return getSquare(square:getX(), square:getY(), square:getZ() + 1)
end

function AdapterSource.isAdapterObject(worldObject)
    if not isIsoObjectUserdata(worldObject) and type(worldObject) ~= "table" then
        return false
    end

    local modData = getModData(worldObject)
    if modData and modData[Constants.ADAPTER_SOURCE_MODDATA_KEY] == true then
        return true
    end

    local spriteName = getSpriteName(worldObject)
    if spriteName == Constants.ADAPTER_SOURCE_HIDDEN_SPRITE then
        return true
    end

    return false
end

local function matchesEndpoint(adapterObject, endpointObject)
    local modData = getModData(adapterObject)
    local reference = getEndpointReference(endpointObject)
    if not modData or not reference then
        return false
    end

    return modData[Constants.ADAPTER_SOURCE_ENDPOINT_X_KEY] == reference.x
        and modData[Constants.ADAPTER_SOURCE_ENDPOINT_Y_KEY] == reference.y
        and modData[Constants.ADAPTER_SOURCE_ENDPOINT_Z_KEY] == reference.z
end

function AdapterSource.findForEndpoint(endpointObject)
    local squareAbove = getAdapterSquare(endpointObject)
    if not squareAbove or not squareAbove.getObjects then
        return nil
    end

    local objects = squareAbove:getObjects()
    for index = 0, objects:size() - 1 do
        local candidate = objects:get(index)
        if AdapterSource.isAdapterObject(candidate) and matchesEndpoint(candidate, endpointObject) then
            return candidate
        end
    end

    return nil
end

function AdapterSource.findOnSquare(square)
    if not square or not square.getObjects then
        return nil
    end

    local objects = square:getObjects()
    for index = 0, objects:size() - 1 do
        local candidate = objects:get(index)
        if AdapterSource.isAdapterObject(candidate) then
            return candidate
        end
    end

    return nil
end

function AdapterSource.squareHasAdapter(square)
    return AdapterSource.findOnSquare(square) ~= nil
end

local function setAdapterCapacity(adapterObject, capacity)
    local fluidContainer = adapterObject and adapterObject.getFluidContainer and adapterObject:getFluidContainer() or nil
    if not fluidContainer or not fluidContainer.setCapacity then
        return false
    end

    local safeCapacity = math.max(capacity or 0, 1)
    local ok = pcall(fluidContainer.setCapacity, fluidContainer, safeCapacity)
    if ok and adapterObject.transmitModData then
        pcall(adapterObject.transmitModData, adapterObject)
    end
    return ok
end

local function removeAdapterObject(adapterObject, reason)
    if not isAuthoritative() or not adapterObject then
        return
    end

    local square = adapterObject.getSquare and adapterObject:getSquare() or nil
    if square and square.transmitRemoveItemFromSquare then
        square:transmitRemoveItemFromSquare(adapterObject)
        if square.RecalcProperties then
            square:RecalcProperties()
        end
        if square.RecalcAllWithNeighbours then
            square:RecalcAllWithNeighbours(true)
        end
    end

    Logger.log("Removed adapter source: " .. describeObject(adapterObject) .. " reason=" .. tostring(reason))
end

function AdapterSource.removeForEndpoint(endpointObject, reason)
    local adapterObject = AdapterSource.findForEndpoint(endpointObject)
    if adapterObject then
        removeAdapterObject(adapterObject, reason or "removeForEndpoint")
    end
end

local function getAdapterLastSyncAmount(adapterObject)
    local modData = getModData(adapterObject)
    if not modData then
        return nil
    end

    local value = modData[Constants.ADAPTER_SOURCE_LAST_SYNC_AMOUNT_KEY]
    return type(value) == "number" and value or nil
end

local function setAdapterLastSyncAmount(adapterObject, amount)
    local modData = getModData(adapterObject)
    if not modData then
        return
    end

    modData[Constants.ADAPTER_SOURCE_LAST_SYNC_AMOUNT_KEY] = amount
    if adapterObject.transmitModData then
        pcall(adapterObject.transmitModData, adapterObject)
    end
end

local function writeAdapterSnapshot(adapterObject, totalAmount, totalCapacity, fluidTypeName)
    local effectiveCapacity = math.max(totalCapacity or 0, 0)
    local effectiveAmount = math.max(math.min(totalAmount or 0, effectiveCapacity), 0)
    local modData = getModData(adapterObject)
    if modData then
        modData.waterMax = effectiveCapacity
        modData[INTERNAL_SYNCING_KEY] = true
        if adapterObject.transmitModData then
            pcall(adapterObject.transmitModData, adapterObject)
        end
    end

    setAdapterCapacity(adapterObject, effectiveCapacity)
    Adapter.writeWorldFluidAmount(adapterObject, effectiveAmount, fluidTypeName)

    if modData then
        modData[INTERNAL_SYNCING_KEY] = nil
    end
    setAdapterLastSyncAmount(adapterObject, effectiveAmount)
end

function AdapterSource.describeHiddenFlags(worldObject)
    if not worldObject then
        return "nil"
    end

    local parts = {
        "sprite=" .. tostring(getSpriteName(worldObject)),
        "name=" .. tostring(worldObject.getName and worldObject:getName() or nil),
        "noPicking=" .. tostring(worldObject.isNoPicking and select(2, pcall(worldObject.isNoPicking, worldObject)) or nil),
        "specialTooltip=" .. tostring(worldObject.haveSpecialTooltip and select(2, pcall(worldObject.haveSpecialTooltip, worldObject)) or nil),
        "outlineOnMouseover=" .. tostring(worldObject.isOutlineOnMouseover and select(2, pcall(worldObject.isOutlineOnMouseover, worldObject)) or nil),
        "objectIndex=" .. tostring(worldObject.getObjectIndex and worldObject:getObjectIndex() or nil),
    }

    return table.concat(parts, " ")
end

local function findEndpointForAdapter(adapterObject)
    local modData = getModData(adapterObject)
    if not modData then
        return nil
    end

    local square = getSquare(
        modData[Constants.ADAPTER_SOURCE_ENDPOINT_X_KEY],
        modData[Constants.ADAPTER_SOURCE_ENDPOINT_Y_KEY],
        modData[Constants.ADAPTER_SOURCE_ENDPOINT_Z_KEY]
    )
    if not square then
        return nil
    end

    local expectedIndex = modData[Constants.ADAPTER_SOURCE_ENDPOINT_INDEX_KEY]
    if type(expectedIndex) == "number" and expectedIndex >= 0 and square.getObjects and expectedIndex < square:getObjects():size() then
        local direct = square:getObjects():get(expectedIndex)
        if direct and EndpointObjects.isEndpointCandidate(direct) then
            return direct
        end
    end

    for _, endpointObject in ipairs(EndpointObjects.collectOnSquare(square)) do
        return endpointObject
    end

    return nil
end

function AdapterSource.onAdapterWaterAmountChange(adapterObject, prevAmount)
    if not AdapterSource.isAdapterObject(adapterObject) then
        return
    end

    local adapterModData = getModData(adapterObject)
    if adapterModData and adapterModData[INTERNAL_SYNCING_KEY] then
        setAdapterLastSyncAmount(adapterObject, math.max(Adapter.readWorldFluidAmount(adapterObject) or 0, 0))
        return
    end

    local endpointObject = findEndpointForAdapter(adapterObject)
    if not endpointObject then
        return
    end

    local currentAmount = math.max(Adapter.readWorldFluidAmount(adapterObject) or 0, 0)
    local lastSyncAmount = getAdapterLastSyncAmount(adapterObject)
    local previousAmount = type(prevAmount) == "number" and prevAmount or lastSyncAmount or currentAmount
    local consumed = math.max(previousAmount - currentAmount, 0)
    if consumed > CONSUME_EPSILON then
        local applied = NetworkAccess.useFluid(endpointObject, consumed)
        Logger.log("Adapter source consumed by vanilla plumbing: endpoint=" .. describeObject(endpointObject) .. " consumed=" .. tostring(applied))
    else
        consumed = 0
    end

    local summary = NetworkAccess.getSummary(endpointObject)
    if summary and not summary.isMixed and summary.isWater and (summary.totalCapacity or 0) > 0 then
        local reserveCapacity = math.min(summary.totalCapacity or 0, Constants.ADAPTER_SOURCE_MAX_CAPACITY)
        local visibleAmount = math.min(summary.totalAmount or 0, reserveCapacity)
        writeAdapterSnapshot(adapterObject, visibleAmount, reserveCapacity, summary.fluidTypeName)
        return
    end

    writeAdapterSnapshot(adapterObject, 0, summary and summary.totalCapacity or 0, nil)
end
