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

-- Plans the concealed pipe tree that connects a building's fixtures to one root tile.
--
-- PURE. It reads the world through a `probe` table and returns a plan; it places nothing, spends
-- nothing and touches no global state. That is deliberate: the shape of this tree is the part of the
-- feature with real design risk, and this way it can be exercised against a hand-built world instead
-- of only in game.
--
-- The laid pipe must stay a TREE once the game connects it: then one valve isolates one subtree.
-- A mesh would be cheaper to lay and would make every valve meaningless.

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

-- Every move out of one tile. Horizontal within the building; vertical ONLY through a riser, and a
-- riser only exists on a tile that owns a North or West wall -- in PZ a tile owns no other, which is
-- why the mod has no East/South riser and why this is a hard constraint rather than a preference.
-- A riser lives on the LOWER square and links it to the square above (PipeObjectUtils:229).
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
-- Laid pipe joins its cardinal neighbours on the same floor, and a riser joins its tile to the tile above
-- and to the one past its wall. The plan tracks those physical links and never lays a branch that would
-- close a ring: in a ring a closed valve isolates nothing.

local function riserTargets(x, y, z, edge)
    local out = { keyOf(x, y, z + 1) }
    if edge == "N" then
        out[2] = keyOf(x, y - 1, z + 1)
    elseif edge == "W" then
        out[2] = keyOf(x - 1, y, z + 1)
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
    if riser[keyOf(x, y + 1, z - 1)] == "N" then out[#out + 1] = keyOf(x, y + 1, z - 1) end
    if riser[keyOf(x + 1, y, z - 1)] == "W" then out[#out + 1] = keyOf(x + 1, y, z - 1) end
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
local function routeFixture(probe, net, origin, fixture, budget)
    local originKey = keyOf(origin.x, origin.y, origin.z)
    local function isTarget(k)
        if net.piped[originKey] then
            return net.piped[k] == true and findRoot(net.parent, k) == findRoot(net.parent, originKey)
        end
        return k == originKey
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

            if isTarget(best.key) then
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
                    chainRisers[keyOf(cursor.riserAt.x, cursor.riserAt.y, cursor.riserAt.z)] = cursor.edge
                end
                cursor = cursor.prev and labels[cursor.prev] or nil
            end
            local chainView = setmetatable(chainRisers, { __index = net.riser })

            for _, s in ipairs(stepsFrom(best)) do
                local nk = keyOf(s.x, s.y, s.z)
                if not closed[nk] and (not best.forced or best.forced == nk) then
                    local cost = best.cost + (net.piped[nk] and 0 or 1)
                    local view, newRiser = chainView, false
                    if s.riserAt then
                        local rk = keyOf(s.riserAt.x, s.riserAt.y, s.riserAt.z)
                        newRiser = view[rk] ~= s.edge
                        if newRiser then
                            cost = cost + 1
                            view = setmetatable({ [rk] = s.edge }, { __index = chainView })
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

local function planOnce(origin, probe, dist, coords, reachable, maxTiles)
    local plan = { placements = {}, connected = {}, skipped = {}, cost = 0, cappedAt = false,
                   order = reachable }

    -- The existing pipe, as the game connects it.
    local net = { piped = {}, riser = {}, parent = {} }
    local existing = {}
    for key in pairs(dist) do
        local c = coords[key]
        local x, y, z = c.x, c.y, c.z
        if probe.hasPipe(x, y, z) then
            net.piped[key] = true
            existing[#existing + 1] = key
        end
        local edge = probe.wallEdge(x, y, z)
        if edge and probe.hasRiser(x, y, z, edge) then
            net.riser[key] = edge
        end
    end
    table.sort(existing)
    joinAll(net, coords, existing)

    for _, entry in ipairs(reachable) do
        local path, why = routeFixture(probe, net, origin, entry.fixture, maxTiles - plan.cost)
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
                    trial.riser[rk] = node.edge
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

-- Plan the tree.
--
-- opts.maxTiles caps how much ONE pass may lay. Over the cap the pass takes the fixtures it can reach
-- most cheaply and stops; re-running extends from wherever the player is working.
function BuildingPlumbing.plan(origin, probe, opts)
    opts = opts or {}
    local maxTiles = opts.maxTiles or Constants.BUILDING_PLUMB_MAX_TILES

    if not origin or not probe or not probe.isBuildingTile(origin.x, origin.y, origin.z) then
        return { placements = {}, connected = {}, skipped = {}, cost = 0, cappedAt = false }
    end

    local dist, coords = solveTree(probe, origin)

    -- Nearest first, so a capped pass lays the plumbing the player is standing next to.
    local reachable, unreachable = {}, {}
    for _, fixture in ipairs(probe.fixtures() or {}) do
        local d = dist[keyOf(fixture.x, fixture.y, fixture.z)]
        if d then
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
    local plan = planOnce(origin, probe, dist, coords, reachable, maxTiles)
    local last = plan
    for _ = 1, BUILDING_PLAN_RETRIES do
        if last.cappedAt then
            break
        end
        local failed = {}
        for _, s in ipairs(last.skipped) do
            if s.reason == "noRoute" then failed[s.fixture] = true end
        end
        if next(failed) == nil then
            break
        end
        local order = {}
        for _, entry in ipairs(last.order) do
            if failed[entry.fixture] then order[#order + 1] = entry end
        end
        for _, entry in ipairs(last.order) do
            if not failed[entry.fixture] then order[#order + 1] = entry end
        end
        last = planOnce(origin, probe, dist, coords, order, maxTiles)
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
    plan.order = nil
    return plan
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


-- Can a floor pipe stand here? A floor to stand on, and that is the whole rule.
--
-- It is NOT "nothing solid or placement-blocking in the way", which is what this asked at first and
-- what broke it. The engine's own check (ISBuildIsoEntity.lua:335) rejects a blocked square only when
-- the thing being PLACED is itself solidtrans or BlocksPlacement:
--
--     if (square blocks) and (tileInfoSpriteProps:has(solidtrans) or has("BlocksPlacement")) then
--
-- A floor pipe is neither, so a blocked square is irrelevant to it -- and the mod's own validity says
-- the same: Build.floorOnIsValid asks only whether a floor pipe is already there. Taking the left half
-- of that condition and dropping the right rejected exactly the tiles that matter most: a sink's own
-- tile, which is where the player clicks AND where the mod requires a pipe before a fixture can be
-- plumbed at all.
local function canHoldPipe(square)
    if not square or not square.hasFloor then
        return false
    end
    local okFloor, floored = pcall(square.hasFloor, square)
    return okFloor and floored or false
end

-- Read the building ONCE, by flooding out from the clicked tile over squares belonging to the same
-- IsoBuilding. A flood rather than walking the BuildingDef's room rectangles: it visits only tiles
-- that are really there, it handles every floor and every irregular shape without needing the room
-- geometry, and `square:getBuilding()` is the primitive vanilla itself uses.
--
-- Returns a probe for BuildingPlumbing.plan, or nil when the tile is not inside a building.
function BuildingPlumbing.probeAt(originSquare, radius)
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

    radius = radius or Constants.BUILDING_PLUMB_MAX_RADIUS
    local ox, oy = originSquare:getX(), originSquare:getY()

    local tiles = {}         -- key -> true, every tile a pipe may stand on
    local walls = {}         -- key -> "N"/"W"
    local piped = {}         -- key -> true, a floor pipe is already there
    local risers = {}        -- key -> edge of a riser already on the tile's own wall
    local fixtures = {}

    local function admit(square)
        local x, y, z = square:getX(), square:getY(), square:getZ()
        local key = keyOf(x, y, z)
        tiles[key] = true
        walls[key] = wallEdgeOf(square)
        piped[key] = WaterPipes.Build.squareHasFloorPipe(square)
        if walls[key] and WaterPipes.Build.squareHasRiserEdge(square, walls[key]) then
            risers[key] = walls[key]
        end
        for _, endpointObject in ipairs(EndpointObjects.collectOnSquare(square)) do
            fixtures[#fixtures + 1] = {
                x = x, y = y, z = z,
                object = endpointObject,
                name = endpointObject.getName and endpointObject:getName() or nil,
            }
        end
    end

    local seen = {}
    local queue = { originSquare }
    seen[keyOf(ox, oy, originSquare:getZ())] = true

    local index = 1
    while index <= #queue do
        local square = queue[index]
        index = index + 1
        admit(square)

        local x, y, z = square:getX(), square:getY(), square:getZ()
        local function consider(nx, ny, nz)
            if math.abs(nx - ox) > radius or math.abs(ny - oy) > radius then
                return
            end
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

    local tileCount = 0
    for _ in pairs(tiles) do tileCount = tileCount + 1 end
    Logger.log(string.format("Building plumbing scan at %d:%d:%d -> %d tile(s), %d fixture(s)",
        ox, oy, originSquare:getZ(), tileCount, #fixtures))

    return {
        isBuildingTile = function(x, y, z) return tiles[keyOf(x, y, z)] == true end,
        hasPipe = function(x, y, z) return piped[keyOf(x, y, z)] == true end,
        wallEdge = function(x, y, z) return walls[keyOf(x, y, z)] end,
        hasRiser = function(x, y, z, edge) return edge ~= nil and risers[keyOf(x, y, z)] == edge end,
        fixtures = function() return fixtures end,
        tileCount = function()
            local n = 0
            for _ in pairs(tiles) do n = n + 1 end
            return n
        end,
    }
end

-- ===== Laying it =====
-- Creating a built object without a build cursor, the way vanilla's own map-object scripts do it
-- (server/Map/MapObjects/MORainCollectorBarrel.lua): build the IsoThumpable, resolve its entity script
-- from its FACE sprite, and associate the two. That association is the step that cannot be skipped --
-- an object without it comes back from a chunk reload as "EntityScript not found", which is exactly
-- the bug the pump and the gauge hit when their art sat on a vanilla cell.

local FACE_FOR = {
    [FLOOR] = function() return Constants.PIPE_HIDDEN_FACE_SPRITE end,
    [RISER] = function(edge)
        return edge == "W" and Constants.PIPE_HIDDEN_RISER_FACE_W or Constants.PIPE_HIDDEN_RISER_FACE_N
    end,
}

-- Health of a generated pipe. Matched to a hand-built one so a zombie does not find the building's
-- plumbing softer than the player's own line.
local GENERATED_HEALTH = 200

-- Lay ONE pipe. Returns the object (or true, when the server was asked to do it), or nil and a reason.
--
-- Creating world objects belongs to the server -- vanilla's own map-object scripts bail on isClient()
-- for exactly this reason -- so on a client each tile is asked for rather than made. One command per
-- tile rather than one for the whole plan: it keeps the progressive laying and the interruption
-- semantics identical in both, and the traffic is bounded by BUILDING_PLUMB_MAX_TILES and spread over
-- the pass by its millisecond budget.
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

-- Everything the network owes after a pass, paid ONCE. Laying N pipes through the ordinary
-- registerPipeAt would rebuild the graph and refresh every plumbed endpoint N times -- the pattern
-- that cost processPumps 56 ms before it was fixed.
function BuildingPlumbing.finish(placements, player)
    if isClient and isClient() then
        -- The server owns the graph; ask it to settle once, then repaint locally (sprites are always
        -- derived client-side and never transmitted -- see PipeAutotile).
        if player then
            sendClientCommand(player, "WaterPipes", "finishBuildingPlumbing", {})
        end
        local PipeAutotile = WaterPipes.PipeAutotile
        if PipeAutotile and PipeAutotile.refreshAround then
            for _, placement in ipairs(placements or {}) do
                PipeAutotile.refreshAround(placement.x, placement.y, placement.z)
            end
        end
        return
    end

    local System = WaterPipes.System
    if System and System.rebuild then
        System.rebuild()
        if System.refreshPlumbedEndpoints then
            System.refreshPlumbedEndpoints()
        end
    end

    local PipeAutotile = WaterPipes.PipeAutotile
    if PipeAutotile and PipeAutotile.refreshAround then
        for _, placement in ipairs(placements or {}) do
            PipeAutotile.refreshAround(placement.x, placement.y, placement.z)
        end
    end
end

-- Connect the fixtures the pass reached.
--
-- Laying pipe to a sink is not the same as plumbing it: the pipe is on its tile, but the fixture still
-- draws from vanilla's own water until EndpointPlumbing.plumb swaps it over. Doing that by hand for
-- every sink in the house right after asking for the house to be plumbed is busywork with no decision
-- in it, so the pass finishes the job.
--
-- MUST run after BuildingPlumbing.finish: plumbing reads the network, and until the rebuild the
-- network does not know the new pipes exist.
--
-- Per SQUARE rather than per fixture, and every endpoint on it: that is what the server command can
-- address, so single-player and multiplayer connect exactly the same set.
function BuildingPlumbing.plumbFixtures(plan, player)
    local EndpointPlumbing = WaterPipes.EndpointPlumbing
    local EndpointObjectsModule = WaterPipes.EndpointObjects
    if not EndpointPlumbing or not EndpointObjectsModule then
        return 0
    end

    local seen = {}
    local plumbed = 0

    for _, fixture in ipairs(plan and plan.connected or {}) do
        local key = keyOf(fixture.x, fixture.y, fixture.z)
        if not seen[key] then
            seen[key] = true
            local square = squareAt(fixture.x, fixture.y, fixture.z)
            -- A pass that ran out of pipe partway can have "connected" a fixture in the plan whose
            -- branch never reached the floor. No pipe on its tile, nothing to plumb.
            if square and PipeObjectUtils.getPipeOnSquare(square) then
                if isClient and isClient() then
                    if player then
                        sendClientCommand(player, "WaterPipes", "plumbEndpointsOnSquare",
                            { x = fixture.x, y = fixture.y, z = fixture.z })
                        plumbed = plumbed + 1
                    end
                else
                    for _, endpointObject in ipairs(EndpointObjectsModule.collectOnSquare(square)) do
                        if not EndpointPlumbing.isPlumbed(endpointObject) then
                            EndpointPlumbing.plumb(endpointObject)
                            plumbed = plumbed + 1
                        end
                    end
                end
            end
        end
    end

    return plumbed
end

-- ===== Cost =====

-- Pipes owed per tile laid, scaled by the BuildingPlumbCostScale sandbox percentage.
function BuildingPlumbing.costPerTile()
    local sv = SandboxVars and SandboxVars.WaterPipes
    local scale = sv and sv.BuildingPlumbCostScale
    if type(scale) ~= "number" then
        scale = 100
    end
    return math.max(scale, 0) / 100
end

function BuildingPlumbing.pipesFor(tiles)
    return math.ceil((tiles or 0) * BuildingPlumbing.costPerTile() - 0.000001)
end

-- Metal only: a generated pipe is stamped metal and pays metal back when dismantled.
function BuildingPlumbing.countPipes(inventory)
    if not inventory or not inventory.getCountTypeRecurse then
        return 0
    end
    local ok, count = pcall(inventory.getCountTypeRecurse, inventory, Constants.PIPE_ITEM_TYPE)
    return ok and count or 0
end

-- ===== Server side of a multiplayer pass =====
-- The client's request is untrusted: validate it, charge the server's copy of the inventory, then lay.

local paidDebt = {}   -- player key -> fractional pipe owed within the current pass

local function playerKey(player)
    local ok, id = pcall(player.getOnlineID, player)
    if ok and id ~= nil then
        return id
    end
    return player.getUsername and player:getUsername() or "?"
end

local function isWholeNumber(v)
    return type(v) == "number" and v == math.floor(v)
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

    -- The menu walks the player next to the plan's origin, and a plan never leaves that radius.
    local reach = Constants.BUILDING_PLUMB_MAX_RADIUS + 2
    if math.abs(args.x - math.floor(player:getX())) > reach
        or math.abs(args.y - math.floor(player:getY())) > reach then
        return nil, "outOfReach"
    end

    local square = squareAt(args.x, args.y, args.z)
    if not square then
        return nil, "noSquare"
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
    for _ = 1, count do
        local item = inventory:getFirstTypeRecurse(Constants.PIPE_ITEM_TYPE)
        if not item then
            return
        end
        local container = item:getContainer() or inventory
        sendRemoveItemFromContainer(container, item)
        container:Remove(item)
    end
end

-- Returns the laid object, or nil and a reason. Nothing is charged unless the pipe is laid.
function BuildingPlumbing.placePaid(args, player)
    local placement, reason = validRequest(args, player)
    if not placement then
        return nil, reason
    end

    local key = playerKey(player)
    local debt = (paidDebt[key] or 0) + BuildingPlumbing.costPerTile()
    local owed = math.floor(debt + 0.000001)
    local inventory = player:getInventory()
    if BuildingPlumbing.countPipes(inventory) < owed then
        return nil, "noPipes"
    end

    local object, placeReason = BuildingPlumbing.place(placement, player)
    if not object then
        return nil, placeReason
    end

    takePipes(inventory, owed)
    paidDebt[key] = debt - owed
    return object
end

function BuildingPlumbing.endPaidPass(player)
    if player then
        paidDebt[playerKey(player)] = nil
    end
end

BuildingPlumbing.FLOOR = FLOOR
BuildingPlumbing.RISER = RISER

return BuildingPlumbing
