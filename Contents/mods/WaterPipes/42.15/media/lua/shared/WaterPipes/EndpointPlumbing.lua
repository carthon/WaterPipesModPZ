WaterPipes = WaterPipes or {}
WaterPipes.EndpointPlumbing = WaterPipes.EndpointPlumbing or {}

require "WaterPipes/Constants"
require "WaterPipes/EndpointAdapterSource"
require "WaterPipes/EndpointFluidSource"
require "WaterPipes/EndpointObjects"
require "WaterPipes/Logger"
require "WaterPipes/NetworkAccess"
require "WaterPipes/PipeObjectUtils"

-- AdapterSource is kept only to clean up the legacy hidden adapter object from older saves.
local AdapterSource = WaterPipes.EndpointAdapterSource
local FluidSource = WaterPipes.EndpointFluidSource
local Constants = WaterPipes.Constants
local EndpointObjects = WaterPipes.EndpointObjects
local EndpointPlumbing = WaterPipes.EndpointPlumbing
local Logger = WaterPipes.Logger
local NetworkAccess = WaterPipes.NetworkAccess
local PipeObjectUtils = WaterPipes.PipeObjectUtils

local function getModData(worldObject)
    if not worldObject or not worldObject.getModData then
        return nil
    end

    return worldObject:getModData()
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

local function describePlumbingDiagnostics(worldObject)
    if not worldObject then
        return "nil"
    end

    local sprite = worldObject.getSprite and worldObject:getSprite() or nil
    local props = sprite and sprite.getProperties and sprite:getProperties() or nil
    local waterAmountProp = props and props.Val and props:Val("waterAmount") or nil
    local waterMaxProp = props and props.Val and props:Val("waterMaxAmount") or nil
    local waterPipedProp = false
    if props then
        if IsoFlagType and props.has then
            waterPipedProp = props:has(IsoFlagType.waterPiped)
        elseif props.Is then
            waterPipedProp = props:Is("waterPiped")
        end
    end

    local amount = worldObject.getFluidAmount and select(2, pcall(worldObject.getFluidAmount, worldObject)) or nil
    local capacity = worldObject.getFluidCapacity and select(2, pcall(worldObject.getFluidCapacity, worldObject)) or nil
    local reserveAmount = worldObject.getReserveWaterAmount and select(2, pcall(worldObject.getReserveWaterAmount, worldObject)) or nil
    local reserveMax = worldObject.getReserveWaterMax and select(2, pcall(worldObject.getReserveWaterMax, worldObject)) or nil
    local usesExternal = worldObject.getUsesExternalWaterSource and select(2, pcall(worldObject.getUsesExternalWaterSource, worldObject)) or nil

    return "props{waterAmount="
        .. tostring(waterAmountProp)
        .. ",waterMaxAmount="
        .. tostring(waterMaxProp)
        .. ",waterPiped="
        .. tostring(waterPipedProp)
        .. "} methods{getFluidAmount="
        .. tostring(worldObject.getFluidAmount ~= nil)
        .. ",getFluidCapacity="
        .. tostring(worldObject.getFluidCapacity ~= nil)
        .. ",emptyFluid="
        .. tostring(worldObject.emptyFluid ~= nil)
        .. ",addFluid="
        .. tostring(worldObject.addFluid ~= nil)
        .. ",getReserveWaterAmount="
        .. tostring(worldObject.getReserveWaterAmount ~= nil)
        .. ",getReserveWaterMax="
        .. tostring(worldObject.getReserveWaterMax ~= nil)
        .. ",setReserveWaterAmount="
        .. tostring(worldObject.setReserveWaterAmount ~= nil)
        .. ",setSourceGrid="
        .. tostring(worldObject.setSourceGrid ~= nil)
        .. ",hasExternalWaterSource="
        .. tostring(worldObject.hasExternalWaterSource ~= nil)
        .. ",getUsesExternalWaterSource="
        .. tostring(worldObject.getUsesExternalWaterSource ~= nil)
        .. ",hasFluid="
        .. tostring(worldObject.hasFluid ~= nil)
        .. ",hasWater="
        .. tostring(worldObject.hasWater ~= nil)
        .. "} values{fluidAmount="
        .. tostring(amount)
        .. ",fluidCapacity="
        .. tostring(capacity)
        .. ",reserveAmount="
        .. tostring(reserveAmount)
        .. ",reserveMax="
        .. tostring(reserveMax)
        .. ",usesExternal="
        .. tostring(usesExternal)
        .. ",hasExternal="
        .. tostring(worldObject.hasExternalWaterSource and select(2, pcall(worldObject.hasExternalWaterSource, worldObject)) or nil)
        .. ",hasFluid="
        .. tostring(worldObject.hasFluid and select(2, pcall(worldObject.hasFluid, worldObject)) or nil)
        .. ",hasWater="
        .. tostring(worldObject.hasWater and select(2, pcall(worldObject.hasWater, worldObject)) or nil)
        .. "}"
