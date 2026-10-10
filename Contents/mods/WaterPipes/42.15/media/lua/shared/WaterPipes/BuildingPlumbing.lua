WaterPipes = WaterPipes or {}
WaterPipes.BuildingPlumbing = WaterPipes.BuildingPlumbing or {}

require "WaterPipes/Constants"
require "WaterPipes/PipeObjectUtils"
require "WaterPipes/EndpointObjects"
require "WaterPipes/World"
require "WaterPipes/Logger"
require "WaterPipes/State"
require "WaterPipes/EndpointPlumbing"
require "WaterPipes/WaterPipesBuild"

local Constants = WaterPipes.Constants
local PipeObjectUtils = WaterPipes.PipeObjectUtils
local EndpointObjects = WaterPipes.EndpointObjects
local Logger = WaterPipes.Logger
local BuildingPlumbing = WaterPipes.BuildingPlumbing

-- Plans the concealed pipe tree that connects a building's fixtures to one root tile. Pure: it reads the
-- world through a `probe` and returns a plan. The laid pipe must stay a tree once the game connects it,
-- so one valve isolates one subtree.
--
-- probe (all coordinates are absolute):
--   isBuildingTile(x, y, z) -> boolean   inside the building being plumbed, and able to hold a pipe
--   hasPipe(x, y, z)        -> boolean   a pipe is already there; the plan reuses it and pays nothing
--   wallEdge(x, y, z)       -> "N"|"W"|nil   the wall THIS tile owns, if any (risers need one)
--   hasRiser(x, y, z, edge) -> boolean   a riser already stands on that tile and edge
--   riserEdges(x, y, z)     -> "N"|"W"|"NW"|nil   optional: every riser on the tile, whatever wall it owns
--   outsidePipes()          -> { {x=,y=,z=,riser=}, ... }   optional: pipe outside the building that is
--                              joined to it; the plan must not close a ring through it either
--   fixtures()              -> { {x=,y=,z=,name=,plumbed=}, ... }   what we are trying to reach; a
--                              plumbed one is already connected and is never connected again

local FLOOR, RISER = "floor", "riser"

-- Isometric mapping, as everywhere else in the mod: E=+x, W=-x, S=+y, N=-y.
local CARDINALS = {
    { dx = 1, dy = 0 }, { dx = -1, dy = 0 }, { dx = 0, dy = 1 }, { dx = 0, dy = -1 },
}

local function keyOf(x, y, z)
    return x .. ":" .. y .. ":" .. z
end

-- A tile already carrying a pipe costs nothing to "lay": the plan reuses it as a segment, which is
-- also what keeps the generator from ever building over the player's own line.
local function stepCost(probe, x, y, z)
    return probe.hasPipe(x, y, z) and 0 or 1
end

