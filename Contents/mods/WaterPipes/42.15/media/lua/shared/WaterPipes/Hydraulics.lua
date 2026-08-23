WaterPipes = WaterPipes or {}
WaterPipes.Hydraulics = WaterPipes.Hydraulics or {}

require "WaterPipes/Constants"
require "WaterPipes/ContainerAdapter"
require "WaterPipes/Hydrant"
require "WaterPipes/Mains"
require "WaterPipes/PipeObjectUtils"
require "WaterPipes/Pressure"
require "WaterPipes/Pump"
require "WaterPipes/Purifier"
require "WaterPipes/Router"

local Adapter = WaterPipes.ContainerAdapter
local Constants = WaterPipes.Constants
local Hydraulics = WaterPipes.Hydraulics
local Hydrant = WaterPipes.Hydrant
local Mains = WaterPipes.Mains
local PipeObjectUtils = WaterPipes.PipeObjectUtils
local Pressure = WaterPipes.Pressure
local Pump = WaterPipes.Pump
local Purifier = WaterPipes.Purifier
local Router = WaterPipes.Router

-- The demand-aware pressure solver: one head field per NETWORK, instead of one arithmetic answer per
-- (source, consumer) pair.
--
-- ===== Why this replaces the per-consumer walk =====
--
-- NetworkAccess used to answer "what head reaches this sprinkler?" by flooding the whole network
-- outward FROM THAT SPRINKLER and pricing every source it found with a closed formula. Two things
-- follow from that shape, and they are the same thing seen twice:
--
--   * A walk that starts at one consumer cannot know the others exist. So there was no way to charge
--     a pipe for the litres actually going through it, and thirty sprinklers each concluded they were
--     alone on the line. Two pumps fed all thirty.
--   * The walk is per consumer, so the cost is O(consumers x network). A field of thirty-eight
--     emitters on a 192-tile grid walked 7 300 tiles per pass -- and again on the client, for the
--     spray FX, every three seconds.
--
-- Running the walk in the WATER'S direction instead -- from the sources outward, once for the whole
-- network -- fixes both at once. The demand of every consumer is visible in one place (so an edge can
-- be charged for its real flow), and the cost drops to O(network).
--
-- ===== The model =====
--
-- Everything is piezometric head, m.c.a. measured from a z = 0 datum, exactly as real hydraulics
-- does it. See the HYDRAULIC_* block in Constants.lua for the equations and the calibration.
--
--   H[source] = elevation(z) + base head of whatever supplies it
--   H[child]  = H[parent] - K * Q(edge)^n      -- friction, charged to the EDGE
--   H[node]  += pump head                      -- boosters lift the node they stand on
--   H[node]   = min(H[node], elevation(z) + ceiling)   -- a regulator caps its own outlet
--   P[node]   = H[node] - elevation(z)         -- what a consumer standing there can use
--
-- Elevation living in the datum is what makes this one sweep instead of two: climbing and falling are
-- already priced by the difference in `elevation`, so the loop body only ever handles friction.
--
-- It is also why the regulator CHAIN arithmetic could go. A backwards walk had to carry a linked list
-- of every valve it had crossed and re-price each one from where it stood; a forward walk meets each
-- valve once, in the order the water does, and "the tightest ceiling upstream" is just a running
-- minimum. (NetworkAccess still threads a chain object through its fill walk -- nothing reads it, but
-- unpicking it from that path is a separate change.)
--
-- ===== What it is not =====
--
-- Not a real network solve. A looped network's true flow split needs Hardy Cross or a global gradient
-- method -- an iterative linear-algebra problem, which is not something to run in Kahlua every game
-- minute. What this does instead is split each node's demand evenly across its shortest-path parents
-- (see the reverse sweep), which captures the property that actually matters to a player: A LOOP
-- CARRIES LESS PER BRANCH THAN A SPUR, so ring-mains beat dead ends. The magnitudes are approximate.
-- The ordering -- who starves first, and what building a loop buys you -- is right.

local function elevation(z)
    return Pressure.levelHead() * (z or 0)
end

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

local function keyOf(x, y, z)
    return tostring(x) .. ":" .. tostring(y) .. ":" .. tostring(z)
end

local function squareKey(square)
    return keyOf(square:getX(), square:getY(), square:getZ())
end

local function hasPipeOnSquare(square)
    return square and PipeObjectUtils.getPipeOnSquare(square) ~= nil
end

-- A router with a tank on it is a hard boundary in both directions -- the fluid is being transformed
-- and the two sides must never share a head field. Mirrors NetworkAccess.routerIsHardBoundary; kept
-- here rather than shared because closing the require loop between the two modules is not worth one
-- function.
local function routerIsHardBoundary(routerSquare)
    if Purifier and Purifier.findForRouterSquare and Purifier.findForRouterSquare(routerSquare) then
        return true
    end
    -- Any other vessel parked on the crossing buffers the flow, so it is a boundary too. Asks the
    -- adapter's classification directly rather than building descriptors: this only needs a yes/no,
    -- and it runs per router crossing inside the walk.
    return Adapter.hasSquareContainers(routerSquare)
end

-- ===== Sandbox tunables =====

local function sandboxPercent(name, fallback)
    local sv = SandboxVars and SandboxVars.WaterPipes
    local v = sv and sv[name]
    if type(v) == "number" then
        return math.max(v, 0) / 100
    end
    return fallback
end