end

local function describeSquare(square)
    if not square then
        return "nil"
    end

    local isPlumbed = square.isPlumbed and select(2, pcall(square.isPlumbed, square)) or nil
    local room = square.getRoom and square:getRoom() or nil
    local roomName = room and room.getName and room:getName() or nil
    return "square{"
        .. "x=" .. tostring(square:getX())
        .. ",y=" .. tostring(square:getY())
        .. ",z=" .. tostring(square:getZ())
        .. ",isOutside=" .. tostring(square.isOutside and square:isOutside() or nil)
        .. ",isPlumbed=" .. tostring(isPlumbed)
        .. ",room=" .. tostring(roomName)
        .. "}"
end

local function logSquareObjects(label, square)
    Logger.log(label .. ": " .. describeSquare(square))
    if not square or not square.getObjects then
        return
    end

    local objects = square:getObjects()
    for index = 0, objects:size() - 1 do
        local object = objects:get(index)
        Logger.log(label .. " object[" .. tostring(index) .. "]: " .. describeObject(object) .. " " .. describePlumbingDiagnostics(object))
    end
end

function EndpointPlumbing.dumpAdapterSquareDiagnostics(worldObject)
    if not worldObject or not worldObject.getSquare then
        Logger.log("Diagnostics adapter square: nil")
        return
    end

    local square = worldObject:getSquare()
    local squareAbove = square and square.getSquareAbove and square:getSquareAbove() or nil
    logSquareObjects("Diagnostics adapter square", squareAbove)

    local adapterObject = AdapterSource.findForEndpoint(worldObject)
    if adapterObject then
        Logger.log("Diagnostics adapter square flags: " .. AdapterSource.describeHiddenFlags(adapterObject))
    else
        Logger.log("Diagnostics adapter square flags: nil")
    end
end

