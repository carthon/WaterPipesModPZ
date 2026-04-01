WaterPipes = WaterPipes or {}
WaterPipes.NetworkGraph = WaterPipes.NetworkGraph or {}

local Graph = WaterPipes.NetworkGraph

local function ensureEdgeTable(graph, nodeId)
    graph.edges[nodeId] = graph.edges[nodeId] or {}
    return graph.edges[nodeId]
end

function Graph.new()
    return {
        nodes = {},
        edges = {},
    }
end

function Graph.clear(graph)
    graph.nodes = {}
    graph.edges = {}
end

function Graph.addNode(graph, nodeId, nodeData)
    graph.nodes[nodeId] = nodeData or {}
    ensureEdgeTable(graph, nodeId)
end

function Graph.removeNode(graph, nodeId)
    graph.nodes[nodeId] = nil
    graph.edges[nodeId] = nil

    for _, neighbors in pairs(graph.edges) do
        neighbors[nodeId] = nil
    end
end

function Graph.connect(graph, leftId, rightId)
    if leftId == rightId then
        return
    end

    if not graph.nodes[leftId] or not graph.nodes[rightId] then
        return
    end

    ensureEdgeTable(graph, leftId)[rightId] = true
    ensureEdgeTable(graph, rightId)[leftId] = true
end

function Graph.disconnect(graph, leftId, rightId)
    if graph.edges[leftId] then
        graph.edges[leftId][rightId] = nil
    end

    if graph.edges[rightId] then
        graph.edges[rightId][leftId] = nil
    end
end

function Graph.getNode(graph, nodeId)
    return graph.nodes[nodeId]
end

function Graph.getComponents(graph)
    local visited = {}
    local components = {}

    for nodeId, nodeData in pairs(graph.nodes) do
        if not visited[nodeId] then
            local stack = { nodeId }
            local component = {
                ids = {},
                nodes = {},
            }

            visited[nodeId] = true

            while #stack > 0 do
                local currentId = table.remove(stack)
                local currentData = graph.nodes[currentId]

                component.ids[#component.ids + 1] = currentId
                component.nodes[currentId] = currentData

                local neighbors = graph.edges[currentId] or {}
                for neighborId, isConnected in pairs(neighbors) do
                    if isConnected and not visited[neighborId] then
                        visited[neighborId] = true
                        stack[#stack + 1] = neighborId
                    end
                end
            end

            components[#components + 1] = component
        end
    end

    return components
end
