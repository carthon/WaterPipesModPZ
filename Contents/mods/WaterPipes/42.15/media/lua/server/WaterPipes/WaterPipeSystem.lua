WaterPipes = WaterPipes or {}
WaterPipes.System = WaterPipes.System or {}

require "WaterPipes/Constants"
require "WaterPipes/Logger"
require "WaterPipes/State"
require "WaterPipes/ContainerAdapter"
require "WaterPipes/EndpointAdapterSource"
require "WaterPipes/EndpointFluidSource"
require "WaterPipes/EndpointPlumbing"
require "WaterPipes/EndpointObjects"
require "WaterPipes/PipeObjectUtils"
require "WaterPipes/PipeAutotile"

local Adapter = WaterPipes.ContainerAdapter
local Constants = WaterPipes.Constants
local AdapterSource = WaterPipes.EndpointAdapterSource
local FluidSource = WaterPipes.EndpointFluidSource
local EndpointPlumbing = WaterPipes.EndpointPlumbing
local EndpointObjects = WaterPipes.EndpointObjects
local Logger = WaterPipes.Logger
local PipeObjectUtils = WaterPipes.PipeObjectUtils
local PipeAutotile = WaterPipes.PipeAutotile
local State = WaterPipes.State
local System = WaterPipes.System

local function mergeInto(target, source)
    for key, value in pairs(source) do
        target[key] = value
    end
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

local function refreshPlumbedEndpointsNearCoordinates(coordinates)
    local visited = {}

    for _, position in ipairs(coordinates or {}) do
        local square = getSquare(position.x, position.y, position.z)
        if square then
            for _, endpointObject in ipairs(EndpointObjects.collectOnSquare(square)) do
                local key = tostring(square:getX()) .. ":" .. tostring(square:getY()) .. ":" .. tostring(square:getZ()) .. ":" .. tostring(endpointObject:getObjectIndex())
                if not visited[key] and EndpointPlumbing.isPlumbed(endpointObject) then
                    visited[key] = true
                    EndpointPlumbing.refreshEndpointSource(endpointObject)
                end
            end
        end
    end
end

local function releasePlumbedEndpointReservationsNearCoordinates(coordinates)
    local visited = {}

    for _, position in ipairs(coordinates or {}) do
        local square = getSquare(position.x, position.y, position.z)
        if square then
            for _, endpointObject in ipairs(EndpointObjects.collectOnSquare(square)) do
                local key = tostring(square:getX()) .. ":" .. tostring(square:getY()) .. ":" .. tostring(square:getZ()) .. ":" .. tostring(endpointObject:getObjectIndex())
                if not visited[key] and EndpointPlumbing.isPlumbed(endpointObject) then
                    visited[key] = true
                    EndpointPlumbing.releaseReservation(endpointObject)
                end
            end
        end
    end
end

function System.scanContainersAroundPipes()
    local state = State.ensure()
    local found = {}

    for _, pipeData in pairs(state.pipes) do
        local coordinates = {
            { x = pipeData.x, y = pipeData.y, z = pipeData.z },
        }

        for _, offset in ipairs(Constants.NETWORK_NEIGHBOR_OFFSETS) do
            coordinates[#coordinates + 1] = {
                x = pipeData.x + offset.x,
                y = pipeData.y + offset.y,
                z = pipeData.z + offset.z,
            }
        end

        for _, position in ipairs(coordinates) do
            local square = getSquare(position.x, position.y, position.z)
            if square then
                mergeInto(found, Adapter.collectSquareContainers(square))
            end
        end
    end

    State.replaceContainers(found)
    return found
end

