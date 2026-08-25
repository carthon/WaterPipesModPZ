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

-- Bracket a stretch of work for the profiler, resolved off the global table so this module keeps no
-- dependency on a debug tool. mark/since rather than Profiler.time, which forwards only two returns.
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

-- A router with a tank on it (the purifier) is a hard boundary: the two sides must never see each
-- other. Bare, it is an inline pressure-reducing valve that water passes through.
local function routerIsHardBoundary(routerSquare)
    if Purifier and Purifier.findForRouterSquare and Purifier.findForRouterSquare(routerSquare) then
        return true
    end
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

local function keyOf(x, y, z)
    return tostring(x) .. ":" .. tostring(y) .. ":" .. tostring(z)
end

local function squareKey(square)
    return keyOf(square:getX(), square:getY(), square:getZ())
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

-- verticalMode gates riser links: "both" (topology), "up" (sources that drain down to origin),
-- "down" (where water introduced at origin would fall). Horizontal links always conduct both ways.

-- A regulator chain node is one router crossing; `parent` walks back toward the consumer. A node also
-- owns the pumps on the squares it covers, which is what keeps a pump from pushing past a valve.
local function newChain(parent, ceiling, hops, z)
    return { parent = parent, ceiling = ceiling, hops = hops, z = z, pumps = {}, supplyHead = 0 }
end


