WaterPipes = WaterPipes or {}
WaterPipes.BuildingPlumbing = WaterPipes.BuildingPlumbing or {}

require "WaterPipes/Constants"

local Constants = WaterPipes.Constants
local BuildingPlumbing = WaterPipes.BuildingPlumbing

-- Plans the concealed pipe tree that connects a building's fixtures to one root tile.
--
-- PURE. It reads the world through a `probe` table and returns a plan; it places nothing, spends
-- nothing and touches no global state. That is deliberate: the shape of this tree is the part of the
-- feature with real design risk, and this way it can be exercised against a hand-built world instead
-- of only in game.
--
-- The tree is a SHORTEST-PATH tree, so it is acyclic by construction -- there is exactly one route
-- from the root to any tile, and every edge is therefore a bridge. That is the whole reason the shape
-- is a tree: it is what lets one valve isolate one well-defined subtree (see the valve, shipped
-- first). A mesh would be cheaper to lay and would make every valve meaningless.
--
-- probe (all coordinates are absolute):
--   isBuildingTile(x, y, z) -> boolean   inside the building being plumbed, and able to hold a pipe
--   hasPipe(x, y, z)        -> boolean   a pipe is already there; the plan reuses it and pays nothing
--   wallEdge(x, y, z)       -> "N"|"W"|nil   the wall THIS tile owns, if any (risers need one)
--   fixtures()              -> { {x=,y=,z=,name=}, ... }   what we are trying to reach

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
        -- The riser is placed on THIS tile and the tile above it still needs its own floor pipe, so a
        -- climb costs the riser plus whatever the landing costs.
        out[#out + 1] = {
            x = x, y = y, z = z + 1, kind = RISER, edge = edge,
            cost = stepCost(probe, x, y, z + 1) + (probe.hasPipe(x, y, z) and 0 or 1),
        }
    end

    return out
end

