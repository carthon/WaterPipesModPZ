#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Invariants for the performance model itself.

wp_model is a simulator whose numbers get used to justify changes to the mod, and
it had no tests at all. It produced confident fiction twice:

  1. It counted only bridge calls, on the premise that pure-Lua work was noise.
     The hydraulic solver ended that, and the harness reported a 145x regression
     as free. Fixed by adding a second counter -- and nothing checks the two stay
     separate.

  2. Caches that legitimately outlived a frame started surviving the scenario
     rebuild that run_suite performs between the server and client pass groups.
     The second scenario inherited the first one's answers, and "one cold spray-FX
     rescan" reported 512 where the truth was 31,478 -- a 60x understatement, read
     and reported as a 98% improvement.

Neither failure was subtle. Both would have been caught in seconds by asserting
things that must be true of ANY cost model, regardless of what the mod does:

  * a measurement must not depend on what was measured before it
  * a cache may change what something COSTS, never what it ANSWERS
  * warm is never more expensive than cold
  * the two counters measure different things and must not bleed

These are those assertions. They are about the harness, not about the mod; the
mod's own invariants live in tools/conservation.

    python test_model.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import wp_model as M
import wp_bench as B

FAILURES = []


def check(name, condition, detail=""):
    status = "OK" if condition else "FAIL"
    print("  %-58s %s%s" % (name, status, ("   " + detail) if detail else ""))
    if not condition:
        FAILURES.append(name)


def check_equal(name, left, right, detail=""):
    ok = left == right
    check(name, ok, detail or ("%s vs %s" % (left, right)))


SMALL = ("small", 100, 10, 3, 1, 1, 4, 1)
MEDIUM = ("medium", 200, 20, 6, 2, 2, 8, 1)


def client_scenario(spec):
    """Exactly what run_suite sets up before the client passes."""
    sc = B.build(spec)
    B.densify()
    M.registry_populate(sc)
    M.STATUS_CACHE.clear()
    return sc


# ---------------------------------------------------------------------------
# 1. Isolation: a measurement must not depend on what ran before it.
# ---------------------------------------------------------------------------
print("\n-- 1. a scenario rebuild really starts over --")

sc = client_scenario(MEDIUM)
first, _, _ = M.measure(M.pass_sprayfx_rescan, sc)

# Run the same thing again after a rebuild. Same spec, same world, same pass:
# the number cannot legitimately differ.
sc = client_scenario(MEDIUM)
again, _, _ = M.measure(M.pass_sprayfx_rescan, sc)
check_equal("the same cold pass measured twice gives the same number", first, again)

# And with unrelated work in between, which is what run_suite actually does: it
# runs every server pass on one scenario, then rebuilds for the client ones.
sc = B.build(MEDIUM)
for _label, fn in B.SERVER_PASSES:
    M.measure(fn, sc)
sc = client_scenario(MEDIUM)
after_server, _, _ = M.measure(M.pass_sprayfx_rescan, sc)
check("a preceding pass group does not change it", after_server == first,
      "%s vs %s" % (after_server, first))

# A bigger scenario in between must not leave anything behind either.
sc = client_scenario(("large", 400, 40, 12, 4, 4, 16, 1))
M.measure(M.pass_sprayfx_rescan, sc)
sc = client_scenario(MEDIUM)
after_large, _, _ = M.measure(M.pass_sprayfx_rescan, sc)
check("a larger scenario in between does not change it", after_large == first,
      "%s vs %s" % (after_large, first))


# ---------------------------------------------------------------------------
# 2. A cache may change the cost. It may never change the answer.
# ---------------------------------------------------------------------------
print("\n-- 2. caches change cost, not answers --")

sc = client_scenario(MEDIUM)
origin = M.getGridSquare(*sc.pipe_coords[0])

M.frame_reset()
M.HYDRAULIC_CACHE.clear()
M.ZONE_OF_NODE.clear()
cold_summary = M.buildSummaryFromSquare(origin, kind="drip")
cold_keys = sorted(cold_summary["descriptors"].keys()) if cold_summary else None
cold_zone = len(cold_summary["pipeSquares"]) if cold_summary else None

warm_summary = M.buildSummaryFromSquare(origin, kind="drip")   # every cache hot
warm_keys = sorted(warm_summary["descriptors"].keys()) if warm_summary else None
warm_zone = len(warm_summary["pipeSquares"]) if warm_summary else None

check("a warm summary describes the same vessels", cold_keys == warm_keys,
      "%d vs %d" % (len(cold_keys or []), len(warm_keys or [])))
check("a warm summary describes the same network", cold_zone == warm_zone,
      "%s vs %s" % (cold_zone, warm_zone))

# The registry's resolved-entry cache: same tiles, same objects, cached or not.
sc = client_scenario(MEDIUM)
M.RESOLVED.clear()
uncached = M.registry_near("emitters", 10, 10, 0, 18)
cached = M.registry_near("emitters", 10, 10, 0, 18)
check_equal("the registry returns the same tiles cached or not",
            sorted((e["x"], e["y"], e["z"]) for e in uncached),
            sorted((e["x"], e["y"], e["z"]) for e in cached))
# The entry carries the coordinates itself now. Assert they AGREE with the square,
# because the whole saving rests on the caller trusting them instead of asking the
# engine -- a registry that remembers the wrong tile would be worse than the cost.
check("the entry's coordinates match its square",
      all(e["x"] == e["square"].x and e["y"] == e["square"].y and e["z"] == e["square"].z
          for e in cached))


# ---------------------------------------------------------------------------
# 3. Warm is never dearer than cold.
# ---------------------------------------------------------------------------
print("\n-- 3. a cache never costs more than not having one --")

