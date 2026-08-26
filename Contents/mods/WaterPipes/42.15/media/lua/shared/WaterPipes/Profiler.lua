-- WaterPipes/Profiler.lua
--
-- Real milliseconds for the mod's periodic work, on the player's own machine. The bench in tools/perf
-- models bridge calls and pure-Lua operations, which is good at SHAPE but cannot say what something
-- costs in a frame on real hardware, or whether the stutter is even ours.
--
-- Off by default, and free when off: time() returns the call straight through with no clock read and no
-- table write. Turn it on from the pipe Debug menu.
--
-- Reports per bucket (calls, total ms, average, worst call), per frame (worst frame, and how many
-- frames crossed 5 / 10 / 20 ms of OUR work) and raw counters, notably the hydraulic cache hit rate.
--
-- The frame figures are approximate by construction: a frame is closed by this module's own OnTick
-- handler and handler order within a tick is not guaranteed, so work registered after it lands in the
-- next frame's bucket. That skews individual frames, not the distribution.

require "WaterPipes/Constants"

WaterPipes = WaterPipes or {}
WaterPipes.Profiler = WaterPipes.Profiler or {}

local Profiler = WaterPipes.Profiler

local enabled = false
local buckets = {}          -- name -> { calls, totalMs, worstMs }
local counters = {}         -- name -> integer
local frameMs = 0           -- our work in the frame being accumulated, TOP LEVEL ONLY
local frames = 0
local worstFrameMs = 0
local over5, over10, over20 = 0, 0, 0
-- What was IN the frame, not just how big it was. "worst frame: 47 ms" names no culprit, and the
-- first guess at one was wrong. Only top-level rows are collected, for the same reason the totals are.
local frameRows = {}
local worstFrameRows = {}
local startedAtMs = nil
local totalMs = 0           -- our work over the window, top level only
local depth = 0             -- how many timings are open right now

-- Timings nest, and for a long time nothing here knew that. `sprayfx: status` runs inside
-- `sprayfx/rescan`; `pump/headroom` runs inside `1min/pumps` inside `system/1min`. Every one was added
-- to the same running total, so the same millisecond was counted two and three times -- 7.11% of wall
-- clock reported where the truth was 4.11%.
-- Worse, it was wrong by a factor that CHANGED: adding nested buckets made the headline number rise
-- while the mod got faster. A measurement that moves when you measure it differently is not one.
-- So a bucket still records its own elapsed time, children included -- that is what a breakdown is for
-- -- but the WINDOW and FRAME totals take only depth-0 timings. Nested buckets are marked and reported
-- as such, so the table says which rows are already inside a row above them.

local function nowMs()
    if not getTimestampMs then
        return nil
    end
    local ok, value = pcall(getTimestampMs)
    if not ok then
        return nil
    end
    return value
end

local function bucketFor(name)
    local bucket = buckets[name]
    if not bucket then
        bucket = { calls = 0, totalMs = 0, worstMs = 0, over1 = 0, over5 = 0, over20 = 0,
                   nested = false }
        buckets[name] = bucket
    end
    return bucket
end

-- ===== Control =====

function Profiler.isEnabled()
    return enabled
end

function Profiler.reset()
    buckets = {}
    counters = {}
    frameMs = 0
    frames = 0
    worstFrameMs = 0
    frameRows = {}
    worstFrameRows = {}
    over5, over10, over20 = 0, 0, 0
    totalMs = 0
    depth = 0
    startedAtMs = nowMs()

    -- The hydraulic counters live in Hydraulics so that module needs no dependency on this one. They are
    -- cumulative since load, so they are zeroed here too -- otherwise the first report after a long session
    -- measures the session, not the window being tested.
    local Hydraulics = WaterPipes.Hydraulics
    if Hydraulics and Hydraulics.counters then
        for key in pairs(Hydraulics.counters) do
            Hydraulics.counters[key] = 0
        end
    end

    local NetworkAccess = WaterPipes.NetworkAccess
    if NetworkAccess and NetworkAccess.counters then
        for key in pairs(NetworkAccess.counters) do
            NetworkAccess.counters[key] = 0
        end
    end
end

function Profiler.setEnabled(value)
    enabled = value and true or false
    if enabled then
        Profiler.reset()
    end
end

function Profiler.toggle()
    Profiler.setEnabled(not enabled)
    return enabled
end

-- ===== Recording =====