-- Every move out of one tile: horizontal within the building, vertical only through a riser on the lower
-- tile's own North or West wall (a tile owns no other).
local function neighboursOf(probe, x, y, z)
    local out = {}
    for _, offset in ipairs(CARDINALS) do
        local nx, ny = x + offset.dx, y + offset.dy
        if probe.isBuildingTile(nx, ny, z) then
            out[#out + 1] = { x = nx, y = ny, z = z, cost = stepCost(probe, nx, ny, z), kind = FLOOR }
        end
    end

    local edge = probe.wallEdge(x, y, z)
    if edge and probe.isBuildingTile(x, y, z + 1) then
        -- A climb costs the riser on THIS tile (free if one is already there) plus the landing above.
        out[#out + 1] = {
            x = x, y = y, z = z + 1, kind = RISER, edge = edge,
            cost = stepCost(probe, x, y, z + 1) + (probe.hasRiser(x, y, z, edge) and 0 or 1),
        }
    end

    -- ...and down, through a riser on the tile below's own wall.
    local below = probe.isBuildingTile(x, y, z - 1) and probe.wallEdge(x, y, z - 1) or nil
    if below then
        out[#out + 1] = {
            x = x, y = y, z = z - 1, kind = RISER, edge = below,
            cost = stepCost(probe, x, y, z - 1) + (probe.hasRiser(x, y, z - 1, below) and 0 or 1),
        }
    end

    return out
end

local function heapPush(heap, cost, key)
    heap.seq = (heap.seq or 0) + 1
    local item = { cost = cost, seq = heap.seq, key = key }
    local i = #heap + 1
    heap[i] = item
    while i > 1 do
        local parent = math.floor(i / 2)
        local a, b = heap[parent], heap[i]
        if a.cost < b.cost or (a.cost == b.cost and a.seq < b.seq) then break end
        heap[parent], heap[i] = b, a
        i = parent
    end
end

local function heapPop(heap)
    local top = heap[1]
    local last = table.remove(heap)
    if #heap > 0 then
        heap[1] = last
        local i, n = 1, #heap
        while true do
            local l, r, m = 2 * i, 2 * i + 1, i
            local function less(x, y)
                return heap[x].cost < heap[y].cost or (heap[x].cost == heap[y].cost and heap[x].seq < heap[y].seq)
            end
            if l <= n and less(l, m) then m = l end
            if r <= n and less(r, m) then m = r end
            if m == i then break end
            heap[i], heap[m] = heap[m], heap[i]
            i = m
        end
    end
    return top
end

-- Cost from the root to every tile the building lets it reach (climbing only). Orders fixtures nearest
-- first and tells reachable from unreachable.
local function solveTree(probe, origin)
    local originKey = keyOf(origin.x, origin.y, origin.z)
    local dist = { [originKey] = stepCost(probe, origin.x, origin.y, origin.z) }
    local coords = { [originKey] = { x = origin.x, y = origin.y, z = origin.z } }
    local visited = {}
    local frontier = {}
    heapPush(frontier, dist[originKey], originKey)

    while #frontier > 0 do
        local item = heapPop(frontier)
        local key = item.key
        if not visited[key] and item.cost == dist[key] then
            visited[key] = true
            local current = coords[key]
            for _, step in ipairs(neighboursOf(probe, current.x, current.y, current.z)) do
                local nk = keyOf(step.x, step.y, step.z)
                local through = item.cost + step.cost
                if through < (dist[nk] or math.huge) then
                    dist[nk] = through
                    coords[nk] = { x = step.x, y = step.y, z = step.z }
                    heapPush(frontier, through, nk)
                end
            end
        end
    end

    return dist, coords
end

-- ===== Keeping the tree a tree =====
-- Pipe joins its cardinal neighbours on a floor; a riser joins its tile to the one above and the one past
-- its wall. A branch that would close a ring is never laid.
-- A riser map holds "N", "W" or "NW": a tile can carry one on each edge.

local function hasEdge(edges, edge)
    return edges ~= nil and edges:find(edge, 1, true) ~= nil
end

local function withEdge(edges, edge)
    if not edges then
        return edge
    end
    return hasEdge(edges, edge) and edges or (edges .. edge)
end

local function riserTargets(x, y, z, edges)
    local out = { keyOf(x, y, z + 1) }
    if hasEdge(edges, "N") then
        out[#out + 1] = keyOf(x, y - 1, z + 1)
    end
    if hasEdge(edges, "W") then
        out[#out + 1] = keyOf(x - 1, y, z + 1)
    end
    return out
end

-- Keys physically linked to (x, y, z), piped or not, given a riser map.
local function linksOf(x, y, z, riser)
    local out = { keyOf(x + 1, y, z), keyOf(x - 1, y, z), keyOf(x, y + 1, z), keyOf(x, y - 1, z) }
    local own = riser[keyOf(x, y, z)]
    if own then
        for _, k in ipairs(riserTargets(x, y, z, own)) do out[#out + 1] = k end
    end
    if riser[keyOf(x, y, z - 1)] then out[#out + 1] = keyOf(x, y, z - 1) end
    if hasEdge(riser[keyOf(x, y + 1, z - 1)], "N") then out[#out + 1] = keyOf(x, y + 1, z - 1) end
    if hasEdge(riser[keyOf(x + 1, y, z - 1)], "W") then out[#out + 1] = keyOf(x + 1, y, z - 1) end
    return out
end

local function findRoot(parent, k)
    local root = k
    while parent[root] and parent[root] ~= root do
        root = parent[root]
    end
    return root
end

-- Union the links that NEW pipe adds: every link of each new tile in `tiles`, and only the riser's own
-- links for each new riser in `risers` (its tile may be old pipe whose links are already joined).
-- Returns false if any of them closes a ring.
local function joinAll(net, coords, tiles, risers)
    local done, acyclic = {}, true
    local function join(a, b)
        local id = a < b and (a .. "|" .. b) or (b .. "|" .. a)
        if done[id] then
            return
        end
        done[id] = true
        net.parent[a] = net.parent[a] or a
        net.parent[b] = net.parent[b] or b
        local ra, rb = findRoot(net.parent, a), findRoot(net.parent, b)
        if ra == rb then
            acyclic = false
        else
            net.parent[ra] = rb
        end
    end
    for _, k in ipairs(tiles) do
        local c = coords[k]
        net.parent[k] = net.parent[k] or k
        for _, other in ipairs(linksOf(c.x, c.y, c.z, net.riser)) do
            if net.piped[other] then
                join(k, other)
            end
        end
    end
    for k, edge in pairs(risers or {}) do
        local c = coords[k]
        if net.piped[k] then
            for _, other in ipairs(riserTargets(c.x, c.y, c.z, edge)) do
                if net.piped[other] then
                    join(k, other)
                end
            end
        end
    end
    return acyclic
end

local function copyNet(net)
    local out = { piped = {}, riser = {}, parent = {} }
    for k, v in pairs(net.piped) do out.piped[k] = v end
    for k, v in pairs(net.riser) do out.riser[k] = v end
    for k, v in pairs(net.parent) do out.parent[k] = v end
    return out
end

-- Dijkstra from a fixture to the tree. A new tile may touch at most one pipe per component, and if one
-- of them is the tree the route must step straight into it. Returns the path, tree end first, or nil.
local function routeFixture(probe, net, origin, fixture, budget, connectedKeys)
    local originKey = keyOf(origin.x, origin.y, origin.z)
    local function isTarget(k)
        if net.piped[originKey] then
            return net.piped[k] == true and findRoot(net.parent, k) == findRoot(net.parent, originKey)
        end
        return k == originKey
    end
    -- Pipe on the network of an already-connected fixture, other than the origin's: joining it would
    -- connect that fixture again.
    local function isForeign(k)
        if not net.piped[k] or isTarget(k) then
            return false
        end
        local root = findRoot(net.parent, k)
        for _, fk in ipairs(connectedKeys or {}) do
            if net.piped[fk] and findRoot(net.parent, fk) == root then
                return true
            end
        end
        return false
    end

    -- Can tile k be entered from fromKey? Existing pipe always can. Returns ok, forcedNextKey.
    local function admit(k, x, y, z, fromKey, riser)
        if net.piped[k] then
            return true, nil
        end
        local candidates = linksOf(x, y, z, riser or net.riser)
        local comps, seen, forced = {}, {}, nil
        for _, other in ipairs(candidates) do
            if other ~= fromKey and not seen[other] and net.piped[other] then
                if isForeign(other) then
                    return false
                end
                seen[other] = true
                local comp = findRoot(net.parent, other)
                if comps[comp] then
                    return false
                end
                comps[comp] = true
                if isTarget(other) then
                    forced = other
                end
            end
        end
        return true, forced
    end

    local startKey = keyOf(fixture.x, fixture.y, fixture.z)
    if isForeign(startKey) then
        return nil
    end
    local start = { key = startKey, x = fixture.x, y = fixture.y, z = fixture.z,
                    cost = net.piped[startKey] and 0 or 1 }
    if isTarget(startKey) then
        if net.piped[startKey] then
            return {}
        end
        return admit(startKey, start.x, start.y, start.z, nil, nil) and { start } or nil
    end
    local ok, forced = admit(startKey, start.x, start.y, start.z, nil, nil)
    if not ok then
        return nil
    end
    start.forced = forced

    local labels = { [startKey] = start }
    local frontier = {}
    heapPush(frontier, start.cost, startKey)
    local closed = {}

    local function stepsFrom(c)
        local out = {}
        for _, offset in ipairs(CARDINALS) do
            local nx, ny = c.x + offset.dx, c.y + offset.dy
            if probe.isBuildingTile(nx, ny, c.z) then
                out[#out + 1] = { x = nx, y = ny, z = c.z }
            end
        end
        local up = probe.wallEdge(c.x, c.y, c.z)
        if up and probe.isBuildingTile(c.x, c.y, c.z + 1) then
            out[#out + 1] = { x = c.x, y = c.y, z = c.z + 1, riserAt = { x = c.x, y = c.y, z = c.z }, edge = up }
        end
        if probe.isBuildingTile(c.x, c.y, c.z - 1) then
            local down = probe.wallEdge(c.x, c.y, c.z - 1)
            if down then
                out[#out + 1] = { x = c.x, y = c.y, z = c.z - 1,
                                  riserAt = { x = c.x, y = c.y, z = c.z - 1 }, edge = down }
            end
        end
        return out
    end

    while #frontier > 0 do
        local item = heapPop(frontier)
        local best = labels[item.key]
        if best.cost > budget then
            return nil, "overCap"
        end

        if not closed[best.key] and item.cost == best.cost then
            closed[best.key] = true

            -- Forced onto the tree, the tile already joins it through that link: the route ends here.
            -- The tree tile may be outside the building, where no step can land.
            if isTarget(best.key) or (best.forced and isTarget(best.forced)) then
                local path, node = {}, best
                while node do
                    path[#path + 1] = node
                    node = node.prev and labels[node.prev] or nil
                end
                return path
            end

            -- The route so far and the risers it lays: a step must not link back into it anywhere but
            -- the tile it came from, or the branch closes a ring of its own.
            local chain, chainRisers = {}, {}
            local cursor = best
            while cursor do
                chain[cursor.key] = true
                if cursor.riserAt and cursor.newRiser then
                    -- Added to whatever riser the tile already carries, never in place of it.
                    local rk = keyOf(cursor.riserAt.x, cursor.riserAt.y, cursor.riserAt.z)
                    chainRisers[rk] = withEdge(rawget(chainRisers, rk) or net.riser[rk], cursor.edge)
                end
                cursor = cursor.prev and labels[cursor.prev] or nil
            end
            local chainView = setmetatable(chainRisers, { __index = net.riser })

            for _, s in ipairs(stepsFrom(best)) do
                local nk = keyOf(s.x, s.y, s.z)
                if not closed[nk] and (not best.forced or best.forced == nk) and not isForeign(nk) then
                    local cost = best.cost + (net.piped[nk] and 0 or 1)
                    local view, newRiser = chainView, false
                    if s.riserAt then
                        local rk = keyOf(s.riserAt.x, s.riserAt.y, s.riserAt.z)
                        newRiser = not hasEdge(view[rk], s.edge)
                        if newRiser then
                            cost = cost + 1
                            view = setmetatable({ [rk] = withEdge(view[rk], s.edge) }, { __index = chainView })
                        end
                    end
                    local selfLinked = false
                    for _, other in ipairs(linksOf(s.x, s.y, s.z, view)) do
                        if other ~= best.key and chain[other] then
                            selfLinked = true
                            break
                        end
                    end
                    if not selfLinked and (not labels[nk] or cost < labels[nk].cost) then
                        local admitted, nextForced = admit(nk, s.x, s.y, s.z, best.key, view)
                        if admitted then
                            labels[nk] = { key = nk, x = s.x, y = s.y, z = s.z, cost = cost, prev = best.key,
                                           forced = nextForced, riserAt = s.riserAt, edge = s.edge,
                                           newRiser = newRiser }
                            heapPush(frontier, cost, nk)
                        end
                    end
                end
            end
        end
    end
    return nil
end

-- One plan for one fixture order.
local BUILDING_PLAN_RETRIES = 3

local function planOnce(origin, probe, dist, coords, reachable, maxTiles, connectedKeys)
    local plan = { placements = {}, connected = {}, skipped = {}, cost = 0, cappedAt = false,
                   order = reachable }

    -- The existing pipe, as the game connects it.
    local net = { piped = {}, riser = {}, parent = {} }
    local existing = {}
    for key in pairs(dist) do
        local c = coords[key]
        local x, y, z = c.x, c.y, c.z
        local edges
        if probe.riserEdges then
            edges = probe.riserEdges(x, y, z)
        else
            local edge = probe.wallEdge(x, y, z)
            edges = edge and probe.hasRiser(x, y, z, edge) and edge or nil
        end
        net.riser[key] = edges
        -- A riser is a pipe object: its tile joins its neighbours with no floor pipe under it.
        if probe.hasPipe(x, y, z) or edges then
            net.piped[key] = true
            existing[#existing + 1] = key
        end
    end
    -- Pipe outside joins the same union-find: a branch touching it twice closes a ring all the same.
    for _, c in ipairs(probe.outsidePipes and probe.outsidePipes() or {}) do
        local key = keyOf(c.x, c.y, c.z)
        if not net.piped[key] then
            net.piped[key] = true
            net.riser[key] = c.riser
            coords[key] = coords[key] or { x = c.x, y = c.y, z = c.z }
            existing[#existing + 1] = key
        end
    end
    table.sort(existing)
    joinAll(net, coords, existing)

    for _, entry in ipairs(reachable) do
        local path, why = routeFixture(probe, net, origin, entry.fixture, maxTiles - plan.cost, connectedKeys)
        if not path then
            if why == "overCap" then
                plan.cappedAt = true
            end
            plan.skipped[#plan.skipped + 1] = { fixture = entry.fixture, reason = why or "noRoute" }
        else
            -- Tree end first: each tile, then the riser that climbs from it to the next tile out. An
            -- interrupted pass therefore always leaves a connected tree.
            local branch, trial, touched, risersLaid = {}, copyNet(net), {}, {}
            for index = 1, #path do
                local node = path[index]
                if not net.piped[node.key] then
                    branch[#branch + 1] = { x = node.x, y = node.y, z = node.z, kind = FLOOR, key = node.key }
                    trial.piped[node.key] = true
                    touched[#touched + 1] = node.key
                end
                if node.riserAt and node.newRiser then
                    local rk = keyOf(node.riserAt.x, node.riserAt.y, node.riserAt.z)
                    branch[#branch + 1] = { x = node.riserAt.x, y = node.riserAt.y, z = node.riserAt.z,
                                            kind = RISER, edge = node.edge, key = rk .. ":riser:" .. node.edge }
                    trial.riser[rk] = withEdge(trial.riser[rk], node.edge)
                    risersLaid[rk] = node.edge
                    if not coords[rk] then
                        coords[rk] = { x = node.riserAt.x, y = node.riserAt.y, z = node.riserAt.z }
                    end
                end
            end
            for _, k in ipairs(touched) do
                if not coords[k] then
                    local x, y, z = k:match("^(-?%d+):(-?%d+):(-?%d+)$")
                    coords[k] = { x = tonumber(x), y = tonumber(y), z = tonumber(z) }
                end
            end

            if #branch > 0 and not joinAll(trial, coords, touched, risersLaid) then
                plan.skipped[#plan.skipped + 1] = { fixture = entry.fixture, reason = "wouldLoop" }
            elseif plan.cost + #branch > maxTiles then
                -- Whole fixtures only: half a branch reaches nothing and would still cost pipe.
                plan.cappedAt = true
                plan.skipped[#plan.skipped + 1] = { fixture = entry.fixture, reason = "overCap" }
            else
                net = trial
                for _, placement in ipairs(branch) do
                    plan.placements[#plan.placements + 1] = placement
                end
                plan.cost = plan.cost + #branch
                plan.connected[#plan.connected + 1] = entry.fixture
            end
        end
    end

    return plan
end

-- Plan the tree. opts.maxTiles caps one pass: over it the nearest fixtures are taken and a re-run extends.
function BuildingPlumbing.plan(origin, probe, opts)
    opts = opts or {}
    local maxTiles = opts.maxTiles or Constants.BUILDING_PLUMB_MAX_TILES

    if not origin or not probe or not probe.isBuildingTile(origin.x, origin.y, origin.z) then
        return { placements = {}, connected = {}, skipped = {}, alreadyConnected = {}, cost = 0, cappedAt = false }
    end

    local dist, coords = solveTree(probe, origin)

    -- Nearest first, so a capped pass lays the plumbing the player is standing next to.
    local reachable, unreachable, alreadyConnected, connectedKeys = {}, {}, {}, {}
    for _, fixture in ipairs(probe.fixtures() or {}) do
        local d = dist[keyOf(fixture.x, fixture.y, fixture.z)]
        if fixture.plumbed then
            alreadyConnected[#alreadyConnected + 1] = fixture
            connectedKeys[#connectedKeys + 1] = keyOf(fixture.x, fixture.y, fixture.z)
        elseif d then
            reachable[#reachable + 1] = { fixture = fixture, dist = d }
        else
            unreachable[#unreachable + 1] = fixture
        end
    end
    table.sort(reachable, function(left, right)
        if left.dist ~= right.dist then
            return left.dist < right.dist
        end
        return keyOf(left.fixture.x, left.fixture.y, left.fixture.z)
            < keyOf(right.fixture.x, right.fixture.y, right.fixture.z)
    end)

    -- Fixtures are routed one at a time, so an early route can wall in a later fixture. When that
    -- happens and the pass is not capped, retry with the walled-in fixtures first and keep the plan
    -- that connects the most (then costs the least).
    table.sort(connectedKeys)
    local plan = planOnce(origin, probe, dist, coords, reachable, maxTiles, connectedKeys)
    local last = plan
    local attempts = { plan }
    for _ = 1, BUILDING_PLAN_RETRIES do
        if last.cappedAt then
            break
        end
        -- Counted, not asked with next(): PZ's Lua does not expose it.
        local failed, failedCount = {}, 0
        for _, s in ipairs(last.skipped) do
            if s.reason == "noRoute" and not failed[s.fixture] then
                failed[s.fixture] = true
                failedCount = failedCount + 1
            end
        end
        if failedCount == 0 then
            break
        end
        local order = {}
        for _, entry in ipairs(last.order) do
            if failed[entry.fixture] then order[#order + 1] = entry end
        end
        for _, entry in ipairs(last.order) do
            if not failed[entry.fixture] then order[#order + 1] = entry end
        end
        last = planOnce(origin, probe, dist, coords, order, maxTiles, connectedKeys)
        attempts[#attempts + 1] = last
        if #last.connected > #plan.connected
            or (#last.connected == #plan.connected and last.cost < plan.cost) then
            plan = last
        end
    end

    for _, fixture in ipairs(unreachable) do
        -- Another floor with no wall to climb is fixable by the player; walled off on its own floor is not.
        plan.skipped[#plan.skipped + 1] = {
            fixture = fixture, reason = fixture.z ~= origin.z and "noClimb" or "noRoute",
        }
    end
    -- What every attempt managed, when one of them left a fixture out. A fixture that no ordering
    -- reaches is walled in; one that only the retries reach was passed over for a plan that connects
    -- more, and moving to another root tile is what connects it.
    if #plan.skipped > 0 and Logger and #attempts > 0 then
        local scores = {}
        for index, attempt in ipairs(attempts) do
            scores[index] = string.format("%d for %d", #attempt.connected, attempt.cost)
        end
        Logger.log(string.format("Building plumbing plan: kept %d fixture(s) for %d tile(s) of %d attempt(s) [%s]",
            #plan.connected, plan.cost, #attempts, table.concat(scores, ", ")))
    end

    plan.order = nil
    plan.alreadyConnected = alreadyConnected
    -- What the pass will cost, in pipes: the tile count is what gets LAID, not what gets paid.
    plan.pipes = BuildingPlumbing.pipesFor(#plan.connected)
    return plan
end

-- Whether a pass has anything to do: pipe to lay, or a fixture already on pipe that is not connected.
function BuildingPlumbing.hasWork(plan)
    return plan ~= nil and (#(plan.placements or {}) > 0 or #(plan.connected or {}) > 0)
end

-- ===== The world-facing half =====
-- Everything above is pure. This builds the probe it reads, and it is the only part that touches PZ.

local function squareAt(x, y, z)
    local World = WaterPipes.World
    return World and World.squareAt and World.squareAt(x, y, z) or nil
end

local function hasFlag(square, flagName)
    if not IsoFlagType or IsoFlagType[flagName] == nil then
        return false
    end
    local props = square.getProperties and square:getProperties() or nil
    if not props or not props.has then
        return false
    end
    local ok, value = pcall(props.has, props, IsoFlagType[flagName])
    return ok and value or false
end

-- The wall THIS tile owns. In PZ a tile owns only its North and West walls -- the South and East ones
-- belong to the neighbouring tiles -- which is why the mod's risers exist for those two edges alone.
local function wallEdgeOf(square)
    if hasFlag(square, "WallN") or hasFlag(square, "WallNW") then
        return "N"
    end
    if hasFlag(square, "WallW") then
        return "W"
    end
    return nil
end


-- Can a floor pipe stand here? Only a floor is needed: as in the engine's placement check, a blocked
-- square only stops a solid object, and a sink's own tile must take the pipe it is plumbed through.
local function canHoldPipe(square)
    if not square or not square.hasFloor then
        return false
    end
    local okFloor, floored = pcall(square.hasFloor, square)
    return okFloor and floored or false
end

-- Read the building once by flooding from the clicked tile over squares of the same IsoBuilding, nearest
-- first. Returns a probe for BuildingPlumbing.plan, or nil outside a building.
function BuildingPlumbing.probeAt(originSquare)
    if not originSquare or not originSquare.getBuilding then
        return nil
    end
    local okBuilding, building = pcall(originSquare.getBuilding, originSquare)
    if not okBuilding or not building then
        -- Silence here is what left a player with an empty log and a refusal they could not explain.
        Logger.warn(string.format("Building plumbing: no building at %d:%d:%d (getBuilding %s)",
            originSquare:getX(), originSquare:getY(), originSquare:getZ(),
            okBuilding and "returned nil" or "threw"))
        return nil
    end

    local ox, oy = originSquare:getX(), originSquare:getY()
    local maxTiles = Constants.BUILDING_PLUMB_MAX_SCAN_TILES
    local truncated = false

    local tiles = {}         -- key -> true, every tile a pipe may stand on
    local walls = {}         -- key -> "N"/"W"
    local piped = {}         -- key -> true, a floor pipe is already there
    local risers = {}        -- key -> "N"/"W"/"NW", every riser on the tile, whatever wall it owns
    local fixtures = {}
    local admitted = {}      -- the tiles in flood order, for the outside sweep below

    local function riserEdgesOf(square)
        local edges = nil
        for _, edge in ipairs({ "N", "W" }) do
            if WaterPipes.Build.squareHasRiserEdge(square, edge) then
                edges = withEdge(edges, edge)
            end
        end
        return edges
    end

    local function admit(square)
        local x, y, z = square:getX(), square:getY(), square:getZ()
        local key = keyOf(x, y, z)
        tiles[key] = true
        admitted[#admitted + 1] = { x = x, y = y, z = z }
        walls[key] = wallEdgeOf(square)
        piped[key] = WaterPipes.Build.squareHasFloorPipe(square)
        risers[key] = riserEdgesOf(square)
        for _, endpointObject in ipairs(EndpointObjects.collectOnSquare(square)) do
            fixtures[#fixtures + 1] = {
                x = x, y = y, z = z,
                object = endpointObject,
                name = endpointObject.getName and endpointObject:getName() or nil,
                plumbed = WaterPipes.EndpointPlumbing.isPlumbed(endpointObject),
            }
        end
    end

    local seen = {}
    local queue = { originSquare }
    seen[keyOf(ox, oy, originSquare:getZ())] = true

    local index = 1
    while index <= #queue do
        if index > maxTiles then
            truncated = true
            break
        end
        local square = queue[index]
        index = index + 1
        admit(square)

        local x, y, z = square:getX(), square:getY(), square:getZ()
        local function consider(nx, ny, nz)
            local key = keyOf(nx, ny, nz)
            if seen[key] then
                return
            end
            seen[key] = true
            local neighbour = squareAt(nx, ny, nz)
            if not neighbour then
                return
            end
            local okNeighbourBuilding, neighbourBuilding = pcall(neighbour.getBuilding, neighbour)
            if not okNeighbourBuilding or neighbourBuilding ~= building then
                return
            end
            if not canHoldPipe(neighbour) then
                return
            end
            queue[#queue + 1] = neighbour
        end

        for _, offset in ipairs(CARDINALS) do
            consider(x + offset.dx, y + offset.dy, z)
        end
        -- Floors are part of the building whether or not a riser can reach them; whether a pipe may
        -- actually climb is the planner's rule, not this one's.
        consider(x, y, z + 1)
        consider(x, y, z - 1)
    end

    -- The origin has to be usable itself, or there is nothing to root the tree on.
    if not canHoldPipe(originSquare) then
        Logger.warn(string.format(
            "Building plumbing: %d:%d:%d is in a building but cannot take a pipe (no floor).",
            ox, oy, originSquare:getZ()))
        return nil
    end

    -- Pipe outside that touches the building, followed as far as it runs: a branch that joins it twice
    -- closes a ring through it as surely as through pipe indoors.
    local outside, outsideSeen = {}, {}
    local function noteOutside(x, y, z)
        local key = keyOf(x, y, z)
        if tiles[key] or outsideSeen[key] then
            return
        end
        outsideSeen[key] = true
        local square = squareAt(x, y, z)
        if not square then
            return
        end
        local edges = riserEdgesOf(square)
        if edges or WaterPipes.Build.squareHasFloorPipe(square) then
            outside[#outside + 1] = { x = x, y = y, z = z, riser = edges }
        end
    end
    local function linksOut(c)
        for _, offset in ipairs(CARDINALS) do
            noteOutside(c.x + offset.dx, c.y + offset.dy, c.z)
        end
        for _, v in ipairs(PipeObjectUtils.getRiserVerticalNeighborCoords(c.x, c.y, c.z)) do
            noteOutside(v.x, v.y, v.z)
        end
    end
    for _, c in ipairs(admitted) do
        linksOut(c)
    end
    local cursor = 1
    while cursor <= #outside and cursor <= maxTiles do
        linksOut(outside[cursor])
        cursor = cursor + 1
    end
    -- Not followed to its end, a ring through the rest of it cannot be seen: say so.
    local outsideTruncated = cursor <= #outside
    if outsideTruncated then
        Logger.warn(string.format(
            "Building plumbing: the pipe outside this building runs past %d tiles; past that a ring through "
            .. "it cannot be seen, so check the plan before closing any valve on it.", maxTiles))
    end

    Logger.log(string.format("Building plumbing scan at %d:%d:%d -> %d tile(s), %d fixture(s), %d pipe tile(s) outside%s",
        ox, oy, originSquare:getZ(), math.min(index - 1, #queue), #fixtures, #outside,
        truncated and " (stopped at the scan limit)" or ""))

    return {
        isBuildingTile = function(x, y, z) return tiles[keyOf(x, y, z)] == true end,
        hasPipe = function(x, y, z) return piped[keyOf(x, y, z)] == true end,
        wallEdge = function(x, y, z) return walls[keyOf(x, y, z)] end,
        hasRiser = function(x, y, z, edge) return edge ~= nil and hasEdge(risers[keyOf(x, y, z)], edge) end,
        riserEdges = function(x, y, z) return risers[keyOf(x, y, z)] end,
        outsidePipes = function() return outside end,
        outsideTruncated = outsideTruncated,
        fixtures = function() return fixtures end,
        truncated = truncated,
    }
end

-- ===== Laying it =====
-- Built without a cursor, as vanilla's map-object scripts do: create the IsoThumpable and associate its
-- entity script from the face sprite, or the object reloads as "EntityScript not found".

local FACE_FOR = {
    [FLOOR] = function() return Constants.PIPE_HIDDEN_FACE_SPRITE end,
    [RISER] = function(edge)
        return edge == "W" and Constants.PIPE_HIDDEN_RISER_FACE_W or Constants.PIPE_HIDDEN_RISER_FACE_N
    end,
}

-- Health of a generated pipe. Matched to a hand-built one so a zombie does not find the building's
-- plumbing softer than the player's own line.
local GENERATED_HEALTH = 200

-- Lay ONE pipe. Returns the object, true when the server was asked to lay it, or nil and a reason.
-- World objects are created by the server, so a client sends one request per tile.
function BuildingPlumbing.place(placement, player)
    if isClient and isClient() then
        if not player then
            return nil, "noPlayer"
        end
        sendClientCommand(player, "WaterPipes", "placeBuildingPipe", {
            x = placement.x, y = placement.y, z = placement.z,
            kind = placement.kind, edge = placement.edge,
        })
        return true
    end

    local square = squareAt(placement.x, placement.y, placement.z)
    if not square then
        return nil, "noSquare"
    end

    local faceSprite = FACE_FOR[placement.kind](placement.edge)
    local info = SpriteConfigManager and SpriteConfigManager.getObjectInfoFromSprite
        and SpriteConfigManager.getObjectInfoFromSprite(faceSprite) or nil
    local script = info and info.getScript and info:getScript() or nil
    local parent = script and script.getParent and script:getParent() or nil
    if not parent then
        -- Without the entity script there is no point creating the object: it would not survive a
        -- reload, and a base full of pipes that vanish on relog is worse than a refusal.
        return nil, "noEntityScript"
    end

    local north = placement.kind == RISER and placement.edge == "N" or false
    local object = IsoThumpable.new(getWorld():getCell(), square, faceSprite, north, {})
    object:setIsThumpable(true)
    object:setIsDismantable(true)
    object:setCanPassThrough(true)
    object:setCanBarricade(false)
    object:setIsContainer(false)
    object:setIsDoor(false)
    object:setIsDoorFrame(false)
    object:setBlockAllTheSquare(false)
    object:setName(Constants.PIPE_OBJECT_NAME)
    object:setMaxHealth(GENERATED_HEALTH)
    object:setHealth(GENERATED_HEALTH)

    -- The SAME stamp a hand-built pipe gets, so the two cannot drift apart. Registration is NOT done
    -- here: the pass owes the network one rebuild at the end, never one per tile.
    WaterPipes.Build.stampPipeModData(object, {
        surface = placement.kind == RISER and Constants.PIPE_SURFACE_WALLCOVER
            or Constants.PIPE_SURFACE_FLOOR,
        riser = placement.kind == RISER or nil,
        edge = placement.kind == RISER and placement.edge or nil,
        hidden = true,
        generated = true,
        transmit = false,   -- not on a tile yet; transmitCompleteItemToClients below carries it
    })

    GameEntityFactory.CreateIsoObjectEntity(object, parent, true)
    square:AddSpecialObject(object)
    if object.transmitCompleteItemToClients then
        pcall(object.transmitCompleteItemToClients, object)
    end

    -- Registry only. State.registerPipe does not rebuild; BuildingPlumbing.finish does, once.
    WaterPipes.State.registerPipe(placement.x, placement.y, placement.z, {
        kinds = true, riser = placement.kind == RISER or nil,
    })

    return object
end

-- Everything the network owes after a pass, paid once rather than per pipe laid.
function BuildingPlumbing.finish(placements, player)
    if isClient and isClient() then
        -- The server owns the graph; ask it to settle once. Sprites are derived client-side, never sent.
        if player then
            sendClientCommand(player, "WaterPipes", "finishBuildingPlumbing", {})
        end
    else
        local System = WaterPipes.System
        if System and System.rebuild then
            System.rebuild()
            if System.refreshPlumbedEndpoints then
                System.refreshPlumbedEndpoints()
            end
        end
    end

    local PipeAutotile = WaterPipes.PipeAutotile
    if PipeAutotile and PipeAutotile.refreshAround then
        for _, placement in ipairs(placements or {}) do
            PipeAutotile.refreshAround(placement.x, placement.y, placement.z)
        end
    end
end

-- Connect the fixtures the pass reached. Must run after BuildingPlumbing.finish, which is what makes the
-- network know the new pipes. Per square, as the server command addresses them.
-- `laid` is what the pass actually put down. A pass that ran out of pipe partway can have "connected"
-- a fixture in the plan whose branch never reached the floor, and that fixture must not be plumbed --
-- but asking the WORLD is the wrong way to tell, because in multiplayer a pipe laid on the last tick
-- has not come back from the server yet. That lost both halves of a bathtub: paid for, piped on the
-- server, and never connected, because the client's own square was still empty when this ran.
function BuildingPlumbing.plumbFixtures(plan, player, laid)
    local EndpointPlumbing = WaterPipes.EndpointPlumbing
    local EndpointObjectsModule = WaterPipes.EndpointObjects
    if not EndpointPlumbing or not EndpointObjectsModule then
        return 0
    end

    local laidHere = {}
    for _, placement in ipairs(laid or {}) do
        laidHere[keyOf(placement.x, placement.y, placement.z)] = true
    end

    local seen = {}
    local plumbed = 0

    for _, fixture in ipairs(plan and plan.connected or {}) do
        local key = keyOf(fixture.x, fixture.y, fixture.z)
        if not seen[key] then
            seen[key] = true
            local square = squareAt(fixture.x, fixture.y, fixture.z)
            if laidHere[key] or (square and PipeObjectUtils.getPipeOnSquare(square)) then
                if isClient and isClient() then
                    if player then
                        sendClientCommand(player, "WaterPipes", "plumbEndpointsOnSquare",
                            { x = fixture.x, y = fixture.y, z = fixture.z })
                        -- Counted by fixture, as single player counts, not by command.
                        local waiting = 0
                        for _, endpointObject in ipairs(square and EndpointObjectsModule.collectOnSquare(square) or {}) do
                            if not EndpointPlumbing.isPlumbed(endpointObject) then
                                waiting = waiting + 1
                            end
                        end
                        plumbed = plumbed + math.max(waiting, 1)
                    end
                elseif square then
                    local landed = false
                    for _, endpointObject in ipairs(EndpointObjectsModule.collectOnSquare(square)) do
                        if not EndpointPlumbing.isPlumbed(endpointObject)
                            and EndpointPlumbing.plumb(endpointObject) == true then
                            plumbed = plumbed + 1
                            landed = true
                        end
                    end
                    -- Single player books the fixture against the pass itself; in multiplayer the
                    -- command handler does. Either way only one that connected is booked.
                    if landed then
                        BuildingPlumbing.notePaidFixture(player, fixture.x, fixture.y, fixture.z)
                    end
                end
            end
        end
    end

    return plumbed
end

-- ===== Cost =====

-- Metal pipes one fixture costs, from the BuildingPlumbCostPerFixture sandbox option. The pipe LAID is
-- free: what the player pays for is the fixture connected, however long the run to reach it turned out
-- to be. At 0 the whole pass is free.
function BuildingPlumbing.costPerFixture()
    local sv = SandboxVars and SandboxVars.WaterPipes
    local cost = sv and sv.BuildingPlumbCostPerFixture
    if type(cost) ~= "number" then
        cost = 1
    end
    return math.max(math.floor(cost), 0)
end

function BuildingPlumbing.pipesFor(fixtures)
    return math.max(fixtures or 0, 0) * BuildingPlumbing.costPerFixture()
end

-- Metal only: a generated pipe is stamped metal and pays metal back when dismantled.
function BuildingPlumbing.countPipes(inventory)
    if not inventory or not inventory.getCountTypeRecurse then
        return 0
    end
    local ok, count = pcall(inventory.getCountTypeRecurse, inventory, Constants.PIPE_ITEM_TYPE)
    return ok and count or 0
end

-- ===== A paid pass =====
-- The cost is per fixture, so it is settled when the pass OPENS, against a fixture list this side
-- validates for itself -- a client asking for a hundred free pipes gets counted, not believed. Pipe is
-- then laid free within the pass, and a pass that never reaches a fixture it paid for refunds it.
-- Single player runs the same three calls without the commands.

local passes = {}   -- player key -> { unit, owed = {squareKey -> true}, plumbed = {squareKey -> true} }

-- By username: the online ID changes between sessions, and a pass outlives the session it opened in.
local function playerKey(player)
    local okName, name = pcall(player.getUsername, player)
    if okName and name ~= nil and name ~= "" then
        return name
    end
    local ok, id = pcall(player.getOnlineID, player)
    return ok and id ~= nil and id or "?"
end

local function isWholeNumber(v)
    return type(v) == "number" and v == math.floor(v)
end

-- A plan never leaves the building the player is working in; without a building to compare, fall back
-- to a distance from the player.
local function withinReach(square, x, y, player)
    local function buildingOf(sq)
        if not sq or not sq.getBuilding then
            return nil
        end
        local ok, building = pcall(sq.getBuilding, sq)
        return ok and building or nil
    end
    local here = buildingOf(player.getCurrentSquare and player:getCurrentSquare() or nil)
    local there = buildingOf(square)
    if here and there then
        return here == there
    end
    local reach = Constants.BUILDING_PLUMB_REACH
    return math.abs(x - math.floor(player:getX())) <= reach
        and math.abs(y - math.floor(player:getY())) <= reach
end

local function validRequest(args, player)
    if type(args) ~= "table" or not player then
        return nil, "badRequest"
    end
    if not isWholeNumber(args.x) or not isWholeNumber(args.y) or not isWholeNumber(args.z) then
        return nil, "badRequest"
    end
    if args.kind == FLOOR then
        if args.edge ~= nil then
            return nil, "badRequest"
        end
    elseif args.kind == RISER then
        if args.edge ~= "N" and args.edge ~= "W" then
            return nil, "badRequest"
        end
    else
        return nil, "badRequest"
    end

    local square = squareAt(args.x, args.y, args.z)
    if not square then
        return nil, "noSquare"
    end

    if not withinReach(square, args.x, args.y, player) then
        return nil, "outOfReach"
    end
    local Build = WaterPipes.Build
    if args.kind == FLOOR and Build.squareHasFloorPipe(square) then
        return nil, "alreadyPiped"
    end
    if args.kind == RISER and Build.squareHasRiserEdge(square, args.edge) then
        return nil, "alreadyPiped"
    end

    return { x = args.x, y = args.y, z = args.z, kind = args.kind, edge = args.edge }
end

local function takePipes(inventory, count)
    local taken = 0
    for _ = 1, count do
        local item = inventory:getFirstTypeRecurse(Constants.PIPE_ITEM_TYPE)
        if not item then
            return taken
        end
        local container = item:getContainer() or inventory
        if sendRemoveItemFromContainer then
            sendRemoveItemFromContainer(container, item)
        end
        container:Remove(item)
        taken = taken + 1
    end
    return taken
end

local function givePipes(player, count)
    local inventory = count > 0 and player and player.getInventory and player:getInventory() or nil
    if not inventory or not inventory.AddItem then
        return 0
    end
    local given = 0
    for _ = 1, count do
        local ok, item = pcall(inventory.AddItem, inventory, Constants.PIPE_ITEM_TYPE)
        if not ok or not item then
            break
        end
        if sendAddItemToContainer then
            pcall(sendAddItemToContainer, inventory, item)
        end
        given = given + 1
    end
    return given
end

-- A fixture square the pass may be charged for: inside the player's building, carrying an endpoint
-- that is not connected yet. Counted here rather than taken on trust, so the price is the server's.
local function chargeableFixture(entry, player)
    if type(entry) ~= "table" or not isWholeNumber(entry.x) or not isWholeNumber(entry.y)
        or not isWholeNumber(entry.z) then
        return nil
    end
    local square = squareAt(entry.x, entry.y, entry.z)
    if not square or not withinReach(square, entry.x, entry.y, player) then
        return nil
    end
    local EndpointPlumbing = WaterPipes.EndpointPlumbing
    for _, endpoint in ipairs(EndpointObjects.collectOnSquare(square)) do
        if not EndpointPlumbing.isPlumbed(endpoint) then
            return keyOf(entry.x, entry.y, entry.z)
        end
    end
    return nil
end

-- Open a pass and take its whole price. Returns the pipes charged, or nil and a reason.
function BuildingPlumbing.beginPaidPass(args, player)
    if not player then
        return nil, "badRequest"
    end
    -- The server never hears a client disconnect: a pass still open is one it left behind. Settle it
    -- first, so the fixtures it never reached are paid back.
    if passes[playerKey(player)] then
        BuildingPlumbing.endPaidPass(player)
    end
    local unit = BuildingPlumbing.costPerFixture()
    local owed, count = {}, 0
    for _, entry in ipairs(type(args) == "table" and args.fixtures or {}) do
        local key = chargeableFixture(entry, player)
        if key and not owed[key] then
            owed[key] = true
            count = count + 1
        end
    end

    -- A pass names what it is for; one with nothing to charge would lay pipe for free.
    if count == 0 then
        return nil, "noFixtures"
    end

    local price = count * unit
    local inventory = player.getInventory and player:getInventory() or nil
    if price > 0 and BuildingPlumbing.countPipes(inventory) < price then
        return nil, "noPipes"
    end
    if price > 0 and takePipes(inventory, price) < price then
        return nil, "noPipes"
    end

    passes[playerKey(player)] = { unit = unit, owed = owed, plumbed = {}, laid = 0 }
    return price
end

-- Returns the laid object, or nil and a reason. Pipe is laid free INSIDE a pass and not at all outside
-- one: the pass is what was paid for, and without that gate a client could ask for pipe all day and
-- dismantle it for the metal.
function BuildingPlumbing.placePaid(args, player)
    local pass = player and passes[playerKey(player)]
    if not pass then
        return nil, "noPass"
    end
    if pass.laid >= Constants.BUILDING_PLUMB_MAX_TILES then
        return nil, "overCap"
    end
    local placement, reason = validRequest(args, player)
    if not placement then
        return nil, reason
    end
    local object, why = BuildingPlumbing.place(placement, player)
    if object then
        pass.laid = pass.laid + 1
    end
    return object, why
end

-- Records that the pass reached one of the fixtures it paid for.
function BuildingPlumbing.notePaidFixture(player, x, y, z)
    local pass = player and passes[playerKey(player)]
    if not pass then
        return
    end
    local key = keyOf(x, y, z)
    if pass.owed[key] then
        pass.plumbed[key] = true
    end
end

-- Close the pass and refund the fixtures it was charged for but never reached. Returns the refund.
function BuildingPlumbing.endPaidPass(player)
    local key = player and playerKey(player)
    local pass = key and passes[key]
    if not pass then
        return 0
    end
    passes[key] = nil

    local missed = 0
    for square in pairs(pass.owed) do
        if not pass.plumbed[square] then
            missed = missed + 1
        end
    end
    return givePipes(player, missed * pass.unit)
end

BuildingPlumbing.FLOOR = FLOOR
BuildingPlumbing.RISER = RISER

return BuildingPlumbing
