WaterPipes = WaterPipes or {}
WaterPipes.NetworkAccess = WaterPipes.NetworkAccess or {}

require "WaterPipes/Constants"
require "WaterPipes/ContainerAdapter"
require "WaterPipes/EndpointObjects"
require "WaterPipes/Logger"
require "WaterPipes/PipeObjectUtils"

local Adapter = WaterPipes.ContainerAdapter
local Constants = WaterPipes.Constants
local EndpointObjects = WaterPipes.EndpointObjects
local Logger = WaterPipes.Logger
local NetworkAccess = WaterPipes.NetworkAccess
local PipeObjectUtils = WaterPipes.PipeObjectUtils

local function getCellSquare(x, y, z)
    if not getCell then
        return nil
    end

    local cell = getCell()
    if not cell or not cell.getGridSquare then
        return nil
    end

    return cell:getGridSquare(x, y, z)
end

local function squareKey(square)
    return tostring(square:getX()) .. ":" .. tostring(square:getY()) .. ":" .. tostring(square:getZ())
end

local function describeEndpointObject(endpointObject)
    if not endpointObject then
        return "nil"
    end

    local name = endpointObject.getName and endpointObject:getName() or "?"
    local spriteName = (endpointObject.getSprite and endpointObject:getSprite() and endpointObject:getSprite():getName()) or "?"
    local objectIndex = endpointObject.getObjectIndex and endpointObject:getObjectIndex() or "?"
    local square = endpointObject.getSquare and endpointObject:getSquare() or nil
    local squareText = square and squareKey(square) or "?"
    return tostring(name) .. " sprite=" .. tostring(spriteName) .. " index=" .. tostring(objectIndex) .. " square=" .. squareText
end

local function addSquare(squareMap, square)
    if not square then
        return false
    end

    local key = squareKey(square)
    if squareMap[key] then
        return false
    end

    squareMap[key] = square
    return true
end