-- Book `elapsed` milliseconds against `name`, at nesting depth `openDepth` (0 = top level).
-- The primitive the two forms below are built on.
function Profiler.record(name, elapsed, openDepth)
    if not enabled or not elapsed then
        return
    end

    local bucket = bucketFor(name)
    if (openDepth or 0) > 0 then
        bucket.nested = true
    end
    bucket.calls = bucket.calls + 1
    bucket.totalMs = bucket.totalMs + elapsed
    if elapsed > bucket.worstMs then
        bucket.worstMs = elapsed
    end
    -- An average is only a description when the calls resemble each other. These stopped doing that: a
    -- spray-FX rebuild averaged 16 ms with a worst of 180, and the histogram showed nothing between 5 and
    -- 20. Dividing total by count there invents a call that never happened.
    if elapsed >= 20 then
        bucket.over20 = bucket.over20 + 1
    elseif elapsed >= 5 then
        bucket.over5 = bucket.over5 + 1
    elseif elapsed >= 1 then
        bucket.over1 = bucket.over1 + 1
    end
    -- Only depth 0 reaches the window and frame totals. A nested timing is already inside the parent's
    -- elapsed time; adding it again is what made every headline number larger than the work it described.
    if (openDepth or 0) == 0 then
        frameMs = frameMs + elapsed
        totalMs = totalMs + elapsed
        frameRows[name] = (frameRows[name] or 0) + elapsed
    end
end

-- Open a timing. Returns a mark to hand to Profiler.since, or nil when the profiler is off -- so the
-- disabled path is one comparison and no clock read.
function Profiler.mark()
    if not enabled then
        return nil
    end
    local started = nowMs()
    if not started then
        return nil
    end
    -- The depth AT WHICH THIS OPENED travels with the mark, so an unbalanced pair cannot make a sibling
    -- look nested. Depth is also reset every frame, so a mark abandoned by an error costs one frame of
    -- accounting rather than the rest of the session.
    depth = depth + 1
    return { at = started, depth = depth - 1 }
end

-- Close a timing opened by Profiler.mark.
-- This pair exists because Profiler.time cannot wrap everything: it forwards only the first two return
-- values, and a call site returning more would lose the rest SILENTLY -- a bug introduced by adding
-- instrumentation. Where the arity does not fit, bracket the call instead of wrapping it.
function Profiler.since(name, mark)
    if not enabled or not mark then
        return
    end
    if depth > 0 then
        depth = depth - 1
    end
    local finished = nowMs()
    if finished then
        Profiler.record(name, finished - mark.at, mark.depth)
    end
end

-- Time one call. Returns whatever the call returned, so a wrapped call site reads the same as the
-- unwrapped one and can be left in place permanently.
-- ONLY THE FIRST TWO RETURN VALUES ARE FORWARDED: carrying an arbitrary number would cost a table
-- allocation per call in the path this module exists to measure. Use mark/since when the arity is more.
function Profiler.time(name, fn, ...)
    if not enabled then
        return fn(...)
    end

    local openedAt = depth
    local started = nowMs()
    depth = depth + 1

    -- pcall, and then re-raise. Without it a throw skips the line that restores the depth, and every timing
    -- for the rest of the frame would be booked as nested -- i.e. dropped from the totals. A measuring
    -- instrument that goes quiet after the first error is the worst failure mode, because the reading still
    -- looks like a reading. Re-raised at level 0 so the message passes through exactly as thrown.
    local ok, first, second = pcall(fn, ...)
    depth = openedAt
    local finished = nowMs()

    if started and finished then
        Profiler.record(name, finished - started, openedAt)
    end

    if not ok then
        error(first, 0)
    end

    return first, second
end

function Profiler.count(name, amount)
    if not enabled then
        return
    end
    counters[name] = (counters[name] or 0) + (amount or 1)
end

-- Close the frame. Registered on OnTick; see the header on why this is approximate. Public so the frame
-- boundary can be exercised without an engine: it is where the nesting depth is recovered after a throw.
function Profiler.endFrame()
    if not enabled then
        return
    end

    -- Depth is reset here, not merely decremented, because an error thrown inside a timed call skips its
    -- close. Without this a single failure would leave everything after it looking nested and the totals
    -- would silently fall to zero. A frame is the natural place: nothing legitimately holds a timing across one.
    depth = 0

    frames = frames + 1
    if frameMs > worstFrameMs then
        worstFrameMs = frameMs
        -- Copied, not aliased: frameRows is cleared below and reused every frame.
        worstFrameRows = {}
        for name, ms in pairs(frameRows) do
            worstFrameRows[name] = ms
        end
    end
    if frameMs >= 20 then
        over20 = over20 + 1
    elseif frameMs >= 10 then
        over10 = over10 + 1
    elseif frameMs >= 5 then
        over5 = over5 + 1
    end
    frameMs = 0
    frameRows = {}