for label, fn in (("spray FX rescan", M.pass_sprayfx_rescan),
                  ("irrigation", M.pass_irrigation),
                  ("endpoint refresh", M.pass_refreshPlumbedEndpoints)):
    sc = client_scenario(MEDIUM)
    M.reset()
    M.frame_reset()
    fn(sc)
    cold = M.total_bc()
    fn(sc)                                   # again, everything hot
    warm = M.total_bc() - cold
    check("%s: warm <= cold" % label, warm <= cold, "%s vs %s" % (warm, cold))


# ---------------------------------------------------------------------------
# 4. The two counters measure different things.
# ---------------------------------------------------------------------------
print("\n-- 4. bridge calls and Lua work stay separate --")

M.reset()
M.bc("probe", 7)
check_equal("bc() does not touch the Lua counter", M.total_lua(), 0, "lua=%d" % M.total_lua())
check_equal("bc() lands in the bridge counter", M.total_bc(), 7)

M.reset()
M.lua("probe", 5)
check_equal("lua() does not touch the bridge counter", M.total_bc(), 0, "bc=%d" % M.total_bc())
check_equal("lua() lands in the Lua counter", M.total_lua(), 5)


# ---------------------------------------------------------------------------
# 5. Cost grows with the network, and the model knows which passes are which.
# ---------------------------------------------------------------------------
print("\n-- 5. cost scales with the thing it is supposed to scale with --")

def cost(spec, fn):
    sc = B.build(spec)
    n, _, _ = M.measure(fn, sc)
    return n

for label, fn in (("endpoint refresh", M.pass_refreshPlumbedEndpoints),
                  ("container scan", M.pass_scanContainersAroundPipes),
                  ("graph rebuild", M.pass_rebuildGraph)):
    small = cost(SMALL, fn)
    medium = cost(MEDIUM, fn)
    check("%s: 200 pipes costs at least as much as 100" % label, medium >= small,
          "%s vs %s" % (medium, small))
    # Twice the pipes must not cost eight times as much: that is the shape of a
    # quadratic hiding in a pass that should be linear.
    check("%s: and not more than 4x as much" % label, medium <= max(small * 4, 4),
          "%s vs %s" % (medium, small * 4))


# ---------------------------------------------------------------------------
# 6. A pass reads the world; it must not silently rewrite it.
# ---------------------------------------------------------------------------
print("\n-- 6. a measured pass leaves the world as it found it --")

sc = client_scenario(MEDIUM)
before = len(M.WORLD.squares)
M.measure(M.pass_sprayfx_rescan, sc)
M.measure(M.pass_refreshPlumbedEndpoints, sc)
check_equal("the square count is unchanged", len(M.WORLD.squares), before)


# ---------------------------------------------------------------------------
# 7. Isolation again, at the granularity the first check missed.
# ---------------------------------------------------------------------------
# Check 1 rebuilds the SCENARIO between measurements, and Scenario.__init__ empties
# every world-derived cache -- so it proves isolation across scenarios and says
# nothing about isolation across passes within one. That gap was real: three of the
# four caches had already been given event lifetimes, so measuring 10min/scan right
# after 1min/routers charged it a warm memo and recorded a seventieth of its true
# cost. The recorded baseline was a worst case for the first pass of each group and
# fiction for every pass after it.
#
# So: every server pass, measured alone, must cost exactly what it costs after every
# other server pass has already run. That is what measure()'s cold() is for, and this
# is the assertion that keeps it there.
print("")
print("-- 7. a pass costs the same whatever ran before it --")

sc = B.build(MEDIUM)
alone = {}
for label, fn in B.SERVER_PASSES:
    sc = B.build(MEDIUM)
    n, _, _ = M.measure(fn, sc)
    alone[label] = n

# Now the same passes back to back on ONE scenario, in order, the way run_suite does.
sc = B.build(MEDIUM)
for label, fn in B.SERVER_PASSES:
    n, _, _ = M.measure(fn, sc)
    check_equal("%s: same measured after its predecessors" % label, n, alone[label])

# And in the reverse order, since a leak that happens to be order-independent would
# slip past the check above.
sc = B.build(MEDIUM)
for label, fn in reversed(B.SERVER_PASSES):
    n, _, _ = M.measure(fn, sc)
    check_equal("%s: and in reverse order too" % label, n, alone[label])


# ---------------------------------------------------------------------------
# 8. A run of minutes costs less per minute than the first one.
# ---------------------------------------------------------------------------
# The point of giving the fill topology an event lifetime: minute two must not
# re-walk what minute one walked. If five minutes ever cost five times one minute,
# the cache is being dropped by something and the whole change has been undone --
# which is the failure this codebase has now had four times, always silently.
print("")
print("-- 8. an event-scoped cache actually survives to the next minute --")

minute = [fn for l, fn in B.SERVER_PASSES if l.startswith("1min/")]

sc = B.build(MEDIUM)
one, _, _ = M.measure_frame(minute, sc)

sc = B.build(MEDIUM)
M.reset()
M.cold()
for _ in range(5):
    M.frame_reset()
    for fn in minute:
        fn(sc)
five = M.total_bc()

check("five minutes cost less than five cold ones", five < one * 5,
      "%s vs %s" % (five, one * 5))
check("...and at least as much as one", five >= one, "%s vs %s" % (five, one))
# A frame boundary must not be what keeps them cheap: dropping the frame memos
# between minutes is already what the loop above does, so this is the real cadence.
check("the saving is worth having (under 4x one minute)", five < one * 4,
      "%s vs %s" % (five, one * 4))

print("")
if FAILURES:
    print("FAILED: %d invariant(s)" % len(FAILURES))
    for name in FAILURES:
        print("  - %s" % name)
    sys.exit(1)
print("All model invariants hold.")
