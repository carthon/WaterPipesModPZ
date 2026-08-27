WaterPipes = WaterPipes or {}
WaterPipes.Purifier = WaterPipes.Purifier or {}

require "WaterPipes/Constants"
require "WaterPipes/Logger"
require "WaterPipes/PipeObjectUtils"
require "WaterPipes/World"

local Constants = WaterPipes.Constants
local Logger = WaterPipes.Logger
local PipeObjectUtils = WaterPipes.PipeObjectUtils
local Purifier = WaterPipes.Purifier
local World = WaterPipes.World

-- A purifier is a NON-pipe container object placed on a router tile, tagged with its tier in modData.
-- It holds two internal buffers (IN tainted / OUT clean); the router drives intake -> convert -> output.
-- Detected by modData (never by sprite).

local function getModData(worldObject)
    if not worldObject or not worldObject.getModData then
        return nil
    end
    local ok, modData = pcall(worldObject.getModData, worldObject)
    return ok and modData or nil
end

-- The tier string ("filter"/"fire"/"electric") baked into a purifier, or nil if not a purifier.
function Purifier.getTier(worldObject)
    local modData = getModData(worldObject)
    local tier = modData and modData[Constants.PURIFIER_MODDATA_KEY]
    if tier == Constants.PURIFIER_TIER_FILTER
        or tier == Constants.PURIFIER_TIER_FIRE
        or tier == Constants.PURIFIER_TIER_ELECTRIC then
        return tier
    end
    return nil
end

function Purifier.isPurifier(worldObject)
    return Purifier.getTier(worldObject) ~= nil
end

-- The purifier's identity sprite. Purifiers are electric-only and the visible tank is drawn by the
-- entity's 2x2 SpriteConfig grid, so this is only the anchor/front-body cell (used for detection/UI).
function Purifier.spriteForTier(tier)
    return Constants.PURIFIER_ELECTRIC_SPRITE
end

function Purifier.spriteFor(worldObject)
    return Purifier.spriteForTier(Purifier.getTier(worldObject))
end

-- ===== Working predicate =====

local function squareHasPower(square)
    if not square or not square.haveElectricity then
        return false
    end
    local ok, powered = pcall(square.haveElectricity, square)
    return ok and powered or false
end

-- The purifier works while its tile has power (electric tier only for now). "Working" is about POWER
-- alone (used for the ambient sound and the grid readout); whether it can actually clean tainted water
-- also depends on the filter condition -- see Purifier.canFilter.
function Purifier.isWorking(worldObject)
    if not Purifier.isPurifier(worldObject) then
        return false
    end
    local square = worldObject.getSquare and worldObject:getSquare() or nil
    return squareHasPower(square)
end

-- ===== Filter condition (maintenance) =====

local function transmitObj(worldObject)
    if worldObject and worldObject.transmitModData then
        pcall(worldObject.transmitModData, worldObject)
    end
end

-- Current filter condition (0..MAX). Absent key => full, so purifiers from saves made before this
-- feature (and freshly built ones whose OnCreate seeds it) read as a fresh filter.
function Purifier.getFilterCondition(worldObject)
    local modData = getModData(worldObject)
    local value = modData and modData[Constants.PURIFIER_FILTER_CONDITION_KEY]
    if type(value) ~= "number" then
        return Constants.PURIFIER_FILTER_MAX_CONDITION
    end
    return math.min(math.max(value, 0), Constants.PURIFIER_FILTER_MAX_CONDITION)
end

function Purifier.setFilterCondition(worldObject, value)
    local modData = getModData(worldObject)
    if not modData then
        return
    end
    modData[Constants.PURIFIER_FILTER_CONDITION_KEY] =
        math.min(math.max(value or 0, 0), Constants.PURIFIER_FILTER_MAX_CONDITION)
    transmitObj(worldObject)
end

-- Effective wear per unit of tainted water filtered. The base rate is scaled by the per-save Sandbox
-- Option WaterPipes.PurifierFilterWear (a percentage: 100 = default, 200 = twice as fast, 0 = filters
-- never wear out). Falls back to the base constant when the sandbox var is absent.
local function filterWearPerUnit()
    local base = Constants.PURIFIER_FILTER_WEAR_PER_UNIT
    local sv = SandboxVars and SandboxVars.WaterPipes
    local pct = sv and sv.PurifierFilterWear
    if type(pct) == "number" then
        return base * (math.max(pct, 0) / 100)
    end
    return base
