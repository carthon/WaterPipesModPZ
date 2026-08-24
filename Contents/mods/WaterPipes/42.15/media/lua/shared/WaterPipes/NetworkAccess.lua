WaterPipes = WaterPipes or {}
WaterPipes.NetworkAccess = WaterPipes.NetworkAccess or {}

require "WaterPipes/Constants"
require "WaterPipes/ContainerAdapter"
require "WaterPipes/EndpointObjects"
require "WaterPipes/Hydrant"
require "WaterPipes/Hydraulics"
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
local Hydraulics = WaterPipes.Hydraulics
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
    -- Any other vessel parked on the crossing buffers the flow, so treat it as a boundary too. This
    -- runs per router crossing inside the network walk and only needs a yes/no, so it asks the
    -- adapter's classification directly rather than building descriptors and reading their fluid.
    return Adapter.hasSquareContainers(routerSquare)
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

-- The regulator CHAIN arithmetic that used to live here is gone. It existed only because the walk ran
-- BACKWARDS, from the consumer toward the sources: a walk in that direction has to carry a linked list
-- of every valve it has crossed and re-price each one from where it stands. Hydraulics.lua runs the
-- other way, with the water, so it meets each valve once in the order the water does and "the tightest
-- ceiling upstream" is a running minimum -- see its forward sweep.
--
-- The walk below still THREADS a chain through, because the fill and visualization paths share its
-- code and it is their `zone` bookkeeping that hangs off the same parameter. Nothing reads the chain
-- any more; unpicking it from the fill path is a separate change with its own risk.

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
    -- purifierOutlets: purifiers whose CLEAN side empties into this network (see recordPurifierOutlet).
    local zone = { pumps = {}, mains = {}, hydrants = {}, purifierOutlets = {},
                   supplyHead = 0, rootChain = rootChain }
    -- Per-walk memo of "is there a purifier on this router tile", and of which outlets we have
    -- already recorded. Two tables, not one: a router is visited from each of its neighbours, and the
    -- lookup is a four-tile footprint scan -- but the ANSWER to "record the outlet" depends on which
    -- side we arrived from, so reaching it first from the dirty side must not mark it done.
    local purifierAt = {}
    local outletSeen = {}

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

        -- Municipal supplies floor the run at their pressure. A plumbed fixture
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

    -- Crossing a bare router. It conducts in ONE direction, and which direction that is depends on
    -- which way the water is going -- because a valve does not care who is asking, only which way the
    -- flow runs through it:
    --
    --   "draw" -- a consumer reaching UPSTREAM for water. It stands on the outlet and steps back to
    --             the inlet. The reverse would be a consumer siphoning through the valve backwards.
    --   "fill" -- water flowing DOWNSTREAM from a supply. It stands on the inlet and steps to the
    --             outlet, which is simply water going the way the router points.
    --
    -- Both are the same physical rule seen from the two ends, and having only the first is what made a
    -- chain of routers a dead end: a fill query treated every router as a solid wall, so a router
    -- whose outlet faced another router found no network to push into at all and moved nothing. A
    -- bare router is meant to be an inline pressure-reducing valve -- water passes through it.
    --
    -- A router with a tank on it (the purifier) is still a hard boundary in BOTH directions: the fluid
    -- is being transformed there and the two sides must never see each other.
    -- A purifier's OUT buffer is storage belonging to the network on its clean side.
    --
    -- Without this the buffer was invisible to everything: a router whose outlet fed a bare pipe run
    -- had nowhere to push its clean water, so the buffer filled to capacity, the convert step stalled
    -- on no headroom, the intake stalled behind it, and the whole device stopped with 50 L trapped
    -- inside it -- reported to the player as simply "Stopped". A tap on that side saw a network with
    -- no containers at all and mirrored a 1-litre tank that never filled.
    --
    -- Recorded during the walk because this is the one place that already has the router and its
    -- direction in hand; buildSummaryFromSquare turns it into a descriptor. Topology only -- the
    -- amount is read fresh every query, like every other container.
    local function recordPurifierOutlet(routerSquare, fromX, fromY, fromZ, distance, chain)
        local key = squareKey(routerSquare)
        if outletSeen[key] then
            return
        end

        local purifier = purifierAt[key]
        if purifier == nil then
            purifier = Purifier.findForRouterSquare(routerSquare) or false
            purifierAt[key] = purifier
        end
        if not purifier then
            return
        end

        local router = Router.findOnSquare(routerSquare)
        local out = router and Router.getOutOffset(router)
        if not out then
            return
        end

        -- Only the OUT side receives it. Reaching the router from its inlet means we are standing on
        -- the dirty side, which must never see the clean water -- that is the whole point of the
        -- purifier being a hard boundary.
        local rx, ry, rz = routerSquare:getX(), routerSquare:getY(), routerSquare:getZ()
        if fromX ~= rx + out.dx or fromY ~= ry + out.dy or fromZ ~= rz then
            return
        end

        outletSeen[key] = true
        zone.purifierOutlets[#zone.purifierOutlets + 1] = {
            purifier = purifier,
            routerKey = key,
            x = fromX, y = fromY, z = fromZ,
            -- `distance` is the hop the router tile occupies; the water lands on the square we came
            -- from, one hop closer to the consumer.
            hops = math.max((distance or 1) - 1, 0),
            chain = chain,
        }
    end

    local function tryCrossRouter(routerSquare, fromX, fromY, fromZ, distance, chain)
        recordPurifierOutlet(routerSquare, fromX, fromY, fromZ, distance, chain)

        if not conduct or routerIsHardBoundary(routerSquare) then
            return
        end

        local router = Router.findOnSquare(routerSquare)
        local out = router and Router.getOutOffset(router)
        if not out then
            return
        end

        local rx, ry, rz = routerSquare:getX(), routerSquare:getY(), routerSquare:getZ()
        if fromZ ~= rz then
            return
        end

        local nextX, nextY
        if conduct == "draw" then
            -- Must be standing on the OUT side; step to the IN side.
            if fromX ~= rx + out.dx or fromY ~= ry + out.dy then
                return
            end
            nextX, nextY = rx - out.dx, ry - out.dy
        else
            -- "fill": must be standing on the IN side; step to the OUT side.
            if fromX ~= rx - out.dx or fromY ~= ry - out.dy then
                return
            end
            nextX, nextY = rx + out.dx, ry + out.dy
        end

        -- `distance` is the hop the router tile itself occupies, which is exactly how far its outlet
        -- sits from the consumer -- the length the regulated head then has to travel back.
        local nextChain = chain
        local ceilingHere = Router.getPressureCeiling(router)
        if ceilingHere then
            nextChain = newChain(chain, ceilingHere, distance, rz)
        end

        -- +1 for the router tile itself, which sits in the run but is never a network square.
        tryAdd(getCellSquare(nextX, nextY, rz), distance + 1, nextChain)
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