function System.redistributeWater()
    local components = State.getComponents()

    for _, component in ipairs(components) do
        local containers = {}
        local totalCapacity = 0
        local totalWater = 0
        local totalByFluidType = {}
        local fluidTypeCount = 0
        local networkFluidType = nil

        for _, node in pairs(component.nodes) do
            if node.kind == Constants.NODE_KIND_CONTAINER then
                local square = getSquare(node.x, node.y, node.z)
                if square and square.getObjects then
                    local squareContainers = Adapter.collectSquareContainers(square)
                    local containerKey = node.key
                    local descriptor = squareContainers[containerKey]

                    if descriptor and descriptor.container then
                        containers[#containers + 1] = descriptor
                        totalCapacity = totalCapacity + math.max(descriptor.capacity or 0, 0)
                        totalWater = totalWater + math.max(descriptor.waterAmount or 0, 0)
                    elseif descriptor and descriptor.object then
                        containers[#containers + 1] = descriptor
                        totalCapacity = totalCapacity + math.max(descriptor.capacity or 0, 0)
                        totalWater = totalWater + math.max(descriptor.waterAmount or 0, 0)
                    end

                    if descriptor and descriptor.fluidType and (descriptor.waterAmount or 0) > 0 then
                        totalByFluidType[descriptor.fluidType] = (totalByFluidType[descriptor.fluidType] or 0) + descriptor.waterAmount
                    end
                end
            end
        end

        for fluidTypeName in pairs(totalByFluidType) do
            fluidTypeCount = fluidTypeCount + 1
            networkFluidType = fluidTypeName
        end

        if fluidTypeCount <= 1 and #containers > 1 and totalCapacity > 0 then
            local ratio = math.min(totalWater / totalCapacity, 1)

            for _, descriptor in ipairs(containers) do
                local targetWater = (descriptor.capacity or 0) * ratio
                Adapter.writeDescriptorWaterAmount(descriptor, targetWater, networkFluidType)
            end
        elseif fluidTypeCount > 1 then
            Logger.warn("Skipping mixed-fluid network with " .. tostring(fluidTypeCount) .. " fluid types")
        end
    end
end

function System.refreshPlumbedEndpoints()
    local state = State.ensure()
    local coordinates = {}

    for _, pipeData in pairs(state.pipes) do
        local pipeCoordinates = {
            { x = pipeData.x, y = pipeData.y, z = pipeData.z },
        }

        for _, offset in ipairs(Constants.NETWORK_NEIGHBOR_OFFSETS) do
            pipeCoordinates[#pipeCoordinates + 1] = {
                x = pipeData.x + offset.x,
                y = pipeData.y + offset.y,
                z = pipeData.z + offset.z,
            }
        end
        for _, position in ipairs(pipeCoordinates) do
            coordinates[#coordinates + 1] = position
        end
    end

    refreshPlumbedEndpointsNearCoordinates(coordinates)
end

function System.rebuild()
    System.scanContainersAroundPipes()
    State.rebuildGraph()
end

function System.tick()
    local ok, err = pcall(function()
        System.rebuild()
        System.redistributeWater()
        System.refreshPlumbedEndpoints()
        PipeAutotile.refreshList(State.ensure().pipes)
    end)

    if not ok then
        Logger.error("Tick failed: " .. tostring(err))
    end
end

function System.registerPipeAt(x, y, z)
    State.registerPipe(x, y, z)
    System.rebuild()
    System.refreshPlumbedEndpoints()
    PipeAutotile.refreshAround(x, y, z)
end

function System.unregisterPipeAt(x, y, z)
    local coordinates = {
        { x = x, y = y, z = z },
    }

    for _, offset in ipairs(Constants.NETWORK_NEIGHBOR_OFFSETS) do
        coordinates[#coordinates + 1] = {
            x = x + offset.x,
            y = y + offset.y,
            z = z + offset.z,
        }
    end

    releasePlumbedEndpointReservationsNearCoordinates(coordinates)
    State.unregisterPipe(x, y, z)
    System.rebuild()

    refreshPlumbedEndpointsNearCoordinates(coordinates)
    PipeAutotile.refreshAround(x, y, z)
end

function System.forceGlobalWaterShutoff()
    local sandboxOptions = getSandboxOptions and getSandboxOptions() or nil
    if sandboxOptions and sandboxOptions.set then
        sandboxOptions:set("WaterShut", 1)
        sandboxOptions:set("WaterShutModifier", 0)
        if sandboxOptions.toLua then
            sandboxOptions:toLua()
        end
    end

    if SandboxVars then
        SandboxVars.WaterShut = 1
        SandboxVars.WaterShutModifier = 0
    end

    Logger.warn("Debug forced global water shutoff")
end

local function onInitGlobalModData()
    State.ensure()
    System.rebuild()
    System.refreshPlumbedEndpoints()
    PipeAutotile.refreshList(State.ensure().pipes)
    Logger.log("Server state initialized")
end

local function onDestroyIsoThumpable(thump, player)
    if AdapterSource.isAdapterObject(thump) then
        -- Legacy phantom adapter from older saves: let it be removed, never recreate it.
        -- Plumbed endpoints now carry their own FluidContainer (see EndpointFluidSource).
        return
    end

    if not PipeObjectUtils.isPipeObject(thump) then
        return
    end

    local square = thump.getSquare and thump:getSquare() or nil
    if square and #PipeObjectUtils.getPipeObjectsOnSquare(square, thump) > 0 then
        return
    end

    System.unregisterPipeAt(thump:getX(), thump:getY(), thump:getZ())
end

local function onEveryTenMinutes()
    System.tick()
end

local function onEveryOneMinute()
    local ok, err = pcall(System.refreshPlumbedEndpoints)
    if not ok then
        Logger.error("Endpoint plumbing refresh failed: " .. tostring(err))
    end
end

local function onWaterAmountChange(object, prevAmount)
    if not object then
        return
    end

    -- Legacy hidden adapter objects from older saves (handled until cleaned up).
    if AdapterSource.isAdapterObject(object) then
        local ok, err = pcall(AdapterSource.onAdapterWaterAmountChange, object, prevAmount)
        if not ok then
            Logger.error("Adapter water change handler failed: " .. tostring(err))
        end
        return
    end

    -- A plumbed endpoint's own FluidContainer changed: reconcile consumption to the network.
    if EndpointPlumbing.isPlumbed(object) then
        local ok, err = pcall(FluidSource.onEndpointWaterAmountChange, object, prevAmount)
        if not ok then
            Logger.error("Endpoint water change handler failed: " .. tostring(err))
        end
    end
end

local function onClientCommand(module, command, player, args)
    if module ~= "WaterPipes" then
        return
    end

    if command == "forceGlobalWaterShutoff" then
        System.forceGlobalWaterShutoff()
        System.tick()
        sendServerCommand(player, "WaterPipes", "debugWaterShutoffApplied", {})
        return
    end

    if command == "forceNetworkTick" then
        System.tick()
        sendServerCommand(player, "WaterPipes", "debugNetworkTickApplied", {})
    end
end

if Events then
    if Events.OnInitGlobalModData then
        Events.OnInitGlobalModData.Add(onInitGlobalModData)
    end

    if Events.EveryTenMinutes then
        Events.EveryTenMinutes.Add(onEveryTenMinutes)
    end

    if Events.EveryOneMinute then
        Events.EveryOneMinute.Add(onEveryOneMinute)
    end

    if Events.OnDestroyIsoThumpable then
        Events.OnDestroyIsoThumpable.Add(onDestroyIsoThumpable)
    end

    if Events.OnWaterAmountChange then
        Events.OnWaterAmountChange.Add(onWaterAmountChange)
    end

    if Events.OnClientCommand then
        Events.OnClientCommand.Add(onClientCommand)
    end
end
