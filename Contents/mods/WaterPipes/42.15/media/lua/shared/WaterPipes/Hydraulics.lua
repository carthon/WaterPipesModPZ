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
require "WaterPipes/World"

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

-- The demand-aware pressure solver: one head field per NETWORK, propagated in the water's direction
-- from the sources outward, instead of one arithmetic answer per (source, consumer) pair. That is what
-- lets an edge be charged for the litres actually going through it, and drops the cost of a pass from
-- O(consumers x network) to O(network).
--
-- Everything is piezometric head, m.c.a. from a z = 0 datum. See the HYDRAULIC_* block in Constants.lua.
--
--   H[source] = elevation(z) + base head of whatever supplies it
--   H[child]  = H[parent] - K * Q(edge)^n              -- friction, charged to the EDGE
--   H[node]  += pump head                              -- boosters lift the node they stand on
--   H[node]   = min(H[node], elevation(z) + ceiling)   -- a regulator caps its own outlet
--   P[node]   = H[node] - elevation(z)                 -- what a consumer standing there can use
--
-- Elevation living in the datum is what makes this one sweep: climbing and falling are already priced
-- by the difference in `elevation`, so the loop body only ever handles friction.
--
-- Not a real network solve. A looped network's true flow split needs Hardy Cross, which is not something
-- to run in Kahlua every game minute. Each node's demand is split evenly across its shortest-path
-- parents instead, which keeps the property that matters: a loop carries less per branch than a spur.
-- The magnitudes are approximate; the ordering -- who starves first -- is right.

-- Bracket a stretch of work for the profiler, resolved off the global table so this module keeps no
-- dependency on a debug tool. Both are one comparison while the profiler is off.
local function markPhase()
    local Profiler = WaterPipes.Profiler
    return Profiler and Profiler.mark and Profiler.mark() or nil
end

local function sincePhase(name, mark)
    if not mark then
        return
    end
    local Profiler = WaterPipes.Profiler
    if Profiler and Profiler.since then
        Profiler.since(name, mark)
    end
end

local function countPhase(name, amount)
    local Profiler = WaterPipes.Profiler
    if Profiler and Profiler.count then
        Profiler.count(name, amount)
    end
end

local function elevation(z)
    return Pressure.levelHead() * (z or 0)
end

local getCellSquare = WaterPipes.World.squareAt

local function keyOf(x, y, z)
    return tostring(x) .. ":" .. tostring(y) .. ":" .. tostring(z)
end

local function squareKey(square)
    return keyOf(square:getX(), square:getY(), square:getZ())
end

local function hasPipeOnSquare(square)
    return square and PipeObjectUtils.getPipeOnSquare(square) ~= nil
end

-- A router with a tank on it is a hard boundary both ways -- the fluid is being transformed and the two
-- sides must never share a head field. Mirrors NetworkAccess.routerIsHardBoundary.
local function routerIsHardBoundary(routerSquare)
    if Purifier and Purifier.findForRouterSquare and Purifier.findForRouterSquare(routerSquare) then
        return true
    end
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

-- The per-tile friction coefficient for this save: K scaled by the sandbox dial, or zero under the
-- SIMPLE model (height only). Split out because both lookups behind it are per-SAVE constants and
-- lossPerTile was making them per node, per relaxation sweep.
local function frictionCoefficient()
    if Pressure.model() == Constants.PRESSURE_MODEL_SIMPLE then
        return 0
    end
    return Constants.HYDRAULIC_FRICTION_K * sandboxPercent("PressureFrictionScale", 1)
end

local function shapeFlow(flow)
    local q = math.max(flow or 0, 0)
    local exponent = Constants.HYDRAULIC_FRICTION_EXPONENT or 1
    if exponent == 1 then
        return q
    end
    return math.pow(q, exponent)
end

function Hydraulics.lossPerTile(flow)
    local coefficient = frictionCoefficient()
    if coefficient == 0 then
        return 0
    end
    return coefficient * shapeFlow(flow)
end

-- ===== Consumer demand =====

-- Litres per in-game hour a consumer of `kind` pulls when running. Derived from the irrigation
-- constants rather than restated, so a watering rate cannot silently desynchronise from the model.
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

-- What the emitter standing on this square demands, if anything. Resolved off the WaterPipes table:
-- Irrigation requires NetworkAccess which requires this module, and closing that loop recurses.
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

-- FIXTURES ARE NOT LOADS, deliberately. A sink or plumbed generator sits BESIDE the line and draws in
-- bursts, and finding them would mean scanning every tile's four neighbours on every solve. They still
-- READ the field; they just do not push anyone else off it.

-- ===== Phase 1: discover the zone =====
-- Undirected: both sides of a bare regulator belong to the same field (the valve prices the crossing,
-- it does not sever it), while a purifier severs it absolutely. Reaches the same set whatever the seed,
-- which is what lets every consumer on a network share one solve.
local function discover(seedSquare)
    local nodes = {}      -- key -> { x, y, z, square }
    local order = {}      -- keys, discovery order
    local adjacency = {}  -- key -> { neighbourKey -> true }
    local routers = {}    -- key -> { inKey, outKey, z, ceiling } for the bare regulators we may cross
    -- Purifiers whose CLEAN side empties into this zone: 50 litres of storage nothing else can see, so if
    -- the walk does not record it the buffer fills and the device stalls with its water trapped inside.
    -- Recorded during discovery, the one place with the router, its direction and our side in hand.
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
                    -- Sealed both ways -- but if it is a purifier and we stand on its OUT side, its clean buffer is storage
                    -- on THIS zone. Only the out side: the dirty side must never see the clean water.
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

