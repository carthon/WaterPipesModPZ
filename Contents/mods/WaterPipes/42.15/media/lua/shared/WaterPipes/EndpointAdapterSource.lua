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

local function setAdapterReference(adapterObject, endpointObject)
    local modData = getModData(adapterObject)
    local reference = getEndpointReference(endpointObject)
    if not modData or not reference then
        return
    end

    modData[Constants.ADAPTER_SOURCE_MODDATA_KEY] = true
    modData[Constants.ADAPTER_SOURCE_ENDPOINT_X_KEY] = reference.x
    modData[Constants.ADAPTER_SOURCE_ENDPOINT_Y_KEY] = reference.y
    modData[Constants.ADAPTER_SOURCE_ENDPOINT_Z_KEY] = reference.z
    modData[Constants.ADAPTER_SOURCE_ENDPOINT_INDEX_KEY] = reference.index
end

local function getAdapterSquare(endpointObject)
    local square = endpointObject and endpointObject.getSquare and endpointObject:getSquare() or nil
    if not square then
        return nil
    end

    return getSquare(square:getX(), square:getY(), square:getZ() + 1)
end

local function applyHiddenAdapterFlags(worldObject)
    if not worldObject then
        return
    end

    if worldObject.setName then
        pcall(worldObject.setName, worldObject, "")
    end
    if worldObject.setNoPicking then
        pcall(worldObject.setNoPicking, worldObject, true)
    end
    if worldObject.setSpecialTooltip then
        pcall(worldObject.setSpecialTooltip, worldObject, false)
    end
    if worldObject.setOutlineOnMouseover then
        pcall(worldObject.setOutlineOnMouseover, worldObject, false)
    end
    if worldObject.setHighlighted then
        pcall(worldObject.setHighlighted, worldObject, false)
    end
    if worldObject.setAlphaAndTarget then
        pcall(worldObject.setAlphaAndTarget, worldObject, 0.0)
    else
        if worldObject.setAlpha then
            pcall(worldObject.setAlpha, worldObject, 0.0)
        end
        if worldObject.setTargetAlpha then
            pcall(worldObject.setTargetAlpha, worldObject, 0.0)
        end
    end
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

local function ensureFluidContainerComponent(adapterObject)
    if not adapterObject then
        return false
    end

    if adapterObject.getFluidContainer and adapterObject:getFluidContainer() then
        return true
    end

    if not GameEntityFactory or not GameEntityFactory.AddComponent or not ComponentType or not ComponentType.FluidContainer then
        return false
    end

    local fluidComponent = ComponentType.FluidContainer.CreateComponent and ComponentType.FluidContainer:CreateComponent() or nil
    if not fluidComponent then
        return false
    end

    fluidComponent:setCapacity(1.0)
    local ok = pcall(GameEntityFactory.AddComponent, adapterObject, true, fluidComponent)
    return ok and adapterObject.getFluidContainer and adapterObject:getFluidContainer() ~= nil or false
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

local function isCompetingWorldSource(candidate)
    if not candidate or AdapterSource.isAdapterObject(candidate) or EndpointObjects.isEndpointCandidate(candidate) then
        return false
    end

    return Adapter.getWorldFluidKind(candidate) == "worldFluid"
end

local function prioritizeAdapterOnSquare(adapterObject)
    local square = adapterObject and adapterObject.getSquare and adapterObject:getSquare() or nil
    local objects = square and square.getObjects and square:getObjects() or nil
    if not objects or not objects.size then
        return false
    end

    local currentIndex = nil
    local targetIndex = nil
    for index = 0, objects:size() - 1 do
        local candidate = objects:get(index)
        if candidate == adapterObject then
            currentIndex = index
        elseif targetIndex == nil and isCompetingWorldSource(candidate) then
            targetIndex = index
        end
    end

    if currentIndex == nil or targetIndex == nil or currentIndex < targetIndex then
        return false
    end

    local removed = pcall(function()
        objects:remove(currentIndex)
    end)
    if not removed then
        return false
    end

    local insertIndex = math.max(math.min(targetIndex, objects:size()), 0)
    local inserted = pcall(function()
        objects:add(insertIndex, adapterObject)
    end)
    if not inserted then
        pcall(function()
            objects:add(adapterObject)
        end)
        return false
    end

    if square.RecalcProperties then
        square:RecalcProperties()
    end
    if square.RecalcAllWithNeighbours then
        square:RecalcAllWithNeighbours(true)
    end

    return true
end

