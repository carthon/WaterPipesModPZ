-- Water-spray visual FX (client-only). B42 exposes no per-object particle system to Lua, so the only
-- way to paint water over a tile is this: draw a small, seamlessly-looping frame set straight to the UI
-- layer in OnPreUIDraw, positioned with isoToScreen. 16 tiny frames per effect, no forced UI framerate.
--
-- Two emitters get a spray: a sprinkler while it is actually watering, and a fire hydrant while it is
-- open and flowing. Both conditions are read client-side on a slow rescan; the per-frame path only
-- draws the cached list.
--
-- Purely presentational, never transmitted. Gated on the mod's EffectsEnabled option, and drawn to
-- player 0's screen space, so splitscreen shows it on the first view only.

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
-- Tiles from the player we scan and draw within. Was 18, which is inside the visible screen: a farm you
-- were looking at drew nothing until you walked into it, and emitters that ARE watering read as
-- disconnected -- the failure the effect exists to rule out.
-- Raising it is cheap because the rescan costs per EMITTER IN RANGE, not per tile: Registry.near walks
-- the emitter registry, and the whole rebuild is throttled to RESCAN_MS. Measured on a 48-emitter farm,
-- radius 18 already had 39.5 of them in range, so the ceiling this raises the cost to is +21 % of a
-- bucket worth 3.6 ms/s. A base with emitters spread wider pays more, still bounded by how many it has.
-- Not tied to the sound modules despite what this line used to claim -- they scan 14 and 15. Audible
-- range and screen range are different questions.
local DRAW_RADIUS = 30
-- Milliseconds, not ticks: a frame count measures how FAST THE MACHINE IS, not how much time has
-- passed. At 127 fps -- ordinary on a decent PC -- 45 ticks is 0.35 s, so a better machine paid for
-- this rebuild twice as often as intended. The cost of a mod should not scale with the framerate.
local RESCAN_MS = 750
local BASE_ALPHA = 0.40      -- floor alpha (night); daylight adds up to +0.5
local MAX_ALPHA = 0.92

-- Per-kind art anchor. origin (ox, oy) is the emitter/ground point INSIDE the frame and matches the
-- generator's own origin, so it is structural -- leave it alone. headLift is the one to nudge: it raises
-- the sprite so the spray leaves the NOZZLE instead of the floor, and is measured off the atlas (ground
-- anchor at y=224 in a 128x256 cell; heads top out at y=189 sprinkler, y=187 drip).
-- cell is the frame's pixel size, matching tools/fx/gen_spray_fx.py. The sprinkler and the hydrant both
-- blanket a 3x3 and use the bigger canvas; only the drip stays on its own tile.
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
-- This used to sweep the whole (2*DRAW_RADIUS+1)^2 block around the player and scan every tile's object
-- list -- ~1400 tiles, three object scans each, whether or not the save held a single emitter. It asks
-- the tile registry now, so the work is proportional to the emitters near the player, not to the area.
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

    -- Tiles already claimed by a hydrant. A pipe (and so an emitter) can legally share a hydrant's tile,
    -- and the hydrant's gush is the bigger effect, so it wins.
    -- Coordinates and the tile key come off the registry entry, not off the square: asking the engine again
    -- was nine bridge calls per emitter per rebuild for numbers already in hand.
    local claimed = {}
    for _, found in ipairs(WaterPipes.Profiler.time("sprayfx: near",
        Registry.near, "hydrants", px, py, pz, DRAW_RADIUS)) do
        claimed[found.key] = true
        if Hydrant.isFlowing(found.object) then
            list[#list + 1] = { x = found.x, y = found.y, z = found.z,
                                kind = "hydrant", phase = phaseFor(found.x, found.y) }
        end
    end

    -- A tile carries a sprinkler OR a drip, never both; whichever is actually watering gets its spray this
    -- pass. The status is cached per tile by the registry -- it derives from the network, which only moves
    -- on the server's minute pass.
    -- One clock read for the whole rebuild: every emitter in it gets the same answer, and asking per emitter
    -- cost a pcall and a bridge call each.
    local stamp = Registry.stamp()

    local considered = 0
    for _, found in ipairs(WaterPipes.Profiler.time("sprayfx: near",
        Registry.near, "emitters", px, py, pz, DRAW_RADIUS)) do
        considered = considered + 1
        if not claimed[found.key] then
            local status = WaterPipes.Profiler.time("sprayfx: status",
                Registry.statusFor, found, stamp)
            if status and status.active then
                local kind = Irrigation.isSprinkler(found.object) and "sprinkler" or "drip"
                list[#list + 1] = { x = found.x, y = found.y, z = found.z,
                                    kind = kind, phase = phaseFor(found.x, found.y) }
            end
        end
    end

    FX.active = list
    -- Per-rebuild totals are meaningless across sessions without these: a farm with forty emitters in range
    -- and one with eight cost different amounts for the same code. Cost per emitter is what compares.
    WaterPipes.Profiler.count("sprayfx: emitters in range", considered)
    WaterPipes.Profiler.count("sprayfx: rebuilds", 1)
end

-- ===== Draw =====

-- The animation is paced off REAL TIME, not off how many times we happen to be drawn.
-- PZ renders the UI to an offscreen buffer at its own configurable rate (Options -> UIRenderFPS,
-- default 60), and OnPreUIDraw fires at that rate -- so advancing the frame with a draw counter clocked
-- the spray off a display setting: at 20 UI FPS the water visibly crawled while the world ran fine.
-- Vanilla hits the same problem and solves it the same way (the 30 / getUIRenderFPS() scaling in
-- ISVehicleDashboard). Pinned to the speed it had at the DEFAULT 60, so nothing changes for anyone on
-- the default. A low UI FPS still shows fewer steps of the loop, but no longer in slow motion.
local MS_PER_FRAME = 1000 * HOLD / 60

local drawTick = 0   -- fallback only, for a build with no getTimestampMs

local function animationFrame()
    if getTimestampMs then
        local ok, ms = pcall(getTimestampMs)
        if ok and type(ms) == "number" then
            -- Kahlua's % falls apart past ~2^31 -- in-game, (epoch_ms % 16) came back as an 11-digit number, so
            -- every frame lookup missed and the spray silently vanished. Fold the clock into a 2^20 ms window
            -- first: a power of two, so the divide/floor/multiply below are exact in doubles.
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
-- The frame counter survives as a fallback for a build with no getTimestampMs.
local tickCounter = 0
local nextRescanAtMs = nil

local function onTick()
    local stamp = nil
    if getTimestampMs then
        local ok, ms = pcall(getTimestampMs)
        stamp = (ok and type(ms) == "number") and ms or nil
    end

    if stamp then
        if nextRescanAtMs and stamp < nextRescanAtMs then
            return
        end
        nextRescanAtMs = stamp + RESCAN_MS
    else
        tickCounter = tickCounter + 1
        if tickCounter < 45 then
            return
        end
        tickCounter = 0
    end

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
