WaterPipes = WaterPipes or {}
WaterPipes.NetworkAccess = WaterPipes.NetworkAccess or {}

require "WaterPipes/Constants"
require "WaterPipes/ContainerAdapter"
require "WaterPipes/EndpointObjects"
require "WaterPipes/Hydrant"
require "WaterPipes/Logger"
require "WaterPipes/Mains"
require "WaterPipes/PipeObjectUtils"
require "WaterPipes/Pressure"
require "WaterPipes/Pump"
require "WaterPipes/Purifier"
require "WaterPipes/Router"

local Adapter = WaterPipes.ContainerAdapter
local Constants = WaterPipes.Constants
local EndpointObjects = WaterPipes.EndpointObjects
local Hydrant = WaterPipes.Hydrant
local Logger = WaterPipes.Logger
local Mains = WaterPipes.Mains
local NetworkAccess = WaterPipes.NetworkAccess
local PipeObjectUtils = WaterPipes.PipeObjectUtils
local Pressure = WaterPipes.Pressure
local Pump = WaterPipes.Pump
local Purifier = WaterPipes.Purifier
local Router = WaterPipes.Router

-- A router is two different real devices depending on what sits on it.
--
-- With a tank on its tile (the purifier) it is a HARD BOUNDARY: the fluid is being transformed, so
-- the IN and OUT sides must never see each other -- otherwise an OUT-side tap could pull the raw
-- tainted water straight off the IN side and bypass purification entirely.
--
-- Bare, it is an inline PRESSURE-REDUCING VALVE: water flows through it and leaves its outlet at
-- whatever ceiling the player set, then keeps losing head down the branch like any other run. That is
-- what real plumbing does, and it is why a sprinkler on a tank-less branch can still draw from the
-- main network.
local function routerIsHardBoundary(routerSquare)
    if Purifier and Purifier.findForRouterSquare and Purifier.findForRouterSquare(routerSquare) then
        return true
    end
    -- Any other vessel parked on the crossing buffers the flow, so treat it as a boundary too.
    -- Iterate rather than use next(): PZ's Lua does not expose next, and the descriptors are a
    -- string-keyed map so # would not work either.
    local containers = Adapter.collectSquareContainers(routerSquare)
    for _ in pairs(containers) do
        return true
    end
    return false
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

local function squareKey(square)
    return tostring(square:getX()) .. ":" .. tostring(square:getY()) .. ":" .. tostring(square:getZ())
end

local function describeEndpointObject(endpointObject)
    if not endpointObject then
        return "nil"
    end

    local name = endpointObject.getName and endpointObject:getName() or "?"
    local spriteName = (endpointObject.getSprite and endpointObject:getSprite() and endpointObject:getSprite():getName()) or "?"
    local objectIndex = endpointObject.getObjectIndex and endpointObject:getObjectIndex() or "?"
    local square = endpointObject.getSquare and endpointObject:getSquare() or nil
    local squareText = square and squareKey(square) or "?"
    return tostring(name) .. " sprite=" .. tostring(spriteName) .. " index=" .. tostring(objectIndex) .. " square=" .. squareText
end

local function addSquare(squareMap, square)
    if not square then
        return false
    end

    local key = squareKey(square)
    if squareMap[key] then
        return false
    end

    squareMap[key] = square
    return true
end