-- WHERE the interesting things stand, as opposed to what they are doing.
-- Where a thing STANDS changes only when an object joins or leaves a tile, which is an event that
-- already drops the topology. What it is DOING -- how full the barrel is, whether the pump has power,
-- whether the drip has burst -- is still read live, every solve. So the search is cached, not the read.
-- The lists are built in `order` so everything downstream stays deterministic, and hold node KEYS.
local function classifySites(nodes, order)
    local sites = { vessels = {}, mains = {}, hydrants = {}, pumps = {}, emitters = {} }
    local Irrigation = WaterPipes.Irrigation

    for _, key in ipairs(order) do
        local square = nodes[key].square

        if Adapter.hasSquareContainers(square) then
            sites.vessels[#sites.vessels + 1] = key
        end

        -- A live inlet is a plumbed fixture AND a town supply still running. Only the fixture is structural,
        -- but the day the water is cut NetworkAccess.supplyClockChanged drops the field globally anyway.
        if Mains.findOnSquare(square) then
            sites.mains[#sites.mains + 1] = key
        end

        if Hydrant.findOnSquare(square) then
            sites.hydrants[#sites.hydrants + 1] = key
        end

        if Pump.findOnSquare(square) then
            sites.pumps[#sites.pumps + 1] = key
        end

        -- A BURST drip belongs here too: repairing it changes no object on the tile, so the site is what is
        -- remembered and the burst flag is read fresh in ownDemandAt.
        if Irrigation then
            for _, worldObject in ipairs(PipeObjectUtils.getPipeObjectsOnSquare(square)) do
                if (Irrigation.isSprinkler and Irrigation.isSprinkler(worldObject))
                    or (Irrigation.isDrip and Irrigation.isDrip(worldObject)) then
                    sites.emitters[#sites.emitters + 1] = key
                    break
                end
            end
        end
    end

    return sites
end

local function collectSupplyAndDemand(nodes, order, sites, purifierOutlets)
    local supply = {}        -- key -> head at that node (m.c.a., absolute)
    local boostable = {}     -- key -> true when a pump may lift this supply (see the end of the pass)
    local demand = {}        -- key -> litres/hour drawn there
    local kinds = {}         -- key -> the consumer kind occupying it
    local pumps = {}         -- key -> list of powered pumps standing there
    local sources = {}       -- descriptor list, for the readouts
    -- Two different numbers. `supplyFloor` is ABSOLUTE head (elevation included) and is what the forward
    -- sweep starts a mains-fed node at. `stats.supplyHead` is the RELATIVE pressure the utility holds its
    -- main at, which is what the lift gate and the readouts want.
    local supplyFloor = 0
    -- Counters the debug readout wants, gathered here because this pass already has every object in hand.
    local stats = { pumpCount = 0, poweredPumps = 0, mainsCount = 0, hydrantCount = 0,
                    pumpHead = 0, supplyHead = 0 }

    local containerBase = Pressure.containerBase()

    local function raise(key, head, pumpsMayLift)
        if not supply[key] or head > supply[key] then
            supply[key] = head
        end
        if pumpsMayLift then
            boostable[key] = true
        end
    end

    -- Stored water. A vessel supplies head only while it holds something, so the AMOUNT is read fresh.
    for _, key in ipairs(sites.vessels) do
        local node = nodes[key]
        for _, descriptor in pairs(Adapter.collectSquareContainers(node.square)) do
            descriptor.nodeKey = key
            sources[#sources + 1] = descriptor
            if (descriptor.waterAmount or 0) > 0 then
                raise(key, elevation(node.z) + containerBase, true)
            end
        end
    end

    -- A purifier's clean buffer is STORED WATER on this zone, exactly like a barrel, and it was the one
    -- store that supplied no head. That is not a rounding error: a head field with no supply anywhere
    -- answers "nothing reaches you" to every consumer on it, so a clean side whose only water is the
    -- buffer -- a purifier with no barrel behind it, which is how most people first build one -- could
    -- take dirty water in and let nobody draw the clean water out. The comment on the settle even
    -- promised the opposite: "with no barrels it is a no-op and a tap can still reach it".
    -- Same base head as a vessel, and boostable for the same reason: a pump lifts stored water.
    for _, outlet in pairs(purifierOutlets or {}) do
        local node = outlet.nodeKey and nodes[outlet.nodeKey]
        if node and Purifier and Purifier.getOutAmount
            and (Purifier.getOutAmount(outlet.purifier) or 0) > 0 then
            raise(outlet.nodeKey, elevation(node.z) + containerBase, true)
        end
    end

    -- A municipal supply holds the whole run at its pressure: a FLOOR, not head added on top, and two of
    -- them do not stack because they are the same town water.
    for _, key in ipairs(sites.mains) do
        local node = nodes[key]
        if Mains.findOnSquare(node.square) then
            local head = elevation(node.z) + Mains.head()
            raise(key, head)
            if head > supplyFloor then supplyFloor = head end
            if Mains.head() > stats.supplyHead then stats.supplyHead = Mains.head() end
            stats.mainsCount = stats.mainsCount + 1
        end
    end

    for _, key in ipairs(sites.hydrants) do
        local node = nodes[key]
        local hydrant = Hydrant.findOnSquare(node.square)
        if hydrant and Hydrant.pressureActive(hydrant) then
            local head = elevation(node.z) + Hydrant.head()
            raise(key, head)
            if head > supplyFloor then supplyFloor = head end
            if Hydrant.head() > stats.supplyHead then stats.supplyHead = Hydrant.head() end
            stats.hydrantCount = stats.hydrantCount + 1
        end
    end

    -- A pump is a booster wherever it stands, and ALSO a source when it has a well or open water beside it.
    -- Power is read live -- a generator starting or stopping announces nothing.
    for _, key in ipairs(sites.pumps) do
        local node = nodes[key]
        local pump = Pump.findOnSquare(node.square)
        if pump then
            stats.pumpCount = stats.pumpCount + 1
            if Pump.isPowered(pump) then
                stats.poweredPumps = stats.poweredPumps + 1
                pumps[key] = pumps[key] or {}
                pumps[key][#pumps[key] + 1] = pump
                stats.pumpHead = stats.pumpHead + Pump.headForPumps({ pump })
                if Pump.findSource and Pump.findSource(pump) then
                    raise(key, elevation(node.z) + containerBase, true)
                end
            end
        end
    end

    -- Demand, read live too: a burst drip still stands there and still conducts, but has stopped loading.
    for _, key in ipairs(sites.emitters) do
        local own, kind = ownDemandAt(nodes[key].square)
        if own > 0 then
            demand[key] = own
            kinds[key] = kind
        end
    end

    -- Pumps are a ZONE term, applied here rather than during propagation. Relaxation has no notion of
    -- direction, so a pump boosting "the node it stands on" boosted head that had come back to it from its
    -- own downstream, and boosted it again next pass: a ten-tile line settled at 297 m.c.a. instead of 49.
    -- A booster has to enter the field as a property of the SUPPLY. Every powered pump in the zone lifts
    -- every vessel in it, they add up in series, and no vessel can be lifted twice.
    -- Municipal supplies are deliberately NOT lifted: a utility is a floor under the run, not a base a pump
    -- stacks onto.
    if stats.pumpHead > 0 then
        for key in pairs(boostable) do
            supply[key] = supply[key] + stats.pumpHead
        end
    end

    return supply, demand, kinds, pumps, sources, supplyFloor, stats
end

-- ===== Phase 3: order the zone by distance from supply =====
-- Multi-source BFS: every supplied node starts at depth 0, so `depth` is the distance to the NEAREST
-- supply and the traversal order is a valid topological order for both sweeps below.
-- `parents` keeps EVERY neighbour one step closer to supply. That is the whole of the loop handling: a
-- node on a ring has two parents and splits its draw between them, so each branch carries half.
local function orderBySupply(nodes, adjacency, routers, supply, adjacencyOrder)
    local depth = {}
    local parents = {}
    local queue = {}
    local sequence = {}

    -- Router crossings are directed edges: water leaves by the OUT side. Indexed by the downstream node.
    local viaRouter = {}
    -- ...and the same edges from the UPSTREAM side, for the walk below. Built here rather than scanned
    -- per node: the walk used to look at every router in the zone for each of its nodes. Sorted for the
    -- same reason the seed below is.
    local outOf = {}
    for _, router in pairs(routers) do
        viaRouter[router.outKey] = viaRouter[router.outKey] or {}
        viaRouter[router.outKey][router.inKey] = router

        local list = outOf[router.inKey]
        if not list then
            list = {}
            outOf[router.inKey] = list
        end
        list[#list + 1] = router.outKey
    end
    for _, list in pairs(outOf) do
        table.sort(list)
    end

    -- Sorted, and not for tidiness. The BFS seeded from here decides each node's `parents`, which decides
    -- how a shared flow splits between parallel branches -- and Lua randomises string hashing per process,
    -- so `pairs` over tile keys made a two-supply network solve differently every session. A simulation
    -- that cannot reproduce its own result cannot be diffed against itself.
    for key in pairs(supply) do
        if nodes[key] then
            queue[#queue + 1] = key
        end
    end
    table.sort(queue)
    for _, key in ipairs(queue) do
        depth[key] = 0
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

        -- A FIXED order, for the reason the seed above is sorted and this was missed by: the order
        -- neighbours are discovered in decides `sequence`, `sequence` decides the order accumulate() sums
        -- a node's children into its flow, and floating-point addition is not associative. Left to
        -- `pairs`, one node of a looped network priced 1 ulp differently in about one run of every
        -- hundred -- rare enough to read as a real regression the day it turned up in a diff.
        -- The order comes off the topology; a caller without one still walks, just not reproducibly.
        local neighbours = adjacencyOrder and adjacencyOrder[key]
        if neighbours then
            for _, neighbourKey in ipairs(neighbours) do
                step(neighbourKey)
            end
        else
            for neighbourKey in pairs(adjacency[key] or {}) do
                step(neighbourKey)
            end
        end

        -- ...and out through any router this node feeds.
        for _, outKey in ipairs(outOf[key] or {}) do
            step(outKey)
        end
    end

    return depth, parents, sequence, viaRouter
end

-- ===== Phase 4: accumulate demand toward the supply =====
-- Walk the BFS order backwards, so every node is processed after everything it feeds. Each node's
-- through-flow is its own draw plus its share of its children's, split evenly across its parents.
-- `peak` rides along beside `flow`: the largest SINGLE consumer downstream. It is what
-- HYDRAULIC_DEMAND_SCALE = 0 falls back to, which is exactly the old per-consumer arithmetic.
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

-- Every node that can hand head to another, precomputed ONCE per solve. This used to be built inside
-- the relaxation, per node, per sweep -- a table allocated and every router in the zone scanned some
-- fifteen thousand times for a single farm. The shape it describes cannot change between sweeps.
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

    -- A valve is an edge, never a node, so its two ends are joined separately. Both directions: a regulator
    -- does not lift its inlet, but refusing to look backwards would strand a supply sitting past one.
    for _, router in pairs(routers or {}) do
        link(router.outKey, router.inKey)
        link(router.inKey, router.outKey)
    end

    return feeders
end

-- ===== Phase 5: propagate head away from the supply =====
-- RELAXATION, not a topological sweep. The BFS seeds EVERY supplied node at depth 0, so a barrel on the
-- line has no parents -- and a sweep that only takes head from a node's parents pinned each barrel to
-- its own base pressure, so a pump next door could not lift it and 47 sprinklers starved with two
-- working pumps ten tiles away.
-- A pump pressurises the WATER, including the water in the vessels feeding it, so a node takes the best
-- head ANY neighbour can deliver. The pump term itself lives on the supply for the same reason: a
-- direction-free field cannot host a direction-dependent booster without feeding it its own output.

local function propagate(nodes, sequence, parents, feeders, supply, flow, peak, viaRouter)
    local count = #sequence
    local scale = Hydraulics.demandScale()

    -- What ONE of the edges feeding `key` actually carries. Two things are interpolated by the same dial
    -- and both must collapse together at scale 0: how much of the shared demand the edge is charged for,
    -- and whether arriving by parallel branches divides it. At 0 this returns the single largest consumer,
    -- undivided -- the old arithmetic. At 1, the true through-flow split evenly across the branches.
    local function edgeFlow(key)
        local list = parents[key]
        local parentCount = list and #list or 1
        local total = flow[key] or 0
        local single = peak[key] or 0
        local effective = single + (total - single) * scale
        local divisor = 1 + (math.max(parentCount, 1) - 1) * scale
        return effective / divisor
    end

    -- Everything the sweeps need, laid out by POSITION instead of by node key. Same arithmetic, same order,
    -- same field: what changed is the cost. Per node per pass the sweeps were doing four hash lookups on
    -- interned strings, an ipairs iterator, a closure call and, on a regulated edge, a sandbox read -- and
    -- Kahlua hashes a string on every one of those lookups. None of it varies between passes, so it is
    -- resolved once into integer-indexed arrays and the inner loop has no strings in it at all.
    local position = {}
    for index = 1, count do
        position[sequence[index]] = index
    end

    local coefficient = frictionCoefficient()
    local supplyAt = {}
    local lossAt = {}
    local feedersAt = {}
    local ceilingAt = {}

    for index = 1, count do
        local key = sequence[index]
        supplyAt[index] = supply[key]
        lossAt[index] = coefficient == 0 and 0 or (coefficient * shapeFlow(edgeFlow(key)))

        -- A feeder outside the sequence is never relaxed, so it never has a head. Dropped once, here.
        local list = feeders[key]
        local mapped = {}
        local caps = nil
        if list then
            local routersHere = viaRouter[key]
            for order = 1, #list do
                local feederPosition = position[list[order]]
                if feederPosition then
                    mapped[#mapped + 1] = feederPosition
                    -- A regulator on this edge fixes the head at ITS OUTLET; past it the water keeps paying friction and
                    -- height like any other run. The cap is a constant of the edge, so the elevation() behind it -- which
                    -- reads a sandbox value -- is computed once, not per pass.
                    local router = routersHere and routersHere[list[order]]
                    if router and router.ceiling then
                        caps = caps or {}
                        caps[#mapped] = elevation(router.z) + router.ceiling
                    end
                end
            end
        end
        feedersAt[index] = mapped
        ceilingAt[index] = caps
    end

    -- Which nodes a given node can feed: the reverse of feedersAt, and what turns a sweep into a worklist.
    local consumersAt = {}
    for index = 1, count do
        consumersAt[index] = {}
    end
    for index = 1, count do
        local list = feedersAt[index]
        for order = 1, #list do
            local feeder = list[order]
            consumersAt[feeder][#consumersAt[feeder] + 1] = index
        end
    end

    -- A worklist, not alternating full sweeps. Relaxing to a fixed point does not care what order the nodes
    -- are visited in, only that no node is left improvable -- so the queue holds exactly the nodes that
    -- could have changed: seeded with everything, re-seeded with a node's consumers whenever its head
    -- actually moves. Same fixed point, same epsilon; nodes that settle early are not looked at again.
    -- The cap survives as a bound on total relaxations rather than on rounds, so a pathological network
    -- still terminates and still says so.
    local headAt = {}
    local passes = math.max(Constants.HYDRAULIC_RELAX_PASSES or 1, 1)
    local limit = passes * count
    local counters = Hydraulics.counters

    local queue = {}
    local queued = {}
    for index = 1, count do
        queue[index] = index
        queued[index] = true
    end

    local cursor = 1
    local processed = 0

    while cursor <= #queue and processed < limit do
        local index = queue[cursor]
        cursor = cursor + 1
        queued[index] = false
        processed = processed + 1

        local base = supplyAt[index]
        local edgeLoss = lossAt[index]
        local list = feedersAt[index]
        local caps = ceilingAt[index]

        for order = 1, #list do
            local feederHead = headAt[list[order]]
            if feederHead then
                local arriving = feederHead - edgeLoss
                local ceiling = caps and caps[order]
                if ceiling and arriving > ceiling then
                    arriving = ceiling
                end
                if not base or arriving > base then
                    base = arriving
                end
            end
        end

        if base then
            local previous = headAt[index]
            if not previous or base > previous + 0.0001 then
                headAt[index] = base
                local consumers = consumersAt[index]
                for order = 1, #consumers do
                    local consumer = consumers[order]
                    if not queued[consumer] then
                        queued[consumer] = true
                        queue[#queue + 1] = consumer
                    end
                end
            end
        end
    end

    counters.relaxCalls = counters.relaxCalls + processed
    counters.relaxPasses = counters.relaxPasses + math.ceil(processed / math.max(count, 1))
    if processed >= limit then
        -- Ran out of relaxations with work still queued. Counted, because it means two things at once and
        -- neither is otherwise visible: the relaxation is doing its maximum work, and the field it returns is
        -- not fully converged.
        counters.relaxCapped = counters.relaxCapped + 1
    end

    -- Back to node keys, which is what every reader of the field expects.
    local head = {}
    for index = 1, count do
        local value = headAt[index]
        if value then
            head[sequence[index]] = value
        end
    end
    return head
end

-- ===== The solve =====

-- How many consumers this zone could serve the LAST time it was solved.
-- Kept across scoped invalidations on purpose: what invalidates the field minute to minute is a barrel
-- crossing empty, and the answer barely moves when it does. The search starts there and walks outward,
-- costing two or three re-pricings instead of the seven a search over the whole range needs, and still
-- finds the same answer because the predicate is monotone and the bracket is proved before it narrows.
-- Cleared only by the global drop, which also bounds it.
local servableHint = {}

-- Each node's neighbours, sorted. See the walk in orderBySupply for why the ORDER is load-bearing.
local function sortedAdjacency(nodes, adjacency)
    local ordered = {}
    for key in pairs(nodes) do
        local list = {}
        for neighbourKey in pairs(adjacency[key] or {}) do
            list[#list + 1] = neighbourKey
        end
        table.sort(list)
        ordered[key] = list
    end
    return ordered
end

-- ===== Topology, which outlives a supply change =====
-- What the zone IS -- its nodes, how they connect, which routers sit on the edges -- changes only when
-- the pipe layout does, and every way that can happen fires an object event. What SUPPLIES it changes
-- constantly: a barrel crossing empty was 211 of 215 field invalidations in a measured window.
-- Split, so a supply change re-prices the field it already has and only an object event goes to the world.
local function discoverTopology(seedSquare)
    local mark = markPhase()
    local nodes, order, adjacency, routers, purifierOutlets = discover(seedSquare)
    sincePhase("solve/discover", mark)
    if #order == 0 then
        return nil
    end

    -- Every node that can hand head to another. Derived from the adjacency and the routers, so it belongs
    -- to the topology rather than to the solve that reads it.
    return {
        nodes = nodes,
        order = order,
        adjacency = adjacency,
        routers = routers,
        purifierOutlets = purifierOutlets,
        feeders = buildFeeders(nodes, adjacency, routers),
        -- Each node's neighbours in a fixed order. Structural, like the sites below, and for the same
        -- reason: a re-pricing must not pay to rediscover the shape. Built here, the walk's determinism
        -- costs the discovery once instead of every solve -- measured at +17 % on a re-price when it was
        -- sorted per solve, which is the common path.
        adjacencyOrder = sortedAdjacency(nodes, adjacency),
        -- Where the vessels, inlets, pumps and emitters stand. Structural, so it belongs here rather than being
        -- rediscovered by every re-pricing.
        sites = classifySites(nodes, order),
    }
end

local function solveWithTopology(topology, zoneKey)
    local nodes = topology.nodes
    local order = topology.order
    local adjacency = topology.adjacency
    local routers = topology.routers
    local purifierOutlets = topology.purifierOutlets
    local feeders = topology.feeders

    countPhase("solve: nodes", #order)

    local mark = markPhase()
    local supply, demand, kinds, pumps, sources, supplyFloor, stats =
        collectSupplyAndDemand(nodes, order, topology.sites, purifierOutlets)
    sincePhase("solve/supply", mark)

    mark = markPhase()
    local depth, parents, sequence, viaRouter =
        orderBySupply(nodes, adjacency, routers, supply, topology.adjacencyOrder)
    sincePhase("solve/order", mark)
    if not sequence then
        -- Nothing supplies this zone: every node is dry, which is a real answer and not a failure.
        -- THE SHAPE, not most of it. `feeders` was once missing here and floodFrom indexes it without a guard,
        -- so a dry network -- the ordinary state of a farm nobody has filled yet -- threw instead of answering.
        return {
            topology = topology,
            nodes = nodes, order = order, adjacency = adjacency, routers = routers,
            feeders = feeders, purifierOutlets = purifierOutlets,
            parents = parents, viaRouter = viaRouter,
            supply = supply, sequence = nil,
            sources = sources, demand = demand, kinds = kinds,
            head = {}, flow = {}, depth = {}, supplyFloor = supplyFloor, pumps = pumps, stats = stats,
            starved = {}, iterations = 0,
        }
    end

    -- ===== Who actually gets to draw =====
    -- A FIXED POINT, and the obvious way to look for it does not converge. Turning every starved consumer
    -- off at once springs the line back to full static head, so on the next pass they all look servable and
    -- switch back on. It oscillates with period two, and capping the iteration count only decides which half
    -- of the oscillation you see -- which is how one report read "47 starved, 0.00 of 84.60 L/h served"
    -- directly above "Flow through this tile: 84.60 L/h".
    -- So the search is made MONOTONE instead. Order the consumers by how easy they are to satisfy and ask
    -- "can the first k all be served at once?" Adding a consumer only adds flow, which only costs head, so
    -- if k fails so does k+1: a binary search finds the largest workable set in about log2(N) solves, and
    -- nothing is ever switched back on.
    -- The ordering is by REQUIRED HEAD first, distance second. A drip needs no pressure at all and draws a
    -- ninth of what a sprinkler draws, so dropping one to feed a sprinkler would be perverse.
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

    countPhase("solve: consumers", #ordered)

    local head, flow, peak
    local solves = 0

    -- The field left behind by the last probe that SUCCEEDED, and the size it was for. The search ends by
    -- re-pricing at the chosen size, because its last probe is usually a failed one -- but in the common
    -- path (hint succeeds, hint+1 fails) the answer IS the hint, whose field was computed two probes ago.
    -- Keeping it turns three re-pricings into two. Safe by reference: accumulate and propagate each build
    -- fresh tables and nothing mutates them afterwards.
    local bestCount, bestHead, bestFlow, bestPeak = nil, nil, nil, nil

    -- Price the network with exactly the first `count` consumers drawing, and report whether every one of
    -- them clears its own minimum. Leaves head/flow/peak describing that state.
    local function trySet(count)
        solves = solves + 1
        Hydraulics.counters.repricings = Hydraulics.counters.repricings + 1
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

        bestCount, bestHead, bestFlow, bestPeak = count, head, flow, peak
        return true
    end

    -- The servable-set binary search: about log2(N)+1 full re-pricings of the field, each an accumulate plus
    -- a propagate over every node. Pure Lua, no world access -- which is why it is timed here.
    local searchMark = markPhase()

    -- Two searches, because a hint and no hint want different ones -- measured, not assumed: walking outward
    -- from the top of the range with no hint was slower than the plain binary search on two of three benched
    -- networks. trySet(0) is vacuously true, so a downward walk always terminates. Every probe is the same
    -- monotone predicate, so the answer is identical whichever branch runs; only the order the range is
    -- explored in differs, and test_hydraulics.lua check 15 asserts that for every hint in the range.
    local count = #ordered
    local hinted = servableHint[zoneKey or ""]
    if hinted and (hinted > count or hinted < 0) then
        hinted = nil
    end

    local low, high

    if hinted then
        -- The usual case in play: re-solved because a barrel crossed empty, and the answer barely moves.
        if trySet(hinted) then
            low, high = hinted, count
            local step = 1
            while low < high do
                local probe = low + step
                if probe > count then probe = count end
                if trySet(probe) then
                    low = probe
                    if probe == count then break end
                    step = step * 2
                else
                    high = probe - 1
                    break
                end
            end
        else
            low, high = 0, hinted - 1
            local step = 1
            while true do
                local probe = hinted - step
                if probe <= 0 then break end
                if trySet(probe) then
                    low = probe
                    break
                end
                high = probe - 1
                step = step * 2
            end
        end
    else
        -- No hint: the first solve of a zone, or the first after a global drop. Probe the WHOLE set once,
        -- because a farm with head to spare serves every emitter -- one probe instead of six -- and fall back
        -- to the plain binary search if it fails.
        if trySet(count) then
            low, high = count, count
        else
            low, high = 0, count - 1
        end
    end

    while low < high do
        local middle = math.floor((low + high + 1) / 2)
        if trySet(middle) then
            low = middle
        else
            high = middle - 1
        end
    end

    if zoneKey then
        servableHint[zoneKey] = low
    end

    -- Re-price at the chosen size, unless the probe that proved it left exactly that field in hand. What the
    -- mod reports and what it priced must be the same state.
    if bestCount == low and bestHead then
        head, flow, peak = bestHead, bestFlow, bestPeak
    else
        trySet(low)
    end

    sincePhase("solve/search", searchMark)
    countPhase("solve: repricings", solves)

    local starved = {}
    for index = low + 1, #ordered do
        starved[ordered[index]] = true
    end

    return {
        -- Carried on the solution so the next supply change can re-price without going to the world.
        topology = topology,
        nodes = nodes,
        order = order,
        adjacency = adjacency,
        routers = routers,
        feeders = feeders,
        -- Carried so the field can be re-priced with ONE extra consumer switched on (see headIfDrawing).
        parents = parents,
        viaRouter = viaRouter,
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

local function solveZone(seedSquare, zoneKey)
    local topology = discoverTopology(seedSquare)
    if not topology then
        return nil
    end
    return solveWithTopology(topology, zoneKey)
end

-- ===== Zone cache, shared across every consumer on the network =====
-- The field is identical for every consumer standing on the same zone, so it is computed once and keyed
-- by every node in it. Dropped by the per-minute pass and by the events that can change it, never by a
-- frame boundary. The FLUID is not cached -- callers still read vessels live through NetworkAccess --
-- so what is cached moves only when topology, pump state or emitter count does.
local solutionCache = {}
local zoneOfNode = {}

-- Counters: the only way to tell a cache that is working from one dropped faster than it is built.
Hydraulics.counters = { solves = 0, hits = 0, scoped = 0, global = 0, untouched = 0,
                        relaxPasses = 0, relaxCalls = 0, repricings = 0, relaxCapped = 0,
                        supplyOnly = 0 }

-- ===== The supply hold =====
-- A pass is ONE instant of simulated time, so the field it drinks from should be priced once. It was
-- priced 45 times: every emitter empties a barrel and the next one re-solves. Measured at 226 of the
-- session's 237 solves. Between hold and release a SUPPLY invalidation is recorded instead of applied,
-- and the release marks every zone that asked -- so the field the pass ends on is the field it would
-- have had, one solve later instead of forty-five.
-- Only the supply form is held. An object event can be a pipe, and that changes the shape.
local heldZones = {}
local holdDepth = 0

-- Nestable: the debug one-frame run can land inside a pass that is already holding.
function Hydraulics.holdSupplyInvalidation()
    holdDepth = holdDepth + 1
end

function Hydraulics.isSupplyHeld()
    return holdDepth > 0
end

-- Apply what was deferred and clear it. Only the outermost release applies; returns whether it did.
function Hydraulics.releaseSupplyInvalidation()
    if holdDepth <= 0 then
        return false
    end

    holdDepth = holdDepth - 1
    if holdDepth > 0 then
        return false
    end

    local applied = false
    for zoneId in pairs(heldZones) do
        local solution = solutionCache[zoneId]
        -- A zone dropped outright while held is simply gone; there is nothing left to mark stale.
        if solution and solution.topology then
            solution.supplyStale = true
            applied = true
        end
    end
    heldZones = {}
    return applied
end

-- Every field on the map. For the per-minute pass and for changes not tied to a tile: a pump switched,
-- a sandbox value, a full network rebuild.
function Hydraulics.invalidate()
    solutionCache = {}
    zoneOfNode = {}
    -- The servable hint survives a SCOPED drop, but not this one: a global drop means the shape itself is
    -- in question. It is also what bounds the table.
    servableHint = {}
    -- Never deferred, and never lifts the hold: a global drop says the SHAPE is in question, which is not
    -- the claim "supply moved". What was pending named zones that no longer exist.
    heldZones = {}
    Hydraulics.counters.global = Hydraulics.counters.global + 1
end

-- Forget one zone, leaving every other network on the map alone.
-- zoneOfNode also holds entries for tiles that are not nodes -- a sink asking for pressure is recorded
-- against the zone it borrows -- which are not walked here and survive as pointers to a zone that no
-- longer exists. Safe: solveAt only trusts a pointer while solutionCache still holds the zone, so a
-- stale one costs one missed lookup and is overwritten by the solve that follows.
local function forgetZone(zoneId)
    local solution = zoneId and solutionCache[zoneId]
    if not solution then
        return false
    end

    solutionCache[zoneId] = nil
    for _, nodeKey in ipairs(solution.order) do
        if zoneOfNode[nodeKey] == zoneId then
            zoneOfNode[nodeKey] = nil
        end
    end
    zoneOfNode[zoneId] = nil
    return true
end

-- The zone's SUPPLY changed -- a vessel crossed between empty and not -- but its shape did not.
-- Marking rather than dropping keeps the topology, so the re-solve skips discover() entirely and never
-- touches the world. This is the common path: 211 of every 215 field invalidations in a real save.
local function staleSupplyInZone(zoneId)
    local solution = zoneId and solutionCache[zoneId]
    if not solution or not solution.topology then
        return false
    end
    -- Held: record it and leave the field priced. The release applies it.
    if holdDepth > 0 then
        heldZones[zoneId] = true
        return true
    end
    solution.supplyStale = true
    return true
end

-- Something appeared or vanished at a tile: drop only the fields whose zone touches it.
-- There is deliberately no test of what the object is. A predicate would have to enumerate every type
-- that can matter, and a missing one would fail silently; "what zone is cached at this tile" needs no
-- such list. A new pipe belongs to no zone yet, but the zones it merges are its NEIGHBOURS'.
-- Vertical neighbours are the plain z+/-1 tiles rather than a riser lookup, which would cost world
-- reads on an event that fires for every streamed object. A riser geometry this misses stays stale
-- until the per-minute pass.
function Hydraulics.invalidateAroundSquare(square)
    if not square or not square.getX then
        Hydraulics.invalidate()
        return
    end

    local okX, x = pcall(square.getX, square)
    local okY, y = pcall(square.getY, square)
    local okZ, z = pcall(square.getZ, square)
    if not okX or not okY or not okZ or x == nil or y == nil or z == nil then
        Hydraulics.invalidate()
        return
    end

    local dropped = forgetZone(zoneOfNode[keyOf(x, y, z)])
    for _, offset in ipairs(Constants.CARDINAL_OFFSETS) do
        if forgetZone(zoneOfNode[keyOf(x + offset.x, y + offset.y, z)]) then
            dropped = true
        end
    end
    if forgetZone(zoneOfNode[keyOf(x, y, z - 1)]) then dropped = true end
    if forgetZone(zoneOfNode[keyOf(x, y, z + 1)]) then dropped = true end

    local counters = Hydraulics.counters
    if dropped then
        counters.scoped = counters.scoped + 1
    else
        counters.untouched = counters.untouched + 1
    end
end

-- The same tile scoping, but for a change that cannot have moved a pipe: a vessel crossing between
-- empty and not. Callers must be sure of that premise -- it holds for OnWaterAmountChange and for
-- nothing else here, since an object appearing or leaving CAN be a pipe and goes to the drop above.
function Hydraulics.invalidateSupplyAroundSquare(square)
    if not square or not square.getX then
        Hydraulics.invalidate()
        return
    end

    local okX, x = pcall(square.getX, square)
    local okY, y = pcall(square.getY, square)
    local okZ, z = pcall(square.getZ, square)
    if not okX or not okY or not okZ or x == nil or y == nil or z == nil then
        Hydraulics.invalidate()
        return
    end

    local marked = staleSupplyInZone(zoneOfNode[keyOf(x, y, z)])
    for _, offset in ipairs(Constants.CARDINAL_OFFSETS) do
        if staleSupplyInZone(zoneOfNode[keyOf(x + offset.x, y + offset.y, z)]) then
            marked = true
        end
    end
    if staleSupplyInZone(zoneOfNode[keyOf(x, y, z - 1)]) then marked = true end
    if staleSupplyInZone(zoneOfNode[keyOf(x, y, z + 1)]) then marked = true end

    local counters = Hydraulics.counters
    if marked then
        counters.supplyOnly = counters.supplyOnly + 1
        -- How much of the churn is a pass draining its own barrels: still raised, now deferred.
        if holdDepth > 0 then
            countPhase("hydraulics: supply invalidations during a pass", 1)
        end
    else
        counters.untouched = counters.untouched + 1
    end
end

function Hydraulics.invalidateAroundObject(worldObject)
    if not worldObject or not worldObject.getSquare then
        Hydraulics.invalidate()
        return
    end

    local ok, square = pcall(worldObject.getSquare, worldObject)
    if not ok or not square then
        Hydraulics.invalidate()
        return
    end

    Hydraulics.invalidateAroundSquare(square)
end

function Hydraulics.solveAt(square)
    if not square then
        return nil
    end

    local key = squareKey(square)
    local zoneId = zoneOfNode[key]
    local cached = zoneId and solutionCache[zoneId] or nil
    if cached and not cached.supplyStale then
        Hydraulics.counters.hits = Hydraulics.counters.hits + 1
        return cached
    end

    -- Marked stale by a vessel crossing empty, but the shape is still good: re-price it without going back
    -- to the world. The node set is identical, so every zoneOfNode entry pointing here stays correct.
    if cached and cached.topology then
        local repriced = solveWithTopology(cached.topology, zoneId)
        if repriced then
            repriced.id = zoneId
            solutionCache[zoneId] = repriced
            Hydraulics.counters.solves = Hydraulics.counters.solves + 1
            if holdDepth > 0 then
                countPhase("hydraulics: solves during a pass", 1)
            end
            return repriced
        end
        -- The zone no longer solves at all against its own topology. Fall through and rediscover.
        solutionCache[zoneId] = nil
    end

    -- The seed must be a pipe tile: a fixture has no pipe of its own, so the zone it belongs to is
    -- whichever one its neighbours are on.
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
        -- Risers too: a sink whose only connection is the riser on its own tile has to keep working.
        for _, coord in ipairs(PipeObjectUtils.getRiserVerticalNeighborCoords(x, y, z)) do
            trySeed(getCellSquare(coord.x, coord.y, coord.z))
        end
    end
    if not seed then
        return nil
    end

    local seedKey = squareKey(seed)
    zoneId = zoneOfNode[seedKey]
    local seeded = zoneId and solutionCache[zoneId] or nil
    if seeded and not seeded.supplyStale then
        zoneOfNode[key] = zoneId
        Hydraulics.counters.hits = Hydraulics.counters.hits + 1
        return seeded
    end

    local solution = solveZone(seed, seedKey)
    if not solution then
        return nil
    end

    solution.id = seedKey
    Hydraulics.counters.solves = Hydraulics.counters.solves + 1
    solutionCache[seedKey] = solution
    zoneOfNode[key] = seedKey
    for _, nodeKey in ipairs(solution.order) do
        zoneOfNode[nodeKey] = seedKey
    end
    return solution
end

-- ===== Readouts =====

-- Usable pressure (m.c.a.) for a `kind` consumer standing on `square`, or nil when nothing supplies it.
-- A consumer on a fixture tile reads the best of its pipe neighbours, minus its own edge -- it is one
-- tile off the line, and that tile costs what any other does.
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

-- Hop count from `square` to every node of the zone: a plain BFS over the solved adjacency, which is
-- the draw order's "nearest vessel first". Kept exact because every supply node sits at depth 0, so
-- ordering by distance-from-supply is degenerate. Affordable because it is PURE LUA -- the expensive
-- part was never the arithmetic but getGridSquare and getObjects on every tile.

-- The zone's squares and powered pumps, as flat lists. Identical for every consumer standing on the
-- zone, so built once on demand and handed back by reference rather than rebuilt per query.
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

-- The zone's tiles that hold a vessel, off the topology's own site list.
-- classifySites already asked Adapter.hasSquareContainers of every node when the shape was discovered,
-- and that answer is structural: it moves only when an object appears or leaves, which rebuilds the
-- topology. NetworkAccess used to re-derive the same list by walking every pipe square of the zone --
-- 191 squares to find 7 vessels, 1780 squares a second in a measured window -- because its own memo for
-- it was dropped every frame.
-- Cached on the SOLUTION rather than the topology so it follows the same lifetime pipeSquares does.
function Hydraulics.vesselSquares(solution)
    if not solution then
        return {}
    end
    if not solution._vesselSquares then
        local list = {}
        local sites = solution.topology and solution.topology.sites or nil
        for _, key in ipairs(sites and sites.vessels or {}) do
            local node = solution.nodes[key]
            if node and node.square then
                list[#list + 1] = { square = node.square, key = key }
            end
        end
        solution._vesselSquares = list
    end
    return solution._vesselSquares
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

    -- Memoised per origin for the life of the solve: a consumer asks for hop counts more than once a pass --
    -- the emitter status, the availability check and the draw all build a summary from the same tile.
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

        -- Walks the precomputed feeder lists (see buildFeeders): a plain queue over keys already in hand, with
        -- no world access and no router rescan per node.
        for _, neighbourKey in ipairs(solution.feeders[key] or {}) do
            if distance[neighbourKey] == nil then
                distance[neighbourKey] = distance[key] + 1
                queue[#queue + 1] = neighbourKey
            end
        end
    end
    return distance
end

-- Which of the zone's nodes a consumer standing on `square` may actually DRAW from, and how far each is.
--
-- The head field joins a router's two ends in BOTH directions on purpose (see buildFeeders): a supply
-- sitting past a valve still has to be visible to the pressure solve, or it strands. STORAGE is not
-- symmetric in the same way. A router carries water one way and refuses the return, so litres that have
-- already crossed are gone as far as the upstream side is concerned -- and a draw that counted them
-- levelled the two networks against each other instead of emptying the source into the destination.
--
-- So: plain adjacency both ways, and a router edge only in the direction a draw may cross it -- standing
-- on the OUT side, reaching back to the IN side, which is what viaRouter already records.
-- Returns (distanceByKey, squares) with the squares in the zone's own order, so the draw's vessel
-- ordering does not depend on how this walk happened to expand.
function Hydraulics.drawReachableFrom(solution, square)
    if not solution or not square then
        return {}, {}
    end

    local startKey = squareKey(square)
    solution._drawReach = solution._drawReach or {}
    local cached = solution._drawReach[startKey]
    if cached then
        return cached.distance, cached.squares
    end

    local distance = {}
    local queue = {}

    if solution.nodes[startKey] then
        distance[startKey] = 0
        queue[1] = startKey
    else
        -- A fixture (sink, generator) has no pipe of its own; it is one tile off the line.
        local x, y, z = square:getX(), square:getY(), square:getZ()
        for _, offset in ipairs(Constants.CARDINAL_OFFSETS) do
            local neighbourKey = keyOf(x + offset.x, y + offset.y, z)
            if solution.nodes[neighbourKey] and distance[neighbourKey] == nil then
                distance[neighbourKey] = 1
                queue[#queue + 1] = neighbourKey
            end
        end
    end

    local index = 1
    while index <= #queue do
        local key = queue[index]
        index = index + 1

        for neighbourKey in pairs(solution.adjacency[key] or {}) do
            if distance[neighbourKey] == nil and solution.nodes[neighbourKey] then
                distance[neighbourKey] = distance[key] + 1
                queue[#queue + 1] = neighbourKey
            end
        end

        -- The one legal valve crossing for a draw: we are on the OUT side, the water we want is behind it.
        for neighbourKey in pairs((solution.viaRouter or {})[key] or {}) do
            if distance[neighbourKey] == nil and solution.nodes[neighbourKey] then
                distance[neighbourKey] = distance[key] + 1
                queue[#queue + 1] = neighbourKey
            end
        end
    end

    -- The lowest reached key doubles as the SOURCE NETWORK's identity: two consumers that can draw from
    -- each other agree on it, and one on the far side of a valve does not. Computed once per origin here
    -- rather than by whoever needs it, which would be once a minute per router.
    local squares = {}
    local sourceId = nil
    for _, key in ipairs(solution.order) do
        if distance[key] ~= nil then
            squares[#squares + 1] = solution.nodes[key].square
            if not sourceId or key < sourceId then
                sourceId = key
            end
        end
    end

    solution._drawReach[startKey] = { distance = distance, squares = squares, sourceId = sourceId }
    return distance, squares, sourceId
end

-- The identity of the body of water a consumer standing here can reach. See drawReachableFrom.
function Hydraulics.drawSourceId(solution, square)
    local _, _, sourceId = Hydraulics.drawReachableFrom(solution, square)
    return sourceId
end

-- Litres/hour flowing through the node, for the gauge and the debug overlay. This is the number that
-- explains a line reading 68 L/h at the pump and 1.8 at its far end.
function Hydraulics.flowAt(solution, square)
    if not solution or not square then
        return nil
    end
    return solution.flow[squareKey(square)]
end

-- THE gate. Every consumer asks this and nothing asks anything narrower.
-- Reading the head field alone is not enough, and the trap is self-concealing: THE FIELD A STARVED
-- CONSUMER READS WAS COMPUTED WITHOUT ITS OWN DRAW. Excluding it is exactly what makes its tile look
-- healthy, so the more consumers the solve turns off, the more comfortably each of them clears the
-- minimum when it checks for itself -- and a head-only gate lets every one of them through.
-- The solve's decision is the authority; the head is only the reason for it. Returns (canDraw, head),
-- the head either way so a refusal can still say how short it fell.
function Hydraulics.canDrawAt(solution, square, kind)
    if not solution or not square then
        return false, nil
    end

    local head = Hydraulics.pressureAt(solution, square, kind)
    if not head then
        return false, nil
    end

    -- Excluded by the solve: the line cannot carry this one on top of what it already serves, however good
    -- the reading looks with it switched off.
    -- Only against the kind that was excluded, though. The search reasons about EMITTERS, so a sprinkler the
    -- line cannot feed must not also switch off a tap or a generator drawing from the same square.
    if Hydraulics.isStarvedAt(solution, square)
        and solution.kinds[squareKey(square)] == kind then
        return false, head
    end

    return head >= Pressure.minimumFor(kind), head
end

-- The head this tile would ACTUALLY have with this consumer drawing.
-- pressureAt reports the field as solved, and it is solved with only the servable consumers drawing --
-- so an excluded consumer reads a high number precisely because it is switched off, which showed a
-- player 37 beside "needs 20" and a sprinkler refusing to run.
-- For a consumer already served this is just the solved field. For an excluded one it re-prices the zone
-- once, so it is NOT for the hot path: the spray FX must keep using the cached field.
-- Returns (head, shortfall), or nil when the question cannot be answered.
function Hydraulics.headIfDrawing(solution, square, kind)
    if not solution or not square or not kind then
        return nil, nil
    end

    local key = squareKey(square)
    local minimum = Pressure.minimumFor(kind)

    -- Already served, or not a consumer the solve knows about: the solved field is the answer.
    if not solution.starved or not solution.starved[key] or not solution.sequence then
        local head = Hydraulics.pressureAt(solution, square, kind)
        if not head then
            return nil, nil
        end
        return head, math.max(minimum - head, 0)
    end

    -- Everything currently being served, plus this one.
    local active = {}
    for demandKey in pairs(solution.demand or {}) do
        if not solution.starved[demandKey] then
            active[demandKey] = true
        end
    end
    active[key] = true

    local flow, peak = accumulate(solution.sequence, solution.parents, solution.demand, active)
    local head = propagate(solution.nodes, solution.sequence, solution.parents, solution.feeders,
        solution.supply, flow, peak, solution.viaRouter)

    local node = solution.nodes[key]
    local absolute = head[key]
    if not node or not absolute then
        return nil, nil
    end

    local available = absolute - elevation(node.z)
    return available, math.max(minimum - available, 0)
end

-- The key a square is indexed by in a solution, for callers outside this module. squareKey is a local,
-- and reproducing "x:y:z" at the call site is how two indexes drift.
function Hydraulics.nodeKeyOf(square)
    if not square then
        return nil
    end
    return squareKey(square)
end

-- How much MORE head this zone needs before this consumer can run.
-- Not the same as how far this tile is below its own minimum, and that is the whole reason it exists: a
-- sprinkler reading 30 against a minimum of 20 is short of nothing itself, it is off because turning it
-- on would push a DIFFERENT emitter under. So the question is asked of the whole set -- serve everything
-- already watering plus this one, and how far below its minimum does the worst-off consumer fall?
-- EXACT for the set it prices: pump head enters as a supply term, so adding X raises every head by X.
-- A LOWER BOUND for this emitter overall, since the search serves a prefix and any starved emitter
-- between it and the ones already running has to clear its own minimum too.
-- Returns (extraHeadNeeded, blockingKey); zero means it could already be served, nil means the question
-- could not be answered. One re-price -- for the tooltip and the debug report, not for the hot path.
function Hydraulics.headNeededToServe(solution, square, kind)
    if not solution or not square or not solution.sequence or not solution.starved then
        return nil, nil
    end

    local key = squareKey(square)

    local active = {}
    for demandKey in pairs(solution.demand or {}) do
        if not solution.starved[demandKey] then
            active[demandKey] = true
        end
    end
    active[key] = true

    local flow, peak = accumulate(solution.sequence, solution.parents, solution.demand, active)
    local head = propagate(solution.nodes, solution.sequence, solution.parents, solution.feeders,
        solution.supply, flow, peak, solution.viaRouter)

    local worst, blocker = 0, nil
    for activeKey in pairs(active) do
        local node = solution.nodes[activeKey]
        local absolute = head[activeKey]
        local available = (node and absolute) and (absolute - elevation(node.z)) or nil
        -- This consumer's own kind, except for the tile being asked about: it is not in the solve's kinds table
        -- as a drawing consumer while it is switched off.
        local ownKind = solution.kinds[activeKey]
        if activeKey == key then
            ownKind = kind or ownKind
        end
        local needed = Pressure.minimumFor(ownKind)

        local missing
        if not available then
            missing = needed          -- nothing reaches it at all
        else
            missing = needed - available
        end
        if missing > worst then
            worst, blocker = missing, activeKey
        end
    end

    return worst, blocker
end

-- Would the line break if this one were switched on as well? The same question, as a yes or no.
function Hydraulics.couldServeAlso(solution, square, kind)
    local needed, blocker = Hydraulics.headNeededToServe(solution, square, kind)
    if needed == nil then
        return nil, nil
    end
    return needed <= 0, blocker
end

function Hydraulics.isStarvedAt(solution, square)
    if not solution or not square then
        return false
    end
    return solution.starved[squareKey(square)] == true
end

-- Deliberately NOT on OnTick, unlike the caches around it. Solving a zone costs a servable-set search --
-- about log2(emitters) probes, each relaxing the whole network -- which is affordable once in a while
-- and ruinous sixty times a second.
-- Nothing the field depends on can change without one of the events below. The one soft edge is a vessel
-- crossing between empty and not, so the per-minute pass drops it as well, bounding staleness at one
-- in-game minute. No water can be conjured by that: every draw still reads the real vessels through
-- NetworkAccess.
if Events then
    -- Scoped, not global. These fire for every object the world streams in as the player walks, and almost
    -- none of them are ours; the global drop here meant the per-zone cache never lived long enough to be one.
    if Events.OnObjectAdded then
        Events.OnObjectAdded.Add(Hydraulics.invalidateAroundObject)
    end
    if Events.OnObjectAboutToBeRemoved then
        Events.OnObjectAboutToBeRemoved.Add(Hydraulics.invalidateAroundObject)
    end
end

return Hydraulics
