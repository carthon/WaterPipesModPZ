-- Water-spray visual FX (client-only). Build 42 exposes no per-object particle system to Lua, so the
-- only way to paint water over a tile is what this does: draw a small, seamlessly-looping frame set
-- straight to the UI layer in OnPreUIDraw, positioned with isoToScreen. We keep it light on purpose --
-- 16 tiny frames per effect, no forced UI framerate -- unlike the reference mod's 720-frame sheets.
--
-- Two emitters get a spray: a sprinkler while it is actually watering, and a fire hydrant while it is
-- open and flowing. Both conditions are read client-side (the same status the irrigation overlay and
-- the hydrant sound already use), on a slow rescan; the per-frame path only draws the cached list.
--
-- Purely presentational -> client-side, never transmitted. Gated on the mod's EffectsEnabled option
-- (Options -> Mods -> Water Pipes), sibling to the sound toggles. Drawn to player 0's screen space, so
-- like the reference mod it is a single-screen effect (splitscreen shows it on the first view only).

require "WaterPipes/Constants"
require "WaterPipes/Profiler"
require "WaterPipes/Hydrant"
require "WaterPipes/Irrigation"
require "WaterPipes/WaterPipesTileRegistry"

WaterPipes = WaterPipes or {}
WaterPipes.SprayFX = WaterPipes.SprayFX or {}

local Hydrant = WaterPipes.Hydrant
local Irrigation = WaterPipes.Irrigation
local Registry = WaterPipes.TileRegistry
local FX = WaterPipes.SprayFX

-- ===== Tunables =====
local FRAMES = 16            -- loop length (frame canvas size is per-effect, see KIND.cell)
local HOLD = 2               -- UI draws per animation frame (advance every HOLD draws)
local DRAW_RADIUS = 18       -- tiles from the player we scan/draw within (matches the sound modules)
local RESCAN_TICKS = 45      -- ~0.75s between active-list rebuilds
local BASE_ALPHA = 0.40      -- floor alpha (night); daylight adds up to +0.5
local MAX_ALPHA = 0.92

-- Per-kind art anchor. origin (ox, oy) is the emitter/ground point INSIDE the frame and matches the
-- generator's own origin, so it is structural -- leave it alone. headLift is the one to nudge: it
-- raises the whole sprite so the spray leaves the NOZZLE instead of the floor.
--
-- headLift is measured off the atlas: the tile's ground anchor sits at y=224 in a 128x256 cell, and
-- the emitter heads top out at y=189 (sprinkler) and y=187 (drip) -- i.e. 35 and 37 px of nozzle above
-- ground. The old 16/6 dated from the retired elbow art and left the spray sitting on the grass.
-- cell = the frame's pixel size (matches tools/fx/gen_spray_fx.py per effect). The sprinkler and the
-- hydrant both blanket a 3x3, so both use the bigger canvas with the ground anchor low and centred
-- (ox = cell/2, oy = cell/2 + 56). Only the drip stays on its own tile.
local KIND = {
    sprinkler = { folder = "sprinkler", cell = 224, ox = 112, oy = 168, headLift = 35 },
    hydrant   = { folder = "hydrant",   cell = 224, ox = 112, oy = 168, headLift = 12 },
    drip      = { folder = "drip",      cell = 128, ox = 64,  oy = 70,  headLift = 37 },
}

-- ===== Options =====
local function effectsEnabled()
    local group = PZAPI and PZAPI.ModOptions and PZAPI.ModOptions:getOptions("WaterPipes")
    local o = group and group:getOption("EffectsEnabled")
    return not o or o:getValue() ~= false
end

-- ===== Texture cache (loaded once) =====
FX.textures = FX.textures or {}
local function textures(kind)
    local cached = FX.textures[kind]
    if cached then
        return cached
    end
    local folder = KIND[kind].folder
    local frames = {}
    for i = 0, FRAMES - 1 do
        local path = string.format("media/textures/WaterPipes/FX/%s/%02d.png", folder, i)
        frames[i] = getTexture and getTexture(path) or nil
    end
    FX.textures[kind] = frames
    return frames
