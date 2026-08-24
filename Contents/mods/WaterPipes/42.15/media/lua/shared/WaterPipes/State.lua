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
    -- Open fire hydrants, keyed by square. A hydrant is a map object, not something we build, so the
    -- drain pass cannot find open ones by scanning pipe squares (an open hydrant with no pipe on its
    -- tile is exactly the case that must still waste water). This persisted set is how it finds them.
    state.openHydrants = state.openHydrants or {}
    -- Where the purifiers are. A purifier cannot exist without a router under it, and both are placed
    -- and destroyed by the player -- so their positions are known at the moment they change and there
    -- is nothing to discover. Kept for the same reason openHydrants is: the alternative is searching
    -- the whole network for them, which is what the per-minute pass used to do once a minute to find
    -- out there were none.
    state.purifiers = state.purifiers or {}
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

function State.setHydrantOpen(x, y, z, open)
    local state = State.ensure()
    local key = State.squareKey(x, y, z)
    if open then
        state.openHydrants[key] = { x = x, y = y, z = z }
    else
        state.openHydrants[key] = nil
    end
end

function State.getOpenHydrants()
    return State.ensure().openHydrants
end

function State.registerPurifier(x, y, z)
    local state = State.ensure()
    state.purifiers[State.squareKey(x, y, z)] = { x = x, y = y, z = z }
end

function State.unregisterPurifier(x, y, z)
    State.ensure().purifiers[State.squareKey(x, y, z)] = nil
end

-- Every registered purifier. Callers must treat an entry as a claim, not a fact: validate it and drop
-- it if the world disagrees, exactly as processHydrants does with an open hydrant. That is what makes
-- the registry safe against the ways a purifier can leave the world without telling us.
function State.getPurifiers()
    return State.ensure().purifiers
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

    local function isRouterAt(x, y, z)
        local data = state.pipes[State.squareKey(x, y, z)]
        return data and data.metadata and data.metadata.router == true or false
    end

    for _, pipeData in pairs(state.pipes) do
        local pipeNodeId = State.pipeNodeId(pipeData.x, pipeData.y, pipeData.z)

        -- Routers are flow boundaries: they never conduct, keeping the IN side and OUT side as two
        -- separate networks. Skip every connection where either endpoint is a router.
        if not (pipeData.metadata and pipeData.metadata.router == true) then
            -- Same-floor neighbours.
            for _, offset in ipairs(Constants.CARDINAL_OFFSETS) do
                local nx, ny, nz = pipeData.x + offset.x, pipeData.y + offset.y, pipeData.z
                if not isRouterAt(nx, ny, nz) then
                    Graph.connect(state.graph, pipeNodeId, State.pipeNodeId(nx, ny, nz))
                end
            end

            -- Cross-floor neighbours through wall risers.
            for _, coord in ipairs(PipeObjectUtils.getRiserVerticalNeighborCoords(pipeData.x, pipeData.y, pipeData.z)) do
                if not isRouterAt(coord.x, coord.y, coord.z) then
                    Graph.connect(state.graph, pipeNodeId, State.pipeNodeId(coord.x, coord.y, coord.z))
                end
            end
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
