#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Stress-test simulator for the WaterPipes PZ mod (build 42.15).

It does NOT run Lua. It replicates, call for call, the control flow of the mod's
hot paths and counts every Lua -> Java bridge call (getGridSquare, getObjects,
getModData, getSprite, instanceof, pcall'd accessors...). Those bridge calls are
what actually costs time in PZ's Kahlua VM; pure Lua arithmetic is noise next to
them.

Cost model: 1 bridge call (BC) = 0.8 us nominal (range 0.3 - 2.0 us).
Frame budget at 60 FPS = 16.7 ms. PZ runs Lua on the main thread.
"""

from collections import defaultdict
import sys

# ----------------------------------------------------------------------------
# Counters
# ----------------------------------------------------------------------------
BC = defaultdict(int)          # bridge calls, by bucket
CALLS = defaultdict(int)       # function invocation counts


def bc(bucket, n=1):
    BC[bucket] += n


def reset():
    BC.clear()
    CALLS.clear()


def total_bc():
    return sum(BC.values())


# ----------------------------------------------------------------------------
# World model
# ----------------------------------------------------------------------------
class Obj:
    __slots__ = ("pipe", "router", "pump", "riser", "container", "endpoint",
                 "hydrant", "purifier", "drip", "sprinkler", "well", "plumbed",
                 "mains_fixture")

    def __init__(self, **kw):
        for s in self.__slots__:
            setattr(self, s, kw.get(s, False))


class Square:
    __slots__ = ("x", "y", "z", "objects")

    def __init__(self, x, y, z, objects):
        self.x, self.y, self.z = x, y, z
        self.objects = objects


class World:
    def __init__(self, filler_objects=4):
        # filler_objects = floor + walls + furniture already on a tile
        self.squares = {}
        self.filler = filler_objects

    def key(self, x, y, z):
        return (x, y, z)

    def ensure(self, x, y, z):
        k = (x, y, z)
        sq = self.squares.get(k)
        if sq is None:
            sq = Square(x, y, z, [Obj() for _ in range(self.filler)])
            self.squares[k] = sq
        return sq

    def add(self, x, y, z, obj):
        self.ensure(x, y, z).objects.append(obj)


WORLD = None


def getGridSquare(x, y, z):
    bc("getGridSquare")
    return WORLD.squares.get((x, y, z))


# ----------------------------------------------------------------------------
# PipeObjectUtils
# ----------------------------------------------------------------------------
def isPipeObject(o):
    # instanceof(IsoThumpable) + getModData [+ getName]
    bc("isPipeObject", 1)              # instanceof
    if not o.pipe:
        return False                    # non-thumpables bail on the instanceof
    bc("isPipeObject", 1)              # getModData
    return True


# Both caches live for exactly one frame, matching the Lua: PipeObjectUtils drops its
# scan memo and NetworkAccess drops its traversal cache on OnTick, plus explicitly
# whenever the pipe layout changes. frame_reset() is that boundary.
PIPE_SCAN_MEMO = {}
TRAVERSAL_CACHE = {}
# ContainerAdapter's vessel memo: which objects on a square are network storage, and
# their capacity. Same one-frame lifetime and the same invalidation events. Only the
# classification is remembered -- the amount and the fluid type are read fresh on
# every call, which is why collectSquareContainers still costs something on a hit.
VESSEL_MEMO = {}


def frame_reset():
    PIPE_SCAN_MEMO.clear()
    TRAVERSAL_CACHE.clear()
    VESSEL_MEMO.clear()


def getPipeObjectsOnSquare(sq):
    CALLS["getPipeObjectsOnSquare"] += 1
    if sq is None:
        return []
    k = (sq.x, sq.y, sq.z)
    hit = PIPE_SCAN_MEMO.get(k)
    if hit is not None:
        CALLS["pipeScanMemoHit"] += 1
        return hit
    bc("getObjects", 1)
    out = []
    for o in sq.objects:
        bc("getObjects", 1)             # objects:get(i)
        if isPipeObject(o):
            out.append(o)
    PIPE_SCAN_MEMO[k] = out
    return out


def getPipeOnSquare(sq):
    p = getPipeObjectsOnSquare(sq)
    return p[0] if p else None


def isWallCover(o):
    if not isPipeObject(o):
        return False
    bc("getModData", 1)
    return o.riser


def riserEdgesAt(x, y, z):
    CALLS["riserEdgesAt"] += 1
    sq = getGridSquare(x, y, z)
    if sq is None:
        return (False, False)
    n = w = False
    for o in getPipeObjectsOnSquare(sq):
        if isWallCover(o):
            bc("getModData", 1)
            n = True
    return (n, w)


def getRiserVerticalNeighborCoords(x, y, z):
    """5 riserEdgesAt calls per invocation -- 5 square lookups + 5 pipe scans."""
    CALLS["getRiserVerticalNeighborCoords"] += 1
    coords = []
    n, w = riserEdgesAt(x, y, z)
    if n:
        coords += [(x, y, z + 1), (x, y - 1, z + 1)]
    if w:
        coords += [(x, y, z + 1), (x - 1, y, z + 1)]
    a = riserEdgesAt(x, y, z - 1)
    b = riserEdgesAt(x, y, z - 1)      # the source really calls it twice (line 152)
    if a[0] or b[1]:
        coords.append((x, y, z - 1))
    if riserEdgesAt(x, y + 1, z - 1)[0]:
        coords.append((x, y + 1, z - 1))
    if riserEdgesAt(x + 1, y, z - 1)[1]:
        coords.append((x + 1, y, z - 1))
    return coords


# ----------------------------------------------------------------------------
# EndpointObjects / ContainerAdapter
# ----------------------------------------------------------------------------
def isEndpointCandidate(o):
    CALLS["isEndpointCandidate"] += 1
    if isPipeObject(o):
        return False
    bc("isEndpointCandidate", 1)       # instanceof IsoWorldInventoryObject
    bc("isEndpointCandidate", 1)       # getSquare
    bc("isEndpointCandidate", 3)       # isWaterAppliance: 3 pcall'd instanceof
    bc("isEndpointCandidate", 3)       # getSprite + getProperties + has(waterPiped)
    if o.endpoint:
        return True
    bc("isEndpointCandidate", 1)       # getModData
    bc("isEndpointCandidate", 2)       # 2 x readBoolean pcall
    return False


def getDirectWorldFluidKind(o):
    bc("fluidKind", 1)                 # getModData (isExcludedWorldObject)
    bc("fluidKind", 1)                 # instanceof IsoWorldInventoryObject
    bc("fluidKind", 3)                 # isExcludedAppliance: 3 pcall'd instanceof
    bc("fluidKind", 1)                 # getFluidContainer (pcall)
    if not o.container:
        return False
    bc("fluidKind", 3)                 # capacity reads: getFluidCapacity/reserve/getCapacity
    return "worldFluid"


def classifySquareVessels(sq):
    """Adapter.classifySquareVessels: the expensive half, memoised per frame.

    This used to be the single most expensive per-square routine in the mod, and it
    ran on every network summary. The classification cannot change unless an object
    joins or leaves the tile, and both raise events -- so it is remembered.
    """
    CALLS["classifySquareVessels"] += 1
    bc("getObjects", 1)
    out = []
    for i, o in enumerate(sq.objects):
        bc("getObjects", 1)
        if isEndpointCandidate(o):
            continue
        bc("isExcludedByName", 1)      # pcall getName
        if getDirectWorldFluidKind(o):
            bc("descriptor", 1)        # capacity read (fixed, so it is memoised too)
            out.append((i, o))
    return out


def classifySquareVesselsCached(sq):
    k = (sq.x, sq.y, sq.z)
    hit = VESSEL_MEMO.get(k)
    if hit is not None:
        CALLS["vesselMemoHit"] += 1
        return hit
    out = classifySquareVessels(sq)
    VESSEL_MEMO[k] = out
    return out


def hasSquareContainers(sq):
    """Adapter.hasSquareContainers: classification only, no fluid read."""
    if sq is None:
        return False
    return bool(classifySquareVesselsCached(sq))


def collectSquareContainers(sq):
    CALLS["collectSquareContainers"] += 1
    if sq is None:
        return {}
    res = {}
    for i, o in classifySquareVesselsCached(sq):
        # Read fresh every time, memo or no memo: a stale amount would conjure water.
        bc("descriptor", 3)            # amount + fluid type reads
        res[(sq.x, sq.y, sq.z, i)] = {"z": sq.z, "obj": o}
    return res


def collectOnSquare_endpoints(sq):
    CALLS["EndpointObjects.collectOnSquare"] += 1
    if sq is None:
        return []
    bc("getObjects", 1)
    out = []
    for o in sq.objects:
        bc("getObjects", 1)
        if isEndpointCandidate(o):
            out.append(o)
    return out


# ----------------------------------------------------------------------------
# Device lookups
# ----------------------------------------------------------------------------
def findOnSquare_generic(sq, attr, per_obj_cost):
    if sq is None:
        return None
    bc("getObjects", 1)
    for o in sq.objects:
        bc("getObjects", 1)
        bc("deviceProbe", per_obj_cost)
        if getattr(o, attr):
            return o
    return None


def Router_findOnSquare(sq):
    CALLS["Router.findOnSquare"] += 1
    for o in getPipeObjectsOnSquare(sq):
        bc("getModData", 1)
        if o.router:
            return o
    return None


def Router_hasRouterOnSquare(sq):
    return Router_findOnSquare(sq) is not None


def Pump_findOnSquare(sq):
    CALLS["Pump.findOnSquare"] += 1
    for o in getPipeObjectsOnSquare(sq):
        bc("getModData", 1)
        if o.pump:
            return o
    return None


def Hydrant_findOnSquare(sq):
    CALLS["Hydrant.findOnSquare"] += 1
    # getObjects + spriteName (2 pcalls: getSprite, getName) per object
    return findOnSquare_generic(sq, "hydrant", 2)


def Purifier_findOnSquare(sq):
    CALLS["Purifier.findOnSquare"] += 1
    return findOnSquare_generic(sq, "purifier", 1)   # getModData


def Purifier_findForRouterSquare(sq):
    CALLS["Purifier.findForRouterSquare"] += 1
    if sq is None:
        return None
    for dx, dy in ((0, 0), (1, 0), (0, 1), (1, 1)):
        s = sq if (dx == 0 and dy == 0) else getGridSquare(sq.x + dx, sq.y + dy, sq.z)
        p = Purifier_findOnSquare(s)
        if p:
            return p
    return None


MAINS_PROBE_CACHE = {}


def Mains_isLiveAt(o, sq, use_cache=True):
    bc("mains", 1)                     # getModData
    if not o.plumbed:
        return False
    # isMainsFixture: getSquare, getRoom, isNoWater, hasProperty, getUsesExternal
    bc("mains", 5)
    if not o.mains_fixture:
        return False
    k = (sq.x, sq.y, sq.z)
    if use_cache and k in MAINS_PROBE_CACHE:
        bc("mains", 1)                 # getTimestampMs
        return MAINS_PROBE_CACHE[k]
    bc("mains", 4)                     # probe: 2 x getFluidCapacity + 2 modData writes
    MAINS_PROBE_CACHE[k] = True
    return True


def Mains_findOnSquare(sq):
    CALLS["Mains.findOnSquare"] += 1
    if sq is None:
        return None
    bc("getObjects", 1)
    for o in sq.objects:
        bc("getObjects", 1)
        if Mains_isLiveAt(o, sq):
            return o
    return None


def Irrigation_findDripOnSquare(sq):
    CALLS["Irrigation.findDrip"] += 1
    for o in getPipeObjectsOnSquare(sq):
        bc("getModData", 1)
        if o.drip:
            return o
    return None


def Irrigation_findSprinklerOnSquare(sq):
    CALLS["Irrigation.findSprinkler"] += 1
    for o in getPipeObjectsOnSquare(sq):
        bc("getModData", 1)
        if o.sprinkler:
            return o
    return None


# ----------------------------------------------------------------------------
# NetworkAccess: the BFS
# ----------------------------------------------------------------------------
CARDINAL = ((1, 0), (-1, 0), (0, 1), (0, -1))


def routerIsHardBoundary(sq):
    if Purifier_findForRouterSquare(sq):
        return True
    # Only needs a yes/no, so it asks the classification and never reads a fluid.
    return hasSquareContainers(sq)


def collectPipeSquaresFromSquare(origin, conduct=False):
    """Faithful port of NetworkAccess.collectPipeSquaresFromSquare."""
    CALLS["BFS"] += 1
    if origin is None:
        return [], {}
    visited = set()
    queue = []
    hops = {}
    pipe_squares = []

    def tryAdd(sq, dist):
        if sq is None:
            return
        if getPipeOnSquare(sq) is None:          # hasPipeOnSquare -> full pipe scan
            return
        if Router_hasRouterOnSquare(sq):         # 2nd full pipe scan
            return
        k = (sq.x, sq.y, sq.z)
        if k in visited:
            return
        visited.add(k)
        queue.append(sq)
        hops[k] = dist
        pipe_squares.append(sq)
        Pump_findOnSquare(sq)                    # 3rd pipe scan
        Mains_findOnSquare(sq)                   # full object scan
        Hydrant_findOnSquare(sq)                 # full object scan + 2 pcalls/obj

    def visit(sq, dist):
        if sq is None:
            return
        if Router_hasRouterOnSquare(sq):         # pipe scan on every neighbour
            if conduct:
                routerIsHardBoundary(sq)
                Router_findOnSquare(sq)
            return
        tryAdd(sq, dist)

    def addNeighborsOf(x, y, z, dist):
        for dx, dy in CARDINAL:
            visit(getGridSquare(x + dx, y + dy, z), dist)
        for (cx, cy, cz) in getRiserVerticalNeighborCoords(x, y, z):
            visit(getGridSquare(cx, cy, cz), dist)

    tryAdd(origin, 0)
    addNeighborsOf(origin.x, origin.y, origin.z, 1)
    i = 0
    while i < len(queue):
        cur = queue[i]
        i += 1
        addNeighborsOf(cur.x, cur.y, cur.z, hops[(cur.x, cur.y, cur.z)] + 1)
    return pipe_squares, hops


def collectStorageDescriptors(pipe_squares):
    scanned = set()
    desc = {}
    for sq in pipe_squares:
        k = (sq.x, sq.y, sq.z)
        if k in scanned:
            continue
        scanned.add(k)
        desc.update(collectSquareContainers(sq))
    return desc


def collectPipeSquaresCached(origin, conduct=False):
    """NetworkAccess.collectPipeSquaresCached.

    Keyed per ORIGIN, not per network: hop counts and regulator chains are measured
    from the consumer, so two consumers on the same network cannot share a walk.
    """
    if origin is None:
        return [], {}
    k = ((origin.x, origin.y, origin.z), conduct)
    hit = TRAVERSAL_CACHE.get(k)
    if hit is not None:
        CALLS["traversalCacheHit"] += 1
        return hit
    result = collectPipeSquaresFromSquare(origin, conduct)
    TRAVERSAL_CACHE[k] = result
    return result


def buildSummaryFromSquare(origin, kind=None, fill=False):
    CALLS["buildSummary"] += 1
    # Matches the Lua: nil / "draw" / "fill". A fill walk now crosses bare routers
    # too (downstream), which also means it pays the hard-boundary check.
    conduct = "fill" if fill else ("draw" if kind else None)
    pipe_squares, hops = collectPipeSquaresCached(origin, conduct)
    if not pipe_squares:
        return None
    # Deliberately NOT cached: the fluid amounts have to be read fresh every time,
    # or a draw and the fill after it would disagree about how much is in the pipes.
    desc = collectStorageDescriptors(pipe_squares)
    if not desc:
        return None
    return {"descriptors": desc, "pipeSquares": pipe_squares}


# One vessel write: resolveFluidTarget (sprite-grid scan) + emptyFluid + addFluid
# + sync + transmitModData + fireExternalWaterChange (read + triggerEvent).
WRITE_BC = 8


def rebalanceSummary(summary):
    """Fills still level the whole network: every vessel takes a share."""
    bc("fluidWrite", WRITE_BC * len(summary["descriptors"]))


def drawFromSummary(summary):
    """Draws empty the nearest vessels instead of re-levelling everything.

    This is what stops the vessel count being a performance setting. A sprinkler
    taking its 1.8 L used to rewrite every barrel on the line; it now writes one.
    """
    if not summary["descriptors"]:
        return
    bc("fluidWrite", WRITE_BC)


def availableToPull(sq):
    return buildSummaryFromSquare(sq, kind="tap")


def availableToPush(sq):
    return buildSummaryFromSquare(sq, fill=True)


def drawFluidAtSquare(sq):
    s = buildSummaryFromSquare(sq, kind="tap")
    if s:
        drawFromSummary(s)
    return s


def fillFluidAtSquare(sq):
    s = buildSummaryFromSquare(sq, fill=True)
    if s:
        rebalanceSummary(s)
    return s


def getPressureAtSquare(sq, kind):
    return buildSummaryFromSquare(sq, kind=kind)


def getNetworkFromSquare(sq):
    ps, hops = collectPipeSquaresFromSquare(sq, False)
    collectStorageDescriptors(ps)
    return ps


# ----------------------------------------------------------------------------
# Scenario builder
# ----------------------------------------------------------------------------
class Scenario:
    """A plausible player base: a spine of pipes with branches, barrels every
    `container_every` tiles, sinks, routers, pumps and emitters."""

    def __init__(self, pipes, containers, endpoints, routers, pumps,
                 emitters, mains_inlets, filler=4, z=0):
        global WORLD, MAINS_PROBE_CACHE
        WORLD = World(filler_objects=filler)
        MAINS_PROBE_CACHE = {}
        self.pipe_coords = []
        self.z = z

        # Serpentine layout, 20 tiles wide: realistic for a farm/base run.
        w = 20
        for i in range(pipes):
            row, col = divmod(i, w)
            x = col if row % 2 == 0 else (w - 1 - col)
            y = row
            self.pipe_coords.append((x, y, z))
            WORLD.add(x, y, z, Obj(pipe=True))

        # Hand out DISTINCT pipe tiles to each device class, round-robin, so no
        # two devices land on the same square.
        self._cursor = 0

        def claim(n):
            """n distinct pipe tiles, spread evenly over the run."""
            if n <= 0:
                return []
            out = []
            step = max(1, pipes // max(n, 1))
            for i in range(n):
                idx = (i * step + self._cursor) % pipes
                out.append(self.pipe_coords[idx])
            self._cursor += 1
            return out

        self.containers = claim(containers)
        for (x, y, zz) in self.containers:
            WORLD.add(x, y, zz, Obj(container=True))

        self.routers = claim(routers)
        for (x, y, zz) in self.routers:
            for o in WORLD.squares[(x, y, zz)].objects:
                if o.pipe and not (o.router or o.pump or o.drip):
                    o.router = True
                    break

        self.pumps = claim(pumps)
        for (x, y, zz) in self.pumps:
            for o in WORLD.squares[(x, y, zz)].objects:
                if o.pipe and not (o.router or o.pump or o.drip):
                    o.pump = True
                    break

        self.emitters = claim(emitters)
        for (x, y, zz) in self.emitters:
            for o in WORLD.squares[(x, y, zz)].objects:
                if o.pipe and not (o.router or o.pump or o.drip):
                    o.drip = True
                    break

        # Endpoints (sinks) sit on their own tile, adjacent to a pipe.
        self.endpoints = []
        for (x, y, zz) in claim(endpoints):
            ex, ey = x, y - 1
            WORLD.add(ex, ey, zz, Obj(endpoint=True, plumbed=True))
            self.endpoints.append((ex, ey, zz))

        self.mains = []
        for (x, y, zz) in claim(mains_inlets):
            WORLD.add(x, y, zz, Obj(endpoint=True, plumbed=True, mains_fixture=True))
            self.mains.append((x, y, zz))

        self.n_pipes = pipes


# ----------------------------------------------------------------------------
# The mod's periodic passes
# ----------------------------------------------------------------------------
def pass_refreshPlumbedEndpoints(sc):
    """WaterPipeSystem.refreshPlumbedEndpoints -- runs EVERY in-game minute
    AND again inside System.tick every ten minutes."""
    coords = []
    for (x, y, z) in sc.pipe_coords:
        coords.append((x, y, z))
        for dx, dy, dz in ((1,0,0), (-1,0,0), (0,1,0), (0,-1,0), (0,0,1), (0,0,-1)):
            coords.append((x + dx, y + dy, z + dz))

    # refreshPlumbedEndpointsNearCoordinates. The `visited` set DOES stop the
    # endpoint from being re-synced, but it is consulted only AFTER the
    # expensive collectOnSquare scan -- so the scan itself still runs once per
    # duplicate coordinate (and the list has no dedup).
    visited = set()
    for (x, y, z) in coords:
        sq = getGridSquare(x, y, z)
        if sq is None:
            continue
        for i, ep in enumerate(collectOnSquare_endpoints(sq)):
            key = (x, y, z, i)
            if key in visited:
                continue
            bc("getModData", 1)                # isPlumbed
            if ep.plumbed:
                visited.add(key)
                refreshEndpointSource(ep, sq)

    # refreshPlumbedGeneratorsNearCoordinates -- the whole list AGAIN
    for (x, y, z) in coords:
        sq = getGridSquare(x, y, z)
        if sq is None:
            continue
        bc("getObjects", 1)
        for o in sq.objects:
            bc("getObjects", 1)
            bc("isGenerator", 2)


SEEN_ENDPOINT = set()


def refreshEndpointSource(ep, sq):
    CALLS["refreshEndpointSource"] += 1
    bc("endpointRefresh", 2)               # modData clear + AdapterSource.removeForEndpoint
    getPipeOnSquare(sq)                    # hasPipeOnEndpointSquare
    bc("endpointRefresh", 4)               # setCanBeWaterPiped / setUsesExternalWaterSource
    # syncForEndpoint:
    bc("endpointRefresh", 2)               # reconcileConsumption reads
    buildSummaryFromSquare(sq, kind="tap")  # <-- FULL BFS per endpoint
    bc("endpointRefresh", 10)              # writeSnapshot: Empty/setCapacity/addFluid/lock/sync/transmit


def pass_processRouters(sc):
    for (x, y, z) in sc.pipe_coords:
        sq = getGridSquare(x, y, z)
        r = Router_findOnSquare(sq)
        if not r:
            continue
        out = (0, -1)
        insq = getGridSquare(x - out[0], y - out[1], z)
        outsq = getGridSquare(x + out[0], y + out[1], z)
        if insq is None or outsq is None:
            continue
        p = Purifier_findForRouterSquare(sq)
        if p:
            # Step 1 is now settleAtSquare(): ONE fill summary, where the old
            # push did availableToPush + fillFluidAtSquare (two walks).
            availableToPush(outsq)
            availableToPull(insq); drawFluidAtSquare(insq)
        else:
            availableToPull(insq)          # BFS 1
            availableToPush(outsq)         # BFS 2
            drawFluidAtSquare(insq)        # BFS 3
            fillFluidAtSquare(outsq)       # BFS 4


def pass_processPumps(sc):
    for (x, y, z) in sc.pipe_coords:
        sq = getGridSquare(x, y, z)
        pump = Pump_findOnSquare(sq)
        if not pump:
            continue
        bc("pumpPower", 2)                 # haveElectricity + getModData
        # Pump.findSource: 3 z-levels x 5 squares
        for drop in range(3):
            for dx, dy in ((0, 0),) + CARDINAL:
                s = getGridSquare(x + dx, y + dy, z - drop)
                if s is None:
                    continue
                bc("getObjects", 1)
                for o in s.objects:
                    bc("getObjects", 1)
                    bc("wellProbe", 2)     # entityNameOf: 2 pcalls
                bc("openWater", 2)         # getFloor + hasProperty
        # no source found in this scenario -> booster only, returns early.
        # For a scenario WITH a source the cost below applies:
        if getattr(sc, "pumps_have_source", False):
            availableToPush(sq)                      # BFS 1
            ps = getNetworkFromSquare(sq)            # BFS 2
            for s in ps:                             # 6 neighbours per pipe square!
                for dx, dy, dz in ((1,0,0), (-1,0,0), (0,1,0), (0,-1,0), (0,0,1), (0,0,-1)):
                    ns = getGridSquare(s.x + dx, s.y + dy, s.z + dz)
                    Router_findOnSquare(ns)
            fillFluidAtSquare(sq)                    # BFS 3


def pass_processAllMains(sc):
    for (x, y, z) in sc.pipe_coords:
        sq = getGridSquare(x, y, z)
        if Mains_findOnSquare(sq):
            availableToPush(sq)
            fillFluidAtSquare(sq)


def pass_scanContainersAroundPipes(sc):
    for (x, y, z) in sc.pipe_coords:
        sq = getGridSquare(x, y, z)
        if sq:
            collectSquareContainers(sq)


def pass_rebuildGraph(sc):
    for (x, y, z) in sc.pipe_coords:
        bc("graph", 1)                     # addNode
        for dx, dy in CARDINAL:
            bc("graph", 1)                 # isRouterAt + connect (table ops)
        getRiserVerticalNeighborCoords(x, y, z)


def pass_redistributeWater(sc):
    # one component -> every container node re-scans its square from scratch
    for (x, y, z) in sc.containers:
        sq = getGridSquare(x, y, z)
        collectSquareContainers(sq)
    bc("fluidWrite", 8 * len(sc.containers))


def pass_irrigation(sc):
    """Irrigation.run: one summary per emitter, and one vessel write per draw.

    Each emitter used to build three identical summaries -- pressure, availability,
    draw -- and then re-level every vessel on the network. It now builds one and
    empties the nearest vessel.

    The real pass is handed out a few emitters per frame (Irrigation.beginPass), so
    this total is spread over IRRIGATION_EMITTERS_PER_TICK-sized slices rather than
    landing in one. The work is the same; only the frame it lands in moves.
    """
    for (x, y, z) in sc.pipe_coords:
        sq = getGridSquare(x, y, z)
        d = Irrigation_findDripOnSquare(sq)
        if d:
            s = buildSummaryFromSquare(sq, kind="drip")   # the only BFS
            if s:
                drawFromSummary(s)
        Irrigation_findSprinklerOnSquare(sq)


# ---------------------------------------------------------------------------
# Client tile registry (WaterPipesTileRegistry.lua)
#
# The client modules used to sweep a square block around the player and scan
# every tile. They now read a registry populated by LoadGridsquare / OnObjectAdded
# and re-validate each remembered tile on read.
# ---------------------------------------------------------------------------
REGISTRY = {"emitters": set(), "hydrants": set(), "purifiers": set()}
STATUS_CACHE = {}          # tile -> status; cleared between "seconds"
STATUS_TTL_HITS = True     # False = model a cold cache (worst case)

_FINDERS = {
    "emitters": lambda sq: (Irrigation_findSprinklerOnSquare(sq)
                            or Irrigation_findDripOnSquare(sq)),
    "hydrants": Hydrant_findOnSquare,
    "purifiers": Purifier_findOnSquare,
}


def registry_reset():
    REGISTRY["emitters"] = set()
    REGISTRY["hydrants"] = set()
    REGISTRY["purifiers"] = set()
    STATUS_CACHE.clear()


def registry_populate(sc):
    """The state the slow sweep leaves behind. Uncounted here; pass_registry_sweep
    measures what it costs."""
    registry_reset()
    for k, sq in WORLD.squares.items():
        for o in sq.objects:
            if o.drip or o.sprinkler:
                REGISTRY["emitters"].add(k)
            if o.hydrant:
                REGISTRY["hydrants"].add(k)
            if o.purifier:
                REGISTRY["purifiers"].add(k)


def pass_registry_sweep(sc, radius=20, px=10, py=10, pz=0):
    """Registry sweep: one full area classification, every ~5 s. This is what
    actually populates the registry -- LoadGridsquare fires before modData is
    attached, so classifying there found nothing."""
    for dx in range(-radius, radius + 1):
        for dy in range(-radius, radius + 1):
            sq = getGridSquare(px + dx, py + dy, pz)
            if sq is None:
                continue
            # classify(): one pipe scan + hydrant + purifier lookup
            getPipeObjectsOnSquare(sq)
            for o in sq.objects:
                bc("isEmitter", 2)          # isSprinkler + isDrip modData reads
            Hydrant_findOnSquare(sq)
            Purifier_findOnSquare(sq)


def registry_near(kind, px, py, pz, radius):
    """Registry.near: iterate the remembered tiles, re-validate each."""
    finder = _FINDERS[kind]
    out = []
    for (x, y, z) in REGISTRY[kind]:
        if z != pz or abs(x - px) > radius or abs(y - py) > radius:
            continue
        sq = getGridSquare(x, y, z)
        if sq is None:
            continue
        obj = finder(sq)
        if obj:
            out.append((sq, obj))
    return out


def emitter_status(sq):
    """Registry.emitterStatus: 1 BFS on a miss, free on a hit.

    Pressure and availability are two questions with one answer, so the readout
    builds a single summary and reads both off it.
    """
    k = (sq.x, sq.y, sq.z)
    if STATUS_TTL_HITS and k in STATUS_CACHE:
        CALLS["statusCacheHit"] += 1
        return STATUS_CACHE[k]
    buildSummaryFromSquare(sq, kind="drip")
    STATUS_CACHE[k] = True
    return True


def pass_sprayfx_rescan(sc, radius=18, px=10, py=10, pz=0):
    claimed = set()
    for sq, obj in registry_near("hydrants", px, py, pz, radius):
        claimed.add((sq.x, sq.y, sq.z))
        bc("hydrantFlowing", 2)         # isOpen + reserve/serviceLive
    for sq, obj in registry_near("emitters", px, py, pz, radius):
        if (sq.x, sq.y, sq.z) in claimed:
            continue
        emitter_status(sq)
        bc("isSprinkler", 1)


def pass_sound_rescan(sc, radius=14, px=10, py=10, pz=0, kind="hydrant"):
    key = "hydrants" if kind == "hydrant" else "purifiers"
    for sq, obj in registry_near(key, px, py, pz, radius):
        bc("soundState", 2)             # isFlowing / isWorking


def pass_wetness(sc, px=10, py=10, pz=0):
    for sq, obj in registry_near("hydrants", px, py, pz, 1):
        bc("hydrantFlowing", 2)
    for sq, obj in registry_near("emitters", px, py, pz, 1):
        bc("isSprinkler", 1)
        # A drip waters its own soil and cannot wet a person: only a sprinkler
        # is worth asking about (matches WaterPipesWetness.playerIsInSpray).
        if obj.sprinkler:
            emitter_status(sq)


# ----------------------------------------------------------------------------
# Runner
# ----------------------------------------------------------------------------
US_PER_BC_MIN, US_PER_BC_NOM, US_PER_BC_MAX = 0.3, 0.8, 2.0


def ms(n_bc, rate=US_PER_BC_NOM):
    return n_bc * rate / 1000.0


def measure(fn, *a, **kw):
    """One pass, starting from a clean frame -- caches are cold on entry."""
    reset()
    frame_reset()
    fn(*a, **kw)
    return total_bc(), dict(BC), dict(CALLS)


def measure_frame(fns, sc):
    """Several passes inside ONE frame, so they share the caches -- which is what
    actually happens: all four EveryOneMinute handlers run in the same frame."""
    reset()
    frame_reset()
    for fn in fns:
        fn(sc)
    return total_bc(), dict(BC), dict(CALLS)


def run_profile(pipes, containers, endpoints, routers, pumps, emitters,
                mains_inlets, filler=4, pumps_have_source=False, label=""):
    sc = Scenario(pipes, containers, endpoints, routers, pumps, emitters,
                  mains_inlets, filler)
    sc.pumps_have_source = pumps_have_source

    results = {}
    for name, fn in (
        ("EveryOneMinute / processRouters", pass_processRouters),
        ("EveryOneMinute / processPumps", pass_processPumps),
        ("EveryOneMinute / processAllMains", pass_processAllMains),
        ("EveryOneMinute / refreshPlumbedEndpoints", pass_refreshPlumbedEndpoints),
        ("EveryTenMinutes / scanContainersAroundPipes", pass_scanContainersAroundPipes),
        ("EveryTenMinutes / rebuildGraph", pass_rebuildGraph),
        ("EveryTenMinutes / redistributeWater", pass_redistributeWater),
        ("EveryHours / Irrigation.run", pass_irrigation),
        ("OnTick(45) / SprayFX rescan", pass_sprayfx_rescan),
        ("OnTick(60) / Hydrant+Purifier sound", lambda s: (pass_sound_rescan(s, kind="hydrant"),
                                                           pass_sound_rescan(s, kind="purifier"))),
        ("OnTick(15) / Wetness check", pass_wetness),
    ):
        n, buckets, calls = measure(fn, sc)
        results[name] = (n, buckets, calls)
    return sc, results


def one_bfs_cost(pipes, filler=4):
    sc = Scenario(pipes, containers=max(1, pipes // 10), endpoints=0, routers=0,
                  pumps=0, emitters=0, mains_inlets=0, filler=filler)
    origin = getGridSquare(*sc.pipe_coords[0])
    reset()
    buildSummaryFromSquare(origin, kind="tap")
    return total_bc()
