-- WaterPipes/Profiler.lua
--
-- Real milliseconds for the mod's periodic work, on the player's own machine.
--
-- The bench in tools/perf models bridge calls and pure-Lua operations. It is good at SHAPE -- work
-- that scales with the network, work happening per frame that belongs per minute -- and it cannot
-- answer the two questions that decide an optimisation: what does this cost in a frame on real
-- hardware, and is the stutter even ours. It cannot see the base game at all.
--
-- This can. It exists because "I see small stutters" is not a number, and every optimisation argued
-- from a number that does not exist is a guess.
--
-- Off by default, and free when off: time() returns the call straight through with no clock read and
-- no table write. Turn it on from the pipe Debug menu.
--
-- What it reports:
--   * per bucket -- calls, total ms, average, worst single call
--   * per frame  -- worst frame, and how many frames crossed 5 / 10 / 20 ms of OUR work
--   * counters   -- raw tallies, notably the hydraulic cache's hit rate
--
-- The frame figures are approximate by construction. A frame is closed by this module's own OnTick
-- handler, and handler order within a tick is not guaranteed, so work registered after it lands in
-- the next frame's bucket. That skews individual frames and not the distribution, which is what the
-- numbers are read for.

require "WaterPipes/Constants"

WaterPipes = WaterPipes or {}
WaterPipes.Profiler = WaterPipes.Profiler or {}

local Profiler = WaterPipes.Profiler

local enabled = false
local buckets = {}          -- name -> { calls, totalMs, worstMs }
local counters = {}         -- name -> integer
local frameMs = 0           -- our work in the frame being accumulated
local frames = 0
local worstFrameMs = 0
local over5, over10, over20 = 0, 0, 0
local startedAtMs = nil

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
        bucket = { calls = 0, totalMs = 0, worstMs = 0, over1 = 0, over5 = 0, over20 = 0 }
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
    over5, over10, over20 = 0, 0, 0
    startedAtMs = nowMs()

    -- The hydraulic counters live in Hydraulics so that module needs no dependency on this one. They
    -- are cumulative since load, so they are zeroed here too -- otherwise the first report after a
    -- long session measures the session, not the window being tested.
    local Hydraulics = WaterPipes.Hydraulics
    if Hydraulics and Hydraulics.counters then
        for key in pairs(Hydraulics.counters) do
            Hydraulics.counters[key] = 0
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

-- Time one call. Returns whatever the call returned, so a wrapped call site reads the same as the
-- unwrapped one and can be left in place permanently.
--
-- Only the first two return values are forwarded. Nothing wrapped here returns more, and carrying an
-- arbitrary number would cost a table allocation per call in the path this module exists to measure.
function Profiler.time(name, fn, ...)
    if not enabled then
        return fn(...)
    end

    local started = nowMs()
    local first, second = fn(...)
    local finished = nowMs()

    if started and finished then
        local elapsed = finished - started
        local bucket = bucketFor(name)
        bucket.calls = bucket.calls + 1
        bucket.totalMs = bucket.totalMs + elapsed
        if elapsed > bucket.worstMs then
            bucket.worstMs = elapsed
        end
        -- An average is only a description when the calls resemble each other. These stopped doing
        -- that: a spray-FX rebuild averaged 16 ms with a worst of 180, and the frame histogram showed
        -- nothing at all between 5 and 20 -- most rebuilds nearly free, a few enormous. Dividing the
        -- total by the count in that situation invents a call that never happened, and one round of
        -- this was spent optimising the number rather than the cost.
        if elapsed >= 20 then
            bucket.over20 = bucket.over20 + 1
        elseif elapsed >= 5 then
            bucket.over5 = bucket.over5 + 1
        elseif elapsed >= 1 then
            bucket.over1 = bucket.over1 + 1
        end
        frameMs = frameMs + elapsed
    end

    return first, second
end

function Profiler.count(name, amount)
    if not enabled then
        return
    end
    counters[name] = (counters[name] or 0) + (amount or 1)
end

-- Close the frame. Registered on OnTick; see the header on why this is approximate.
local function endFrame()
    if not enabled then
        return
    end

    frames = frames + 1
    if frameMs > worstFrameMs then
        worstFrameMs = frameMs
    end
    if frameMs >= 20 then
        over20 = over20 + 1
    elseif frameMs >= 10 then
        over10 = over10 + 1
    elseif frameMs >= 5 then
        over5 = over5 + 1
    end
    frameMs = 0
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
    add(string.format("%-22s %8s %10s %9s %9s %19s",
        "bucket", "calls", "total ms", "avg ms", "worst ms", "calls 1+/5+/20+ ms"))
    local totalMs = 0
    for _, name in ipairs(sortedBucketNames()) do
        local bucket = buckets[name]
        totalMs = totalMs + bucket.totalMs
        add(string.format("%-22s %8d %10.1f %9.3f %9.1f %6d /%5d /%5d",
            name, bucket.calls, bucket.totalMs,
            bucket.calls > 0 and (bucket.totalMs / bucket.calls) or 0,
            bucket.worstMs, bucket.over1, bucket.over5, bucket.over20))
    end
    add(string.format("%-22s %8s %10.1f", "TOTAL", "", totalMs))
    add("The last three columns are how many calls cost at least 1, 5 and 20 ms. Read those before")
    add("the average: a bucket whose calls do not resemble each other has no meaningful average.")

    if elapsedMs and elapsedMs > 0 then
        add(string.format("share of wall clock spent in WaterPipes: %.2f%%",
            (totalMs / elapsedMs) * 100))
    end

    add("")
    add(string.format("worst frame: %.1f ms of our work", worstFrameMs))
    add(string.format("frames over 5 ms: %d    over 10 ms: %d    over 20 ms: %d",
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
        add(string.format("  invalidations: %d scoped, %d global, %d ignored (nothing cached there)",
            c.scoped, c.global, c.untouched))
        add("  'ignored' is the win: world objects that touched no cached network. Before the scoped")
        add("  invalidation every one of those was a global drop.")
    end

    -- The header is written by the first counter rather than tested for up front: next() is not
    -- exposed by PZ's Lua, and reaching for it to ask "is this table empty" is a mistake this repo has
    -- now made three times (see ffc19f4 and 843016d).
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

    return lines
end

-- Guarded, and not out of habit. report() builds every line and prints none until it returns, so a
-- fault anywhere in it costs the whole window -- which is exactly what the next() bug did: the
-- buckets, the frame histogram and the cache figures had all been formatted correctly and were thrown
-- away by the last and least useful section. A diagnostic that destroys the measurement it was asked
-- for is worse than one that says it failed.
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
    Events.OnTick.Add(endFrame)
end

return Profiler
