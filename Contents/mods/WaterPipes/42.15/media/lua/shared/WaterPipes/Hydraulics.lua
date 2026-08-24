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

-- Bracket a stretch of work for the profiler, if it is loaded and on. Resolved off the global table
-- rather than required: this module must not depend on a debug tool, and while the profiler is off
-- both of these are one comparison.
--
-- Why the solve is broken out at all: with the field now caching at 99.9%, the RARE cold solve stopped
-- being a cost spread over a session and became a single visible spike -- one measured at 161 ms in
-- one frame, which is ten times the threshold where a stutter is visible. "The solve is expensive" is
-- not actionable; which PHASE of it is expensive is. Three wrong guesses were spent locating the
-- spray-FX cost by reasoning instead of measuring, and this is the cheaper version of that lesson.
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
-- The per-tile friction coefficient for this save: K scaled by the sandbox dial, or zero under the
-- SIMPLE model (height only, exactly as before).
--
-- Split out because both of the lookups behind it are per-SAVE constants and lossPerTile was making
-- them per NODE, per relaxation sweep. Twelve sweeps over 181 nodes, seven times per solve, is thirty
-- thousand SandboxVars table walks for two numbers that cannot change while the solve runs -- and the
-- solve was measured at 141 ms, 87% of it in exactly that loop.
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