-- ===== Per-frame traversal cache =====
--
-- The walk above is the mod's hot spot, and most consumers ask for it more than once from the SAME
-- square in the same instant: a router runs availableToPull then drawFluidAtSquare on its IN side and
-- availableToPush then fillFluidAtSquare on its OUT side -- four walks for two questions -- and the
-- irrigation pass asks for pressure, then availability, then draws, all from the emitter's tile.
--
-- What is cached is ONLY topology: which squares are in the network, how far each sits from this
-- origin, the regulator chains, and which pumps/inlets/hydrants the walk passed. None of it can move
-- without a pipe being built or removed. The fluid itself is deliberately NOT cached -- every caller
-- still re-reads the containers through collectStorageDescriptors -- so a draw and the fill that
-- follows it always see real amounts, and no amount of caching can make water appear or vanish.
--
-- Keyed per ORIGIN, not per network, and that is not an oversight: hop counts and regulator chains
-- are measured FROM the consumer, so two consumers on the same network genuinely have different
-- answers and cannot share a walk. Sharing across origins needs the adjacency itself cached, which is
-- a larger change.
--
-- Dropped once per frame, plus explicitly whenever the pipe layout changes.
local traversalCache = {}

-- Zone id -> the tiles of that zone that actually hold a vessel. Same lifetime as the traversal cache
-- above: one frame, plus an explicit drop when the layout changes. See vesselSquaresOfZone.
local zoneVesselMemo = {}

-- "zone|z|kind" -> the summary every consumer on that zone, at that level, would have built for
-- itself. See NetworkAccess.getStatusSummary.
local statusSummaryMemo = {}

-- `conduct` is part of the key, and it must be the VALUE, not its truthiness: a draw walk and a fill
-- walk from the same square cross routers in opposite directions and so reach different squares.
-- Collapsing them to a boolean would hand a fill query the draw query's network.
local function traversalKey(square, verticalMode, conduct)
    return squareKey(square) .. "|" .. tostring(verticalMode) .. "|" .. tostring(conduct)
end

-- Two caches with two different lifetimes, and conflating them cost real frames.
--
-- The traversal cache is a WITHIN-FRAME memo: it exists so a router asking availableToPull and then
-- drawFluidAtSquare in the same instant walks once instead of twice. Dropping it every frame is
-- exactly right and costs nothing.
--
-- The head field is not that. Solving one costs a servable-set search over the whole network, and it
-- only changes when the layout, a pump, a valve or a vessel's emptiness changes -- none of which a
-- frame boundary implies. Wiring it to the same OnTick meant rebuilding it sixty times a second to
-- get the same answer, which is what made the pressure work feel slower than the walk it replaced.
local function dropTraversalCacheOnly()
    traversalCache = {}
    zoneVesselMemo = {}
    statusSummaryMemo = {}
end

-- An object appeared or vanished somewhere. The traversal cache is frame-scoped and rebuilt on demand,
-- so dropping all of it costs nothing and needs no reasoning about where the object was. The head
-- field is the opposite -- expensive to rebuild, and only wrong near the tile that changed -- so it is
-- invalidated by tile, from its own handler in Hydraulics.lua. This one does NOT call the global drop:
-- these events fire for every object the map streams in, and doing so meant the field never survived
-- long enough to be a cache at all.
local function onWorldObjectChanged()
    traversalCache = {}
end

-- The layout changed: drop both. This is what a build, a removal, a valve setting or a hydrant toggle
-- wants -- the shape the field was solved against no longer exists.
function NetworkAccess.invalidateTraversalCache()
    traversalCache = {}
    zoneVesselMemo = {}
    statusSummaryMemo = {}
    if Hydraulics and Hydraulics.invalidate then
        Hydraulics.invalidate()
    end
end

local function collectPipeSquaresCached(originSquare, verticalMode, conduct)
    if not originSquare then
        return {}, {}, { pumps = {}, mains = {} }, {}
    end

    local key = traversalKey(originSquare, verticalMode, conduct)
    local hit = traversalCache[key]
    if hit then
        return hit[1], hit[2], hit[3], hit[4]
    end

    local pipeSquares, hops, zone, chains =
        collectPipeSquaresFromSquare(originSquare, verticalMode, conduct)
    traversalCache[key] = { pipeSquares, hops, zone, chains }
    return pipeSquares, hops, zone, chains
end