-- Returns (pipeSquares, hopsByKey, zone). hopsByKey is the min hop count from originSquare to each
-- pipe square, which is all the pressure model needs: loss is friction * hops.
-- `zone` carries the powered pumps and bounding routers, gathered as the walk goes.
-- `conduct` ("draw" or "fill") lets the walk cross bare routers; nil keeps every router a wall.
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
    -- Two tables, not one: a router is visited from each neighbour, but whether its outlet is recorded
    -- depends on which side we arrived from.
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
            chain.pumps[#chain.pumps + 1] = pump
        end

        -- Municipal supplies floor the run at their pressure; a regulator holds them down like a pump.
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

    -- The purifier's OUT buffer is storage belonging to the network on its clean side. Recorded during
    -- the walk, the one place that has the router and its direction in hand. Topology only -- the amount
    -- is read fresh every query.
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

        -- Only the OUT side receives it: the dirty side must never see the clean water.
        local rx, ry, rz = routerSquare:getX(), routerSquare:getY(), routerSquare:getZ()
        if fromX ~= rx + out.dx or fromY ~= ry + out.dy or fromZ ~= rz then
            return
        end

        outletSeen[key] = true
        zone.purifierOutlets[#zone.purifierOutlets + 1] = {
            purifier = purifier,
            routerKey = key,
            x = fromX, y = fromY, z = fromZ,
            -- The water lands on the square we came from, one hop closer to the consumer.
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

    -- The origin is often a fixture with no pipe of its own, so its neighbours are seeded unconditionally.
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

-- Per-origin cache of walk TOPOLOGY only: which squares, how far, the regulator chains, the pumps
-- and inlets passed. The fluid is never cached, so a draw always sees real amounts.
-- Keyed per origin because hop counts are measured FROM the consumer.
local traversalCache = {}

-- Past this many origins scoped invalidation costs more than the walks are worth; start over instead.
local TRAVERSAL_CACHE_LIMIT = 64

-- Counters: the only way to tell a cache that is working from one dropped faster than it is built.
NetworkAccess.counters = { walks = 0, hits = 0, scoped = 0, global = 0, untouched = 0, overflow = 0 }

-- Zone id -> the tiles of that zone that hold a vessel.
local zoneVesselMemo = {}

-- Zone, level and kind -> the summary every consumer there would have built for itself.
local statusSummaryMemo = {}

-- `conduct` is part of the key BY VALUE, not by truthiness: draw and fill walks cross routers in
-- opposite directions and so reach different squares.
local function traversalKey(square, verticalMode, conduct)
    return squareKey(square) .. "|" .. tostring(verticalMode) .. "|" .. tostring(conduct)
end

-- Three caches, three lifetimes. statusSummaryMemo holds FLUID, so it dies with the frame.
-- zoneVesselMemo is keyed by solve id and follows it.
-- traversalCache holds fill topology and lives until the LAYOUT changes: pipe add/remove by tile,
-- router direction and ceiling, hydrant open, a vessel landing on a router tile. Pump power is not
-- cached at all, and the mains clock is watched by supplyClockChanged.
local function dropFrameMemos()
    zoneVesselMemo = {}
    statusSummaryMemo = {}
end

-- Forget one cached walk.
local function forgetTraversal(key)
    if traversalCache[key] == nil then
        return false
    end
    traversalCache[key] = nil
    return true
end

-- An object appeared or vanished at a tile: drop only the walks that pass through it or a neighbour.
-- There is deliberately no test of WHAT the object was -- a predicate would need a list of every type
-- that matters, and a missing type would fail silently.
-- Neighbours count because a new pipe belongs to no walk yet: what it changes is the walks it joins.
function NetworkAccess.invalidateAroundSquare(square)
    if not square or not square.getX then
        NetworkAccess.invalidateTraversalCache()
        return
    end

    local okX, x = pcall(square.getX, square)
    local okY, y = pcall(square.getY, square)
    local okZ, z = pcall(square.getZ, square)
    if not okX or not okY or not okZ or x == nil or y == nil or z == nil then
        NetworkAccess.invalidateTraversalCache()
        return
    end

    local counters = NetworkAccess.counters

    -- One key, and one lookup per cached walk. The neighbourhood is precomputed per WALK instead (the
    -- halo below), because this fires for every streamed object -- ~230 a second -- while a walk is
    -- cached twice in a session.
    local touched = keyOf(x, y, z)

    local dropped = false
    for key, entry in pairs(traversalCache) do
        if entry.halo[touched] then
            if forgetTraversal(key) then
                dropped = true
            end
        end
    end

    if dropped then
        counters.scoped = counters.scoped + 1
    else
        counters.untouched = counters.untouched + 1
    end
end

function NetworkAccess.invalidateAroundObject(worldObject)
    if not worldObject or not worldObject.getSquare then
        NetworkAccess.invalidateTraversalCache()
        return
    end

    local ok, square = pcall(worldObject.getSquare, worldObject)
    if not ok or not square then
        NetworkAccess.invalidateTraversalCache()
        return
    end

    NetworkAccess.invalidateAroundSquare(square)
end

-- The layout changed wholesale: drop everything.
function NetworkAccess.invalidateTraversalCache()
    traversalCache = {}
    zoneVesselMemo = {}
    statusSummaryMemo = {}
    NetworkAccess.counters.global = NetworkAccess.counters.global + 1
    if Hydraulics and Hydraulics.invalidate then
        Hydraulics.invalidate()
    end
end

-- The mains shutoff is the one input to a cached walk that no event announces, and it is a CLOCK: it
-- flips once in the life of a save. Watching it is a compare per minute, where expiring the cache for
-- it would be a full re-walk per minute forever.
local lastServiceLive = nil

-- REPORTS, does not act: the caller is asking the pump-power watcher the same kind of question and
-- coalesces both answers into a single drop.
function NetworkAccess.supplyClockChanged()
    local live = true
    if Mains and Mains.serviceLive then
        local ok, answer = pcall(Mains.serviceLive)
        live = (not ok) or (answer and true or false)
    end

    if lastServiceLive == nil then
        -- First look of the session: nothing was known when the caches were built.
        lastServiceLive = live
        return true
    end

    if lastServiceLive ~= live then
        lastServiceLive = live
        return true
    end

    return false
end

local function collectPipeSquaresCached(originSquare, verticalMode, conduct)
    if not originSquare then
        return {}, {}, { pumps = {}, mains = {} }, {}
    end

    local key = traversalKey(originSquare, verticalMode, conduct)
    local hit = traversalCache[key]
    if hit then
        NetworkAccess.counters.hits = NetworkAccess.counters.hits + 1
        return hit.pipeSquares, hit.hops, hit.zone, hit.chains, hit
    end

    NetworkAccess.counters.walks = NetworkAccess.counters.walks + 1
    local pipeSquares, hops, zone, chains =
        collectPipeSquaresFromSquare(originSquare, verticalMode, conduct)

    -- The halo: this walk's tiles plus their neighbours, precomputed so invalidation is one lookup.
    -- The origin goes in too -- it is often a fixture with no pipe of its own.
    local halo = {}
    local function haloAround(hx, hy, hz)
        halo[keyOf(hx, hy, hz)] = true
        for _, offset in ipairs(Constants.CARDINAL_OFFSETS) do
            halo[keyOf(hx + offset.x, hy + offset.y, hz)] = true
        end
        halo[keyOf(hx, hy, hz - 1)] = true
        halo[keyOf(hx, hy, hz + 1)] = true
    end

    haloAround(originSquare:getX(), originSquare:getY(), originSquare:getZ())
    for _, pipeSquare in ipairs(pipeSquares) do
        haloAround(pipeSquare:getX(), pipeSquare:getY(), pipeSquare:getZ())
    end

    local count = 0
    for _ in pairs(traversalCache) do
        count = count + 1
    end
    if count >= TRAVERSAL_CACHE_LIMIT then
        -- More origins than any real base has. Start over rather than degrade quietly.
        traversalCache = {}
        NetworkAccess.counters.overflow = NetworkAccess.counters.overflow + 1
    end

    local entry = {
        pipeSquares = pipeSquares, hops = hops, zone = zone, chains = chains, halo = halo,
        -- vessels: filled in on first use by vesselSquaresOfWalk. A visualization query wants the tile set
        -- and should not pay to classify every tile for containers it will not look at.
        vessels = nil,
    }
    traversalCache[key] = entry
    return pipeSquares, hops, zone, chains, entry
end

local function collectConnectedPipeSquares(endpointObject)
    if not endpointObject or not endpointObject.getSquare then
        return {}
    end
    return collectPipeSquaresCached(endpointObject:getSquare())
end

-- Which tiles of a cached walk hold a vessel, found once per walk and hung on the entry: an object
-- joining or leaving any tile of the walk already drops it, halo and all.
-- Only the DISCOVERY is pooled. The descriptors stay per query, because they carry hops measured from
-- the asking tile and sharing them would have one caller overwrite the other's.
local function vesselSquaresOfWalk(entry, pipeSquares)
    if entry and entry.vessels then
        return entry.vessels
    end

    local list = {}
    local seen = {}
    for _, pipeSquare in ipairs(pipeSquares) do
        local key = squareKey(pipeSquare)
        if not seen[key] then
            seen[key] = true
            if Adapter.hasSquareContainers(pipeSquare) then
                list[#list + 1] = { square = pipeSquare, key = key }
            end
        end
    end

    if entry then
        entry.vessels = list
    end
    return list
end

-- The original walk, kept for fills and visualization: they ask where water can GO from here.
local function collectStorageDescriptorsByWalk(pipeSquares, hops, chains, entry)
    local descriptors = {}

    -- A container counts only when it shares its tile with a pipe (same square), not by adjacency.
    for _, vessel in ipairs(vesselSquaresOfWalk(entry, pipeSquares)) do
        local key = vessel.key
        -- How far this container sits from the origin, and the regulators standing between the two.
        local distance = hops and hops[key] or 0
        local chain = chains and chains[key] or nil
        for descriptorKey, descriptor in pairs(Adapter.collectSquareContainers(vessel.square)) do
            descriptor.pipeHops = distance
            descriptor.pressureChain = chain
            descriptors[descriptorKey] = descriptor
        end
    end

    return descriptors
end

-- The tiles of a zone that hold a vessel, found once per zone per frame.
-- Safe to key by zone because squaresFromSolution hands back the tile set BY REFERENCE; only the hop
-- counts are measured from the asking tile. Only the discovery is pooled, the pricing stays private.
local function vesselSquaresOfZone(solution)
    local id = solution and solution.id
    if not id then
        return nil
    end

    local cached = zoneVesselMemo[id]
    if cached then
        return cached
    end

    -- TEMPORARY attribution. draw/descriptors is 489 ms of a 2701 ms window and its calls are one per
    -- EMITTER, but this memo dies with the frame -- so a pass spread over frames rebuilds it every few
    -- emitters, walking every pipe square of the zone. Which half costs is a guess until measured.
    local mark = markPhase()
    local list = {}
    local seen = {}
    local walked = 0
    for _, pipeSquare in ipairs(Hydraulics.pipeSquares(solution)) do
        local key = squareKey(pipeSquare)
        if not seen[key] then
            seen[key] = true
            walked = walked + 1
            if Adapter.hasSquareContainers(pipeSquare) then
                list[#list + 1] = { square = pipeSquare, key = key }
            end
        end
    end
    sincePhase("descriptors/zonewalk", mark)
    countPhase("descriptors: zone walks", 1)
    countPhase("descriptors: squares walked", walked)

    zoneVesselMemo[id] = list
    return list
end

local function collectStorageDescriptors(pipeSquares, hops, chains, solution, entry)
    local pooled = solution and vesselSquaresOfZone(solution) or nil
    if pooled then
        -- The other half: one live re-read of every vessel in the zone, per emitter. The amounts have to
        -- be live -- an earlier emitter's draw must be visible to the next -- but whether that is worth
        -- 0.4 ms an emitter is what the counter below answers.
        local mark = markPhase()
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
        sincePhase("descriptors/vessels", mark)
        countPhase("descriptors: vessel reads", #pooled)
        return descriptors
    end

    return collectStorageDescriptorsByWalk(pipeSquares, hops, chains, entry)
end


-- Turn the purifier outlets the walk found into ordinary storage descriptors.
-- Skipped when the network already holds tainted water: the OUT buffer has no taint flag, so letting
-- it join a contaminated network would relabel its contents or break conservation.
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
-- best head any survivor delivers.
-- PRESSURE is a property of the consumer's TILE: one head field with every consumer's demand priced
-- into it. LIFT stays per source, because the field reports the BEST head reaching the tile and that
-- may be coming from some other, higher source.
-- statusOnly keeps the water behind the tile visible even when the solve excluded this consumer: the
-- answer is shared with every consumer on the level, so one starved emitter must not empty it.
local function applyPressureGate(descriptors, originSquare, kind, solution, zoneLift, statusOnly)
    local enabled = Pressure.isEnabled()
    if not enabled then
        return descriptors, Pressure.containerBase()
    end

    -- Hydraulics.canDrawAt, not a head comparison of our own: an excluded consumer reads a healthy head
    -- precisely BECAUSE it was excluded, so re-deriving it here lets every starved emitter through.
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

-- Which containers can fluid entering at originSquare reach? Only lift is priced (Pressure.canFillTo).
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

-- Re-shape a solved zone into what the descriptor builders already take: a list of squares, a hop
-- count per square key, and a `zone` of the pumps and inlets in it. A projection, not a second pass.
local function squaresFromSolution(solution, originSquare)
    -- By reference, not rebuilt: these are properties of the zone, identical for every consumer on it.
    local pipeSquares = Hydraulics.pipeSquares(solution)

    -- Hop counts stay measured FROM THE CONSUMER, which is what nearest-vessel draw order means. Walked
    -- over the solved adjacency instead of the world: pure Lua, zero bridge calls.
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

    -- Which way the water is travelling, which decides how a bare router may be crossed.
    -- Visualization asks for neither and keeps every router solid.
    local conduct = nil
    if fill then
        conduct = "fill"
    elseif kind then
        conduct = "draw"
    end

    -- A DRAW query takes its topology from the hydraulic solve, shared by every consumer on the zone.
    -- Fills and visualization keep the per-origin walk: they ask where water can GO from here.
    local pipeSquares, hops, zone, chains, walkEntry
    local solution = nil
    if kind and not fill then
        solution = Hydraulics.solveAt(originSquare)
        if not solution then
            return nil
        end
        pipeSquares, hops, zone = squaresFromSolution(solution, originSquare)
    else
        local mark = fill and markPhase() or nil
        pipeSquares, hops, zone, chains, walkEntry =
            collectPipeSquaresCached(originSquare, verticalMode, conduct)
        sincePhase("fill/walk", mark)
    end
    if #pipeSquares == 0 then
        return nil
    end

    -- Split under the profiler so its cost can be located, not guessed at. The DRAW path was left
    -- untimed and that hid where a tap's summary spends its time -- 7.6 ms of it, once a minute.
    local descriptorMark = markPhase()
    local descriptorMap = collectStorageDescriptors(pipeSquares, hops, chains, solution, walkEntry)
    sincePhase(fill and "fill/descriptors" or "draw/descriptors", descriptorMark)
    addPurifierOutletDescriptors(descriptorMap, zone)
    local descriptors = normalizeDescriptorList(descriptorMap)
    if #descriptors == 0 then
        return nil
    end

    -- Visualization asks for neither gate and sees the whole physical network.
    local pressure = nil
    if kind or fill then
        -- How far water entering here can be pushed UPHILL. Fills are never regulated, so the whole zone's
        -- lift counts; a live inlet or open hydrant is a floor the pumps do not have to find.
        local liftHead = math.max(Pump.headForPumps(zone.pumps), zone.supplyHead or 0)
        if fill then
            local gateMark = markPhase()
            descriptors = applyFillGate(descriptors, originSquare, liftHead)
            sincePhase("fill/gate", gateMark)
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

    -- TAINTED WINS. A network holding both is not "mixed", it is tainted -- one litre of dirty water is
    -- enough. Treating it as mixed made the network refuse to deliver anything at all.
    -- Only the WATER FAMILY collapses this way; petrol beside water stays a hard refusal.
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
    -- A tap draws only what gravity can bring it: its own floor plus anything above that drains down.
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

-- What a network holding `current` becomes once `incoming` is added, or nil if the two must not meet.
-- Contamination travels one way only: tainted ruins a clean line, clean does not rinse a tainted one.
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

-- Take the purifier OUT buffers out of a summary and recompute its totals.
-- Their writer refuses anything but clean Water, and a refusal DURING a rebalance is too late: the
-- share it refuses would be litres conjured or destroyed. They must leave before the arithmetic.
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

-- Spread `remainingAmount` over the summary's vessels in proportion to their capacity.
-- CARRY: a write under Constants.FLUID_WRITE_EPSILON is skipped, but the caller has already been told
-- it drew those litres, so they roll to the next vessel and the last one absorbs the rest. Overflow
-- from a vessel at capacity uses the same carry.
-- WRITE-BACK: descriptors and totals are updated to what actually landed, so a second draw from the
-- same summary does not price itself against water the first one took.
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
            -- Skipped or refused: the vessel still holds what it held, and the difference rolls to the next one.
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

-- Turn every water vessel connected to `originSquare` tainted in one pass, keeping each one's amount.
-- Tainting the whole network at once is what keeps redistribution from seeing a half-and-half network
-- and refusing to settle it. Returns the litres turned.
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

-- Even the stored water out across the network without adding or removing any; returns litres moved.
-- The purifier needs it: a network otherwise settles only when something draws from it or fills it,
-- so a purifier feeding barrels nobody drinks from would stall at a full buffer.
function NetworkAccess.settleAtSquare(originSquare)
    local summary = buildSummaryFromSquare(originSquare, nil, true)
    if not summary or summary.isMixed or (summary.totalAmount or 0) <= 0 then
        return 0
    end
    if #summary.descriptors < 2 then
        return 0   -- nothing to even out against
    end

    -- Already level? Touch nothing. rebalanceSummary rewrites every vessel it is given -- empty, refill,
    -- sync, transmit -- so running it once a minute per purifier would be a steady stream of packets.
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

-- For visualization: the tiles of the physically-connected network, both directions, routers solid.
-- No descriptors -- building those reads the fluid in every vessel on the network, and the callers
-- that wanted only the tiles were throwing them away.
function NetworkAccess.getNetworkSquares(originSquare)
    local pipeSquares = collectPipeSquaresCached(originSquare, "both")
    return pipeSquares
end

function NetworkAccess.getNetworkFromSquare(originSquare)
    local pipeSquares, hops = collectPipeSquaresCached(originSquare, "both")
    local descriptors = normalizeDescriptorList(collectStorageDescriptors(pipeSquares, hops))
    return pipeSquares, descriptors
end

-- Best head (m.c.a.) available to a `kind` consumer standing on `square`, or nil if nothing reaches it.
function NetworkAccess.getPressureAtSquare(square, kind)
    -- Straight to the head field: a lookup on a solve the zone already shares.
    return Hydraulics.pressureAt(Hydraulics.solveAt(square), square,
        kind or Constants.PRESSURE_KIND_TAP)
end

-- Everything the pressure model knows about one point, for the debug readout. The gauge answers
-- "how much?"; this answers "why?" -- FLOW being the field that explains a starved far end.
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
                -- Two different numbers. `staticHead` is what gravity alone gives this vessel here; `supplyHead` is
                -- the pressure it actually pushes at, pumps included. Without the second, every barrel on a farm with
                -- two pumps read the same figure and looked like the reason the far end was dry.
                staticHead = containerBase + levelHead * ((descriptor.z or 0) - consumerZ),
                supplyHead = descriptor.nodeKey and solution.supply[descriptor.nodeKey]
                    and (solution.supply[descriptor.nodeKey] - levelHead * (descriptor.z or 0))
                    or nil,
            }
        end
    end
    report.containerCount = #report.sources

    -- Reported separately from the head, because the two can disagree and that disagreement is the whole
    -- story: a starved tile reads a comfortable head, since the field it reads excludes its own draw.
    report.starvedHere = Hydraulics.isStarvedAt(solution, square)

    -- ...and, if starved, whether it COULD be served: everything already watering plus this one.
    -- Not the same claim. The servable set is a binary search over a PREFIX, so once one consumer cannot
    -- be served every consumer after it is dropped too -- including ones that would have been fine. This
    -- is what tells "the line cannot carry it" from "the search gave up before reaching it".
    if report.starvedHere and Hydraulics.couldServeAlso then
        local kindHere = solution.kinds and solution.kinds[Hydraulics.nodeKeyOf(square)] or nil
        local servable, blocker = Hydraulics.couldServeAlso(solution, square, kindHere)
        report.couldServeHere = servable
        report.serveBlockedBy = blocker
    end

    for _, kind in ipairs({ Constants.PRESSURE_KIND_TAP, Constants.PRESSURE_KIND_DRIP,
        Constants.PRESSURE_KIND_SPRINKLER }) do
        local canDraw, head = Hydraulics.canDrawAt(solution, square, kind)
        local minimum = Pressure.minimumFor(kind)
        report.kinds[kind] = {
            head = head,
            minimum = minimum,
            canDraw = canDraw,
            -- Loss per tile is what this tile's actual flow costs, not a constant of the consumer.
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
    -- Clean water may always join a tainted line; only a genuinely incompatible fluid is refused.
    local merged = mergeFluidNames(summary.fluidTypeName, fluidType)
    if (summary.totalAmount or 0) > 0 and summary.fluidTypeName and not merged then
        return 0
    end
    -- What the line would hold after the push. Anything but clean Water and the purifier buffers stand
    -- aside: their headroom must not be promised to a fill their writer will refuse.
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

-- The summary a consumer standing on `square` needs, built ONCE. It already carries every answer the
-- three separate queries wanted: `pressure`, `totalAmount` + `fluidTypeName`, and `descriptors`.
-- LIVE: drawFromSummary updates it in place, so repeated draws see what the previous one left. Do not
-- hold one across a frame, or across anything that could move water behind its back.
function NetworkAccess.getDrawSummary(square, kind)
    return buildSummaryFromSquare(square, "both", kind or Constants.PRESSURE_KIND_TAP)
end

-- The same summary, shared by every consumer on the zone standing at the same LEVEL.
-- READ-ONLY, not for draws: the descriptors carry the hop counts of whichever consumer built it first
-- and a draw orders by those. getDrawSummary stays the way to take water.
-- Sound because the only per-consumer term in the gate is elevation -- three numbers, none of them the
-- tile. test_hydraulics.lua test 13 pins that; if it fails, this function is invalid.
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
-- Deliberately NOT a rebalance: re-levelling on every sip made the vessel count a term in the cost of
-- every draw, and every write is also a packet in multiplayer.
-- The nearest vessels are emptied instead, one before the next -- which is what a real line does, and
-- gravity settle (System.redistributeWater) is what evens the network out.
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
        -- Same distance: drain the fullest first, so the network settles toward level rather than away from it.
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
        -- writeWorldFluidAmount empties the vessel and only refills it when given a type, so a positive
        -- amount with no type would destroy the remainder outright.
        local fluidTypeName = nil
        if target > 0 then
            fluidTypeName = descriptor.fluidType or summary.fluidTypeName
            if not fluidTypeName then
                -- Unknown fluid and water still in the vessel: leave it alone rather than risk it.
                break
            end
        end

        -- Nothing has moved yet: the caller is about to be told it drew these litres, so the write must land.
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

-- Draw up to `amount` of `requiredFluidType` from the network reachable from `originSquare`. Only
-- works on a single-fluid network whose fluid matches. Returns the amount actually drawn.
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

    -- A non-empty network takes the incoming fluid only if the two can share a pipe: water and tainted
    -- water always can, so only a real clash (petrol into water) is refused.
    local merged = mergeFluidNames(summary.fluidTypeName, fluidType)
    if (summary.totalAmount or 0) > 0 and summary.fluidTypeName and not merged then
        return 0
    end

    -- An empty network adopts the incoming fluid type; a stocked one takes the merged result.
    local landing = (summary.totalAmount or 0) <= 0 and fluidType or merged

    -- The purifier's clean buffers leave the summary before the arithmetic when what lands is not clean
    -- Water, so the rebalance is computed over the vessels that will actually take it.
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

    -- Same nearest-vessel draw a sprinkler uses: one vessel write instead of one per vessel on the line.
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

    -- Same rule as fillFluidAtSquare: the purifier's clean buffers step out first.
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

-- Anything that changes what the walk would FIND has to drop it. The object events do it by tile;
-- router direction, ceilings and hydrant toggles call the global drop directly.
-- OnTick drops only the two memos that hold fluid or are keyed to a solve.
if Events then
    if Events.OnObjectAdded then
        Events.OnObjectAdded.Add(NetworkAccess.invalidateAroundObject)
    end
    if Events.OnObjectAboutToBeRemoved then
        Events.OnObjectAboutToBeRemoved.Add(NetworkAccess.invalidateAroundObject)
    end
    -- A square the engine rebuilt while streaming: its objects were never announced one by one.
    if Events.LoadGridsquare then
        Events.LoadGridsquare.Add(NetworkAccess.invalidateAroundSquare)
    end
    if Events.OnTick then
        Events.OnTick.Add(dropFrameMemos)
    end
end