local function getNeighborSquares(square)
    local neighbors = { square }
    for _, offset in ipairs(Constants.NETWORK_NEIGHBOR_OFFSETS) do
        local neighbor = getCellSquare(square:getX() + offset.x, square:getY() + offset.y, square:getZ() + offset.z)
        if neighbor then
            neighbors[#neighbors + 1] = neighbor
        end
    end
    return neighbors
end

-- Containers connect to pipes on the SAME floor (the square itself + cardinal neighbours).
local function getHorizontalNeighborSquares(square)
    local neighbors = { square }
    for _, offset in ipairs(Constants.CARDINAL_OFFSETS) do
        local neighbor = getCellSquare(square:getX() + offset.x, square:getY() + offset.y, square:getZ())
        if neighbor then
            neighbors[#neighbors + 1] = neighbor
        end
    end
    return neighbors
end

local function getFluidTypeByName(fluidTypeName)
    if fluidTypeName == "Water" then
        return Fluid and Fluid.Water or (FluidType and FluidType.Water)
    end

    if fluidTypeName == "TaintedWater" then
        return Fluid and Fluid.TaintedWater or (FluidType and FluidType.TaintedWater)
    end

    if FluidType and FluidType.FromNameLower then
        return FluidType.FromNameLower(string.lower(fluidTypeName))
    end

    if Fluid and Fluid.FromNameLower then
        return Fluid.FromNameLower(string.lower(fluidTypeName))
    end

    return nil
end

local function isWaterTypeName(fluidTypeName)
    return fluidTypeName == "Water" or fluidTypeName == "TaintedWater"
end

local function hasPipeOnSquare(square)
    return square and PipeObjectUtils.getPipeOnSquare(square) ~= nil
end

-- verticalMode gates how riser (cross-floor) links are followed so gravity is honoured:
--   "both" (default) -> both directions (topology / visualization),
--   "up"   -> only to HIGHER floors: the sources whose water can drain down to originSquare,
--   "down" -> only to LOWER floors: where water introduced at originSquare would fall.
-- Same-floor (horizontal) links always conduct both ways.
--
-- ===== Regulator chains =====
--
-- The walk starts at the CONSUMER and runs outward, so every square is reached through some sequence
-- of regulators. That sequence is what prices the square, and it is stored as a linked chain: each
-- node is one router crossing (its setting, its height, and how far it sits from the consumer), and
-- `parent` walks back toward the consumer. The root node is the unregulated stretch the consumer
-- itself stands in.
--
-- A chain node also owns the pumps found on the squares it covers, which is what lets a pump be
-- placed on the right side of a regulator: pumps hanging off a node are UPSTREAM of that node's valve
-- and cannot push past it, while everything on the way back to the consumer boosts freely.
local function newChain(parent, ceiling, hops, z)
    return { parent = parent, ceiling = ceiling, hops = hops, z = z, pumps = {}, supplyHead = 0 }
end

-- Head the pumps between `chain` and the consumer add, inclusive of the chain's own stretch. Pumps ADD
-- UP: they sit in series, and buying a second one is meant to buy more head. Cached per node, so a
-- network with two routers and forty pipes asks this once per node.
local function chainPumpHead(chain)
    if not chain then
        return 0
    end
    if not chain.pumpHead then
        chain.pumpHead = chainPumpHead(chain.parent) + Pump.headForPumps(chain.pumps)
    end
    return chain.pumpHead
end

-- The pressure a municipal supply on `chain` floors the run at. A utility (the town mains, or an open
-- fire hydrant fed by it) holds its main at a set pressure, and every connection sits at that pressure
-- -- so it is a FLOOR under the whole run, not head added on top of a source. Two supplies do not
-- stack: they are the same town water, so the floor is simply the highest one present, which is what
-- taking the max gives. Each chain node records the best floor contributed by sources on its own
-- squares (see tryAdd); this walks node + parents for the best between `chain` and the consumer.
-- Deliberately uncached, unlike chainPumpHead: `supplyHead` is still being raised as the walk finds
-- squares, so caching could freeze a value taken before a later inlet was reached.
local function chainSupplyHead(chain)
    if not chain then
        return 0
    end
    return math.max(chain.supplyHead or 0, chainSupplyHead(chain.parent))
end

-- Everything a source on `chain` gets for free, applied to a head it computed on its own.
local function applyChainSupply(head, chain)
    return math.max(head, chainSupplyHead(chain))
end

-- What a source at (z, hops) on `chain` actually delivers to a `kind` consumer at consumerZ: the
-- unregulated head, then held down by every valve on the way, each priced from where it stands.
local function headThroughChain(sourceZ, consumerZ, hops, kind, chain)
    local head = applyChainSupply(
        Pressure.delivered(sourceZ, consumerZ, hops, kind, chainPumpHead(chain)), chain)

    local node = chain
    while node do
        if node.ceiling then
            -- A valve is priced from where it stands, and then gets whatever is BETWEEN it and the
            -- consumer: pumps in front of it boost its branch, and an inlet in front of it holds that
            -- branch at mains pressure no matter what the valve is set to. It cannot regulate a supply
            -- that joins downstream of itself -- only what flows through it.
            local capped = applyChainSupply(
                Pressure.atRegulator(node.ceiling, node.z, consumerZ, node.hops, kind,
                    chainPumpHead(node.parent)), node.parent)
            if capped < head then
                head = capped
            end
        end
        node = node.parent
    end
    return head
end

-- The tightest raw setting on a chain, for readouts that want to name the regulator responsible.
local function chainTightestCeiling(chain)
    local tightest = nil
    local node = chain
    while node do
        if node.ceiling and (not tightest or node.ceiling < tightest) then
            tightest = node.ceiling
        end
        node = node.parent
    end
    return tightest
end

-- Returns (pipeSquares, hopsByKey, zone). hopsByKey is the min hop count from originSquare to each
-- pipe square, which is all the pressure model needs from the traversal: head loss is friction *
-- hops, and the elevation term depends only on the endpoints (see Constants.lua), so minimising loss
-- is just minimising hops -- no weighted search required.
--
-- `zone` carries what the pressure gate needs about this network, gathered as we go: the powered
-- pumps inside it and the routers bounding it. Both fall out of work the walk already does -- it
-- must look at every square's pipe objects anyway, and it already asks each one whether it is a
-- router -- so collecting them here costs nothing, where a second and third pass over the zone
-- would have tripled the cost of every draw query.
--
-- Draw queries pass "both" and let the pressure gate do the filtering; "up" survives only for
-- callers that want the old gravity-reachable set without pricing it. See buildSummaryFromSquare.
-- `conduct` turns bare routers into inline regulators the walk may cross (draw queries). Fills and
-- visualization pass false and keep the old behaviour, where every router is a wall.
local function collectPipeSquaresFromSquare(originSquare, verticalMode, conduct)
    if not originSquare then
        return {}, {}, { pumps = {}, mains = {} }, {}
    end

    verticalMode = verticalMode or "both"

    local visited = {}
    local queue = {}
    local hops = {}
    local chains = {}   -- regulator chain each square was reached through (see newChain)
    local pipeSquares = {}
    local rootChain = newChain(nil, nil, 0, originSquare:getZ())
    local zone = { pumps = {}, mains = {}, hydrants = {}, supplyHead = 0, rootChain = rootChain }

    local function tryAdd(square, distance, chain)
        if not square or not hasPipeOnSquare(square) or Router.hasRouterOnSquare(square) then
            return
        end

        if not addSquare(visited, square) then
            return
        end

        local key = squareKey(square)
        queue[#queue + 1] = square
        hops[key] = distance
        chains[key] = chain
        pipeSquares[#pipeSquares + 1] = square

        local pump = Pump.findOnSquare(square)
        if pump then
            zone.pumps[#zone.pumps + 1] = pump
            -- Also filed under the stretch it stands in, so the regulator arithmetic knows which side
            -- of which valve it is on.
            chain.pumps[#chain.pumps + 1] = pump
        end

        -- Municipal supplies floor the run at their pressure (see chainSupplyHead). A plumbed fixture
        -- with live town water behind it, and an OPEN hydrant that is still mains-fed, are both such
        -- floors; each raises the chain node's best floor and the zone's, so a regulator holds them
        -- down the same way it holds a pump down.
        local function addSupply(head)
            if head > (chain.supplyHead or 0) then
                chain.supplyHead = head
            end
            if head > zone.supplyHead then
                zone.supplyHead = head
            end
        end

        local mains = Mains.findOnSquare(square)
        if mains then
            zone.mains[#zone.mains + 1] = mains
            addSupply(Mains.head())
        end

        local hydrant = Hydrant.findOnSquare(square)
        if hydrant and Hydrant.pressureActive(hydrant) then
            zone.hydrants[#zone.hydrants + 1] = hydrant
            addSupply(Hydrant.head())
        end
    end

    -- Crossing a bare router, one way only: we may step from its OUT side back to its IN side, which
    -- is a consumer reaching upstream for water. The reverse (IN side reaching downstream) would be
    -- backflow, so it stays blocked and the router keeps its one-way meaning.
    local function tryCrossRouter(routerSquare, fromX, fromY, fromZ, distance, chain)
        if not conduct or routerIsHardBoundary(routerSquare) then
            return
        end

        local router = Router.findOnSquare(routerSquare)
        local out = router and Router.getOutOffset(router)
        if not out then
            return
        end

        local rx, ry, rz = routerSquare:getX(), routerSquare:getY(), routerSquare:getZ()
        -- Are we standing on its OUT side?
        if fromX ~= rx + out.dx or fromY ~= ry + out.dy or fromZ ~= rz then
            return
        end

        -- `distance` is the hop the router tile itself occupies, which is exactly how far its outlet
        -- sits from the consumer -- the length the regulated head then has to travel back.
        local nextChain = chain
        local ceilingHere = Router.getPressureCeiling(router)
        if ceilingHere then
            nextChain = newChain(chain, ceilingHere, distance, rz)
        end

        -- +1 for the router tile itself, which sits in the run but is never a network square.
        tryAdd(getCellSquare(rx - out.dx, ry - out.dy, rz), distance + 1, nextChain)
    end

    local function visit(square, fromX, fromY, fromZ, distance, chain)
        if not square then
            return
        end
        if Router.hasRouterOnSquare(square) then
            tryCrossRouter(square, fromX, fromY, fromZ, distance, chain)
            return
        end
        tryAdd(square, distance, chain)
    end

    -- Same-floor cardinal neighbours (both ways) + cross-floor riser neighbours filtered by gravity.
    local function addNeighborsOf(x, y, z, distance, chain)
        for _, offset in ipairs(Constants.CARDINAL_OFFSETS) do
            visit(getCellSquare(x + offset.x, y + offset.y, z), x, y, z, distance, chain)
        end
        for _, coord in ipairs(PipeObjectUtils.getRiserVerticalNeighborCoords(x, y, z)) do
            local keep = true
            if verticalMode == "up" then
                keep = coord.z > z
            elseif verticalMode == "down" then
                keep = coord.z < z
            end
            if keep then
                visit(getCellSquare(coord.x, coord.y, coord.z), x, y, z, distance, chain)
            end
        end
    end

    -- The origin is often a fixture (sink, generator) with no pipe of its own, so its neighbours are
    -- seeded unconditionally -- tryAdd would drop the whole search otherwise.
    tryAdd(originSquare, 0, rootChain)
    addNeighborsOf(originSquare:getX(), originSquare:getY(), originSquare:getZ(), 1, rootChain)

    local index = 1
    while index <= #queue do
        local current = queue[index]
        index = index + 1
        local key = squareKey(current)
        addNeighborsOf(current:getX(), current:getY(), current:getZ(),
            (hops[key] or 0) + 1, chains[key])
    end

    return pipeSquares, hops, zone, chains
end

local function collectConnectedPipeSquares(endpointObject)
    if not endpointObject or not endpointObject.getSquare then
        return {}
    end
    return collectPipeSquaresFromSquare(endpointObject:getSquare())
end

local function collectStorageDescriptors(pipeSquares, hops, chains)
    local scannedSquares = {}
    local descriptors = {}

    -- A container counts only when it shares its tile with a pipe (same square), not by adjacency.
    for _, pipeSquare in ipairs(pipeSquares) do
        if addSquare(scannedSquares, pipeSquare) then
            local key = squareKey(pipeSquare)
            -- How far this container sits from the origin, so the pressure gate can price the run,
            -- and the regulators standing between the two (nil when nothing regulates it).
            local distance = hops and hops[key] or 0
            local chain = chains and chains[key] or nil
            local squareDescriptors = Adapter.collectSquareContainers(pipeSquare)
            for descriptorKey, descriptor in pairs(squareDescriptors) do
                descriptor.pipeHops = distance
                descriptor.pressureChain = chain
                descriptors[descriptorKey] = descriptor
            end
        end
    end

    return descriptors
end

local function normalizeDescriptorList(descriptorMap)
    local descriptors = {}

    for _, descriptor in pairs(descriptorMap) do
        descriptors[#descriptors + 1] = descriptor
    end

    table.sort(descriptors, function(left, right)
        return tostring(left.key) < tostring(right.key)
    end)

    return descriptors
end

-- Drop the sources that cannot push their water to a `kind` consumer at originSquare, and record the
-- best head any surviving source delivers. A source that sits too far away, or too low with no pump
-- to lift it, simply is not part of this consumer's supply.
-- Regulators are applied PER SOURCE, using the chain of routers between that source and the consumer:
-- water arriving through a router set to 12 leaves the valve at 12 and then loses head over the run
-- home, while a barrel on the consumer's own side is untouched.
-- No pumpHead argument: each source's chain already carries the pumps that are allowed to help it.
local function applyPressureGate(descriptors, originSquare, kind)
    local enabled = Pressure.isEnabled()
    local minimum = Pressure.minimumFor(kind)
    local consumerZ = originSquare:getZ()
    local best = nil
    local reachable = {}

    for _, descriptor in ipairs(descriptors) do
        local head = headThroughChain(descriptor.z, consumerZ, descriptor.pipeHops, kind,
            descriptor.pressureChain)
        if not enabled or head >= minimum then
            descriptor.pressure = head
            reachable[#reachable + 1] = descriptor
            if not best or head > best then
                best = head
            end
        end
    end

    return reachable, best
end

-- Which containers can fluid entering at originSquare actually reach? Only lift is priced (see
-- Pressure.canFillTo): with no pump this is exactly the old gravity fill, and with one the water
-- climbs as many floors as the pump's head allows.
local function applyFillGate(descriptors, originSquare, pumpHead)
    local originZ = originSquare:getZ()
    local reachable = {}
    for _, descriptor in ipairs(descriptors) do
        if Pressure.canFillTo(originZ, descriptor.z, pumpHead) then
            reachable[#reachable + 1] = descriptor
        end
    end
    return reachable
end

-- kind (Constants.PRESSURE_KIND_*) picks the friction coefficient, since head loss scales with flow:
-- a tap sipping loses far less per tile than a sprinkler running wide open. Passing a kind is what
-- marks this as a DRAW query: the pressure gate runs and pumps are counted.
-- Passing fill = true marks a FILL query, which is gated on lift instead.
--
-- Draw queries traverse "both" rather than "up", because a pump in the basement pushing water
-- upstairs is a legitimate build that an ascending-only search would never find. The pressure gate
-- reproduces gravity on its own (a source one floor down delivers -2 m.c.a. and is dropped), so
-- nothing is lost. The one liberty it takes: a route that climbs over a hump higher than its source
-- is allowed. Real closed pipes do siphon over humps up to ~10 m, so this is right below ~3 floors
-- and merely generous above that -- and above that you almost certainly have a pump anyway.
local function buildSummaryFromSquare(originSquare, verticalMode, kind, fill)
    if not originSquare then
        return nil
    end

    -- Only a draw reaches through a bare router; fills and visualization keep every router solid.
    local conduct = kind ~= nil and not fill
    local pipeSquares, hops, zone, chains =
        collectPipeSquaresFromSquare(originSquare, verticalMode, conduct)
    if #pipeSquares == 0 then
        return nil
    end

    local descriptorMap = collectStorageDescriptors(pipeSquares, hops, chains)
    local descriptors = normalizeDescriptorList(descriptorMap)
    if #descriptors == 0 then
        return nil
    end

    -- Visualization asks for neither gate and sees the whole physical network.
    local pressure = nil
    if kind or fill then
        -- How far water entering here can be pushed UPHILL. Fills are not regulated (a fill query
        -- never crosses a router), so the whole zone's lift counts. A municipal supply is a floor here
        -- too: a live inlet or open hydrant holds the network at its pressure, which is lift the pumps
        -- do not have to find. zone.supplyHead already carries the highest such floor.
        local liftHead = math.max(Pump.headForPumps(zone.pumps), zone.supplyHead or 0)
        if fill then
            descriptors = applyFillGate(descriptors, originSquare, liftHead)
        else
            descriptors, pressure = applyPressureGate(descriptors, originSquare, kind)
        end
        if #descriptors == 0 then
            return nil
        end
    end

    local totalAmount = 0
    local totalCapacity = 0
    local fluidTypes = {}
    local fluidTypeCount = 0
    local fluidTypeName = nil

    for _, descriptor in ipairs(descriptors) do
        local descriptorAmount = math.max(descriptor.waterAmount or 0, 0)
        local descriptorCapacity = math.max(descriptor.capacity or 0, 0)
        totalAmount = totalAmount + descriptorAmount
        totalCapacity = totalCapacity + descriptorCapacity

        if descriptorAmount > 0 and descriptor.fluidType then
            fluidTypes[descriptor.fluidType] = true
        end
    end

    -- TAINTED WINS. A network holding both clean and tainted water is not "mixed", it is tainted:
    -- one litre of dirty water in the line is enough, which is what contamination means and what a
    -- player expects after wiring a filthy barrel into a clean run. Before this, two water types made
    -- the network `isMixed`, and a mixed network refuses to deliver anything at all -- so connecting a
    -- tainted barrel did not dirty the water, it silently killed the whole network.
    --
    -- Only the WATER FAMILY collapses this way. Petrol sitting beside water is not contamination, it
    -- is a ruined tank, and that stays the hard refusal it always was.
    local allWater = true
    for candidateFluidType in pairs(fluidTypes) do
        fluidTypeCount = fluidTypeCount + 1
        fluidTypeName = candidateFluidType
        if not isWaterTypeName(candidateFluidType) then
            allWater = false
        end
    end
    if fluidTypeCount > 1 and allWater then
        fluidTypeCount = 1
        fluidTypeName = "TaintedWater"
    end

    return {
        square = originSquare,
        pipeSquares = pipeSquares,
        descriptors = descriptors,
        totalAmount = totalAmount,
        totalCapacity = totalCapacity,
        fluidTypeName = fluidTypeName,
        fluidTypeCount = fluidTypeCount,
        isMixed = fluidTypeCount > 1,
        isWater = fluidTypeName == "Water" or fluidTypeName == "TaintedWater",
        isTainted = fluidTypeName == "TaintedWater",
        -- Best head (m.c.a.) any reachable source delivers here; nil unless this was a draw query.
        pressure = pressure,
    }
end

-- Endpoint summaries are gated on being a real plumbable fixture (sink/shower/toilet).
local function buildSummary(endpointObject)
    if not EndpointObjects.isEndpointCandidate(endpointObject) then
        return nil
    end

    local originSquare = endpointObject.getSquare and endpointObject:getSquare() or nil
    -- A tap draws only water that can reach it under gravity: its own floor plus anything above that
    -- drains down to it. Water on a lower floor cannot climb up, so it is excluded.
    local summary = buildSummaryFromSquare(originSquare, "both", Constants.PRESSURE_KIND_TAP)
    if summary then
        summary.endpoint = endpointObject
    end
    return summary
end

local function fluidNameMatches(actual, required)
    if not actual or not required then
        return false
    end
    return string.lower(actual) == string.lower(required)
end

-- What a network already holding `current` becomes once `incoming` is added, or nil if the two must
-- not meet at all.
--
-- Inside the water family the answer is always "yes, and tainted wins". The asymmetry is the point:
-- tipping tainted water into a clean line ruins it, and tipping clean water into a tainted line does
-- NOT rinse it out. Contamination only travels one way, which is what makes the purifier the only
-- road back. Outside the water family nothing merges -- petrol still refuses to meet water.
local function mergeFluidNames(current, incoming)
    if not current then
        return incoming
    end
    if not incoming then
        return current
    end
    if fluidNameMatches(current, incoming) then
        return current
    end
    if isWaterTypeName(current) and isWaterTypeName(incoming) then
        return "TaintedWater"
    end
    return nil
end

local function rebalanceSummary(summary, remainingAmount)
    local fluidTypeName = remainingAmount > 0 and summary.fluidTypeName or nil
    local totalCapacity = math.max(summary.totalCapacity or 0, 0)
    local ratio = totalCapacity > 0 and math.min(remainingAmount / totalCapacity, 1) or 0

    for _, descriptor in ipairs(summary.descriptors) do
        local nextAmount = (descriptor.capacity or 0) * ratio
        Adapter.writeDescriptorWaterAmount(descriptor, nextAmount, fluidTypeName)
    end
end

function NetworkAccess.getSummary(endpointObject)
    return buildSummary(endpointObject)
end

-- Square-based access for non-endpoint consumers (e.g. generators pulling Petrol).
function NetworkAccess.getFluidSummaryAtSquare(originSquare)
    -- A square-based consumer (generator, API read) sees the fluid that can reach it under gravity.
    return buildSummaryFromSquare(originSquare, "both", Constants.PRESSURE_KIND_TAP)
end

-- Turn every water vessel physically connected to `originSquare` tainted, in one pass, keeping each
-- one's amount. Used by stagnation and rain: tainting the whole network at once is what keeps the
-- redistribution step from seeing a half-and-half network and refusing to settle it. A no-op on an
-- empty network, on petrol, or on water that is already tainted. Returns the litres turned.
function NetworkAccess.taintNetworkAt(originSquare)
    local pipeSquares, hops = collectPipeSquaresFromSquare(originSquare, "both")
    local descriptors = normalizeDescriptorList(collectStorageDescriptors(pipeSquares, hops))
    local turned = 0
    for _, descriptor in ipairs(descriptors) do
        local amount = descriptor.waterAmount or 0
        if amount > 0 and descriptor.fluidType == "Water" then
            Adapter.writeDescriptorWaterAmount(descriptor, amount, "TaintedWater")
            turned = turned + amount
        end
    end
    return turned
end

-- For visualization: the pipe squares reachable from a square + the container descriptors on them.
-- Unlike getFluidSummaryAtSquare it returns the pipe squares even when there are no containers.
function NetworkAccess.getNetworkFromSquare(originSquare)
    -- Visualization: show the whole physically-connected network (both directions), not just the
    -- gravity-reachable part.
    local pipeSquares, hops = collectPipeSquaresFromSquare(originSquare, "both")
    local descriptors = normalizeDescriptorList(collectStorageDescriptors(pipeSquares, hops))
    return pipeSquares, descriptors
end

-- Best head (m.c.a.) available to a `kind` consumer standing on `square`, or nil when nothing can
-- reach it. Public because the pump, the sprinkler and the gauge all need to ask the same question.
function NetworkAccess.getPressureAtSquare(square, kind)
    local summary = buildSummaryFromSquare(square, "both", kind or Constants.PRESSURE_KIND_TAP)
    return summary and summary.pressure or nil
end

-- Everything the pressure model knows about one point, for the debug readout. The gauge answers
-- "how much?"; this answers "why?" -- it breaks out every term that fed the number, so a surprising
-- reading can be traced to the source, hop count, pump or router ceiling responsible for it.
-- One walk serves the whole report.
function NetworkAccess.getPressureReport(square)
    if not square then
        return nil
    end

    local pipeSquares, hops, zone, chains = collectPipeSquaresFromSquare(square, "both", true)
    local report = {
        enabled = Pressure.isEnabled(),
        model = Pressure.model(),
        pipeCount = #pipeSquares,
        pumpCount = #zone.pumps,
        poweredPumps = 0,
        mainsCount = #zone.mains,
        hydrantCount = #zone.hydrants,
        sources = {},
        kinds = {},
    }

    for _, pump in ipairs(zone.pumps) do
        if Pump.isPowered(pump) then
            report.poweredPumps = report.poweredPumps + 1
        end
    end
    report.pumpHead = Pump.headForPumps(zone.pumps)
    report.mainsHead = #zone.mains > 0 and Mains.head() or 0
    -- The supply floor the whole zone sits at, whichever municipal source is highest.
    report.supplyHead = zone.supplyHead or 0

    if #pipeSquares == 0 then
        return report
    end

    local descriptors = normalizeDescriptorList(collectStorageDescriptors(pipeSquares, hops, chains))
    report.containerCount = #descriptors

    -- Per source: what it holds and the head it actually lands here with (tap flow).
    local consumerZ = square:getZ()
    for _, descriptor in ipairs(descriptors) do
        report.sources[#report.sources + 1] = {
            key = tostring(descriptor.key),
            z = descriptor.z,
            hops = descriptor.pipeHops,
            amount = descriptor.waterAmount,
            capacity = descriptor.capacity,
            fluidType = descriptor.fluidType,
            ceiling = chainTightestCeiling(descriptor.pressureChain),
            head = headThroughChain(descriptor.z, consumerZ, descriptor.pipeHops,
                Constants.PRESSURE_KIND_TAP, descriptor.pressureChain),
        }
    end

    -- Per consumer kind: the head the best source delivers, and whether that clears its minimum.
    for _, kind in ipairs({ Constants.PRESSURE_KIND_TAP, Constants.PRESSURE_KIND_DRIP,
        Constants.PRESSURE_KIND_SPRINKLER }) do
        local best = nil
        for _, descriptor in ipairs(descriptors) do
            local head = headThroughChain(descriptor.z, consumerZ, descriptor.pipeHops, kind,
                descriptor.pressureChain)
            if not best or head > best then
                best = head
            end
        end
        report.kinds[kind] = {
            head = best,
            minimum = Pressure.minimumFor(kind),
            friction = Pressure.frictionFor(kind),
            ok = best ~= nil and best >= Pressure.minimumFor(kind),
        }
    end

    return report
end

-- Router intake helper: which single fluid (and how much) can be PULLED from the network reachable
-- upward from `square` (gravity-consumer view). Returns (amount, fluidTypeName) or (0, nil).
function NetworkAccess.availableToPull(square, kind)
    local summary = buildSummaryFromSquare(square, "both", kind or Constants.PRESSURE_KIND_TAP)
    if not summary or summary.isMixed or (summary.totalAmount or 0) <= 0 then
        return 0, nil
    end
    return summary.totalAmount, summary.fluidTypeName
end

-- Router output helper: how much `fluidType` can be PUSHED into the network reachable downward from
-- `square` (gravity-fill view). Returns the free headroom, or 0 if full / mixed / incompatible fluid.
function NetworkAccess.availableToPush(square, fluidType)
    local summary = buildSummaryFromSquare(square, "both", nil, true)
    if not summary or summary.isMixed then
        return 0
    end
    local headroom = (summary.totalCapacity or 0) - (summary.totalAmount or 0)
    if headroom <= 0 then
        return 0
    end
    -- Clean water may always join a tainted line (it just becomes tainted); only a genuinely
    -- incompatible fluid is refused.
    if (summary.totalAmount or 0) > 0 and summary.fluidTypeName
        and not mergeFluidNames(summary.fluidTypeName, fluidType) then
        return 0
    end
    return headroom
end

-- Draw up to `amount` of `requiredFluidType` from the network reachable from `originSquare`.
-- Only works on a single-fluid network whose fluid matches requiredFluidType. Returns the
-- amount actually drawn (rebalanced out of the network's containers).
function NetworkAccess.drawFluidAtSquare(originSquare, requiredFluidType, amount, kind)
    -- Drawing is consumption: only fluid whose head reaches this square is available.
    local summary = buildSummaryFromSquare(originSquare, "both", kind or Constants.PRESSURE_KIND_TAP)
    if not summary or summary.isMixed or (summary.totalAmount or 0) <= 0 then
        return 0
    end

    if not fluidNameMatches(summary.fluidTypeName, requiredFluidType) then
        return 0
    end

    local drawn = math.min(math.max(amount or 0, 0), summary.totalAmount)
    if drawn <= 0 then
        return 0
    end

    rebalanceSummary(summary, summary.totalAmount - drawn)
    return drawn
end

-- Add up to `amount` of `fluidType` into the network reachable from `originSquare`. Only works if
-- the network is empty or already holds the SAME fluid (never mixes). Returns the amount added.
function NetworkAccess.fillFluidAtSquare(originSquare, fluidType, amount)
    if not fluidType then
        return 0
    end

    -- Water introduced here settles downhill -- or climbs, if a pump in this zone has the head.
    local summary = buildSummaryFromSquare(originSquare, "both", nil, true)
    if not summary or summary.isMixed then
        return 0
    end

    local headroom = (summary.totalCapacity or 0) - (summary.totalAmount or 0)
    if headroom <= 0 then
        return 0
    end

    -- A non-empty network takes the incoming fluid only if the two can share a pipe. Water and
    -- tainted water always can -- the result is tainted -- so this now refuses nothing but a real
    -- fluid clash (petrol into water).
    local merged = mergeFluidNames(summary.fluidTypeName, fluidType)
    if (summary.totalAmount or 0) > 0 and summary.fluidTypeName and not merged then
        return 0
    end

    local added = math.min(math.max(amount or 0, 0), headroom)
    if added <= 0 then
        return 0
    end

    -- An empty network adopts the incoming fluid type; a stocked one takes the merged result, which
    -- is what turns the whole line tainted the moment dirty water is pushed into it.
    summary.fluidTypeName = (summary.totalAmount or 0) <= 0 and fluidType or merged

    rebalanceSummary(summary, (summary.totalAmount or 0) + added)
    return added
end

function NetworkAccess.isNetworkBackedEndpoint(endpointObject)
    return buildSummary(endpointObject) ~= nil
end

-- Any single (non-mixed) fluid is usable at a tap now -- not only water. Taps purify TaintedWater
-- into Water at the point of use (see EndpointFluidSource), but any other liquid is drawn as-is.
function NetworkAccess.getUsableWaterSummary(endpointObject)
    local summary = buildSummary(endpointObject)
    if not summary or summary.isMixed or summary.totalAmount <= 0 then
        return nil
    end
    return summary
end

function NetworkAccess.getFluidAmount(endpointObject)
    local summary = NetworkAccess.getUsableWaterSummary(endpointObject)
    return summary and summary.totalAmount or 0
end

function NetworkAccess.getFluidCapacity(endpointObject)
    local summary = buildSummary(endpointObject)
    return summary and summary.totalCapacity or 0
end

function NetworkAccess.isTaintedWater(endpointObject)
    local summary = NetworkAccess.getUsableWaterSummary(endpointObject)
    return summary and summary.isTainted or false
end

function NetworkAccess.hasFluid(endpointObject)
    return NetworkAccess.getFluidAmount(endpointObject) > 0
end

function NetworkAccess.hasWater(endpointObject)
    return NetworkAccess.hasFluid(endpointObject)
end

function NetworkAccess.canTransferFluidTo(endpointObject, targetContainer)
    local summary = NetworkAccess.getUsableWaterSummary(endpointObject)
    if not summary or not targetContainer or not targetContainer.canAddFluid then
        return false
    end

    local fluidType = getFluidTypeByName(summary.fluidTypeName)
    if not fluidType then
        return false
    end

    local ok, canAdd = pcall(targetContainer.canAddFluid, targetContainer, fluidType)
    return ok and canAdd
end

function NetworkAccess.useFluid(endpointObject, amount)
    local summary = NetworkAccess.getUsableWaterSummary(endpointObject)
    if not summary then
        return 0
    end

    local clamped = math.min(math.max(amount or 0, 0), summary.totalAmount)
    if clamped <= 0 then
        return 0
    end

    rebalanceSummary(summary, summary.totalAmount - clamped)
    return clamped
end

function NetworkAccess.restoreFluid(endpointObject, amount, fluidTypeName)
    local summary = buildSummary(endpointObject)
    if not summary or not isWaterTypeName(fluidTypeName) then
        return 0
    end

    if summary.isMixed then
        return 0
    end

    local merged = mergeFluidNames(summary.fluidTypeName, fluidTypeName)
    if summary.totalAmount > 0 and summary.fluidTypeName and not merged then
        return 0
    end

    local clamped = math.max(amount or 0, 0)
    local availableCapacity = math.max((summary.totalCapacity or 0) - (summary.totalAmount or 0), 0)
    local restored = math.min(clamped, availableCapacity)
    if restored <= 0 then
        return 0
    end

    summary.fluidTypeName = merged or fluidTypeName
    rebalanceSummary(summary, summary.totalAmount + restored)
    return restored
end

function NetworkAccess.transferFluidTo(endpointObject, targetContainer, amount)
    local summary = NetworkAccess.getUsableWaterSummary(endpointObject)
    if not summary or not targetContainer or not targetContainer.addFluid then
        return 0
    end

    local fluidType = getFluidTypeByName(summary.fluidTypeName)
    if not fluidType then
        return 0
    end

    local requested = math.min(math.max(amount or 0, 0), summary.totalAmount)
    if requested <= 0 then
        return 0
    end

    local beforeAmount = targetContainer.getAmount and targetContainer:getAmount() or 0
    local ok = pcall(targetContainer.addFluid, targetContainer, fluidType, requested)
    if not ok then
        return 0
    end

    local afterAmount = targetContainer.getAmount and targetContainer:getAmount() or (beforeAmount + requested)
    local transferred = math.max(afterAmount - beforeAmount, 0)
    if transferred <= 0 then
        return 0
    end

    NetworkAccess.useFluid(endpointObject, transferred)
    return transferred
end

function NetworkAccess.moveFluidToTemporaryContainer(endpointObject, amount)
    local summary = NetworkAccess.getUsableWaterSummary(endpointObject)
    if not summary or not FluidContainer or not FluidContainer.CreateContainer then
        return nil
    end

    local fluidType = getFluidTypeByName(summary.fluidTypeName)
    if not fluidType then
        return nil
    end

    local taken = math.min(math.max(amount or 0, 0), summary.totalAmount)
    if taken <= 0 then
        return nil
    end

    local temporaryContainer = FluidContainer.CreateContainer()
    if not temporaryContainer then
        return nil
    end

    local ok = pcall(temporaryContainer.addFluid, temporaryContainer, fluidType, taken)
    if not ok then
        if FluidContainer.DisposeContainer then
            FluidContainer.DisposeContainer(temporaryContainer)
        end
        return nil
    end

    NetworkAccess.useFluid(endpointObject, taken)
    return temporaryContainer
end
