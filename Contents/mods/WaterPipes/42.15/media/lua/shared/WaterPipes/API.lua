-- =====================================================================================
-- WaterPipes public integration API
--
-- A small, STABLE surface that other mods can call to read and consume water from a
-- Water Pipes network, WITHOUT depending on this mod's internals. It only delegates to
-- the network layer, so our internals can change freely without breaking integrators.
--
-- Availability: the global table `WaterPipesAPI`, present once this mod's shared files
-- have loaded (i.e. from OnGameStart / OnServerStarted onward). Always guard:
--     if WaterPipesAPI and WaterPipesAPI.getWaterAmount(sq) > 0 then ... end
--
-- All functions are SQUARE-based: pass the IsoGridSquare of a tile that has a pipe on it
-- (typically your fixture's OWN tile, with a pipe built on it). The network reachable
-- from that pipe is what gets read/drawn.
--
-- Multiplayer: the read functions (hasNetwork / getWaterAmount / getWaterSummary) are safe on
-- any side. The WRITE functions (drawWater / fillWater) mutate network containers, so they only
-- run on the AUTHORITATIVE side (server or single-player) and return 0 on a plain MP client --
-- call them server-side (a client write would desync and be overwritten on the next sync).
--
-- API:
--   WaterPipesAPI.VERSION                              -> integer (bumped on breaking changes)
--   WaterPipesAPI.hasNetwork(square)                   -> bool        (a pipe network is reachable)
--   WaterPipesAPI.getWaterAmount(square)               -> number      (usable fluid units; 0 if none/mixed)
--   WaterPipesAPI.getWaterSummary(square)              -> table|nil   { amount, capacity, fluidType, isMixed }
--   WaterPipesAPI.drawWater(square, fluidType, amount) -> number      (units actually drawn from the network)
--        fluidType may be nil to draw whatever single fluid the network currently holds.
--   WaterPipesAPI.fillWater(square, fluidType, amount) -> number      (units actually added to the network)
--        only fills an empty network, or one already holding the same fluid (never mixes).
--
-- Example (a shower reading then consuming network water at its own tile):
--     local sq = shower:getSquare()
--     if WaterPipesAPI and WaterPipesAPI.getWaterAmount(sq) > 0 then
--         local got = WaterPipesAPI.drawWater(sq, "Water", needed)
--     end
-- =====================================================================================

require "WaterPipes/NetworkAccess"

WaterPipes = WaterPipes or {}
local NetworkAccess = WaterPipes.NetworkAccess

-- Fluid mutations must only run on the authoritative side (server or single-player). A plain MP
-- client writing to a FluidContainer would desync and be overwritten on the next server sync, so
-- the write functions below no-op there. Mirrors the guard used across the mod.
local function isAuthoritative()
    if isServer and isServer() then
        return true
    end
    return not (isClient and isClient())
end

WaterPipesAPI = WaterPipesAPI or {}
WaterPipesAPI.VERSION = 1

-- Is a Water Pipes network reachable from this square?
function WaterPipesAPI.hasNetwork(square)
    if not square then
        return false
    end
    local pipeSquares = NetworkAccess.getNetworkFromSquare(square)
    return pipeSquares ~= nil and #pipeSquares > 0
end

-- Summary of the single-fluid network reachable from this square, or nil if none.
function WaterPipesAPI.getWaterSummary(square)
    if not square then
        return nil
    end
    local summary = NetworkAccess.getFluidSummaryAtSquare(square)
    if not summary then
        return nil
    end
    return {
        amount = summary.totalAmount or 0,
        capacity = summary.totalCapacity or 0,
        fluidType = summary.fluidTypeName,
        isMixed = summary.isMixed or false,
    }
end

-- Usable fluid units in the network reachable from this square (0 if none or mixed).
function WaterPipesAPI.getWaterAmount(square)
    local summary = WaterPipesAPI.getWaterSummary(square)
    if not summary or summary.isMixed then
        return 0
    end
    return summary.amount or 0
end

-- Draw up to `amount` from the network at this square. `fluidType` (e.g. "Water") must
-- match the network's fluid; pass nil to draw whatever single fluid it currently holds.
-- Returns the amount actually drawn.
function WaterPipesAPI.drawWater(square, fluidType, amount)
    if not square or not isAuthoritative() then
        return 0
    end
    if fluidType == nil then
        local summary = NetworkAccess.getFluidSummaryAtSquare(square)
        fluidType = summary and summary.fluidTypeName or nil
        if not fluidType then
            return 0
        end
    end
    return NetworkAccess.drawFluidAtSquare(square, fluidType, amount) or 0
end

-- Add up to `amount` of `fluidType` into the network at this square. Only fills an empty network,
-- or one already holding the same fluid (never mixes). Returns the amount actually added.
function WaterPipesAPI.fillWater(square, fluidType, amount)
    if not square or not fluidType or not isAuthoritative() then
        return 0
    end
    return NetworkAccess.fillFluidAtSquare(square, fluidType, amount) or 0
end

return WaterPipesAPI