end

-- Wear the filter by the volume of tainted water just converted. Only ever called from the server
-- convert step, so the condition stays authoritative there.
function Purifier.wearFilter(worldObject, volume)
    if (volume or 0) <= 0 then
        return
    end
    local perUnit = filterWearPerUnit()
    if perUnit <= 0 then
        return   -- wear disabled via sandbox: the filter never degrades
    end
    local worn = Purifier.getFilterCondition(worldObject) - volume * perUnit
    Purifier.setFilterCondition(worldObject, worn)
end

-- Restore the filter to full (the "Repair Filter" action, after consuming the repair kit).
function Purifier.repairFilter(worldObject)
    Purifier.setFilterCondition(worldObject, Constants.PURIFIER_FILTER_MAX_CONDITION)
end

function Purifier.isFilterClogged(worldObject)
    return Purifier.getFilterCondition(worldObject) <= 0
end

function Purifier.needsRepair(worldObject)
    return Purifier.getFilterCondition(worldObject) < Constants.PURIFIER_FILTER_MAX_CONDITION
end

-- Can the purifier actually clean tainted water right now: powered AND filter not spent.
function Purifier.canFilter(worldObject)
    return Purifier.isWorking(worldObject) and Purifier.getFilterCondition(worldObject) > 0
end

-- ===== IN / OUT buffers (two internal tanks, stored as modData) =====

local function transmit(worldObject)
    if worldObject and worldObject.transmitModData then
        pcall(worldObject.transmitModData, worldObject)
    end
end

function Purifier.getInAmount(worldObject)
    local modData = getModData(worldObject)
    local value = modData and modData[Constants.PURIFIER_IN_AMOUNT_KEY]
    return type(value) == "number" and math.max(value, 0) or 0
end

function Purifier.isInTainted(worldObject)
    local modData = getModData(worldObject)
    return modData and modData[Constants.PURIFIER_IN_TAINTED_KEY] == true or false
end

function Purifier.getOutAmount(worldObject)
    local modData = getModData(worldObject)
    local value = modData and modData[Constants.PURIFIER_OUT_AMOUNT_KEY]
    return type(value) == "number" and math.max(value, 0) or 0
end

-- Was fluid actually moving on the last server tick? Distinct from isWorking, which only says the
-- tile has electricity.
function Purifier.isProcessing(worldObject)
    local modData = getModData(worldObject)
    return modData and modData[Constants.PURIFIER_PROCESSING_KEY] == true or false
end

-- Server-side, once per tick. Only writes and transmits on a CHANGE: this runs every tick on every
-- purifier, and transmitting an unchanged flag would be steady multiplayer traffic for nothing.
function Purifier.setProcessing(worldObject, processing)
    local modData = getModData(worldObject)
    if not modData then
        return
    end
    local value = processing and true or nil
    if modData[Constants.PURIFIER_PROCESSING_KEY] == value then
        return
    end
    modData[Constants.PURIFIER_PROCESSING_KEY] = value
    transmit(worldObject)
end

-- Room left in the IN buffer for `tainted`-ness of water, or 0 if it cannot take that kind.
-- This exists so a pump can feed the purifier directly. The pump used to ask the NETWORK how much it
-- could take, and that question never crosses a router -- which is exactly what a purifier sits on --
-- so a lake pump with a barrel only on the clean side was told "no room" and drew nothing.
-- A buffer already holding water accepts only more of the SAME kind: addIn keeps the existing taint
-- flag, so letting clean water into a tainted buffer would quietly relabel it.
function Purifier.intakeHeadroom(worldObject, tainted)
    if not Purifier.isPurifier(worldObject) then
        return 0
    end
    local amount = Purifier.getInAmount(worldObject)
    if amount > 0 and Purifier.isInTainted(worldObject) ~= (tainted and true or false) then
        return 0
    end
    return math.max(Constants.PURIFIER_BUFFER_CAPACITY - amount, 0)
end

-- Add intake into the IN buffer, recording whether it is tainted (an empty buffer adopts the type).
function Purifier.addIn(worldObject, amount, tainted)
    local modData = getModData(worldObject)
    if not modData or (amount or 0) <= 0 then
        return
    end
    if Purifier.getInAmount(worldObject) <= 0 then
        modData[Constants.PURIFIER_IN_TAINTED_KEY] = tainted and true or nil
    end
    modData[Constants.PURIFIER_IN_AMOUNT_KEY] = Purifier.getInAmount(worldObject) + amount
    transmit(worldObject)