-- WHERE the interesting things stand, as opposed to what they are doing.
--
-- collectSupplyAndDemand used to SEARCH for its inputs: for every node of the zone it asked the world
-- five separate questions -- is there a vessel here, a mains fixture, a hydrant, a pump, an emitter --
-- and on 181 nodes that is 905 probes, several of them a getObjects plus a getModData per object on
-- the tile. It ran on every supply change: 276 of them in a 40 s window, at 6.9 ms each.
--
-- Where a thing STANDS changes only when an object joins or leaves a tile, which is an event and
-- already drops the whole topology. What it is DOING -- how full the barrel is, whether the pump has
-- power, whether the drip has burst -- changes constantly and is still read live, every solve, from
-- the world. So the search is cached and the reading is not.
--
-- The lists are built in `order` so everything downstream stays deterministic, and they hold node
-- KEYS rather than squares because that is what the field is indexed by.
local function classifySites(nodes, order)
    local sites = { vessels = {}, mains = {}, hydrants = {}, pumps = {}, emitters = {} }
    local Irrigation = WaterPipes.Irrigation

    for _, key in ipairs(order) do
        local square = nodes[key].square

        if Adapter.hasSquareContainers(square) then
            sites.vessels[#sites.vessels + 1] = key
        end

        -- A live inlet is a plumbed fixture AND a town supply that is still running. Only the fixture
        -- is structural, but asking the whole question here is safe and simpler: the day the water is
        -- cut, NetworkAccess.supplyClockChanged drops the field globally and this is rebuilt. A
        -- fixture plumbed later is an event too (see EndpointPlumbing.plumb).
        if Mains.findOnSquare(square) then
            sites.mains[#sites.mains + 1] = key
        end

        if Hydrant.findOnSquare(square) then
            sites.hydrants[#sites.hydrants + 1] = key
        end

        if Pump.findOnSquare(square) then
            sites.pumps[#sites.pumps + 1] = key
        end

        -- A BURST drip belongs here too. It draws nothing today and will draw again when repaired,
        -- and repairing it changes no object on the tile -- so the site is what is remembered and the
        -- burst flag is read fresh in ownDemandAt.
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

local function collectSupplyAndDemand(nodes, order, sites)
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

    local function raise(key, head, pumpsMayLift)
        if not supply[key] or head > supply[key] then
            supply[key] = head
        end
        if pumpsMayLift then
            boostable[key] = true
        end
    end

    -- Stored water. A vessel only supplies head while it actually holds something -- so the AMOUNT is
    -- read fresh here on every solve, and only where a vessel is known to stand.
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

    -- A municipal supply holds the whole run at its pressure -- a FLOOR, not head added on top, and
    -- two of them do not stack because they are the same town water. Same rule the chain arithmetic
    -- used; it is just a max over the zone now instead of a walk back up a chain.
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

    -- A pump is a booster wherever it stands, and ALSO a source when it has a well or open water
    -- beside it: that is where the water physically enters the network. Power is read live -- a
    -- generator starting or stopping announces nothing.
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

    -- Demand, read live too: a drip that has burst still stands there and still conducts, but it has
    -- stopped being a load until somebody repairs it.
    for _, key in ipairs(sites.emitters) do
        local own, kind = ownDemandAt(nodes[key].square)
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

    -- Sorted, and that is not tidiness. The BFS seeded from here decides each node's `parents`, and
    -- `parents` decides how a shared flow is split between parallel branches -- so an unordered seed
    -- makes the field differ in its last digits between one run and the next. Lua randomises string
    -- hashing per process, so `pairs` over a table of tile keys is genuinely unstable, and a network
    -- with two supplies solved to a slightly different answer every session.
    --
    -- Nothing visible depended on it, but a simulation that cannot reproduce its own result cannot be
    -- compared against itself either -- which is exactly what a golden-field diff needs to do. There
    -- are a handful of supplies in a zone; sorting them costs nothing.
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

local function propagate(nodes, sequence, parents, feeders, supply, flow, peak, viaRouter)
    local count = #sequence
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

    -- ===== Everything the sweeps need, laid out by POSITION instead of by node key =====
    --
    -- This is the single change that made a cold solve affordable, and it is not an algorithmic one:
    -- the relaxation does the same arithmetic in the same order and produces the same field. What
    -- changed is what each step of it COSTS.
    --
    -- The sweeps were doing, per node per pass: four hash lookups on interned strings (supply, loss,
    -- feeders, viaRouter), an ipairs iterator, a closure call, and -- on any edge carrying a regulator
    -- -- an elevation() that reads a sandbox value. Measured in game: 1 260 to 1 800 of those per
    -- solve, and a solve at 141 ms with 87% of it here. PZ's Kahlua hashes a string on every one of
    -- those lookups.
    --
    -- None of it varies between passes. So it is resolved ONCE into integer-indexed arrays, and the
    -- inner loop becomes array reads and arithmetic with no strings in it at all.
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

        -- A feeder outside the sequence is never relaxed, so it never has a head and the old code
        -- skipped it every pass. Dropping it here is the same answer, found once.
        local list = feeders[key]
        local mapped = {}
        local caps = nil
        if list then
            local routersHere = viaRouter[key]
            for order = 1, #list do
                local feederPosition = position[list[order]]
                if feederPosition then
                    mapped[#mapped + 1] = feederPosition
                    -- A regulator on this edge fixes the head at ITS OUTLET. Past it the water keeps
                    -- paying friction and keeps gaining or losing height like any other run, which
                    -- falls out for free: we cap here and the relaxation carries on. The cap itself is
                    -- a constant of the edge, so the elevation() behind it is computed once, not per
                    -- pass -- it reads a sandbox value.
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

    -- Which nodes a given node can feed. The reverse of feedersAt, built once, and the thing that
    -- turns a sweep into a worklist: when a node's head improves, only these can improve because of
    -- it.
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

    -- A worklist, not alternating full sweeps.
    --
    -- The sweeps were the honest first version: Kahlua has no heap, so a Dijkstra order was out, and
    -- sweeping the BFS order forwards and back converges in a few rounds. But "a few" turned out to be
    -- TEN on a real farm where the bench needed five, and every one of those rounds re-examined all
    -- 181 nodes -- 5 430 relaxations per solve to move a handful of heads.
    --
    -- Relaxing to a fixed point does not care what order the nodes are visited in; it cares that no
    -- node is left improvable. So the queue holds exactly the nodes that could have changed: seeded
    -- with everything, and re-seeded with a node's consumers whenever its head actually moves. The
    -- fixed point is identical -- same predicate, same epsilon -- and the nodes that settle early are
    -- simply not looked at again.
    --
    -- The cap survives as a bound on total relaxations rather than on rounds, so a pathological
    -- network still terminates and still says so.
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
        -- Ran out of relaxations with the queue still holding work. Counted, because it means two
        -- different things at once and neither is visible otherwise: the relaxation is doing its
        -- maximum work every time (the cost), and the field it returns is not fully converged (the
        -- answer).
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
--
-- Kept across scoped invalidations on purpose. What actually invalidates the field, minute to minute,
-- is a barrel crossing empty -- 47 of the 50 solves in one measured window -- and the answer barely
-- moves when it does: a farm serving 31 of 47 sprinklers still serves about 31 a moment later. The
-- binary search below starts there and walks outward, so the usual case costs two or three
-- re-pricings instead of the seven a search over the whole range needs, and it still finds exactly
-- the same answer because the predicate is monotone and the bracket is proved before it narrows.
--
-- Cleared only by the global drop, which also bounds it: keys are seed tiles, and a save has as many
-- as it has networks.
local servableHint = {}

-- ===== Topology, which outlives a supply change =====
--
-- What the zone IS -- its nodes, how they connect, which routers sit on the edges -- changes only when
-- the pipe layout does, and every way that can happen fires an object event. What SUPPLIES it changes
-- constantly: a barrel crossing empty is 211 of the 215 field invalidations in a measured window.
--
-- Those were the same drop, so every barrel emptying re-walked the world. discover() is the only phase
-- that touches it -- a getGridSquare and a pipe/router probe per neighbour of every node -- and it was
-- measured at 12.9 ms of a 40 ms re-solve. Splitting them means a supply change re-prices the field it
-- already has, and only an object event goes back to the world.
local function discoverTopology(seedSquare)
    local mark = markPhase()
    local nodes, order, adjacency, routers, purifierOutlets = discover(seedSquare)
    sincePhase("solve/discover", mark)
    if #order == 0 then
        return nil
    end

    -- Every node that can hand head to another. Derived purely from the adjacency and the routers, so
    -- it belongs to the topology and not to the solve that reads it.
    return {
        nodes = nodes,
        order = order,
        adjacency = adjacency,
        routers = routers,
        purifierOutlets = purifierOutlets,
        feeders = buildFeeders(nodes, adjacency, routers),
        -- Where the vessels, inlets, pumps and emitters stand. Structural, so it belongs here rather
        -- than being rediscovered by every re-pricing. See classifySites.
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
        collectSupplyAndDemand(nodes, order, topology.sites)
    sincePhase("solve/supply", mark)

    mark = markPhase()
    local depth, parents, sequence, viaRouter = orderBySupply(nodes, adjacency, routers, supply)
    sincePhase("solve/order", mark)
    if not sequence then
        -- Nothing supplies this zone: no water, no mains, no pump with a source. Every node is dry,
        -- which is a real answer and not a failure -- return the shape with an empty field.
        --
        -- THE SHAPE, not most of it. `feeders` was missing here, and Hydraulics.floodFrom indexes it
        -- without a guard -- so asking a dry zone for anything measured from a tile (a tap's summary,
        -- an emitter's status: both go through distancesFrom) threw instead of answering "nothing".
        -- A dry network is the ordinary state of a farm the player has not filled yet, so this was
        -- not an edge case. Two return statements describing the same table is the trap; the fix is
        -- to keep them describing the same table.
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

    countPhase("solve: consumers", #ordered)

    local head, flow, peak
    local solves = 0

    -- The field left behind by the last probe that SUCCEEDED, and the size it was for.
    --
    -- The search ends by re-pricing at the chosen size, because its last probe is usually a failed one
    -- and the head/flow left behind would otherwise describe a state the mod reports as not happening.
    -- But in the common path -- hint succeeds, hint+1 fails -- the answer IS the hint, and its field
    -- was computed two probes ago and thrown away. Keeping it turns three re-pricings into two, and a
    -- re-pricing is a whole relaxation of the zone.
    --
    -- Safe to keep by reference: accumulate and propagate each build fresh tables and nothing mutates
    -- them afterwards.
    local bestCount, bestHead, bestFlow, bestPeak = nil, nil, nil, nil

    -- Price the network with exactly the first `count` consumers drawing, and report whether every one
    -- of them clears its own minimum. Leaves head/flow/peak describing that state, which is what makes
    -- the final call below the thing that decides what the readouts say.
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

    -- The servable-set binary search: about log2(N)+1 full re-pricings of the field, each an
    -- accumulate plus a propagate over every node. Pure Lua, no world access -- which is exactly why
    -- the bridge-call model could never see it, and why it is timed here instead.
    local searchMark = markPhase()

    -- Two searches, because a hint and no hint want different ones -- and measured, not assumed:
    -- walking outward from the TOP of the range with no hint made a starved farm slower than the plain
    -- binary search it replaced, on two of three benched networks. A bracket walk is only a good search
    -- when you already have reason to believe the answer is close.
    --
    -- trySet(0) is vacuously true -- no consumer drawing, nothing to fail -- so a downward walk always
    -- terminates with a workable `low`. Every probe is the same monotone predicate the plain search
    -- used, so the answer is identical whichever branch runs; only the order the range is explored in
    -- differs. tools/conservation/test_hydraulics.lua check 15 asserts exactly that, for every hint in
    -- the range.
    local count = #ordered
    local hinted = servableHint[zoneKey or ""]
    if hinted and (hinted > count or hinted < 0) then
        hinted = nil
    end

    local low, high

    if hinted then
        -- The usual case in play: the field is re-solved because a barrel crossed empty, and the
        -- answer barely moves. Walk outward from where it was.
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
        -- No hint: the first solve of a zone, or the first after a global drop. Probe the WHOLE set
        -- once, because a farm with head to spare serves every emitter and that is one probe instead
        -- of six -- and if it fails, fall back to the plain binary search over what is left rather
        -- than groping downward from the top.
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

    -- Re-price at the chosen size -- unless the field for exactly that size is already in hand from
    -- the probe that proved it. The point stands either way: what the mod reports and what it priced
    -- must be the same state, which is the contradiction this replaced.
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
        -- Carried so the field can be re-priced with ONE extra consumer switched on, which is what
        -- Hydraulics.headIfDrawing needs. Nothing else reads them.
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

-- ===== Per-frame cache, shared across every consumer on the network =====
--
-- This is the other half of the point. The field is identical for every consumer standing on the same
-- zone, so it is computed once and keyed by every node in it -- a second emitter three tiles away hits
-- the cache instead of walking 192 tiles again.
--
-- Dropped by the per-minute pass and by the events that can change it, never by a frame boundary --
-- see Hydraulics.invalidateAroundSquare and the note on NetworkAccess.invalidateTraversalCache. The FLUID is
-- not cached (callers still read vessels live through NetworkAccess); what is cached is the field,
-- which moves only when topology, pump state or emitter count does -- none of which can change inside
-- a frame without an event firing.
local solutionCache = {}
local zoneOfNode = {}

-- Counters. Free while nothing reads them, and the only way to tell a cache that is working from one
-- being dropped faster than it is built -- which is the failure this file already shipped with once.
Hydraulics.counters = { solves = 0, hits = 0, scoped = 0, global = 0, untouched = 0,
                        relaxPasses = 0, relaxCalls = 0, repricings = 0, relaxCapped = 0,
                        supplyOnly = 0 }

-- Every field on the map. For the per-minute pass and for the changes not tied to a tile: a pump
-- switched, a sandbox value, a full network rebuild.
function Hydraulics.invalidate()
    solutionCache = {}
    zoneOfNode = {}
    -- The servable hint survives a SCOPED drop, which is the common one, but not this: a global drop
    -- means the shape itself is in question, and this is also what bounds the table.
    servableHint = {}
    Hydraulics.counters.global = Hydraulics.counters.global + 1
end

-- Forget one zone, leaving every other network on the map alone.
--
-- zoneOfNode also holds entries for tiles that are not network nodes -- a sink asking for pressure is
-- recorded against the zone it borrows. Those are not walked here, so they survive as pointers to a
-- zone that no longer exists. That is safe by construction: solveAt only trusts a pointer when
-- solutionCache still holds the zone, so a stale one costs one missed lookup and is overwritten by
-- the solve that follows. The global drop clears them.
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
--
-- Marking rather than dropping is the whole point: the solution keeps its topology, so the re-solve
-- that follows skips discover() entirely and never touches the world. A barrel emptying is 211 of
-- every 215 field invalidations in a real save, so this is the common path, not the exception.
local function staleSupplyInZone(zoneId)
    local solution = zoneId and solutionCache[zoneId]
    if not solution or not solution.topology then
        return false
    end
    solution.supplyStale = true
    return true
end

-- Something appeared or vanished at a tile. The only fields that can be wrong because of it are the
-- ones whose zone touches that tile, so those are the only ones dropped.
--
-- There is deliberately NO test of what the object is. A predicate here would have to enumerate every
-- type that can matter -- pipe, router, pump, hydrant, purifier, mains fixture, sprinkler, drip,
-- anything holding a fluid -- and a type missing from that list would fail silently, which is the
-- failure mode this subsystem specialises in. Asking "what zone is cached at this tile" needs no such
-- list: if nothing is cached there, nothing can be wrong, whatever the object was. A new pipe looks
-- like a counterexample and is not -- it belongs to no zone yet, but the zones it merges are its
-- NEIGHBOURS', which is why they are dropped too.
--
-- Vertical neighbours are the plain z+/-1 tiles rather than a riser lookup, which would cost world
-- reads on an event that fires for every object the map streams in. A riser geometry this misses
-- stays stale until the per-minute pass -- the same backstop that already bounds vessel emptiness.
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
-- empty and not. The zone keeps its shape and re-prices from it.
--
-- Callers must be sure of that premise. It holds for OnWaterAmountChange and for nothing else in this
-- mod -- an object appearing or leaving goes to invalidateAroundSquare above, which drops the topology
-- with everything else, because an object CAN be a pipe.
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

    -- Marked stale by a vessel crossing empty, but the shape is still good: re-price it without going
    -- back to the world. The node set is identical, so every zoneOfNode entry pointing here stays
    -- correct and no other tile has to be told.
    if cached and cached.topology then
        local repriced = solveWithTopology(cached.topology, zoneId)
        if repriced then
            repriced.id = zoneId
            solutionCache[zoneId] = repriced
            Hydraulics.counters.solves = Hydraulics.counters.solves + 1
            return repriced
        end
        -- The zone no longer solves at all against its own topology. Fall through and rediscover.
        solutionCache[zoneId] = nil
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

-- The head this tile would ACTUALLY have with this consumer drawing.
--
-- Hydraulics.pressureAt reports the field as solved, and the field is solved with only the servable
-- consumers drawing -- so a consumer the search excluded reads a high number precisely because it is
-- switched off. Showing that to a player produced a sprinkler reporting 37 next to "needs 20" and
-- refusing to run, which reads as a bug and is not one.
--
-- This answers the question the player is really asking: switch this one on as well, and what does it
-- get? For a consumer that is already served the answer is simply the solved field, so this costs
-- nothing. For an excluded one it re-prices the zone once with that consumer added.
--
-- That is a whole relaxation, so it is NOT for the hot path: the spray FX asks about every emitter
-- near the player several times a second and must keep using the cached field. This is for the
-- tooltip, which a player opens deliberately, one emitter at a time.
--
-- Returns (head, shortfall) where shortfall is how much more head it would need, or nil when the
-- question cannot be answered.
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

-- The key a square is indexed by in a solution, for callers outside this module that need to look
-- one up. squareKey is a local, and reproducing "x:y:z" at the call site is how two indexes drift.
function Hydraulics.nodeKeyOf(square)
    if not square then
        return nil
    end
    return squareKey(square)
end

-- How much MORE head this zone needs before this consumer can run.
--
-- Not the same as how far this tile is below its own minimum, and that distinction is the whole
-- reason this exists. A sprinkler reporting 30 m against a minimum of 20 is not short of anything
-- itself: it is switched off because turning it on would push a DIFFERENT emitter below ITS minimum.
-- Asking "what do you need" of the tile you are standing on answers the wrong question and returns
-- zero, which is why the readout could only say "the line cannot supply it" and nothing more.
--
-- So the question is asked of the whole set: serve everything already watering plus this one, and how
-- far below its minimum does the worst-off consumer fall? That number is what the line is missing.
--
-- It is EXACT for the set it prices. Pump head enters the field as a supply term, so adding X raises
-- every head by X and the worst-off consumer lands exactly on its minimum -- which is why "add a
-- pump" is such a reliable fix and why the number is worth showing. It is a LOWER BOUND for this
-- emitter overall: the search serves a prefix, so if other starved emitters sit between this one and
-- the ones already running, they have to clear their own minimums too.
--
-- Returns (extraHeadNeeded, blockingKey). Zero means it could already be served. Nil means the
-- question could not be answered.
--
-- One re-price. For the tooltip and the debug report, not for the hot path.
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
        -- This consumer's own kind, except for the tile being asked about: it is not in the solve's
        -- kinds table as a drawing consumer while it is switched off.
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
    -- Scoped, not global. These fire for every object the world streams in as the player walks, and
    -- almost none of them are ours; wiring the global drop here meant the field was thrown away
    -- continuously and the per-zone cache never lived long enough to be one.
    if Events.OnObjectAdded then
        Events.OnObjectAdded.Add(Hydraulics.invalidateAroundObject)
    end
    if Events.OnObjectAboutToBeRemoved then
        Events.OnObjectAboutToBeRemoved.Add(Hydraulics.invalidateAroundObject)
    end
end

return Hydraulics