function Hydraulics.demandScale()
    return sandboxPercent("HydraulicDemandScale", Constants.HYDRAULIC_DEMAND_SCALE)
end

-- Loss over one pipe tile carrying `flow` litres/hour, scaled by the same PressureFrictionScale the
-- old model used -- so a save that had already dialled distance down keeps that setting meaning the
-- same thing.
function Hydraulics.lossPerTile(flow)
    if Pressure.model() == Constants.PRESSURE_MODEL_SIMPLE then
        return 0   -- height only, exactly as before
    end
    local q = math.max(flow or 0, 0)
    local exponent = Constants.HYDRAULIC_FRICTION_EXPONENT or 1
    local shaped = exponent == 1 and q or math.pow(q, exponent)
    return Constants.HYDRAULIC_FRICTION_K * shaped * sandboxPercent("PressureFrictionScale", 1)
end

-- ===== Consumer demand =====

-- Litres per in-game hour a consumer of `kind` pulls when it is running. Derived from the irrigation
-- constants rather than restated, so changing a watering rate cannot silently desynchronise the
-- pressure model from the water it is meant to be pricing.
function Hydraulics.flowFor(kind)
    if kind == Constants.PRESSURE_KIND_SPRINKLER then
        return Constants.SPRINKLER_WATER_PER_HOUR
            * Constants.SPRINKLER_WASTE_TILES
            * Constants.IRRIGATION_LITRES_PER_WATER_LEVEL
    elseif kind == Constants.PRESSURE_KIND_DRIP then
        return Constants.DRIP_WATER_PER_HOUR
            * Constants.IRRIGATION_LITRES_PER_WATER_LEVEL
    end
    return Constants.HYDRAULIC_TAP_FLOW
end

-- What the emitter standing on this square demands, if anything. Resolved off the WaterPipes table
-- rather than required: Irrigation requires NetworkAccess which requires this module, and closing
-- that loop is a recursive require. Same dodge Router.setPressureCeiling uses.
local function ownDemandAt(square)
    local Irrigation = WaterPipes.Irrigation
    if not Irrigation then
        return 0, nil
    end
    for _, worldObject in ipairs(PipeObjectUtils.getPipeObjectsOnSquare(square)) do
        if Irrigation.isSprinkler and Irrigation.isSprinkler(worldObject) then
            return Hydraulics.flowFor(Constants.PRESSURE_KIND_SPRINKLER),
                Constants.PRESSURE_KIND_SPRINKLER
        end
        if Irrigation.isDrip and Irrigation.isDrip(worldObject) then
            -- A burst emitter still conducts but no longer waters, so it stops being a load.
            if Irrigation.isDripBurst and Irrigation.isDripBurst(worldObject) then
                return 0, nil
            end
            return Hydraulics.flowFor(Constants.PRESSURE_KIND_DRIP), Constants.PRESSURE_KIND_DRIP
        end
    end
    return 0, nil
end

-- FIXTURES ARE NOT LOADS, and that is deliberate rather than an omission. A sink, a shower or a
-- plumbed generator sits BESIDE the line, not on it, and it draws in bursts when a player uses it
-- rather than continuously the way an emitter does. Charging the network for a tap that might be used
-- once a day would starve the sprinklers around it for nothing, and finding them would mean scanning
-- every pipe tile's four neighbours for fixtures on every solve -- the exact per-tile cost this module
-- exists to remove. They still READ the field (see Hydraulics.pressureAt), and their own flow is
-- priced on the one tile between them and the pipe. They just do not push anyone else off it.