-- Dijkstra from the root over the building. Returns the distance to every reachable tile and the
-- parent pointer that got there, which IS the tree.
local function solveTree(probe, origin)
    local dist = { [keyOf(origin.x, origin.y, origin.z)] = stepCost(probe, origin.x, origin.y, origin.z) }
    local parent = {}
    local visited = {}
    local frontier = { { x = origin.x, y = origin.y, z = origin.z } }

    while #frontier > 0 do
        -- Linear scan for the cheapest open tile. A building is hundreds of tiles, not millions, and a
        -- heap here would be more code than the whole planner saves.
        local bestIndex, bestKey, bestDist = nil, nil, math.huge
        for index, node in ipairs(frontier) do
            local key = keyOf(node.x, node.y, node.z)
            if (dist[key] or math.huge) < bestDist then
                bestIndex, bestKey, bestDist = index, key, dist[key]
            end
        end
        if not bestIndex then
            break
        end

        local current = table.remove(frontier, bestIndex)
        if not visited[bestKey] then
            visited[bestKey] = true
            for _, step in ipairs(neighboursOf(probe, current.x, current.y, current.z)) do
                local key = keyOf(step.x, step.y, step.z)
                local through = bestDist + step.cost
                if through < (dist[key] or math.huge) then
                    dist[key] = through
                    parent[key] = {
                        x = current.x, y = current.y, z = current.z,
                        kind = step.kind, edge = step.edge,
                    }
                    frontier[#frontier + 1] = { x = step.x, y = step.y, z = step.z }
                end
            end
        end
    end

    return dist, parent
end

-- The tiles a single fixture adds to the tree, walking its branch back to the root and stopping at
-- the first tile already claimed. Returns nil if the branch runs off the tree (it cannot, once the
-- fixture is known reachable, but a probe that lies should not loop forever).
local function branchFor(probe, origin, parent, claimed, fixture)
    local branch = {}
    local x, y, z = fixture.x, fixture.y, fixture.z
    local guard = 0

    while true do
        local key = keyOf(x, y, z)
        if claimed[key] then
            break
        end
        if not probe.hasPipe(x, y, z) then
            branch[#branch + 1] = { x = x, y = y, z = z, kind = FLOOR, key = key }
        else
            -- Already piped: claimed so the walk stops here next time, but nothing to build.
            branch[#branch + 1] = { x = x, y = y, z = z, kind = FLOOR, key = key, existing = true }
        end

        if x == origin.x and y == origin.y and z == origin.z then
            break
        end

        local step = parent[key]
        if not step then
            return nil
        end
        -- A climb also owes the riser on the tile below it.
        if step.kind == RISER then
            local riserKey = keyOf(step.x, step.y, step.z) .. ":riser:" .. tostring(step.edge)
            if not claimed[riserKey] then
                branch[#branch + 1] = {
                    x = step.x, y = step.y, z = step.z, kind = RISER, edge = step.edge, key = riserKey,
                }
            end
        end

        x, y, z = step.x, step.y, step.z
        guard = guard + 1
        if guard > 10000 then
            return nil
        end
    end

    return branch
end

-- Plan the tree.
--
-- opts.maxTiles caps how much ONE pass may lay. Over the cap the pass takes the fixtures it can reach
-- most cheaply and stops -- it does not refuse. Re-running extends, so a building bigger than the cap
-- (a Louisville hospital is one BuildingDef of thousands of tiles) is plumbed in several passes,
-- spreading outward from wherever the player is working.
function BuildingPlumbing.plan(origin, probe, opts)
    opts = opts or {}
    local maxTiles = opts.maxTiles or Constants.BUILDING_PLUMB_MAX_TILES

    local plan = { placements = {}, connected = {}, skipped = {}, cost = 0, cappedAt = false }
    if not origin or not probe or not probe.isBuildingTile(origin.x, origin.y, origin.z) then
        return plan
    end

    local dist, parent = solveTree(probe, origin)

    -- Nearest first, so a capped pass lays the plumbing the player is standing next to rather than an
    -- arbitrary corner of the building, and so a re-run extends outward from what is already there.
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
        -- Ties broken on coordinates so the same building always plans the same way.
        return keyOf(left.fixture.x, left.fixture.y, left.fixture.z)
            < keyOf(right.fixture.x, right.fixture.y, right.fixture.z)
    end)

    local claimed = {}
    for _, entry in ipairs(reachable) do
        local branch = branchFor(probe, origin, parent, claimed, entry.fixture)
        if not branch then
            plan.skipped[#plan.skipped + 1] = { fixture = entry.fixture, reason = "noRoute" }
        else
            local newTiles = 0
            for _, placement in ipairs(branch) do
                if not placement.existing then
                    newTiles = newTiles + 1
                end
            end

            if plan.cost + newTiles > maxTiles then
                -- Whole fixtures only: half a branch reaches nothing and would still cost pipe.
                plan.cappedAt = true
                plan.skipped[#plan.skipped + 1] = { fixture = entry.fixture, reason = "overCap" }
            else
                for _, placement in ipairs(branch) do
                    claimed[placement.key] = true
                    if not placement.existing then
                        plan.placements[#plan.placements + 1] = placement
                    end
                end
                plan.cost = plan.cost + newTiles
                plan.connected[#plan.connected + 1] = entry.fixture
            end
        end
    end

    for _, fixture in ipairs(unreachable) do
        -- Told apart so the report can say something useful: a fixture on a floor with no wall to climb
        -- is a different problem from one walled off on its own floor, and only the first is fixable by
        -- the player putting a pipe somewhere.
        local reason = "noRoute"
        if fixture.z ~= origin.z then
            reason = "noClimb"
        end
        plan.skipped[#plan.skipped + 1] = { fixture = fixture, reason = reason }
    end

    -- Root outward, so a pass interrupted partway has always laid a CONNECTED tree rather than
    -- islands: the ms-budgeted placement can stop at any point and what is on the ground still works.
    table.sort(plan.placements, function(left, right)
        local ld = dist[keyOf(left.x, left.y, left.z)] or math.huge
        local rd = dist[keyOf(right.x, right.y, right.z)] or math.huge
        if ld ~= rd then
            return ld < rd
        end
        return left.key < right.key
    end)

    return plan
end

BuildingPlumbing.FLOOR = FLOOR
BuildingPlumbing.RISER = RISER

return BuildingPlumbing