function EndpointPlumbing.dumpDiagnostics(worldObject)
    Logger.log("Diagnostics target: " .. describeObject(worldObject))
    Logger.log("Diagnostics target detail: " .. describePlumbingDiagnostics(worldObject))

    local square = worldObject and worldObject.getSquare and worldObject:getSquare() or nil
    logSquareObjects("Diagnostics current square", square)

    local squareAbove = square and square.getSquareAbove and square:getSquareAbove() or nil
    logSquareObjects("Diagnostics square above", squareAbove)

    local adapterObject = AdapterSource.findForEndpoint(worldObject)
    if adapterObject then
        Logger.log("Diagnostics adapter flags: " .. AdapterSource.describeHiddenFlags(adapterObject))
    else
        Logger.log("Diagnostics adapter flags: nil")
    end

    local summary = NetworkAccess.getSummary(worldObject)
    if not summary then
        Logger.log("Diagnostics network summary: nil")
        return
    end

    Logger.log(
        "Diagnostics network summary: totalAmount="
            .. tostring(summary.totalAmount)
            .. " totalCapacity="
            .. tostring(summary.totalCapacity)
            .. " descriptorCount="
            .. tostring(summary.descriptors and #summary.descriptors or 0)
            .. " mixed="
            .. tostring(summary.isMixed)
    )
    for index, descriptor in ipairs(summary.descriptors or {}) do
        local objectText = describeObject(descriptor.object)
        Logger.log("Diagnostics descriptor[" .. tostring(index) .. "]: object=" .. objectText .. " fluidType=" .. tostring(descriptor.fluidType) .. " amount=" .. tostring(descriptor.waterAmount) .. " capacity=" .. tostring(descriptor.capacity) .. " tainted=" .. tostring(descriptor.tainted))
    end
end

local function transmitObjectState(worldObject)
    if not worldObject then
        return
    end

    if worldObject.transmitModData then
        pcall(worldObject.transmitModData, worldObject)
    end

    if worldObject.sync then
        pcall(worldObject.sync, worldObject)
    end
end

local function sendExternalWaterSourceChange(worldObject, value)
    if not worldObject or not worldObject.sendObjectChange then
        return
    end

    local changeName = IsoObjectChange and IsoObjectChange.USES_EXTERNAL_WATER_SOURCE or "usesExternalWaterSource"
    pcall(worldObject.sendObjectChange, worldObject, changeName, { value = value and true or false })
end

local function setUsesExternalWaterSource(worldObject, value)
    if not worldObject then
        return
    end

    local modData = getModData(worldObject)
    if modData then
        modData.usesExternalWaterSource = value and true or false
    end

    if worldObject.setUsesExternalWaterSource then
        pcall(worldObject.setUsesExternalWaterSource, worldObject, value and true or false)
    end

    sendExternalWaterSourceChange(worldObject, value)
    transmitObjectState(worldObject)
end

local function setCanBeWaterPiped(worldObject, value)
    local modData = getModData(worldObject)
    if modData then
        modData.canBeWaterPiped = value and true or false
    end
end

function EndpointPlumbing.isPlumbed(worldObject)
    local modData = getModData(worldObject)
    return modData and modData[Constants.PLUMBED_ENDPOINT_MODDATA_KEY] == true or false
end

function EndpointPlumbing.hasPipeOnEndpointSquare(worldObject)
    local square = worldObject and worldObject.getSquare and worldObject:getSquare() or nil
    return square and PipeObjectUtils.getPipeOnSquare(square) ~= nil or false
end

function EndpointPlumbing.canPlumb(worldObject)
    return EndpointObjects.isEndpointCandidate(worldObject)
        and not EndpointPlumbing.isPlumbed(worldObject)
        and EndpointPlumbing.hasPipeOnEndpointSquare(worldObject)
end

function EndpointPlumbing.canUnplumb(worldObject)
    return EndpointPlumbing.isPlumbed(worldObject)
end

function EndpointPlumbing.refreshEndpointSource(worldObject)
    if not EndpointPlumbing.isPlumbed(worldObject) then
        return false
    end

    local modData = getModData(worldObject)
    if modData then
        modData[Constants.PLUMBED_ENDPOINT_SOURCE_MODDATA_KEY] = nil
    end

    -- Legacy cleanup: remove the hidden adapter object created by older mod versions.
    AdapterSource.removeForEndpoint(worldObject, "migrateToFluidSource")

    if not EndpointPlumbing.hasPipeOnEndpointSquare(worldObject) then
        FluidSource.clearForEndpoint(worldObject)
        setUsesExternalWaterSource(worldObject, false)
        return false
    end

    setCanBeWaterPiped(worldObject, false)
    -- Own-container path: the engine reads water from the endpoint's own FluidContainer.
    setUsesExternalWaterSource(worldObject, false)
    return FluidSource.syncForEndpoint(worldObject)
end

function EndpointPlumbing.releaseReservation(worldObject)
    if not EndpointPlumbing.isPlumbed(worldObject) then
        return 0
    end

    FluidSource.clearForEndpoint(worldObject)
    return 0
end

function EndpointPlumbing.plumb(worldObject)
    if not EndpointPlumbing.canPlumb(worldObject) then
        Logger.warn("Plumb rejected for endpoint: " .. describeObject(worldObject))
        return false
    end

    local modData = getModData(worldObject)
    if modData then
        modData[Constants.PLUMBED_ENDPOINT_MODDATA_KEY] = true
    end

    Logger.log("Plumbing endpoint to pipe network: " .. describeObject(worldObject))
    Logger.log("Plumbing diagnostics: " .. describePlumbingDiagnostics(worldObject))
    setCanBeWaterPiped(worldObject, false)
    setUsesExternalWaterSource(worldObject, false)
    EndpointPlumbing.refreshEndpointSource(worldObject)

    if buildUtil and buildUtil.setHaveConstruction and worldObject.getSquare then
        pcall(buildUtil.setHaveConstruction, worldObject:getSquare(), true)
    end

    transmitObjectState(worldObject)
    return true
end

function EndpointPlumbing.unplumb(worldObject)
    if not EndpointPlumbing.canUnplumb(worldObject) then
        Logger.warn("Unplumb rejected for endpoint: " .. describeObject(worldObject))
        return false
    end

    local modData = getModData(worldObject)
    if modData then
        modData[Constants.PLUMBED_ENDPOINT_MODDATA_KEY] = nil
        modData[Constants.PLUMBED_ENDPOINT_SOURCE_MODDATA_KEY] = nil
    end

    setCanBeWaterPiped(worldObject, true)
    FluidSource.clearForEndpoint(worldObject)
    AdapterSource.removeForEndpoint(worldObject, "unplumb")
    setUsesExternalWaterSource(worldObject, false)
    Logger.log("Unplumbed endpoint from pipe network: " .. describeObject(worldObject))

    if buildUtil and buildUtil.setHaveConstruction and worldObject.getSquare then
        pcall(buildUtil.setHaveConstruction, worldObject:getSquare(), true)
    end

    transmitObjectState(worldObject)
    return true
end