-- ===== Phase 1: discover the zone =====
--
-- Undirected, because a hydraulic zone is a physical thing: both sides of a bare regulator belong to
-- the same field (the valve prices the crossing, it does not sever it), while a purifier severs it
-- absolutely. Seeded from anywhere in the zone and reaching the same set whatever the seed, which is
-- what lets every consumer on a network share one solve.
local function discover(seedSquare)
    local nodes = {}      -- key -> { x, y, z, square }
    local order = {}      -- keys, discovery order
    local adjacency = {}  -- key -> { neighbourKey -> true }
    local routers = {}    -- key -> { inKey, outKey, z, ceiling } for the bare regulators we may cross
    -- Purifiers whose CLEAN side empties into this zone. A purifier's OUT buffer is 50 litres of
    -- storage belonging to the network on its clean side, and nothing else can see it -- so if the
    -- walk does not record it here, the buffer fills, the convert step stalls on no headroom and the
    -- device stops with its water trapped inside. Recorded during discovery because this is the one
    -- place that has the router, its direction and the side we approached from all in hand.
    local purifierOutlets = {}

    local queue = { seedSquare }
    local seen = {}
    seen[squareKey(seedSquare)] = true

    local function link(leftKey, rightKey)
        adjacency[leftKey] = adjacency[leftKey] or {}
        adjacency[rightKey] = adjacency[rightKey] or {}
        adjacency[leftKey][rightKey] = true
        adjacency[rightKey][leftKey] = true
    end

    local function push(square)
        local key = squareKey(square)
        if seen[key] then
            return key
        end
        seen[key] = true
        queue[#queue + 1] = square
        return key
    end

    local index = 1
    while index <= #queue do
        local square = queue[index]
        index = index + 1
        local key = squareKey(square)
        local x, y, z = square:getX(), square:getY(), square:getZ()

        nodes[key] = { x = x, y = y, z = z, square = square }
        order[#order + 1] = key
        adjacency[key] = adjacency[key] or {}

        local function consider(neighbourSquare)
            if not neighbourSquare then
                return
            end
            if Router.hasRouterOnSquare(neighbourSquare) then
                -- A router tile is never a node of the field; it is an edge with a valve on it.
                local router = Router.findOnSquare(neighbourSquare)
                local out = router and Router.getOutOffset(router)
                if not out then
                    return
                end
                local rx, ry, rz = neighbourSquare:getX(), neighbourSquare:getY(), neighbourSquare:getZ()
                if z ~= rz then
                    return
                end

                if routerIsHardBoundary(neighbourSquare) then
                    -- Sealed in both directions -- but if it is a purifier and we are standing on its
                    -- OUT side, its clean buffer is storage on THIS zone. Only the out side: reaching
                    -- it from the inlet means we are on the dirty side, which must never see the clean
                    -- water. That is the whole point of the boundary.
                    local routerKey = keyOf(rx, ry, rz)
                    if not purifierOutlets[routerKey]
                        and x == rx + out.dx and y == ry + out.dy then
                        local purifier = Purifier.findForRouterSquare(neighbourSquare)
                        if purifier then
                            purifierOutlets[routerKey] = {
                                purifier = purifier, routerKey = routerKey,
                                x = x, y = y, z = z, nodeKey = key,
                            }
                        end
                    end
                    return
                end
                local inSquare = getCellSquare(rx - out.dx, ry - out.dy, rz)
                local outSquare = getCellSquare(rx + out.dx, ry + out.dy, rz)
                if not inSquare or not outSquare then
                    return
                end
                if not hasPipeOnSquare(inSquare) or not hasPipeOnSquare(outSquare) then
                    return
                end
                local inKey = push(inSquare)
                local outKey = push(outSquare)
                routers[keyOf(rx, ry, rz)] = {
                    square = neighbourSquare,
                    inKey = inKey,
                    outKey = outKey,
                    z = rz,
                    ceiling = Router.getPressureCeiling(router),
                }
                return
            end
            if not hasPipeOnSquare(neighbourSquare) then
                return
            end
            link(key, push(neighbourSquare))
        end

        for _, offset in ipairs(Constants.CARDINAL_OFFSETS) do
            consider(getCellSquare(x + offset.x, y + offset.y, z))
        end
        for _, coord in ipairs(PipeObjectUtils.getRiserVerticalNeighborCoords(x, y, z)) do
            consider(getCellSquare(coord.x, coord.y, coord.z))
        end
    end

    return nodes, order, adjacency, routers, purifierOutlets
end

-- ===== Phase 2: what supplies the zone, and what loads it =====

local function collectSupplyAndDemand(nodes, order)
    local supply = {}        -- key -> head at that node (m.c.a., absolute)
    local boostable = {}     -- key -> true when a pump may lift this supply (see the end of the pass)
    local demand = {}        -- key -> litres/hour drawn there
    local kinds = {}         -- key -> the consumer kind occupying it
    local pumps = {}         -- key -> list of powered pumps standing there
    local sources = {}       -- descriptor list, for the readouts
    -- Two different numbers, and conflating them is a real bug rather than a tidiness point.
    -- `supplyFloor` is ABSOLUTE head (elevation included) and belongs to the field: it is what the
    -- forward sweep starts a mains-fed node at. `stats.supplyHead` is the RELATIVE pressure the
    -- utility holds its main at, and it is what the lift gate and the readouts want -- feeding them
    -- the absolute value would let a network on the third floor claim 9 m.c.a. of free lift it does
    -- not have.
    local supplyFloor = 0
    -- Counters the debug readout wants. Gathered here because this pass already has every object in
    -- hand; asking again afterwards would be a second scan of the whole zone for numbers we just saw.
    local stats = { pumpCount = 0, poweredPumps = 0, mainsCount = 0, hydrantCount = 0,
                    pumpHead = 0, supplyHead = 0 }

    local containerBase = Pressure.containerBase()

    for _, key in ipairs(order) do
        local node = nodes[key]
        local square = node.square

        local function raise(head, pumpsMayLift)
            if not supply[key] or head > supply[key] then
                supply[key] = head
            end
            if pumpsMayLift then
                boostable[key] = true
            end
        end

        -- Stored water. A vessel only supplies head while it actually holds something.
        local descriptors = Adapter.collectSquareContainers(square)
        for descriptorKey, descriptor in pairs(descriptors) do
            descriptor.nodeKey = key
            sources[#sources + 1] = descriptor
            if (descriptor.waterAmount or 0) > 0 then
                raise(elevation(node.z) + containerBase, true)
            end
        end

        -- A municipal supply holds the whole run at its pressure -- a FLOOR, not head added on top,
        -- and two of them do not stack because they are the same town water. Same rule the chain
        -- arithmetic used; it is just a max over the zone now instead of a walk back up a chain.
        local mains = Mains.findOnSquare(square)
        if mains then
            local head = elevation(node.z) + Mains.head()
            raise(head)
            if head > supplyFloor then supplyFloor = head end
            if Mains.head() > stats.supplyHead then stats.supplyHead = Mains.head() end
            stats.mainsCount = stats.mainsCount + 1
        end

        local hydrant = Hydrant.findOnSquare(square)
        if hydrant and Hydrant.pressureActive(hydrant) then
            local head = elevation(node.z) + Hydrant.head()
            raise(head)
            if head > supplyFloor then supplyFloor = head end
            if Hydrant.head() > stats.supplyHead then stats.supplyHead = Hydrant.head() end
            stats.hydrantCount = stats.hydrantCount + 1
        end

        -- A pump is a booster wherever it stands, and ALSO a source when it has a well or open water
        -- beside it: that is where the water physically enters the network.
        local pump = Pump.findOnSquare(square)
        if pump then
            stats.pumpCount = stats.pumpCount + 1
            if Pump.isPowered(pump) then
                stats.poweredPumps = stats.poweredPumps + 1
                pumps[key] = pumps[key] or {}
                pumps[key][#pumps[key] + 1] = pump
                stats.pumpHead = stats.pumpHead + Pump.headForPumps({ pump })
                if Pump.findSource and Pump.findSource(pump) then
                    raise(elevation(node.z) + containerBase, true)
                end
            end
        end

        local own, kind = ownDemandAt(square)
        if own > 0 then
            demand[key] = own
            kinds[key] = kind
        end
    end

    -- ===== Pumps are a ZONE term, applied here rather than during propagation =====
    --
    -- This is the fix for a real and very visible bug, so it is worth being explicit about why it is
    -- shaped this way. Head propagates by relaxation (phase 5), and a relaxation has no notion of
    -- direction -- so a pump that boosted "the node it stands on" boosted head that had come back to
    -- it from its own downstream, which boosted it again on the next sweep. A ten-tile line settled at
    -- 297 m.c.a. instead of 49, climbing by one pump's worth every pass.
    --
    -- A booster cannot be a node-local term in a direction-free field. It has to enter the field as a
    -- property of the SUPPLY, which is also exactly the semantics the mod already shipped and
    -- documented -- "pumps are counted PER ZONE, not per path" (see Pressure.lua). Every powered pump
    -- in the zone lifts every vessel in it, they add up in series, and no vessel can be lifted twice.
    --
    -- Municipal supplies are deliberately NOT lifted. A utility holds its main at a set pressure and
    -- is a floor under the run rather than a head a pump can stack onto -- which is what the old chain
    -- arithmetic did too, by taking a max rather than a sum.
    if stats.pumpHead > 0 then
        for key in pairs(boostable) do
            supply[key] = supply[key] + stats.pumpHead
        end
    end

    return supply, demand, kinds, pumps, sources, supplyFloor, stats
end

-- ===== Phase 3: order the zone by distance from supply =====
--
-- Multi-source BFS: every supplied node starts at depth 0, so `depth` is the distance to the NEAREST
-- supply and the traversal order is a valid topological order for both sweeps below.
--
-- `parents` keeps EVERY neighbour one step closer to supply, not just the first one found. That is
-- the whole of the loop handling: a node on a ring has two parents and splits its draw between them,
-- so each branch of the ring carries half. A node on a spur has one parent and it carries everything.
local function orderBySupply(nodes, adjacency, routers, supply)
    local depth = {}
    local parents = {}
    local queue = {}
    local sequence = {}

    -- Router crossings are directed edges: water leaves by the OUT side. Indexed by the downstream
    -- node so the sweeps can find the valve sitting on the edge they are pricing.
    local viaRouter = {}
    for _, router in pairs(routers) do
        viaRouter[router.outKey] = viaRouter[router.outKey] or {}
        viaRouter[router.outKey][router.inKey] = router
    end

    for key in pairs(supply) do
        if nodes[key] then
            depth[key] = 0
            queue[#queue + 1] = key
        end
    end

    if #queue == 0 then
        return nil, nil, nil, viaRouter
    end

    local index = 1
    while index <= #queue do
        local key = queue[index]
        index = index + 1
        sequence[#sequence + 1] = key

        local function step(neighbourKey)
            if not nodes[neighbourKey] then
                return
            end
            if depth[neighbourKey] == nil then
                depth[neighbourKey] = depth[key] + 1
                parents[neighbourKey] = { key }
                queue[#queue + 1] = neighbourKey
            elseif depth[neighbourKey] == depth[key] + 1 then
                local list = parents[neighbourKey]
                for _, existing in ipairs(list) do
                    if existing == key then
                        return
                    end
                end
                list[#list + 1] = key
            end
        end

        for neighbourKey in pairs(adjacency[key] or {}) do
            step(neighbourKey)
        end
        -- ...and out through any router this node feeds.
        for _, router in pairs(routers) do
            if router.inKey == key then
                step(router.outKey)
            end
        end
    end

    return depth, parents, sequence, viaRouter
end

-- ===== Phase 4: accumulate demand toward the supply =====
--
-- Walk the BFS order backwards, so every node is processed after everything it feeds. Each node's
-- through-flow is its own draw plus its share of its children's, and it pushes that up to its parents
-- split evenly -- which is the loop approximation described in the header.
--
-- `peak` rides along beside `flow`: the largest SINGLE consumer downstream of this node. It is what
-- HYDRAULIC_DEMAND_SCALE = 0 falls back to, and it is exactly the old per-consumer arithmetic -- so
-- the dial really does span both models rather than merely softening one.
local function accumulate(sequence, parents, demand, active)
    local flow = {}
    local peak = {}

    for _, key in ipairs(sequence) do
        local own = active[key] and (demand[key] or 0) or 0
        flow[key] = own
        peak[key] = own
    end

    for index = #sequence, 1, -1 do
        local key = sequence[index]
        local list = parents[key]
        if list and #list > 0 then
            local share = flow[key] / #list
            for _, parentKey in ipairs(list) do
                flow[parentKey] = (flow[parentKey] or 0) + share
                if (peak[key] or 0) > (peak[parentKey] or 0) then
                    peak[parentKey] = peak[key]
                end
            end
        end
    end

    return flow, peak
end

-- Every node that can hand head to another, precomputed ONCE per solve.
--
-- This used to be built inside the relaxation, per node, per sweep -- which meant allocating a table
-- and scanning every router in the zone something like fifteen thousand times for a single farm. The
-- shape it describes cannot change between sweeps, or between the probes of the servable-set search,
-- so building it once and reading it back is the same answer for a fraction of the work. On a slow
-- interpreter that difference is the whole cost of the pass.
local function buildFeeders(nodes, adjacency, routers)
    local feeders = {}

    local function link(toKey, fromKey)
        if not nodes[toKey] or not nodes[fromKey] then
            return
        end
        feeders[toKey] = feeders[toKey] or {}
        local list = feeders[toKey]
        list[#list + 1] = fromKey
    end

    for key in pairs(nodes) do
        for neighbourKey in pairs(adjacency[key] or {}) do
            link(key, neighbourKey)
        end
    end

    -- A valve is an edge, never a node, so its two ends are joined separately. Both directions: a
    -- regulator does not lift its inlet, but it does not seal it either, and refusing to look
    -- backwards would strand a supply that happens to sit past one.
    for _, router in pairs(routers or {}) do
        link(router.outKey, router.inKey)
        link(router.inKey, router.outKey)
    end

    return feeders
end

-- ===== Phase 5: propagate head away from the supply =====
--
-- RELAXATION, not a topological sweep, and the difference is not academic -- getting it wrong is what
-- made a farm read 51 m.c.a. on the pump tile and 1.00 on the tile beside it.
--
-- The BFS seeds EVERY supplied node at depth 0, so a barrel standing on the line has no parents. A
-- sweep that only ever takes head from a node's parents therefore pinned each barrel to its own base
-- pressure, and a pump next door could not lift it: the water in the barrel is a supply, so the sweep
-- decided it needed nothing from anywhere. On a build with a bank of vessels beside the pump, every
-- one of them sat at 1.0, the whole network downstream inherited that, and 47 sprinklers starved with
-- two working pumps ten tiles away.
--
-- A pump pressurises the WATER, including the water in the vessels feeding it. So a node takes the
-- best head ANY neighbour can deliver, whether or not it also supplies itself, which makes this a
-- max-relaxation over the graph rather than a walk down a tree. The pump term itself lives on the
-- supply for the same reason -- a direction-free field cannot host a direction-dependent booster
-- without feeding it its own output. See the end of collectSupplyAndDemand.
--
-- Bounded alternating sweeps rather than a priority queue: Kahlua has no heap, and sweeping the BFS
-- order forwards and then backwards converges on grid-shaped networks in two or three rounds where
-- naive Bellman-Ford would need one per tile of diameter. The loop exits as soon as nothing moves.
local emptyList = {}

local function propagate(nodes, sequence, parents, feeders, supply, flow, peak, viaRouter)
    local head = {}
    local scale = Hydraulics.demandScale()

    -- What ONE of the edges feeding `key` actually carries.
    --
    -- Two things are being interpolated by the same dial, and both have to collapse together at
    -- scale 0 for that setting to really mean "the old model":
    --   * how much of the shared demand the edge is charged for, and
    --   * whether arriving by several parallel branches divides that load.
    -- The old arithmetic had neither -- it priced friction * hops for one consumer down one shortest
    -- path -- so at scale 0 this must return the single largest consumer, undivided. At scale 1 it
    -- returns the true through-flow split evenly across the parallel branches, which is what makes a
    -- ring main worth building.
    local function edgeFlow(key)
        local list = parents[key]
        local parentCount = list and #list or 1
        local total = flow[key] or 0
        local single = peak[key] or 0
        local effective = single + (total - single) * scale
        local divisor = 1 + (math.max(parentCount, 1) - 1) * scale
        return effective / divisor
    end

    local function relax(key)
        local base = supply[key]
        local loss = Hydraulics.lossPerTile(edgeFlow(key))

        for _, feederKey in ipairs(feeders[key] or emptyList) do
            local feederHead = head[feederKey]
            if feederHead then
                local arriving = feederHead - loss
                -- A regulator on this edge fixes the head at ITS OUTLET. Past it the water keeps
                -- paying friction and keeps gaining or losing height like any other run, which falls
                -- out for free: we cap here and the rest of the relaxation carries on.
                local router = viaRouter[key] and viaRouter[key][feederKey]
                if router and router.ceiling then
                    local ceiling = elevation(router.z) + router.ceiling
                    if arriving > ceiling then
                        arriving = ceiling
                    end
                end
                if not base or arriving > base then
                    base = arriving
                end
            end
        end

        if not base then
            return false
        end

        -- No pump term here, deliberately: see the end of collectSupplyAndDemand. A booster raises the
        -- supply, not the tile it happens to sit on -- doing it here is what made the field diverge.

        local previous = head[key]
        if previous and base <= previous + 0.0001 then
            return false
        end
        head[key] = base
        return true
    end

    local passes = math.max(Constants.HYDRAULIC_RELAX_PASSES or 1, 1)
    for pass = 1, passes do
        local changed = false
        if pass % 2 == 1 then
            for index = 1, #sequence do
                if relax(sequence[index]) then changed = true end
            end
        else
            for index = #sequence, 1, -1 do
                if relax(sequence[index]) then changed = true end
            end
        end
        if not changed then
            break
        end
    end

    return head
end

-- ===== The solve =====

local function solveZone(seedSquare)
    local nodes, order, adjacency, routers, purifierOutlets = discover(seedSquare)
    if #order == 0 then
        return nil
    end

    local supply, demand, kinds, pumps, sources, supplyFloor, stats =
        collectSupplyAndDemand(nodes, order)

    local feeders = buildFeeders(nodes, adjacency, routers)
    local depth, parents, sequence, viaRouter = orderBySupply(nodes, adjacency, routers, supply)
    if not sequence then
        -- Nothing supplies this zone: no water, no mains, no pump with a source. Every node is dry,
        -- which is a real answer and not a failure -- return the shape with an empty field.
        return {
            nodes = nodes, order = order, adjacency = adjacency, routers = routers,
            purifierOutlets = purifierOutlets,
            sources = sources, demand = demand, kinds = kinds,
            head = {}, flow = {}, depth = {}, supplyFloor = supplyFloor, pumps = pumps, stats = stats,
            starved = {}, iterations = 0,
        }
    end

    -- ===== Who actually gets to draw =====
    --
    -- This is a FIXED POINT, and the obvious way to look for it does not converge. Turning every
    -- starved consumer off at once and re-pricing overshoots: with nothing drawing, the line springs
    -- back to full static head, so on the next pass every one of them looks servable again and they
    -- all switch back on. The field then collapses again. It oscillates with period two, and capping
    -- the iteration count does not fix that -- it just decides which half of the oscillation you get
    -- to see. On a 47-emitter farm that produced a report stating "47 starved, 0.00 of 84.60 L/h
    -- served" directly above "Flow through this tile: 84.60 L/h", with -5.34 m.c.a. at the far end:
    -- two different iterations' answers printed side by side as though they described one state.
    --
    -- So the search is made MONOTONE instead. Order the consumers by how easy they are to satisfy and
    -- ask a question that can only go one way: "can the nearest k all be served at once?" Adding a
    -- consumer only ever adds flow, which only ever costs head, so if k cannot be served then neither
    -- can k+1 -- the predicate is monotone in k and a binary search finds the largest workable set in
    -- about log2(N) solves. No oscillation is possible, because nothing is ever switched back on.
    --
    -- The ordering is by REQUIRED HEAD first, distance second. A drip needs no pressure at all and
    -- draws a ninth of what a sprinkler draws, so dropping one to feed a sprinkler would be perverse;
    -- among consumers with the same requirement, the line serves the near ones, which is what a real
    -- line does.
    local ordered = {}
    for key in pairs(demand) do
        ordered[#ordered + 1] = key
    end
    table.sort(ordered, function(left, right)
        local minLeft = Pressure.minimumFor(kinds[left])
        local minRight = Pressure.minimumFor(kinds[right])
        if minLeft ~= minRight then
            return minLeft < minRight
        end
        local depthLeft = depth[left] or 0
        local depthRight = depth[right] or 0
        if depthLeft ~= depthRight then
            return depthLeft < depthRight
        end
        return left < right
    end)

    local head, flow, peak
    local solves = 0

    -- Price the network with exactly the first `count` consumers drawing, and report whether every one
    -- of them clears its own minimum. Leaves head/flow/peak describing that state, which is what makes
    -- the final call below the thing that decides what the readouts say.
    local function trySet(count)
        solves = solves + 1
        local active = {}
        for index = 1, count do
            active[ordered[index]] = true
        end
        flow, peak = accumulate(sequence, parents, demand, active)
        head = propagate(nodes, sequence, parents, feeders, supply, flow, peak, viaRouter)
        for index = 1, count do
            local key = ordered[index]
            local available = head[key] and (head[key] - elevation(nodes[key].z)) or nil
            if not available or available < Pressure.minimumFor(kinds[key]) then
                return false
            end
        end
        return true
    end

    local low, high = 0, #ordered
    while low < high do
        local middle = math.floor((low + high + 1) / 2)
        if trySet(middle) then
            low = middle
        else
            high = middle - 1
        end
    end

    -- Re-price at the chosen size, unconditionally. The binary search's last probe is usually a
    -- FAILED one, so without this the head and flow left behind would describe a state the mod then
    -- reports as not happening -- which is exactly the contradiction this replaced.
    trySet(low)

    local starved = {}
    for index = low + 1, #ordered do
        starved[ordered[index]] = true
    end

    return {
        nodes = nodes,
        order = order,
        adjacency = adjacency,
        routers = routers,
        feeders = feeders,
        purifierOutlets = purifierOutlets,
        supply = supply,
        sequence = sequence,
        sources = sources,
        demand = demand,
        kinds = kinds,
        head = head,
        flow = flow,
        depth = depth,
        pumps = pumps,
        supplyFloor = supplyFloor,
        stats = stats,
        starved = starved,
        iterations = solves,
    }
end

-- ===== Per-frame cache, shared across every consumer on the network =====
--
-- This is the other half of the point. The field is identical for every consumer standing on the same
-- zone, so it is computed once and keyed by every node in it -- a second emitter three tiles away hits
-- the cache instead of walking 192 tiles again.
--
-- Dropped once per frame like the other caches, and explicitly when the layout changes. The FLUID is
-- not cached (callers still read vessels live through NetworkAccess); what is cached is the field,
-- which moves only when topology, pump state or emitter count does -- none of which can change inside
-- a frame without an event firing.
local solutionCache = {}
local zoneOfNode = {}

function Hydraulics.invalidate()
    solutionCache = {}
    zoneOfNode = {}
end

function Hydraulics.solveAt(square)
    if not square then
        return nil
    end

    local key = squareKey(square)
    local zoneId = zoneOfNode[key]
    if zoneId and solutionCache[zoneId] then
        return solutionCache[zoneId]
    end

    -- The seed must be a pipe tile: a fixture (sink, generator) has no pipe of its own, so the zone it
    -- belongs to is whichever one its neighbours are on.
    local seed = nil
    if hasPipeOnSquare(square) and not Router.hasRouterOnSquare(square) then
        seed = square
    else
        local x, y, z = square:getX(), square:getY(), square:getZ()
        local function trySeed(neighbour)
            if seed then
                return
            end
            if neighbour and hasPipeOnSquare(neighbour)
                and not Router.hasRouterOnSquare(neighbour) then
                seed = neighbour
            end
        end
        for _, offset in ipairs(Constants.CARDINAL_OFFSETS) do
            trySeed(getCellSquare(x + offset.x, y + offset.y, z))
        end
        -- Risers too. The walk this replaced seeded a fixture's neighbours through addNeighborsOf,
        -- which follows vertical links as well -- so a sink whose only connection is the riser on its
        -- own tile has to keep working.
        for _, coord in ipairs(PipeObjectUtils.getRiserVerticalNeighborCoords(x, y, z)) do
            trySeed(getCellSquare(coord.x, coord.y, coord.z))
        end
    end
    if not seed then
        return nil
    end

    local seedKey = squareKey(seed)
    zoneId = zoneOfNode[seedKey]
    if zoneId and solutionCache[zoneId] then
        zoneOfNode[key] = zoneId
        return solutionCache[zoneId]
    end

    local solution = solveZone(seed)
    if not solution then
        return nil
    end

    solution.id = seedKey
    solutionCache[seedKey] = solution
    zoneOfNode[key] = seedKey
    for _, nodeKey in ipairs(solution.order) do
        zoneOfNode[nodeKey] = seedKey
    end
    return solution
end

-- ===== Readouts =====

-- Usable pressure (m.c.a.) for a `kind` consumer standing on `square`, or nil when nothing supplies
-- it. A consumer on a fixture tile reads the best of its pipe neighbours, minus its own edge -- it is
-- one tile off the line, and that tile costs what any other does.
function Hydraulics.pressureAt(solution, square, kind)
    if not solution or not square then
        return nil
    end

    local key = squareKey(square)
    local node = solution.nodes[key]
    if node then
        local head = solution.head[key]
        if not head then
            return nil
        end
        return head - elevation(node.z)
    end

    local best = nil
    local x, y, z = square:getX(), square:getY(), square:getZ()
    for _, offset in ipairs(Constants.CARDINAL_OFFSETS) do
        local neighbourKey = keyOf(x + offset.x, y + offset.y, z)
        local neighbourNode = solution.nodes[neighbourKey]
        local head = neighbourNode and solution.head[neighbourKey]
        if head then
            local available = head - elevation(z) - Hydraulics.lossPerTile(Hydraulics.flowFor(kind))
            if not best or available > best then
                best = available
            end
        end
    end
    return best
end

-- Hop count from `square` to every node of the zone, as a plain BFS over the solved adjacency.
--
-- This is the draw order's "nearest vessel first", and it is kept exact rather than approximated
-- because the approximations available were all worse: every supply node sits at depth 0, so ordering
-- by distance-from-supply is degenerate, and ordering by |depth difference| is the same thing again.
--
-- It is affordable because it is PURE LUA. The expensive walk was never the arithmetic -- it was
-- getGridSquare and getObjects on every tile, thirteen times over (see PipeObjectUtils' scan memo).
-- Walking a table of keys that is already in hand costs no bridge calls at all, which is the whole
-- reason the topology now lives in the solution instead of being rediscovered per consumer.
-- The zone's squares and powered pumps, as flat lists. Identical for every consumer standing on the
-- zone, so they are built once on demand and handed back by reference rather than rebuilt per query --
-- which is what they were doing, at 179 table inserts a time, for each of 47 emitters.
function Hydraulics.pipeSquares(solution)
    if not solution then
        return {}
    end
    if not solution._pipeSquares then
        local list = {}
        for _, key in ipairs(solution.order) do
            list[#list + 1] = solution.nodes[key].square
        end
        solution._pipeSquares = list
    end
    return solution._pipeSquares
end

function Hydraulics.poweredPumps(solution)
    if not solution then
        return {}
    end
    if not solution._pumpList then
        local list = {}
        for _, pumps in pairs(solution.pumps or {}) do
            for _, pump in ipairs(pumps) do
                list[#list + 1] = pump
            end
        end
        solution._pumpList = list
    end
    return solution._pumpList
end

function Hydraulics.distancesFrom(solution, square)
    if not solution or not square then
        return {}
    end

    local startKey = squareKey(square)

    -- Memoised per origin for the life of the solve. Hop counts are the one genuinely per-consumer
    -- thing left, and a consumer asks for them more than once per pass -- the emitter status, the
    -- availability check and the draw all build a summary from the same tile.
    solution._distances = solution._distances or {}
    local cached = solution._distances[startKey]
    if cached then
        return cached
    end
    local result = Hydraulics.computeDistancesFrom(solution, square, startKey)
    solution._distances[startKey] = result
    return result
end

function Hydraulics.computeDistancesFrom(solution, square, startKey)
    local distance = {}

    -- A fixture (sink, generator) has no pipe of its own; it is one tile off the line.
    if not solution.nodes[startKey] then
        local x, y, z = square:getX(), square:getY(), square:getZ()
        local queue = {}
        for _, offset in ipairs(Constants.CARDINAL_OFFSETS) do
            local neighbourKey = keyOf(x + offset.x, y + offset.y, z)
            if solution.nodes[neighbourKey] and distance[neighbourKey] == nil then
                distance[neighbourKey] = 1
                queue[#queue + 1] = neighbourKey
            end
        end
        return Hydraulics.floodFrom(solution, distance, queue)
    end

    distance[startKey] = 0
    return Hydraulics.floodFrom(solution, distance, { startKey })
end

-- Shared tail of the BFS above: expand `queue` over the zone's adjacency, honouring router crossings
-- in the direction water actually travels.
function Hydraulics.floodFrom(solution, distance, queue)
    local index = 1
    while index <= #queue do
        local key = queue[index]
        index = index + 1

        -- Walks the precomputed feeder lists (see buildFeeders), so this is a plain queue over keys
        -- already in hand: no world access, no router rescan per node.
        for _, neighbourKey in ipairs(solution.feeders[key] or {}) do
            if distance[neighbourKey] == nil then
                distance[neighbourKey] = distance[key] + 1
                queue[#queue + 1] = neighbourKey
            end
        end
    end
    return distance
end

-- Distance in tiles from the nearest supply, for the draw ordering and the readouts.
function Hydraulics.depthAt(solution, square)
    if not solution or not square then
        return nil
    end
    return solution.depth[squareKey(square)]
end

-- Litres/hour flowing through the node, for the gauge and the debug overlay. This is the number that
-- did not exist before and that explains everything the player sees: a line reading 68 L/h at the
-- pump and 1.8 at its far end is a line that has been told, in its own units, why the far end is dry.
function Hydraulics.flowAt(solution, square)
    if not solution or not square then
        return nil
    end
    return solution.flow[squareKey(square)]
end

-- THE gate. Every consumer asks this and nothing asks anything narrower, which is the point.
--
-- Reading the head field alone is not enough, and getting that wrong made the whole starvation model
-- a no-op in the field: the solver had decided that 32 of 47 sprinklers could not be fed, and every
-- one of them watered anyway. The reason is a trap worth naming, because it is self-concealing --
-- THE FIELD A STARVED CONSUMER READS WAS COMPUTED WITHOUT ITS OWN DRAW. Excluding it is exactly what
-- makes its tile look healthy. So the more consumers the solve turns off, the more comfortably each
-- of them clears the minimum when it checks for itself, and a gate that only looks at head lets every
-- single one of them through.
--
-- The solve's decision is therefore the authority, and the head is only the reason for it. Returns
-- (canDraw, head) -- the head comes back either way so a refusal can still say how short it fell.
function Hydraulics.canDrawAt(solution, square, kind)
    if not solution or not square then
        return false, nil
    end

    local head = Hydraulics.pressureAt(solution, square, kind)
    if not head then
        return false, nil
    end

    -- Excluded by the solve: the line cannot carry this one on top of what it is already serving,
    -- however good the reading looks with it switched off.
    --
    -- Only against the kind that was actually excluded, though. The search reasons about EMITTERS, and
    -- its verdict is about that emitter's draw -- not about the tile. A sprinkler the line cannot feed
    -- must not also switch off a tap or a generator drawing from the same square, which need a
    -- fraction of the flow and, for a tap, no pressure at all.
    if Hydraulics.isStarvedAt(solution, square)
        and solution.kinds[squareKey(square)] == kind then
        return false, head
    end

    return head >= Pressure.minimumFor(kind), head
end

function Hydraulics.isStarvedAt(solution, square)
    if not solution or not square then
        return false
    end
    return solution.starved[squareKey(square)] == true
end

-- Deliberately NOT on OnTick, unlike the caches around it, and that is the difference between this
-- being cheap and being the most expensive thing in the mod.
--
-- Solving a zone costs a servable-set search -- about log2(emitters) probes, each relaxing the whole
-- network. That is affordable once in a while and ruinous sixty times a second, which is what dropping
-- it every frame bought: the field was rebuilt from scratch on every frame that anything asked for a
-- pressure, and the readouts, the spray FX and the per-minute pass all ask.
--
-- Nothing the field depends on can change without one of the events below: the layout, a pump being
-- switched, a valve being set, or a vessel crossing between empty and not. The last one is the only
-- soft edge -- the field cares WHETHER a vessel holds water, not how much -- so the per-minute pass
-- drops it as well, which bounds staleness at one in-game minute. No water can be conjured by that:
-- every draw still reads the real vessels through NetworkAccess. The worst a stale field can do is
-- let an emitter believe for one minute that a barrel that just ran dry is still behind it.
if Events then
    if Events.OnObjectAdded then Events.OnObjectAdded.Add(Hydraulics.invalidate) end
    if Events.OnObjectAboutToBeRemoved then Events.OnObjectAboutToBeRemoved.Add(Hydraulics.invalidate) end
end

return Hydraulics