end

-- Move fluid IN -> OUT (the OUT buffer is always clean Water). Clears the taint flag when IN empties.
function Purifier.moveInToOut(worldObject, amount)
    local modData = getModData(worldObject)
    if not modData then
        return
    end
    local moved = math.min(amount or 0, Purifier.getInAmount(worldObject))
    if moved <= 0 then
        return
    end
    local newIn = Purifier.getInAmount(worldObject) - moved
    modData[Constants.PURIFIER_IN_AMOUNT_KEY] = newIn
    if newIn <= 0 then
        modData[Constants.PURIFIER_IN_AMOUNT_KEY] = 0
        modData[Constants.PURIFIER_IN_TAINTED_KEY] = nil
    end
    modData[Constants.PURIFIER_OUT_AMOUNT_KEY] = Purifier.getOutAmount(worldObject) + moved
    transmit(worldObject)
end

-- (Purifier.removeOut is gone: the OUT buffer is a network container now, so the only thing that
-- takes water out of it is an ordinary rebalance through ContainerAdapter.writeDescriptorWaterAmount.
-- Keeping a second, hand-rolled way to drain it was how the old push step double-counted.)

-- ===== Location =====

-- The purifier-container object sitting on a square, or nil. It is a NON-pipe object (placed on a
-- router tile), so we scan every object on the square, not only pipes.
function Purifier.findOnSquare(square)
    if not square or not square.getObjects then
        return nil
    end
    local objects = square:getObjects()
    for index = 0, objects:size() - 1 do
        local worldObject = objects:get(index)
        if Purifier.isPurifier(worldObject) then
            return worldObject
        end
    end
    return nil
end

-- The purifier whose 2x2 footprint sits on a router tile. The tank's modData lives on ONE footprint
-- tile, not necessarily the anchor the engine registered, so a bare findOnSquare(routerTile) can miss it
-- and the router then wrongly runs as a plain passthrough. The footprint extends +x/+y from the anchor
-- and the router sits on the anchor, so scan that block.
local PURIFIER_FOOTPRINT_OFFSETS = { { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } }
Purifier.FOOTPRINT_OFFSETS = PURIFIER_FOOTPRINT_OFFSETS
function Purifier.findForRouterSquare(square)
    if not square then
        return nil
    end
    for _, off in ipairs(PURIFIER_FOOTPRINT_OFFSETS) do
        local sq = square
        if off[1] ~= 0 or off[2] ~= 0 then
            sq = World.squareAt(square:getX() + off[1], square:getY() + off[2], square:getZ())
        end
        local purifier = sq and Purifier.findOnSquare(sq)
        if purifier then
            return purifier
        end
    end
    return nil
end

-- ===== Removal =====

local function spriteNameOf(worldObject)
    if not worldObject or not worldObject.getSprite then
        return nil
    end
    local ok, sprite = pcall(worldObject.getSprite, worldObject)
    if not ok or not sprite or not sprite.getName then
        return nil
    end
    local okName, name = pcall(sprite.getName, sprite)
    return okName and name or nil
end

-- Is this object one of the four quadrants of a purifier tank? Answered by SPRITE, not by modData: only
-- ONE quadrant carries the modData, and the removal path has to recognise the other three -- they are
-- what would otherwise be left standing on the tile as a tank that no longer exists.
function Purifier.isTankPart(worldObject)
    if Purifier.isPurifier(worldObject) then
        return true
    end
    local name = spriteNameOf(worldObject)
    return name ~= nil and Constants.PURIFIER_TANK_ANCHOR_OFFSETS[name] ~= nil
end

-- Where the anchor (footprint 0,0) of the tank this quadrant belongs to stands. nil for anything that
-- is not a quadrant -- including a legacy purifier from a save that predates the 2x2 tank art, which
-- has no footprint to speak of and is its own anchor.
function Purifier.anchorCoordsForPart(worldObject)
    local square = worldObject and worldObject.getSquare and worldObject:getSquare() or nil
    if not square then
        return nil
    end
    local offset = Constants.PURIFIER_TANK_ANCHOR_OFFSETS[spriteNameOf(worldObject)]
    if not offset then
        return nil
    end
    return square:getX() + offset.dx, square:getY() + offset.dy, square:getZ()
end

