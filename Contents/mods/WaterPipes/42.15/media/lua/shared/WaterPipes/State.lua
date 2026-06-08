WaterPipes = WaterPipes or {}
WaterPipes.State = WaterPipes.State or {}

require "WaterPipes/Constants"
require "WaterPipes/Logger"
require "WaterPipes/NetworkGraph"
require "WaterPipes/PipeObjectUtils"

local Constants = WaterPipes.Constants
local Graph = WaterPipes.NetworkGraph
local Logger = WaterPipes.Logger
local PipeObjectUtils = WaterPipes.PipeObjectUtils
local State = WaterPipes.State

local function getSquareAt(x, y, z)
    if not getCell then
        return nil
    end
    local cell = getCell()
    return cell and cell.getGridSquare and cell:getGridSquare(x, y, z) or nil
end

local fallbackState = nil

local function getRawState()
    if ModData and ModData.getOrCreate then
        return ModData.getOrCreate(Constants.MOD_DATA_KEY)
    end

    fallbackState = fallbackState or {}
    return fallbackState
end

local function ensureStateShape(state)
    state.version = state.version or Constants.STATE_VERSION
    state.pipes = state.pipes or {}
    state.containers = state.containers or {}
    state.graph = state.graph or Graph.new()
    state.lastRebuild = state.lastRebuild or 0
    return state
end

function State.squareKey(x, y, z)
    return tostring(x) .. ":" .. tostring(y) .. ":" .. tostring(z)
end

function State.pipeNodeId(x, y, z)
    return Constants.NODE_KIND_PIPE .. ":" .. State.squareKey(x, y, z)
end

function State.containerNodeId(containerKey)
    return Constants.NODE_KIND_CONTAINER .. ":" .. tostring(containerKey)
end

function State.ensure()
    return ensureStateShape(getRawState())
end

function State.registerPipe(x, y, z, metadata)
    local state = State.ensure()
    local key = State.squareKey(x, y, z)

    state.pipes[key] = {
        x = x,
        y = y,
        z = z,
        metadata = metadata or {},
    }

    Logger.log("Registered pipe at " .. key)
    return state.pipes[key]
end

function State.unregisterPipe(x, y, z)
    local state = State.ensure()
    local key = State.squareKey(x, y, z)
    state.pipes[key] = nil
    Logger.log("Unregistered pipe at " .. key)
end

function State.replaceContainers(containerMap)
    local state = State.ensure()
    state.containers = {}

    for key, containerData in pairs(containerMap or {}) do
        state.containers[key] = {
            key = containerData.key,
            squareKey = containerData.squareKey,
            x = containerData.x,
            y = containerData.y,
            z = containerData.z,
            objectIndex = containerData.objectIndex,
            containerIndex = containerData.containerIndex,
            capacity = containerData.capacity,
            waterAmount = containerData.waterAmount,
        }
    end
end

function State.rebuildGraph()
    local state = State.ensure()
    Graph.clear(state.graph)

    for pipeKey, pipeData in pairs(state.pipes) do
        local nodeId = State.pipeNodeId(pipeData.x, pipeData.y, pipeData.z)
        Graph.addNode(state.graph, nodeId, {
            kind = Constants.NODE_KIND_PIPE,
            key = pipeKey,
            x = pipeData.x,
            y = pipeData.y,
            z = pipeData.z,
            metadata = pipeData.metadata or {},
        })
    end

    for containerKey, containerData in pairs(state.containers) do
        local nodeId = State.containerNodeId(containerKey)
        Graph.addNode(state.graph, nodeId, {
            kind = Constants.NODE_KIND_CONTAINER,
            key = containerKey,
            squareKey = containerData.squareKey,
            x = containerData.x,
            y = containerData.y,
            z = containerData.z,
            objectIndex = containerData.objectIndex,
            containerIndex = containerData.containerIndex,
            capacity = containerData.capacity,
            waterAmount = containerData.waterAmount,
        })
    end

    for _, pipeData in pairs(state.pipes) do
        local pipeNodeId = State.pipeNodeId(pipeData.x, pipeData.y, pipeData.z)

        -- Same-floor neighbours.
        for _, offset in ipairs(Constants.CARDINAL_OFFSETS) do
            Graph.connect(state.graph, pipeNodeId,
                State.pipeNodeId(pipeData.x + offset.x, pipeData.y + offset.y, pipeData.z))
        end

        -- Cross-floor neighbours through wall risers.
        for _, coord in ipairs(PipeObjectUtils.getRiserVerticalNeighborCoords(pipeData.x, pipeData.y, pipeData.z)) do
            Graph.connect(state.graph, pipeNodeId, State.pipeNodeId(coord.x, coord.y, coord.z))
        end
    end

    for containerKey, containerData in pairs(state.containers) do
        local containerNodeId = State.containerNodeId(containerKey)
        -- A container attaches only to the pipe on its OWN tile.
        local squareNodeId = State.pipeNodeId(containerData.x, containerData.y, containerData.z)
        Graph.connect(state.graph, containerNodeId, squareNodeId)
    end

    state.lastRebuild = getTimestampMs and getTimestampMs() or 0
    return state.graph
end

function State.getComponents()
    local state = State.ensure()
    return Graph.getComponents(state.graph)
end