local function getNeighborSquares(square)
    local neighbors = { square }
    for _, offset in ipairs(Constants.NETWORK_NEIGHBOR_OFFSETS) do
        local neighbor = getCellSquare(square:getX() + offset.x, square:getY() + offset.y, square:getZ() + offset.z)
        if neighbor then
            neighbors[#neighbors + 1] = neighbor
        end
    end
    return neighbors
end

-- Containers connect to pipes on the SAME floor (the square itself + cardinal neighbours).
local function getHorizontalNeighborSquares(square)
    local neighbors = { square }
    for _, offset in ipairs(Constants.CARDINAL_OFFSETS) do
        local neighbor = getCellSquare(square:getX() + offset.x, square:getY() + offset.y, square:getZ())
        if neighbor then
            neighbors[#neighbors + 1] = neighbor
        end
    end
    return neighbors
end

-- A vertical step is only allowed when a wall cover bridges the floors (it sits on the lower
-- square and climbs up). Keeps two stacked networks separate unless a vertical pipe links them.
local function verticalStepAllowed(x, y, z, offsetZ)
    if offsetZ == 0 then
        return true
    end
    local lowerZ = (offsetZ < 0) and (z + offsetZ) or z
    local square = getCellSquare(x, y, lowerZ)
    return square ~= nil and PipeObjectUtils.hasWallCoverOnSquare(square)
end

local function getFluidTypeByName(fluidTypeName)
    if fluidTypeName == "Water" then
        return Fluid and Fluid.Water or (FluidType and FluidType.Water)
    end

    if fluidTypeName == "TaintedWater" then
        return Fluid and Fluid.TaintedWater or (FluidType and FluidType.TaintedWater)
    end

    if FluidType and FluidType.FromNameLower then
        return FluidType.FromNameLower(string.lower(fluidTypeName))
    end

    if Fluid and Fluid.FromNameLower then
        return Fluid.FromNameLower(string.lower(fluidTypeName))
    end

    return nil
end

local function isWaterTypeName(fluidTypeName)
    return fluidTypeName == "Water" or fluidTypeName == "TaintedWater"
end

local function hasPipeOnSquare(square)
    return square and PipeObjectUtils.getPipeOnSquare(square) ~= nil
end

local function collectConnectedPipeSquares(endpointObject)
    if not endpointObject or not endpointObject.getSquare then
        return {}
    end

    local originSquare = endpointObject:getSquare()
    if not originSquare then
        return {}
    end

    local visited = {}
    local queue = {}
    local pipeSquares = {}

    local function tryAdd(square)
        if square and hasPipeOnSquare(square) and addSquare(visited, square) then
            queue[#queue + 1] = square
            pipeSquares[#pipeSquares + 1] = square
        end
    end

    -- Seed from the endpoint's square + neighbours; vertical neighbours need a wall cover.
    tryAdd(originSquare)
    local ox, oy, oz = originSquare:getX(), originSquare:getY(), originSquare:getZ()
    for _, offset in ipairs(Constants.NETWORK_NEIGHBOR_OFFSETS) do
        if verticalStepAllowed(ox, oy, oz, offset.z) then
            tryAdd(getCellSquare(ox + offset.x, oy + offset.y, oz + offset.z))
        end
    end

    local index = 1
    while index <= #queue do
        local current = queue[index]
        index = index + 1
        local cx, cy, cz = current:getX(), current:getY(), current:getZ()

        for _, offset in ipairs(Constants.NETWORK_NEIGHBOR_OFFSETS) do
            if verticalStepAllowed(cx, cy, cz, offset.z) then
                tryAdd(getCellSquare(cx + offset.x, cy + offset.y, cz + offset.z))
            end
        end
    end

    return pipeSquares
end

local function collectStorageDescriptors(pipeSquares)
    local scannedSquares = {}
    local descriptors = {}

    for _, pipeSquare in ipairs(pipeSquares) do
        for _, nearbySquare in ipairs(getHorizontalNeighborSquares(pipeSquare)) do
            if addSquare(scannedSquares, nearbySquare) then
                local squareDescriptors = Adapter.collectSquareContainers(nearbySquare)
                for key, descriptor in pairs(squareDescriptors) do
                    descriptors[key] = descriptor
                end
            end
        end
    end

    return descriptors
end

local function normalizeDescriptorList(descriptorMap)
    local descriptors = {}

    for _, descriptor in pairs(descriptorMap) do
        descriptors[#descriptors + 1] = descriptor
    end

    table.sort(descriptors, function(left, right)
        return tostring(left.key) < tostring(right.key)
    end)

    return descriptors
end

local function buildSummary(endpointObject)
    if not EndpointObjects.isEndpointCandidate(endpointObject) then
        return nil
    end

    local pipeSquares = collectConnectedPipeSquares(endpointObject)
    if #pipeSquares == 0 then
        return nil
    end

    local descriptorMap = collectStorageDescriptors(pipeSquares)
    local descriptors = normalizeDescriptorList(descriptorMap)
    if #descriptors == 0 then
        return nil
    end

    local totalAmount = 0
    local totalCapacity = 0
    local fluidTypes = {}
    local fluidTypeCount = 0
    local fluidTypeName = nil

    for _, descriptor in ipairs(descriptors) do
        local descriptorAmount = math.max(descriptor.waterAmount or 0, 0)
        local descriptorCapacity = math.max(descriptor.capacity or 0, 0)
        totalAmount = totalAmount + descriptorAmount
        totalCapacity = totalCapacity + descriptorCapacity

        if descriptorAmount > 0 and descriptor.fluidType then
            fluidTypes[descriptor.fluidType] = true
        end
    end

    for candidateFluidType in pairs(fluidTypes) do
        fluidTypeCount = fluidTypeCount + 1
        fluidTypeName = candidateFluidType
    end

    return {
        endpoint = endpointObject,
        pipeSquares = pipeSquares,
        descriptors = descriptors,
        totalAmount = totalAmount,
        totalCapacity = totalCapacity,
        fluidTypeName = fluidTypeName,
        fluidTypeCount = fluidTypeCount,
        isMixed = fluidTypeCount > 1,
        isWater = fluidTypeName == "Water" or fluidTypeName == "TaintedWater",
        isTainted = fluidTypeName == "TaintedWater",
    }
end

local function rebalanceSummary(summary, remainingAmount)
    local fluidTypeName = remainingAmount > 0 and summary.fluidTypeName or nil
    local totalCapacity = math.max(summary.totalCapacity or 0, 0)
    local ratio = totalCapacity > 0 and math.min(remainingAmount / totalCapacity, 1) or 0

    for _, descriptor in ipairs(summary.descriptors) do
        local nextAmount = (descriptor.capacity or 0) * ratio
        Adapter.writeDescriptorWaterAmount(descriptor, nextAmount, fluidTypeName)
    end
end

function NetworkAccess.getSummary(endpointObject)
    return buildSummary(endpointObject)
end

function NetworkAccess.isNetworkBackedEndpoint(endpointObject)
    return buildSummary(endpointObject) ~= nil
end

function NetworkAccess.getUsableWaterSummary(endpointObject)
    local summary = buildSummary(endpointObject)
    if not summary or summary.isMixed or not summary.isWater or summary.totalAmount <= 0 then
        return nil
    end
    return summary
end

function NetworkAccess.getFluidAmount(endpointObject)
    local summary = NetworkAccess.getUsableWaterSummary(endpointObject)
    return summary and summary.totalAmount or 0
end

function NetworkAccess.getFluidCapacity(endpointObject)
    local summary = buildSummary(endpointObject)
    return summary and summary.totalCapacity or 0
end

function NetworkAccess.isTaintedWater(endpointObject)
    local summary = NetworkAccess.getUsableWaterSummary(endpointObject)
    return summary and summary.isTainted or false
end

function NetworkAccess.hasFluid(endpointObject)
    return NetworkAccess.getFluidAmount(endpointObject) > 0
end

function NetworkAccess.hasWater(endpointObject)
    return NetworkAccess.hasFluid(endpointObject)
end

function NetworkAccess.canTransferFluidTo(endpointObject, targetContainer)
    local summary = NetworkAccess.getUsableWaterSummary(endpointObject)
    if not summary or not targetContainer or not targetContainer.canAddFluid then
        return false
    end

    local fluidType = getFluidTypeByName(summary.fluidTypeName)
    if not fluidType then
        return false
    end

    local ok, canAdd = pcall(targetContainer.canAddFluid, targetContainer, fluidType)
    return ok and canAdd
end

function NetworkAccess.useFluid(endpointObject, amount)
    local summary = NetworkAccess.getUsableWaterSummary(endpointObject)
    if not summary then
        return 0
    end

    local clamped = math.min(math.max(amount or 0, 0), summary.totalAmount)
    if clamped <= 0 then
        return 0
    end

    rebalanceSummary(summary, summary.totalAmount - clamped)
    return clamped
end

function NetworkAccess.restoreFluid(endpointObject, amount, fluidTypeName)
    local summary = buildSummary(endpointObject)
    if not summary or not isWaterTypeName(fluidTypeName) then
        return 0
    end

    if summary.isMixed then
        return 0
    end

    if summary.totalAmount > 0 and summary.fluidTypeName and summary.fluidTypeName ~= fluidTypeName then
        return 0
    end

    local clamped = math.max(amount or 0, 0)
    local availableCapacity = math.max((summary.totalCapacity or 0) - (summary.totalAmount or 0), 0)
    local restored = math.min(clamped, availableCapacity)
    if restored <= 0 then
        return 0
    end

    summary.fluidTypeName = summary.fluidTypeName or fluidTypeName
    rebalanceSummary(summary, summary.totalAmount + restored)
    return restored
end

function NetworkAccess.transferFluidTo(endpointObject, targetContainer, amount)
    local summary = NetworkAccess.getUsableWaterSummary(endpointObject)
    if not summary or not targetContainer or not targetContainer.addFluid then
        return 0
    end

    local fluidType = getFluidTypeByName(summary.fluidTypeName)
    if not fluidType then
        return 0
    end

    local requested = math.min(math.max(amount or 0, 0), summary.totalAmount)
    if requested <= 0 then
        return 0
    end

    local beforeAmount = targetContainer.getAmount and targetContainer:getAmount() or 0
    local ok = pcall(targetContainer.addFluid, targetContainer, fluidType, requested)
    if not ok then
        return 0
    end

    local afterAmount = targetContainer.getAmount and targetContainer:getAmount() or (beforeAmount + requested)
    local transferred = math.max(afterAmount - beforeAmount, 0)
    if transferred <= 0 then
        return 0
    end

    NetworkAccess.useFluid(endpointObject, transferred)
    return transferred
end

function NetworkAccess.moveFluidToTemporaryContainer(endpointObject, amount)
    local summary = NetworkAccess.getUsableWaterSummary(endpointObject)
    if not summary or not FluidContainer or not FluidContainer.CreateContainer then
        return nil
    end

    local fluidType = getFluidTypeByName(summary.fluidTypeName)
    if not fluidType then
        return nil
    end

    local taken = math.min(math.max(amount or 0, 0), summary.totalAmount)
    if taken <= 0 then
        return nil
    end

    local temporaryContainer = FluidContainer.CreateContainer()
    if not temporaryContainer then
        return nil
    end

    local ok = pcall(temporaryContainer.addFluid, temporaryContainer, fluidType, taken)
    if not ok then
        if FluidContainer.DisposeContainer then
            FluidContainer.DisposeContainer(temporaryContainer)
        end
        return nil
    end

    NetworkAccess.useFluid(endpointObject, taken)
    return temporaryContainer
end