-- Purifier on the tile: IN network -> IN buffer -> convert -> OUT buffer -> OUT network. Intake pulls
-- ONLY TAINTED water and ONLY from the IN network; output pushes clean water ONLY into the OUT network.
-- Intake happens with or without power; only converting needs power and filter life.
-- Step order is OUTPUT -> CONVERT -> INTAKE on purpose: draining the output first and refilling the
-- intake last leaves water resident in both buffers between ticks, so the tanks hold a real level
-- instead of being cycled to 0 every tick. Water just takes one extra tick to traverse.
-- `dt` is the elapsed in-game minutes for this sub-step; the per-minute rates are scaled by it.
-- ===== The per-tick step =====
-- Moved here from WaterPipeSystem: the ORDER below is the purifier's own contract and it was a
-- comment in another module, where nothing stopped a tidy-up from reordering it.
function Purifier.step(purifier, inSquare, outSquare, dt)
    if not purifier or (dt or 0) <= 0 then
        return
    end
    -- Resolved off the WaterPipes table rather than required: NetworkAccess requires this module.
    local NetworkAccess = WaterPipes.NetworkAccess
    -- Set by whichever step actually moves fluid. A tank sitting full while it pushes clean water out IS
    -- busy, and the readout used to call that "Stopped" purely because the levels looked static.
    local processed = false

    -- 1. Output: even the OUT buffer out with the rest of the clean network.
    -- It used to PUSH -- read the buffer, ask the network for headroom, fill it, subtract what was taken --
    -- which is exactly wrong now that the buffer IS one of that network's containers: the fill rebalances
    -- water back into the buffer and the subtraction removes it a second time. Settling moves nothing in or
    -- out, it only lets the level equalise; with no barrels it is a no-op and a tap can still reach it.
    local outAmount = Purifier.getOutAmount(purifier)
    if outAmount > 0 then
        local settled = NetworkAccess.settleAtSquare(outSquare)
        if settled > 0 and Purifier.getOutAmount(purifier) ~= outAmount then
            processed = true
        end
    end

    -- 2. Convert: move IN -> OUT. Tainted needs power AND filter life; clean water always passes.
    local inAmount = Purifier.getInAmount(purifier)
    if inAmount > 0 then
        local outHeadroom = Constants.PURIFIER_BUFFER_CAPACITY - Purifier.getOutAmount(purifier)
        if outHeadroom > 0 then
            local move = math.min(Constants.PURIFIER_CONVERT_RATE * dt, inAmount, outHeadroom)
            if Purifier.isInTainted(purifier) then
                -- Cleaning tainted water needs power AND a filter with life left. Every unit converted wears the
                -- filter; at 0 condition it stops and the water waits in IN until the player repairs it.
                if Purifier.canFilter(purifier) then
                    local before = Purifier.getInAmount(purifier)
                    Purifier.moveInToOut(purifier, move)   -- lands in the OUT buffer as clean Water
                    local converted = before - Purifier.getInAmount(purifier)
                    Purifier.wearFilter(purifier, converted)
                    processed = processed or converted > 0
                end
                -- tainted + not powered / clogged filter: stays in the IN buffer until it can be cleaned
            else
                local before = Purifier.getInAmount(purifier)
                Purifier.moveInToOut(purifier, move)       -- clean water always passes through
                processed = processed or Purifier.getInAmount(purifier) < before
            end
        end
    end

    -- 3. Intake: pull ONLY TAINTED water, and ONLY from the router's IN side. The purifier never draws
    -- clean water and never pulls anything back off the OUT side. Runs with or without power; only
    -- converting it later needs power and filter life.
    local avail, fluidType = NetworkAccess.availableToPull(inSquare)
    if fluidType == "TaintedWater" and avail > 0 then
        local curIn = Purifier.getInAmount(purifier)
        -- Pull into an empty buffer or one already holding tainted water (it is always tainted now).
        if curIn <= 0 or Purifier.isInTainted(purifier) then
            local headroom = Constants.PURIFIER_BUFFER_CAPACITY - curIn
            local pull = math.min(Constants.PURIFIER_INTAKE_RATE * dt, avail, headroom)
            if pull > 0 then
                local drawn = NetworkAccess.drawFluidAtSquare(inSquare, "TaintedWater", pull)
                if drawn and drawn > 0 then
                    Purifier.addIn(purifier, drawn, true)
                    processed = true
                end
            end
        end
    end

    -- Record what actually happened, so the readout reports it instead of guessing from the levels.
    Purifier.setProcessing(purifier, processed)
end

return Purifier