local function createAdapterObject(endpointObject)
    if not isAuthoritative() then
        return nil
    end

    local squareAbove = getAdapterSquare(endpointObject)
    if not squareAbove or not IsoThumpable or not getWorld then
        return nil
    end

    local cell = getWorld():getCell()
    if not cell then
        return nil
    end

    local javaObject = IsoThumpable.new(cell, squareAbove, Constants.ADAPTER_SOURCE_SPRITE, false, {})
    if not javaObject then
        return nil
    end

    if javaObject.setName then
        javaObject:setName("")
    end
    if javaObject.setCanPassThrough then
        javaObject:setCanPassThrough(true)
    end
    if javaObject.setBlockAllTheSquare then
        javaObject:setBlockAllTheSquare(false)
    end
    if javaObject.setCanBarricade then
        javaObject:setCanBarricade(false)
    end
    if javaObject.setIsDismantable then
        javaObject:setIsDismantable(false)
    end
    if javaObject.setIsHoppable then
        javaObject:setIsHoppable(false)
    end
    if javaObject.setIsThumpable then
        javaObject:setIsThumpable(false)
    end
    applyHiddenAdapterFlags(javaObject)

    setAdapterReference(javaObject, endpointObject)
    local modData = getModData(javaObject)
    if modData then
        modData.waterMax = 0
    end

    local info = SpriteConfigManager and SpriteConfigManager.getObjectInfoFromSprite and SpriteConfigManager.getObjectInfoFromSprite(Constants.ADAPTER_SOURCE_SPRITE) or nil
    if info and info.getScript and info:getScript() and info:getScript():getParent() and GameEntityFactory and GameEntityFactory.CreateIsoObjectEntity then
        local gameEntityScript = info:getScript():getParent()
        pcall(GameEntityFactory.CreateIsoObjectEntity, javaObject, gameEntityScript, true)
    end

    applyHiddenAdapterFlags(javaObject)

    squareAbove:AddSpecialObject(javaObject)
    applyHiddenAdapterFlags(javaObject)
    if not ensureFluidContainerComponent(javaObject) then
        Logger.error("Failed to attach FluidContainer to adapter source " .. describeObject(javaObject))
    end
    prioritizeAdapterOnSquare(javaObject)
    if javaObject.transmitCompleteItemToClients then
        pcall(javaObject.transmitCompleteItemToClients, javaObject)
    end
    applyHiddenAdapterFlags(javaObject)

    Logger.log("Created adapter source: " .. describeObject(javaObject) .. " for endpoint " .. describeObject(endpointObject))
    return javaObject
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

local function reconcileAdapterConsumption(adapterObject, endpointObject)
    if not adapterObject or not endpointObject then
        return 0
    end

    local adapterModData = getModData(adapterObject)
    if adapterModData and adapterModData[INTERNAL_SYNCING_KEY] then
        return 0
    end

    local currentAmount = math.max(Adapter.readWorldFluidAmount(adapterObject) or 0, 0)
    local lastSyncAmount = getAdapterLastSyncAmount(adapterObject)
    if type(lastSyncAmount) ~= "number" then
        setAdapterLastSyncAmount(adapterObject, currentAmount)
        return 0
    end

    local consumed = math.max(lastSyncAmount - currentAmount, 0)
    if consumed <= CONSUME_EPSILON then
        if currentAmount > lastSyncAmount + CONSUME_EPSILON then
            setAdapterLastSyncAmount(adapterObject, currentAmount)
        end
        return 0
    end

    local applied = NetworkAccess.useFluid(endpointObject, consumed)
    Logger.log(
        "Adapter source reconciled consumption: endpoint="
            .. describeObject(endpointObject)
            .. " requested="
            .. tostring(consumed)
            .. " applied="
            .. tostring(applied)
    )

    setAdapterLastSyncAmount(adapterObject, currentAmount)
    return applied
end

function AdapterSource.syncForEndpoint(endpointObject)
    if not isAuthoritative() then
        return nil
    end

    local squareAbove = getAdapterSquare(endpointObject)
    if not squareAbove then
        AdapterSource.removeForEndpoint(endpointObject, "noSquareAbove")
        return nil
    end

    local adapterObject = AdapterSource.findForEndpoint(endpointObject)
    if adapterObject then
        reconcileAdapterConsumption(adapterObject, endpointObject)
    end

    local summary = NetworkAccess.getSummary(endpointObject)
    if not summary or summary.totalCapacity <= 0 then
        if adapterObject then
            writeAdapterSnapshot(adapterObject, 0, 0, nil)
        end
        return adapterObject
    end

    adapterObject = adapterObject or createAdapterObject(endpointObject)
    if not adapterObject then
        return nil
    end

    applyHiddenAdapterFlags(adapterObject)

    if not ensureFluidContainerComponent(adapterObject) then
        Logger.error("Adapter source missing FluidContainer component for " .. describeObject(endpointObject))
        return nil
    end

    prioritizeAdapterOnSquare(adapterObject)

    if summary.isMixed or not summary.isWater then
        writeAdapterSnapshot(adapterObject, 0, summary.totalCapacity, nil)
        return adapterObject
    end

    local reserveCapacity = math.max(summary.totalCapacity or 0, 0)
    local visibleAmount = math.min(summary.totalAmount or 0, reserveCapacity)
    if reserveCapacity <= 0 or visibleAmount <= 0 then
        writeAdapterSnapshot(adapterObject, 0, reserveCapacity, nil)
        return adapterObject
    end

    writeAdapterSnapshot(adapterObject, visibleAmount, reserveCapacity, summary.fluidTypeName)
    return adapterObject
end

function AdapterSource.returnReservation(endpointObject)
    local adapterObject = AdapterSource.findForEndpoint(endpointObject)
    if not adapterObject then
        return 0
    end

    writeAdapterSnapshot(adapterObject, 0, 0, nil)
    return 0
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

function AdapterSource.onAdapterDestroyed(adapterObject)
    if not AdapterSource.isAdapterObject(adapterObject) then
        return nil
    end

    local endpointObject = findEndpointForAdapter(adapterObject)
    if not endpointObject then
        return nil
    end

    return AdapterSource.syncForEndpoint(endpointObject)
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