end

-- ===== Active list (rebuilt on a slow cadence) =====
-- Each entry: { x, y, z, kind, phase } where phase de-syncs multiple emitters so they don't animate
-- in lockstep. Deterministic from the tile so it is stable frame to frame.
FX.active = FX.active or {}

local function phaseFor(x, y)
    return (x * 7 + y * 13) % FRAMES
end

-- Rebuild the list of tiles currently worth drawing a spray over.
--
-- This used to sweep the whole (2*DRAW_RADIUS+1)^2 block around the player and scan every tile's
-- object list looking for something to draw -- ~1400 tiles and three object scans each, whether or
-- not the save contained a single emitter. It now asks the tile registry, which remembers where they
-- are, so the work is proportional to the number of emitters near the player rather than to the area
-- around them. See WaterPipesTileRegistry.
local function rescanInner()
    local player = getPlayer and getPlayer() or nil
    if not player then
        FX.active = {}
        return
    end
    local px = math.floor(player:getX())
    local py = math.floor(player:getY())
    local pz = math.floor(player:getZ())
    local list = {}

    -- Tiles already claimed by a hydrant. A pipe (and so an emitter) can legally share a hydrant's
    -- tile, and the hydrant's gush is the bigger effect, so it wins the tile.
    local claimed = {}
    for _, found in ipairs(WaterPipes.Profiler.time("sprayfx: near",
        Registry.near, "hydrants", px, py, pz, DRAW_RADIUS)) do
        local sq = found.square
        claimed[sq:getX() .. ":" .. sq:getY() .. ":" .. sq:getZ()] = true
        if Hydrant.isFlowing(found.object) then
            list[#list + 1] = { x = sq:getX(), y = sq:getY(), z = sq:getZ(),
                                kind = "hydrant", phase = phaseFor(sq:getX(), sq:getY()) }
        end
    end

    -- A tile carries a sprinkler OR a drip, never both; whichever is actually watering (has
    -- pressure + water + not burst) gets its spray this pass. The status is cached per tile by the
    -- registry -- it is derived from the network, which only moves on the server's minute pass, so
    -- recomputing it on every rescan was asking a question whose answer could not have changed.
    local considered = 0
    for _, found in ipairs(WaterPipes.Profiler.time("sprayfx: near",
        Registry.near, "emitters", px, py, pz, DRAW_RADIUS)) do
        considered = considered + 1
        local sq, emitter = found.square, found.object
        if not claimed[sq:getX() .. ":" .. sq:getY() .. ":" .. sq:getZ()] then
            local status = WaterPipes.Profiler.time("sprayfx: status",
                Registry.emitterStatus, emitter, sq)
            if status and status.active then
                local kind = Irrigation.isSprinkler(emitter) and "sprinkler" or "drip"
                list[#list + 1] = { x = sq:getX(), y = sq:getY(), z = sq:getZ(),
                                    kind = kind, phase = phaseFor(sq:getX(), sq:getY()) }
            end
        end
    end

    FX.active = list
    -- Per-rebuild totals are meaningless across sessions without these: a farm with
    -- forty emitters in range and one with eight cost different amounts for the same
    -- code. Cost per emitter is the number that compares.
    WaterPipes.Profiler.count("sprayfx: emitters in range", considered)
    WaterPipes.Profiler.count("sprayfx: rebuilds", 1)
end

-- ===== Draw =====