local function collectConnectedPipeSquares(endpointObject)
    if not endpointObject or not endpointObject.getSquare then
        return {}
    end
    return collectPipeSquaresCached(endpointObject:getSquare())
end

-- The original walk, kept for fills and visualization: they have no solve to key a zone off, ask a
-- different question (where can water GO from here) and are not on the hot path.
local function collectStorageDescriptorsByWalk(pipeSquares, hops, chains)
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

-- The tiles of a zone that hold a vessel, found once per zone per frame.
--
-- collectStorageDescriptors walked every tile of the zone for every consumer that asked. On a 180-tile
-- farm with 47 emitters the spray FX did that 47 times per rebuild -- 8 400 iterations and as many key
-- strings built and thrown away -- to rediscover the same twenty barrels. Where a zone keeps its water
-- is a property of the ZONE, so it is found once and shared: the same collapse the head field got, on
-- the half that was left behind.
--
-- Safe to key by zone because squaresFromSolution hands back Hydraulics.pipeSquares BY REFERENCE --
-- the tile set is identical for every consumer on the zone, and only the hop counts are measured from
-- the asking tile.
--
-- What is deliberately NOT shared is the descriptors. Those are still built per query, because the
-- caller decorates them with pipeHops and pressureChain measured from ITS own tile, and handing two
-- consumers the same table would have the second silently overwrite the first's. Only the discovery is
-- pooled; the pricing stays private.
local function vesselSquaresOfZone(solution)
    local id = solution and solution.id
    if not id then
        return nil
    end

    local cached = zoneVesselMemo[id]
    if cached then
        return cached
    end

    local list = {}
    local seen = {}
    for _, pipeSquare in ipairs(Hydraulics.pipeSquares(solution)) do
        local key = squareKey(pipeSquare)
        if not seen[key] then
            seen[key] = true
            -- Cheap: the adapter memoises its per-square classification for the frame, and this asks
            -- only whether anything is there, never what is inside it.
            if Adapter.hasSquareContainers(pipeSquare) then
                list[#list + 1] = { square = pipeSquare, key = key }
            end
        end
    end

    zoneVesselMemo[id] = list
    return list
end

local function collectStorageDescriptors(pipeSquares, hops, chains, solution)
    local pooled = solution and vesselSquaresOfZone(solution) or nil
    if pooled then
        local descriptors = {}
        for _, entry in ipairs(pooled) do
            local distance = hops and hops[entry.key] or 0
            local chain = chains and chains[entry.key] or nil
            for descriptorKey, descriptor in pairs(Adapter.collectSquareContainers(entry.square)) do
                descriptor.pipeHops = distance
                descriptor.pressureChain = chain
                descriptors[descriptorKey] = descriptor
            end
        end
        return descriptors
    end

    return collectStorageDescriptorsByWalk(pipeSquares, hops, chains)
end


-- Turn the purifier outlets the walk found into ordinary storage descriptors, so every consumer,
-- gauge and rebalance treats the clean buffer as what it is: 50 litres of storage on that network.
--
-- Skipped entirely when the network already holds tainted water. The OUT buffer has no taint flag --
-- it is clean by construction -- so letting it join a contaminated network would either quietly
-- relabel its contents or force the writer to refuse a rebalance and break conservation. Standing
-- aside until the line is clean again costs nothing and keeps the invariant true.
local function addPurifierOutletDescriptors(descriptorMap, zone)
    local outlets = zone and zone.purifierOutlets
    if not outlets or #outlets == 0 then
        return
    end

    for _, descriptor in pairs(descriptorMap) do
        if (descriptor.waterAmount or 0) > 0 and descriptor.fluidType ~= "Water" then
            return
        end
    end

    for _, outlet in ipairs(outlets) do
        local amount = Purifier.getOutAmount(outlet.purifier) or 0
        local key = "purifierOut:" .. outlet.routerKey
        descriptorMap[key] = {
            key = key,
            squareKey = outlet.routerKey,
            x = outlet.x, y = outlet.y, z = outlet.z,
            objectIndex = -1,
            containerIndex = -1,
            capacity = Constants.PURIFIER_BUFFER_CAPACITY,
            waterAmount = amount,
            fluidType = amount > 0 and "Water" or nil,
            kind = "purifierOut",
            fluidMode = "purifierOut",
            object = outlet.purifier,
            pipeHops = outlet.hops,
            pressureChain = outlet.chain,
        }
    end
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
-- Rewritten onto the hydraulic solver (see Hydraulics.lua). What changed, and why it is two gates now
-- where it used to be one:
--
--   PRESSURE is a property of the CONSUMER'S TILE, not of each source separately. The solver has
--   already propagated one head field over the whole zone with every consumer's demand priced into
--   it, so the question "can this sprinkler run?" is a single lookup -- and, for the first time, its
--   answer depends on how many other sprinklers are running. That is the entire point of the change.
--
--   LIFT is still per source, because it is a different question. A barrel on the floor below cannot
--   feed a tap upstairs however much head the field says is available at that tap, and the field
--   cannot say so on its own: it reports the BEST head reaching the tile, which may be coming from
--   some other, higher source. So each vessel is still asked whether the zone's pumps can raise its
--   water to the consumer -- the same rule, and the same function, that fills already use.
--
-- With the pressure model off both gates stand aside and every connected vessel qualifies, exactly as
-- before.
-- statusOnly asks a different question, and the difference is the short-circuit below. A DRAW must
-- return nothing when the solve excluded this consumer -- that is what stops a starved emitter taking
-- water. A STATUS query wants to know what water is behind the tile whether or not this consumer may
-- have it, because the caller reports the two facts separately and because the answer is shared with
-- every consumer on the level (see getStatusSummary): letting one starved emitter empty the shared
-- summary would report every healthy emitter beside it as dry.
local function applyPressureGate(descriptors, originSquare, kind, solution, zoneLift, statusOnly)
    local enabled = Pressure.isEnabled()
    if not enabled then
        return descriptors, Pressure.containerBase()
    end

    -- Hydraulics.canDrawAt, not a head comparison of our own: a consumer the solve excluded reads a
    -- healthy head precisely BECAUSE it was excluded, so anything that re-derives the answer from the
    -- field here lets every starved emitter straight through. See that function.
    local canDraw, head = Hydraulics.canDrawAt(solution, originSquare, kind)
    if not canDraw and not statusOnly then
        return {}, nil
    end

    local reachable = {}
    for _, descriptor in ipairs(descriptors) do
        if Pressure.canFillTo(descriptor.z, originSquare:getZ(), zoneLift) then
            descriptor.pressure = head
            reachable[#reachable + 1] = descriptor
        end
    end

    return reachable, head
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
-- Re-shape a solved zone into what collectStorageDescriptors and addPurifierOutletDescriptors were
-- already written to take: a list of squares, a hop count per square key, and a `zone` of the pumps
-- and inlets found in it. Nothing is recomputed here -- the solve carries all of it -- so this is a
-- projection, not a second pass.
local function squaresFromSolution(solution, originSquare)
    -- By reference, not rebuilt: these are properties of the zone, identical for every consumer on it.
    local pipeSquares = Hydraulics.pipeSquares(solution)

    -- Hop counts still measured FROM THE CONSUMER, because that is what the nearest-vessel draw order
    -- means and no cheaper proxy survives contact with a real layout (every supply node sits at depth
    -- 0, so ordering by distance-from-supply is degenerate). It stays affordable by walking the solved
    -- adjacency instead of the world: pure Lua, zero bridge calls.
    local hops = Hydraulics.distancesFrom(solution, originSquare)

    local pumps = Hydraulics.poweredPumps(solution)

    local outlets = {}
    for _, outlet in pairs(solution.purifierOutlets or {}) do
        outlets[#outlets + 1] = {
            purifier = outlet.purifier,
            routerKey = outlet.routerKey,
            x = outlet.x, y = outlet.y, z = outlet.z,
            hops = hops[outlet.nodeKey] or 0,
        }
    end

    return pipeSquares, hops, {
        pumps = pumps,
        mains = {},
        hydrants = {},
        purifierOutlets = outlets,
        -- The RELATIVE utility pressure, not the field's absolute floor: this feeds the lift gate.
        supplyHead = (solution.stats and solution.stats.supplyHead) or 0,
    }
end

local function buildSummaryFromSquare(originSquare, verticalMode, kind, fill, statusOnly)
    if not originSquare then
        return nil
    end

    -- Which way the water is travelling, which is what decides how a bare router may be crossed (see
    -- tryCrossRouter). Visualization asks for neither and keeps every router solid, so the overlay
    -- still draws the zones the player built rather than silently merging them.
    local conduct = nil
    if fill then
        conduct = "fill"
    elseif kind then
        conduct = "draw"
    end

    -- A DRAW query takes its topology from the hydraulic solve, which is shared by every consumer on
    -- the zone. That is the perf half of this change: the walk below is O(network) and used to run
    -- once PER CONSUMER, so a field of thirty-eight emitters on a 192-tile grid walked 7 300 tiles a
    -- pass -- and the client walked it again, per emitter, every three seconds for the spray FX. Fills
    -- and visualization keep the old per-origin walk: they ask a different question (where can water
    -- GO from here), cross routers the other way, and are not on the hot path.
    local pipeSquares, hops, zone, chains
    local solution = nil
    if kind and not fill then
        solution = Hydraulics.solveAt(originSquare)
        if not solution then
            return nil
        end
        pipeSquares, hops, zone = squaresFromSolution(solution, originSquare)
    else
        pipeSquares, hops, zone, chains =
            collectPipeSquaresCached(originSquare, verticalMode, conduct)
    end
    if #pipeSquares == 0 then
        return nil
    end

    local descriptorMap = collectStorageDescriptors(pipeSquares, hops, chains, solution)
    addPurifierOutletDescriptors(descriptorMap, zone)
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
            descriptors, pressure = applyPressureGate(descriptors, originSquare, kind,
                solution, liftHead, statusOnly)
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

-- Take the purifier OUT buffers out of a summary and recompute its totals. Called by the fill paths
-- the moment the fluid that will land is anything but clean Water.
--
-- The buffer is clean by construction and its writer (ContainerAdapter.writePurifierOutAmount)
-- refuses everything else -- correctly. But a refusal DURING a rebalance is too late: the rebalance
-- has already divided the total assuming the buffer takes its share, so the share it refuses is
-- litres conjured or destroyed. The buffer has to leave the summary BEFORE the arithmetic, keeping
-- its clean water and lending the dirty line neither its contents nor its capacity. It rejoins
-- naturally once the line is clean again (addPurifierOutletDescriptors re-admits it per query).
local function excludePurifierOutlets(summary)
    local kept = {}
    local removed = false
    for _, descriptor in ipairs(summary.descriptors) do
        if descriptor.fluidMode == "purifierOut" then
            removed = true
            summary.totalAmount = summary.totalAmount - math.max(descriptor.waterAmount or 0, 0)
            summary.totalCapacity = summary.totalCapacity - math.max(descriptor.capacity or 0, 0)
        else
            kept[#kept + 1] = descriptor
        end
    end
    if removed then
        summary.descriptors = kept
        summary.totalAmount = math.max(summary.totalAmount, 0)
        summary.totalCapacity = math.max(summary.totalCapacity, 0)
    end
    return removed
end

-- Spread `remainingAmount` over the summary's vessels in proportion to their capacity, and leave the
-- summary describing what the world now holds.
--
-- Two things here are load-bearing:
--
-- CARRY. Adapter.writeDescriptorWaterAmount refuses writes that would move less than
-- Constants.FLUID_WRITE_EPSILON, because the write itself (empty, refill, sync, transmitModData,
-- OnWaterAmountChange) costs far more than a hundredth of a litre is worth. But the caller has
-- already been told it drew those litres -- drawFluidAtSquare returns `drawn` whatever the writes do
-- -- so litres a skipped write leaves behind must land somewhere or the network conjures water out
-- of nothing. They are carried to the next vessel; the last one absorbs whatever is left. A vessel
-- that clamps at its capacity feeds its overflow into the same carry, which is the same arithmetic.
--
-- WRITE-BACK. The descriptors and the totals are updated to what was actually written, so the
-- summary stays a true picture of the network after the call. A summary is now handed around and
-- drawn from more than once (see getDrawSummary), and without this the second draw would price
-- itself against water the first one already took.
local function rebalanceSummary(summary, remainingAmount)
    local fluidTypeName = remainingAmount > 0 and summary.fluidTypeName or nil
    local totalCapacity = math.max(summary.totalCapacity or 0, 0)
    local ratio = totalCapacity > 0 and math.min(remainingAmount / totalCapacity, 1) or 0

    local carry = 0
    local written = 0

    for _, descriptor in ipairs(summary.descriptors) do
        local capacity = math.max(descriptor.capacity or 0, 0)
        local share = capacity * ratio
        local target = math.min(math.max(share + carry, 0), capacity)
        local before = math.max(descriptor.waterAmount or 0, 0)

        local ok, wrote = Adapter.writeDescriptorWaterAmount(descriptor, target, fluidTypeName)
        local landed
        if ok and wrote then
            landed = target
            descriptor.waterAmount = target
            descriptor.fluidType = target > 0 and fluidTypeName or nil
        else
            -- Either the write was skipped as not worth doing, or it failed outright (a vessel that
            -- refused the fluid). Either way the vessel still holds what it held, and the difference
            -- rolls on to the next one rather than evaporating.
            landed = before
        end

        carry = carry + share - landed
        written = written + landed
    end

    summary.totalAmount = written
    summary.fluidTypeName = written > 0 and fluidTypeName or nil
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
    local pipeSquares, hops = collectPipeSquaresCached(originSquare, "both")
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

-- Even the stored water out across the network reachable from `originSquare`, without adding or
-- removing any. Returns the litres it had to move, or 0.
--
-- The purifier needs this. Its clean buffer is now ordinary storage on the OUT network, so it no
-- longer PUSHES its water anywhere -- but nothing would move that water into the barrels either,
-- because a network only settles when something draws from it or fills it. A purifier feeding a
-- barrel farm that nobody is drinking from would sit at a full buffer and stall exactly as before.
-- This is the missing nudge, and it is conservation-safe by construction: the total handed back to
-- rebalanceSummary is the total it was given.
function NetworkAccess.settleAtSquare(originSquare)
    local summary = buildSummaryFromSquare(originSquare, nil, true)
    if not summary or summary.isMixed or (summary.totalAmount or 0) <= 0 then
        return 0
    end
    if #summary.descriptors < 2 then
        return 0   -- nothing to even out against
    end

    -- Already level? Then say so and touch nothing. rebalanceSummary rewrites every vessel it is
    -- given -- empty, refill, sync, transmit -- so running it unconditionally once a minute per
    -- purifier would be a steady stream of writes and multiplayer traffic to change nothing.
    local totalCapacity = math.max(summary.totalCapacity or 0, 0)
    if totalCapacity <= 0 then
        return 0
    end
    local ratio = math.min(summary.totalAmount / totalCapacity, 1)
    local levelled = true
    for _, descriptor in ipairs(summary.descriptors) do
        local target = (descriptor.capacity or 0) * ratio
        if math.abs((descriptor.waterAmount or 0) - target) > 0.01 then
            levelled = false
            break
        end
    end
    if levelled then
        return 0
    end

    rebalanceSummary(summary, summary.totalAmount)
    return summary.totalAmount
end

-- For visualization: the pipe squares reachable from a square + the container descriptors on them.
-- Unlike getFluidSummaryAtSquare it returns the pipe squares even when there are no containers.
-- Just the tiles of the physically-connected network -- both directions, routers solid, the shape the
-- player built rather than the shape water can travel.
--
-- Split out from getNetworkFromSquare because two of its three callers wanted only this and threw the
-- descriptors away. Building those means visiting every tile of the network and reading the fluid in
-- every vessel on it, which is the most expensive thing a summary does; doing it for a caller that
-- discards the result is pure waste. Measured on the per-minute pass, where the purifier lookup was
-- paying it once a minute to answer a question about routers.
function NetworkAccess.getNetworkSquares(originSquare)
    local pipeSquares = collectPipeSquaresCached(originSquare, "both")
    return pipeSquares
end

function NetworkAccess.getNetworkFromSquare(originSquare)
    -- Visualization: show the whole physically-connected network (both directions), not just the
    -- gravity-reachable part.
    local pipeSquares, hops = collectPipeSquaresCached(originSquare, "both")
    local descriptors = normalizeDescriptorList(collectStorageDescriptors(pipeSquares, hops))
    return pipeSquares, descriptors
end

-- Best head (m.c.a.) available to a `kind` consumer standing on `square`, or nil when nothing can
-- reach it. Public because the pump, the sprinkler and the gauge all need to ask the same question.
function NetworkAccess.getPressureAtSquare(square, kind)
    -- Straight to the head field. This used to build a whole network summary -- walk, descriptors,
    -- gate -- to read one number, and it is called by the gauge, by every pump's status line and by
    -- every emitter the spray FX draws. Now it is a lookup on a solve the zone already shares.
    return Hydraulics.pressureAt(Hydraulics.solveAt(square), square,
        kind or Constants.PRESSURE_KIND_TAP)
end

-- Everything the pressure model knows about one point, for the debug readout. The gauge answers
-- "how much?"; this answers "why?".
--
-- Rebased on the solver, and one field is genuinely new: FLOW. That is the number that explains
-- everything the player is looking at. A line reading 68 L/h at the pump and 1.8 L/h at its far end
-- has just told them, in units they can act on, that the far end is dry because thirty-seven other
-- emitters are upstream of it -- a question the old readout could not even phrase, because nothing
-- in the old model knew that the other emitters existed.
function NetworkAccess.getPressureReport(square)
    if not square then
        return nil
    end

    local solution = Hydraulics.solveAt(square)
    local report = {
        enabled = Pressure.isEnabled(),
        model = Pressure.model(),
        pipeCount = solution and #solution.order or 0,
        sources = {},
        kinds = {},
        demandScale = Hydraulics.demandScale(),
    }

    if not solution then
        report.pumpCount, report.poweredPumps = 0, 0
        report.mainsCount, report.hydrantCount = 0, 0
        report.pumpHead, report.mainsHead, report.supplyHead = 0, 0, 0
        return report
    end

    local stats = solution.stats or {}
    report.pumpCount = stats.pumpCount or 0
    report.poweredPumps = stats.poweredPumps or 0
    report.mainsCount = stats.mainsCount or 0
    report.hydrantCount = stats.hydrantCount or 0
    report.pumpHead = stats.pumpHead or 0
    report.mainsHead = (stats.mainsCount or 0) > 0 and Mains.head() or 0
    report.supplyHead = stats.supplyHead or 0

    -- Load: what the zone is being asked for, and how much of it is actually being served.
    local totalDemand, servedDemand, emitterCount, starvedCount = 0, 0, 0, 0
    for key, litres in pairs(solution.demand or {}) do
        emitterCount = emitterCount + 1
        totalDemand = totalDemand + litres
        if solution.starved[key] then
            starvedCount = starvedCount + 1
        else
            servedDemand = servedDemand + litres
        end
    end
    report.emitterCount = emitterCount
    report.starvedCount = starvedCount
    report.totalDemand = totalDemand
    report.servedDemand = servedDemand
    report.iterations = solution.iterations
    report.flow = Hydraulics.flowAt(solution, square) or 0

    if report.pipeCount == 0 then
        return report
    end

    -- Hop counts are measured over the solved adjacency, which costs no world access at all.
    local distance = Hydraulics.distancesFrom(solution, square)
    local consumerZ = square:getZ()
    local levelHead = Pressure.levelHead()
    local containerBase = Pressure.containerBase()

    local seen = {}
    for _, descriptor in ipairs(solution.sources or {}) do
        if not seen[descriptor.key] then
            seen[descriptor.key] = true
            report.sources[#report.sources + 1] = {
                key = tostring(descriptor.key),
                z = descriptor.z,
                hops = distance[descriptor.nodeKey],
                amount = descriptor.waterAmount,
                capacity = descriptor.capacity,
                fluidType = descriptor.fluidType,
                -- Two different numbers, and the readout needs both to be answerable.
                --
                -- `staticHead` is what gravity alone gives this vessel here: whether it sits high
                -- enough to help at all, which is the one thing still genuinely per source.
                --
                -- `supplyHead` is the pressure it actually pushes at, pumps included. Without it the
                -- column read "1.00" for every barrel on a farm with two pumps running -- true (they
                -- are all on the same floor) and completely misleading, because it looked like the
                -- barrels were the reason the far end had no pressure when the real answer was the
                -- 84 L/h being drawn between here and there.
                staticHead = containerBase + levelHead * ((descriptor.z or 0) - consumerZ),
                supplyHead = descriptor.nodeKey and solution.supply[descriptor.nodeKey]
                    and (solution.supply[descriptor.nodeKey] - levelHead * (descriptor.z or 0))
                    or nil,
            }
        end
    end
    report.containerCount = #report.sources

    -- Does the solve list an emitter on THIS tile as one it cannot feed? Reported separately from the
    -- head, because the two can disagree and that disagreement is the whole story: a starved tile
    -- reads a comfortable head, since the field it is reading excludes its own draw.
    report.starvedHere = Hydraulics.isStarvedAt(solution, square)

    for _, kind in ipairs({ Constants.PRESSURE_KIND_TAP, Constants.PRESSURE_KIND_DRIP,
        Constants.PRESSURE_KIND_SPRINKLER }) do
        local canDraw, head = Hydraulics.canDrawAt(solution, square, kind)
        local minimum = Pressure.minimumFor(kind)
        report.kinds[kind] = {
            head = head,
            minimum = minimum,
            canDraw = canDraw,
            -- Loss per tile is no longer a constant of the consumer -- it is what this tile's actual
            -- flow costs. Reported as such.
            friction = Hydraulics.lossPerTile(report.flow > 0 and report.flow
                or Hydraulics.flowFor(kind)),
            ok = canDraw,
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
    -- Clean water may always join a tainted line (it just becomes tainted); only a genuinely
    -- incompatible fluid is refused.
    local merged = mergeFluidNames(summary.fluidTypeName, fluidType)
    if (summary.totalAmount or 0) > 0 and summary.fluidTypeName and not merged then
        return 0
    end
    -- What the line would hold after the push. Anything but clean Water and the purifier buffers
    -- stand aside (see excludePurifierOutlets) -- their headroom must not be promised to a fill
    -- that their writer will refuse.
    local landing = (summary.totalAmount or 0) > 0 and summary.fluidTypeName and merged or fluidType
    if landing and landing ~= "Water" then
        excludePurifierOutlets(summary)
    end
    local headroom = (summary.totalCapacity or 0) - (summary.totalAmount or 0)
    if headroom <= 0 then
        return 0
    end
    return headroom
end

-- The summary a consumer standing on `square` needs, built ONCE.
--
-- Every draw used to build three of these -- one to read the pressure, one to ask what was available,
-- one to actually take it -- all with identical arguments and all rebuilding the container
-- descriptors from scratch. The traversal cache spared the walk but not that, and on a farm network
-- it was the walk's cost all over again, three times per emitter. The summary already carries every
-- answer all three wanted: `pressure`, `totalAmount` + `fluidTypeName`, and `descriptors`.
--
-- The returned summary is LIVE: drawFromSummary updates it in place, so a caller may draw from it
-- repeatedly and each draw sees what the previous one left. It is a snapshot of topology and of the
-- fluid at build time -- so do not hold one across a frame, or across anything that could move water
-- behind its back.
function NetworkAccess.getDrawSummary(square, kind)
    return buildSummaryFromSquare(square, "both", kind or Constants.PRESSURE_KIND_TAP)
end

-- The same summary, shared by every consumer on the zone standing at the same LEVEL.
--
-- READ-ONLY, and not for draws. The descriptors carry the hop counts of whichever consumer built the
-- summary first, and a draw orders by those to empty the nearest vessel -- handing this to one would
-- silently reorder it. getDrawSummary stays the way to take water.
--
-- What makes the sharing sound is that the only per-consumer term in the gate is elevation:
--
--     Pressure.canFillTo(vessel.z, consumer.z, zoneLift)
--
-- three numbers, none of them the tile. So which vessels are reachable is a property of the zone and
-- the level and nothing finer. test_hydraulics.lua test 13 pins exactly that; if it ever fails, this
-- function is invalid and the callers must go back to building their own.
--
-- Why it exists: the presentational callers -- spray FX, wetness, the emitter tooltip -- all ask one
-- question, "is there water behind me", and each was building the whole summary to answer it. A
-- descriptor table and a live fluid read for every vessel on the zone, per emitter. Measured in game
-- at 4.3 ms each with the spray FX asking ten times a second: 42 ms/s, half of everything this mod
-- spent. Shared, it is one build per zone per level per frame.
--
-- Per-frame, like the caches it sits beside, because the AMOUNTS in it are live: a draw made later in
-- the frame must not be hidden from whatever reads next.
function NetworkAccess.getStatusSummary(square, kind)
    if not square then
        return nil
    end

    local solution = Hydraulics.solveAt(square)
    if not solution then
        return nil
    end

    kind = kind or Constants.PRESSURE_KIND_TAP
    local key = tostring(solution.id) .. "|" .. tostring(square:getZ()) .. "|" .. tostring(kind)
    local cached = statusSummaryMemo[key]
    if cached ~= nil then
        return cached or nil          -- `false` is a remembered "there is nothing here"
    end

    local summary = buildSummaryFromSquare(square, "both", kind, nil, true)
    statusSummaryMemo[key] = summary or false
    return summary
end

-- Take `amount` out of an already-built summary. Returns the amount actually drawn.
--
-- Deliberately NOT a rebalance. Re-levelling the whole network on every sip made the vessel count a
-- term in the cost of every draw: a sprinkler taking 1.8 L from ten barrels rewrote all ten -- empty,
-- refill, sync, transmitModData, OnWaterAmountChange, ten times -- to move 0.18 L into each. Thirty-
-- two sprinklers made that 320 vessel writes per pass where 32 would do.
--
-- (Measured, so it is not oversold: on a 250-tile farm those writes are a small share of the pass
-- next to the per-emitter network summaries -- see tools/perf. This removes the term rather than the
-- bottleneck. It matters most in multiplayer, where every write is also a packet, and for whatever
-- other mods hang off OnWaterAmountChange.)
--
-- So we empty the nearest vessels instead, taking all of one before touching the next. One write for
-- a typical draw, whatever the network holds. Nothing is lost by not levelling here: gravity settle
-- (System.redistributeWater, every ten in-game minutes) is what evens the network out, and it was
-- always the thing doing that job -- the rebalance here was only ever duplicating it, once per sip.
--
-- Nearest-first is not arbitrary either. It is what a real line does: the consumer pulls from the
-- vessel with the shortest run to it, and the rest of the line refills that one at its own pace.
local function drawFromSummaryDescriptors(summary, amount)
    local order = {}
    for _, descriptor in ipairs(summary.descriptors) do
        if (descriptor.waterAmount or 0) > 0 then
            order[#order + 1] = descriptor
        end
    end

    table.sort(order, function(left, right)
        local leftHops, rightHops = left.pipeHops or 0, right.pipeHops or 0
        if leftHops ~= rightHops then
            return leftHops < rightHops
        end
        -- Same distance: drain the fullest first, so a network settles toward level rather than away
        -- from it between gravity passes.
        local leftAmount, rightAmount = left.waterAmount or 0, right.waterAmount or 0
        if leftAmount ~= rightAmount then
            return leftAmount > rightAmount
        end
        return tostring(left.key) < tostring(right.key)
    end)

    local remaining = amount
    local removed = 0

    for _, descriptor in ipairs(order) do
        if remaining <= 0 then
            break
        end

        local have = math.max(descriptor.waterAmount or 0, 0)
        local take = math.min(have, remaining)
        local target = have - take
        -- Falling back to the network's fluid is not belt-and-braces: writeWorldFluidAmount empties
        -- the vessel and only refills it when it is given a type, so handing it a positive amount
        -- with no type would destroy the remainder outright.
        local fluidTypeName = nil
        if target > 0 then
            fluidTypeName = descriptor.fluidType or summary.fluidTypeName
            if not fluidTypeName then
                -- Unknown fluid and water still in the vessel: leave it alone rather than risk it.
                break
            end
        end

        -- Force the write once nothing has moved yet: the caller is about to be told it drew these
        -- litres, so a request too small to clear the epsilon must still land somewhere.
        local force = (removed <= 0)
        local ok, wrote = Adapter.writeDescriptorWaterAmount(descriptor, target, fluidTypeName, force)
        if ok and wrote then
            descriptor.waterAmount = target
            descriptor.fluidType = fluidTypeName
            removed = removed + take
            remaining = remaining - take
        end
    end

    summary.totalAmount = math.max((summary.totalAmount or 0) - removed, 0)
    if summary.totalAmount <= 0 then
        summary.fluidTypeName = nil
    end
    return removed
end

function NetworkAccess.drawFromSummary(summary, requiredFluidType, amount)
    if not summary or summary.isMixed or (summary.totalAmount or 0) <= 0 then
        return 0
    end

    if not fluidNameMatches(summary.fluidTypeName, requiredFluidType) then
        return 0
    end

    local wanted = math.min(math.max(amount or 0, 0), summary.totalAmount)
    if wanted <= 0 then
        return 0
    end

    return drawFromSummaryDescriptors(summary, wanted)
end

-- Draw up to `amount` of `requiredFluidType` from the network reachable from `originSquare`.
-- Only works on a single-fluid network whose fluid matches requiredFluidType. Returns the
-- amount actually drawn. Kept as the one-shot form for callers with no summary in hand.
function NetworkAccess.drawFluidAtSquare(originSquare, requiredFluidType, amount, kind)
    -- Drawing is consumption: only fluid whose head reaches this square is available.
    return NetworkAccess.drawFromSummary(
        buildSummaryFromSquare(originSquare, "both", kind or Constants.PRESSURE_KIND_TAP),
        requiredFluidType, amount)
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

    -- A non-empty network takes the incoming fluid only if the two can share a pipe. Water and
    -- tainted water always can -- the result is tainted -- so this now refuses nothing but a real
    -- fluid clash (petrol into water).
    local merged = mergeFluidNames(summary.fluidTypeName, fluidType)
    if (summary.totalAmount or 0) > 0 and summary.fluidTypeName and not merged then
        return 0
    end

    -- An empty network adopts the incoming fluid type; a stocked one takes the merged result, which
    -- is what turns the whole line tainted the moment dirty water is pushed into it.
    local landing = (summary.totalAmount or 0) <= 0 and fluidType or merged

    -- The purifier's clean buffers leave the summary before the arithmetic when what lands is not
    -- clean Water (see excludePurifierOutlets): they keep their clean water, and the headroom and
    -- rebalance below are computed over the vessels that will actually take the fluid.
    if landing ~= "Water" and excludePurifierOutlets(summary) and #summary.descriptors == 0 then
        return 0
    end

    local headroom = (summary.totalCapacity or 0) - (summary.totalAmount or 0)
    if headroom <= 0 then
        return 0
    end

    local added = math.min(math.max(amount or 0, 0), headroom)
    if added <= 0 then
        return 0
    end

    summary.fluidTypeName = landing
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

    -- Same nearest-vessel draw a sprinkler uses: a tap emptying the barrel next to it is what the
    -- plumbing does anyway, and it costs one vessel write instead of one per vessel on the line.
    return drawFromSummaryDescriptors(summary, clamped)
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

    -- Same rule as fillFluidAtSquare: restoring anything but clean Water and the purifier's clean
    -- buffers step out of the summary first (see excludePurifierOutlets).
    local landing = merged or fluidTypeName
    if landing ~= "Water" and excludePurifierOutlets(summary) and #summary.descriptors == 0 then
        return 0
    end

    local clamped = math.max(amount or 0, 0)
    local availableCapacity = math.max((summary.totalCapacity or 0) - (summary.totalAmount or 0), 0)
    local restored = math.min(clamped, availableCapacity)
    if restored <= 0 then
        return 0
    end

    summary.fluidTypeName = landing
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

-- The traversal cache's invalidation. Anything that changes what the walk would FIND has to drop it:
-- a pipe appearing or disappearing changes the shape of the network, and a router's direction or its
-- ceiling changes which squares are reachable and how they are priced. The per-frame clear is the
-- backstop -- it means no mistake here can outlive a single frame -- and the explicit calls exist
-- because a build and the network rebuild it triggers happen inside that same frame.
if Events then
    if Events.OnObjectAdded then
        Events.OnObjectAdded.Add(onWorldObjectChanged)
    end
    if Events.OnObjectAboutToBeRemoved then
        Events.OnObjectAboutToBeRemoved.Add(onWorldObjectChanged)
    end
    if Events.OnTick then
        Events.OnTick.Add(dropTraversalCacheOnly)
    end
end