end

-- ===== Report =====

local function sortedBucketNames()
    local names = {}
    for name in pairs(buckets) do
        names[#names + 1] = name
    end
    table.sort(names, function(left, right)
        return buckets[left].totalMs > buckets[right].totalMs
    end)
    return names
end

function Profiler.report()
    local lines = {}
    local function add(text)
        lines[#lines + 1] = text
    end

    if not enabled then
        add("WaterPipes profiler is OFF. Turn it on from the pipe Debug menu, play for a minute or")
        add("two, then dump again.")
        return lines
    end

    local elapsedMs = nil
    local started = startedAtMs
    local finished = nowMs()
    if started and finished then
        elapsedMs = finished - started
    end

    add("===== WaterPipes profile =====")
    if elapsedMs then
        add(string.format("window: %.1f s real, %d frames", elapsedMs / 1000, frames))
    else
        add(string.format("window: %d frames (no clock available)", frames))
    end

    add("")
    add(string.format("%-24s %8s %10s %9s %9s %18s",
        "bucket", "calls", "total ms", "avg ms", "worst ms", "calls 1-5/5-20/20+"))
    local summed = 0
    for _, name in ipairs(sortedBucketNames()) do
        local bucket = buckets[name]
        summed = summed + bucket.totalMs
        -- A leading dot means this row ran inside another row, so its milliseconds are already
        -- counted in that one. Only the undotted rows add up to the total below.
        local label = (bucket.nested and "." or "") .. name
        add(string.format("%-24s %8d %10.1f %9.3f %9.1f %6d /%6d /%5d",
            label, bucket.calls, bucket.totalMs,
            bucket.calls > 0 and (bucket.totalMs / bucket.calls) or 0,
            bucket.worstMs, bucket.over1, bucket.over5, bucket.over20))
    end
    add(string.format("%-24s %8s %10.1f    <- top-level only; nested rows are inside these",
        "TOTAL", "", totalMs))
    if summed > totalMs then
        add(string.format("%-24s %8s %10.1f    <- every row added up, so nested work counted twice",
            "(sum of all rows)", "", summed))
    end
    add("The last three columns are BANDS, not thresholds: how many calls landed in [1,5), [5,20)")
    add("and [20+) ms. Read them before the average -- a bucket whose calls do not resemble each")
    add("other has no meaningful average, and these have never resembled each other.")

    if elapsedMs and elapsedMs > 0 then
        add(string.format("share of wall clock spent in WaterPipes: %.2f%%",
            (totalMs / elapsedMs) * 100))
    end

    add("")
    add(string.format("worst frame: %.1f ms of our work", worstFrameMs))

    -- What was in it. Two cheap passes worth 20 ms each landing together is a different problem from one
    -- pass worth 40, and the headline number cannot tell them apart.
    local worstNames = {}
    for name in pairs(worstFrameRows) do
        worstNames[#worstNames + 1] = name
    end
    table.sort(worstNames, function(left, right)
        return worstFrameRows[left] > worstFrameRows[right]
    end)
    for _, name in ipairs(worstNames) do
        add(string.format("  %-28s %.1f ms", name, worstFrameRows[name]))
    end

    add(string.format("frames costing 5-10 ms: %d    10-20 ms: %d    20+ ms: %d",
        over5, over10, over20))
    add("A stutter you can see is roughly 16 ms of total frame time, ours plus the game's. If the")
    add("three counts above are zero and you still feel it, it is not this mod.")

    -- The hydraulic cache. Hits well above solves means the field is being reused, which is the whole
    -- point of it; solves rivalling hits means it is being dropped faster than it is built.
    local Hydraulics = WaterPipes.Hydraulics
    if Hydraulics and Hydraulics.counters then
        local c = Hydraulics.counters
        local lookups = c.hits + c.solves
        add("")
        add("hydraulic field:")
        add(string.format("  solves %d   cache hits %d   hit rate %s",
            c.solves, c.hits,
            lookups > 0 and string.format("%.1f%%", (c.hits / lookups) * 100) or "n/a"))
        add(string.format(
            "  invalidations: %d supply-only, %d scoped, %d global, %d ignored (nothing cached there)",
            c.supplyOnly or 0, c.scoped, c.global, c.untouched))
        add("  'supply-only' is a vessel crossing empty: the zone keeps its shape and is re-priced")
        add("  without walking the world. It should be most of them on a farm that is watering.")
        if c.solves and c.solves > 0 then
            -- What a cold solve actually DOES, which is the number to optimise against: a re-pricing is one
            -- accumulate plus one relaxation of the whole zone. Times move between machines; these do not.
            add(string.format("  per solve: %.1f re-pricings, %.1f relax passes, %.0f relax calls",
                (c.repricings or 0) / c.solves,
                (c.relaxPasses or 0) / c.solves,
                (c.relaxCalls or 0) / c.solves))
            local capped = c.relaxCapped or 0
            if capped > 0 then
                add(string.format(
                    "  %d relaxation(s) ran out of passes with the field still moving (of %d)",
                    capped, c.repricings or 0))
                add("  That is the cap deciding the answer, not convergence. A bench network of the")
                add("  same size settles in three passes; if this is most of them, the real layouts")
                add("  are not like the bench and HYDRAULIC_RELAX_PASSES is doing the deciding.")
            end
        end
        add("  'ignored' is the win: world objects that touched no cached network. Before the scoped")
        add("  invalidation every one of those was a global drop.")
    end

    -- The fill topology, the same story one layer up: every network walk that is not a draw goes through
    -- this cache. It used to be dropped every frame, so pump/headroom walked the network cold, 20 ms a call.
    local NetworkAccess = WaterPipes.NetworkAccess
    if NetworkAccess and NetworkAccess.counters then
        local c = NetworkAccess.counters
        local lookups = c.hits + c.walks
        add("")
        add("fill topology:")
        add(string.format("  walks %d   cache hits %d   hit rate %s",
            c.walks, c.hits,
            lookups > 0 and string.format("%.1f%%", (c.hits / lookups) * 100) or "n/a"))
        add(string.format("  invalidations: %d scoped, %d global, %d ignored%s",
            c.scoped, c.global, c.untouched,
            c.overflow > 0 and string.format(", %d overflow", c.overflow) or ""))
        add("  A walk count near the number of pumps per minute is right. A walk count that tracks")
        add("  'global' is the cache being dropped faster than it is built -- look at what is calling")
        add("  invalidateTraversalCache. 'overflow' should be 0: above it, scoping is given up on.")
    end

    -- The header is written by the first counter rather than tested for up front: next() is not exposed by
    -- PZ's Lua, and reaching for it to ask "is this table empty" is a mistake this repo has made three times.
    local Audit = WaterPipes.RemovalAudit
    if Audit and Audit.isEnabled and Audit.isEnabled() then
        add("")
        add(Audit.report())
    end

    local wroteCounterHeader = false
    for name, value in pairs(counters) do
        if not wroteCounterHeader then
            add("")
            add("counters:")
            wroteCounterHeader = true
        end
        add(string.format("  %-28s %d", name, value))
    end

    -- The headline: a pass is one instant of simulated time, so it should cost about one re-price.
    -- Zero solves in a pass leaves no counter at all, and that is the BEST result -- so the row is
    -- derived from the passes alone and reads 0.0 rather than vanishing.
    local passes = counters["irrigation: passes started"]
    if passes and passes > 0 then
        local duringPass = counters["hydraulics: solves during a pass"] or 0
        add(string.format("  %-28s %.1f", "irrigation: solves per pass", duringPass / passes))
    end

    return lines
end

-- Guarded, and not out of habit. report() builds every line and prints none until it returns, so a fault
-- anywhere in it costs the whole window -- which is exactly what the next() bug did. A diagnostic that
-- destroys the measurement it was asked for is worse than one that says it failed.
function Profiler.dump()
    local ok, lines = pcall(Profiler.report)
    if not ok then
        print("[WaterPipes] profile dump failed: " .. tostring(lines))
        return
    end

    for _, line in ipairs(lines) do
        print("[WaterPipes] " .. line)
    end
end

if Events and Events.OnTick then
    Events.OnTick.Add(Profiler.endFrame)
end

return Profiler