-- The animation is paced off REAL TIME, not off how many times we happen to be drawn.
--
-- PZ renders the UI to an offscreen buffer at its own configurable rate (Options -> UIRenderFPS,
-- default 60), independent of the world's framerate -- and OnPreUIDraw fires at that rate. Advancing
-- the frame with a draw counter therefore clocked the spray off a display setting: at 20 UI FPS the
-- loop took three times as long and the water visibly crawled while the world around it ran fine.
--
-- Nothing about the animation was ever expensive; the counter costs nothing. It was being driven by
-- the wrong thing. Vanilla hits the same problem and solves it the same way -- see the
-- `30 / getPerformance():getUIRenderFPS()` scaling in ISVehicleDashboard and ISSkillProgressBar --
-- and WaterPipesWetness in this mod is already paced off elapsed milliseconds for the same reason.
--
-- Pinned to the speed it had at the DEFAULT 60 UI FPS, so nothing changes for anyone on the default
-- and it stops degrading for everyone below it. A low UI FPS still shows fewer steps of the loop --
-- there is no way around that from the UI layer -- but it no longer plays in slow motion.
local MS_PER_FRAME = 1000 * HOLD / 60

local drawTick = 0   -- fallback only, for a build with no getTimestampMs

local function animationFrame()
    if getTimestampMs then
        local ok, ms = pcall(getTimestampMs)
        if ok and type(ms) == "number" then
            -- Kahlua's % falls apart past ~2^31 -- in-game, (epoch_ms % 16) came back as an
            -- 11-digit number, so every frame lookup missed and the spray silently vanished.
            -- Fold the clock into a 2^20 ms (~17 min) window FIRST: the window is a power of
            -- two, so the divide/floor/multiply below are all exact in doubles. The loop's
            -- once-per-window phase jump is invisible.
            local within = ms - math.floor(ms / 1048576) * 1048576
            return math.floor(within / MS_PER_FRAME) % FRAMES
        end
    end
    -- No clock available: count draws, which is exactly what this replaced.
    drawTick = (drawTick + 1) % (FRAMES * HOLD)
    return math.floor(drawTick / HOLD)
end

local function daylightAlpha()
    local world = getWorld and getWorld() or nil
    local cm = world and world.getClimateManager and world:getClimateManager() or nil
    local dls = 0.5
    if cm and cm.getDayLightStrength then
        local ok, v = pcall(cm.getDayLightStrength, cm)
        if ok and type(v) == "number" then
            dls = v
        end
    end
    return math.min(MAX_ALPHA, BASE_ALPHA + 0.5 * math.max(0, math.min(1, dls)))
end

function FX.render()
    if not isIngameState or not isIngameState() then
        return
    end
    if not effectsEnabled() then
        return
    end
    local list = FX.active
    if not list or #list == 0 then
        return
    end
    local player = getPlayer and getPlayer() or nil
    if not player then
        return
    end
    if not UIManager or not UIManager.DrawTexture or not isoToScreenX then
        return
    end

    local pn = player:getPlayerNum() or 0
    local zoom = getCore and getCore():getZoom(pn) or 1
    if not zoom or zoom <= 0 then
        zoom = 1
    end
    local frameIndex = animationFrame()
    local alpha = daylightAlpha()

    for _, e in ipairs(list) do
        local spec = KIND[e.kind]
        if spec then
            local tex = textures(e.kind)[(frameIndex + e.phase) % FRAMES]
            if tex then
                -- place the frame's origin pixel onto the tile centre, then lift to nozzle height
                local size = spec.cell / zoom
                local sx = isoToScreenX(pn, e.x + 0.5, e.y + 0.5, e.z) - spec.ox / zoom
                local sy = isoToScreenY(pn, e.x + 0.5, e.y + 0.5, e.z) - spec.oy / zoom - spec.headLift / zoom
                UIManager.DrawTexture(tex, sx, sy, size, size, alpha)
            end
        end
    end
end

-- ===== Wiring =====
local tickCounter = 0
local function onTick()
    tickCounter = tickCounter + 1
    if tickCounter < RESCAN_TICKS then
        return
    end
    tickCounter = 0
    pcall(WaterPipes.Profiler.time, "sprayfx/rescan", rescanInner)
end

if Events and Events.OnTick then
    Events.OnTick.Add(onTick)
end
if Events and Events.OnPreUIDraw then
    Events.OnPreUIDraw.Add(function() pcall(FX.render) end)
end
if Events and Events.OnGameStop then
    Events.OnGameStop.Add(function() FX.active = {} end)
end

return FX
