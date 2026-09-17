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
-- The tree is a SHORTEST-PATH tree, so it is acyclic by construction -- there is exactly one route
-- from the root to any tile, and every edge is therefore a bridge. That is the whole reason the shape
-- is a tree: it is what lets one valve isolate one well-defined subtree (see the valve, shipped
-- first). A mesh would be cheaper to lay and would make every valve meaningless.
--
-- probe (all coordinates are absolute):
--   isBuildingTile(x, y, z) -> boolean   inside the building being plumbed, and able to hold a pipe
--   hasPipe(x, y, z)        -> boolean   a pipe is already there; the plan reuses it and pays nothing
--   wallEdge(x, y, z)       -> "N"|"W"|nil   the wall THIS tile owns, if any (risers need one)
--   hasRiser(x, y, z, edge) -> boolean   a riser already stands on that tile and edge
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
        -- A climb costs the riser on THIS tile (free if one is already there) plus the landing above.
        out[#out + 1] = {
            x = x, y = y, z = z + 1, kind = RISER, edge = edge,
            cost = stepCost(probe, x, y, z + 1) + (probe.hasRiser(x, y, z, edge) and 0 or 1),
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
                    existing = probe.hasRiser(step.x, step.y, step.z, step.edge) or nil,
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
