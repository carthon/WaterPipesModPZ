WaterPipes = WaterPipes or {}
WaterPipes.Pump = WaterPipes.Pump or {}

require "WaterPipes/Constants"
require "WaterPipes/PipeObjectUtils"
require "WaterPipes/Pressure"

local Constants = WaterPipes.Constants
local PipeObjectUtils = WaterPipes.PipeObjectUtils
local Pressure = WaterPipes.Pressure
local Pump = WaterPipes.Pump

-- A water pump is a floor pipe flagged in modData that needs power. It does two jobs, and which one
-- it does falls out of where the player puts it (see the pump block in Constants.lua):
--   * head   -- every powered pump raises the pressure of the zone it sits in.
--   * intake -- a pump next to a well or open water also injects fluid into the network.
-- Both are gated on power: cut the electricity and the pump contributes nothing, so the network
-- silently falls back to plain gravity.

local function getModData(worldObject)
    if not worldObject or not worldObject.getModData then
        return nil
    end
    local ok, modData = pcall(worldObject.getModData, worldObject)
    return ok and modData or nil
end

function Pump.isPump(worldObject)
    local modData = getModData(worldObject)
    return modData and modData[Constants.PUMP_MODDATA_KEY] == true or false
end

function Pump.findOnSquare(square)
    if not square then
        return nil
    end
    for _, worldObject in ipairs(PipeObjectUtils.getPipeObjectsOnSquare(square)) do
        if Pump.isPump(worldObject) then
            return worldObject
        end
    end
    return nil
end

function Pump.hasPumpOnSquare(square)
    return Pump.findOnSquare(square) ~= nil
end

-- Sprite is picked by axis, like a straight pipe: the pump never autotiles into corners.
function Pump.spriteFor(worldObject)
    local modData = getModData(worldObject)
    local axis = modData and modData[Constants.PIPE_AXIS_MODDATA_KEY]
    if axis == Constants.PIPE_AXIS_NS then
        return Constants.PUMP_SPRITE_NS
    end
    return Constants.PUMP_SPRITE_EW
end

-- ===== Power =====

local function squareHasPower(square)
    if not square or not square.haveElectricity then
        return false
    end
    local ok, powered = pcall(square.haveElectricity, square)
    return ok and powered or false
end

-- A pump runs only with BOTH gates up: mains power on its tile, and the player's switch left on.
-- Everything downstream (head, intake, the pressure report) asks isPowered and nothing else, so
-- combining the two there is enough -- no call site needs to know the switch exists.
function Pump.hasPower(worldObject)
    if not Pump.isPump(worldObject) then
        return false
    end
    local square = worldObject.getSquare and worldObject:getSquare() or nil
    return squareHasPower(square)
end

-- Absent key means ON -- see PUMP_ENABLED_KEY. Every pump that predates the switch keeps working.
function Pump.isEnabled(worldObject)
    local modData = getModData(worldObject)
    return not modData or modData[Constants.PUMP_ENABLED_KEY] ~= false
end

-- Server-authoritative in MP: clients request the flip, the server lands here (see ISTogglePump).
function Pump.setEnabled(worldObject, enabled)
    local modData = getModData(worldObject)
    if not modData then
        return
    end
    modData[Constants.PUMP_ENABLED_KEY] = enabled and true or false
    if worldObject.transmitModData then
        pcall(worldObject.transmitModData, worldObject)
    end
end

function Pump.isPowered(worldObject)
    return Pump.hasPower(worldObject) and Pump.isEnabled(worldObject)
end

-- ===== Head =====

-- Total head a zone's pumps add. `pumps` comes from the network walk, which already had each
-- square's pipe objects in hand. Unpowered pumps contribute nothing, so cutting the electricity
-- silently drops the whole network back to plain gravity.
function Pump.headForPumps(pumps)
    if not pumps then
        return 0
    end

    local perPump = Pressure.pumpHead()
    local total = 0
    for _, pump in ipairs(pumps) do
        if Pump.isPowered(pump) then
            total = total + perPump
        end
    end
    return total
end

-- ===== Source detection (extractor mode) =====

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

-- Server admins can switch off pumping from rivers and lakes without losing wells or the rest of
-- the pressure model: it is the one source that is genuinely infinite.
local function waterBodiesAllowed()
    local sv = SandboxVars and SandboxVars.WaterPipes
    local v = sv and sv.PumpFromWaterBodies
    if type(v) == "boolean" then
        return v
    end
    return true
end

-- Open water, identified the way vanilla's own isValidWaterSquare does it: the floor tile carries
-- the `water` property. Infinite, and always TaintedWater.
local function isOpenWaterSquare(square)
    if not square or not square.getFloor then
        return false
    end
    local ok, floor = pcall(square.getFloor, square)
    if not ok or not floor or not floor.hasProperty then
        return false
    end
    local okProp, hasWater = pcall(floor.hasProperty, floor, IsoFlagType.water)
    return okProp and hasWater or false
end

-- The name of the entity script behind a world object, or nil for a plain scenery tile.
--
-- getEntityScript() is the accessor that answers on a B42 entity object; getScriptName() is the
-- vehicle one and returns the literal string "none" here, which is why asking it alone never matched
-- a well. Both are tried, cheapest-correct first, so this keeps working either way.
local function entityNameOf(worldObject)
    if not worldObject then
        return nil
    end

    if worldObject.getEntityScript then
        local ok, script = pcall(worldObject.getEntityScript, worldObject)
        if ok and script and script.getName then
            local okName, name = pcall(script.getName, script)
            if okName and name and name ~= "" then
                return name
            end
        end
    end

    if worldObject.getScriptName then
        local ok, name = pcall(worldObject.getScriptName, worldObject)
        if ok and name and name ~= "" and name ~= "none" then
            return name
        end
    end

    return nil
end
Pump.entityNameOf = entityNameOf

function Pump.isWell(worldObject)
    local name = entityNameOf(worldObject)
    return name == Constants.WELL_ENTITY_NAME or name == Constants.WELL_SCRIPT_NAME
end

-- A well is an entity object carrying a FluidContainer of clean water. It is deliberately NOT an
-- ordinary network container (its capacity is above MAX_FINITE_FLUID_CAPACITY), so the pump is the
-- only way its water reaches the pipes.
local function findWellOnSquare(square)
    if not square or not square.getObjects then
        return nil
    end
    local ok, objects = pcall(square.getObjects, square)
    if not ok or not objects then
        return nil
    end
    for i = 0, objects:size() - 1 do
        local worldObject = objects:get(i)
        if Pump.isWell(worldObject) then
            return worldObject
        end
    end
    return nil
end

-- Can a pump at pumpZ still lift a source sitting at sourceZ? Suction is capped by atmospheric
-- pressure, not by the motor, so a source more than ~2 floors down simply will not prime.
function Pump.canLiftFrom(pumpZ, sourceZ)
    local drop = (pumpZ or 0) - (sourceZ or 0)
    if drop <= 0 then
        return true   -- source level with the pump or above it: gravity feeds the inlet
    end
    return drop * Pressure.levelHead() <= Pressure.suctionLimit()
end

-- The natural source a pump can draw from, searched over its own tile and the cardinal neighbours,
-- across the floors its suction can still reach. Returns a descriptor or nil.
function Pump.findSource(pumpObject)
    local square = pumpObject and pumpObject.getSquare and pumpObject:getSquare() or nil
    if not square then
        return nil
    end

    local px, py, pz = square:getX(), square:getY(), square:getZ()
    -- How many floors down suction still reaches (0 = same floor only).
    local levelHead = Pressure.levelHead()
    local maxDrop = levelHead > 0 and math.floor(Pressure.suctionLimit() / levelHead) or 0

    local offsets = { { x = 0, y = 0 } }
    for _, offset in ipairs(Constants.CARDINAL_OFFSETS) do
        offsets[#offsets + 1] = { x = offset.x, y = offset.y }
    end

    for drop = 0, maxDrop do
        local z = pz - drop
        for _, offset in ipairs(offsets) do
            local candidate = getCellSquare(px + offset.x, py + offset.y, z)
            if candidate then
                local well = findWellOnSquare(candidate)
                if well then
                    return { kind = "well", object = well, square = candidate, fluidType = "Water" }
                end
                if waterBodiesAllowed() and isOpenWaterSquare(candidate) then
                    -- Rivers and lakes are infinite and dirty: this is what feeds the purifier.
                    return { kind = "water", square = candidate, fluidType = "TaintedWater" }
                end
            end
        end
    end

    return nil
end

-- How much a pump may move in `dt` in-game minutes.
function Pump.intakeFor(dt)
    local sv = SandboxVars and SandboxVars.WaterPipes
    local rate = sv and sv.PumpIntakeRate
    if type(rate) ~= "number" then
        rate = Constants.PUMP_INTAKE_RATE
    end
    return math.max(rate, 0) * math.max(dt or 0, 0)
end

-- Draw up to `amount` out of a source descriptor. A well has a real FluidContainer to drain; open
-- water is infinite, so nothing is deducted. Returns how much was actually taken.
function Pump.drawFromSource(source, amount)
    if not source or (amount or 0) <= 0 then
        return 0
    end

    if source.kind == "water" then
        return amount   -- a river does not run dry
    end

    local container = source.object and source.object.getFluidContainer
        and source.object:getFluidContainer() or nil
    if not container or not container.getAmount then
        return 0
    end

    local okAmount, available = pcall(container.getAmount, container)
    if not okAmount or (available or 0) <= 0 then
        return 0
    end

    local taken = math.min(amount, available)
    if taken <= 0 then
        return 0
    end

    -- adjustAmount is an absolute set, not a delta -- see ISWaterPlantAction for vanilla's usage.
    local okSet = pcall(container.adjustAmount, container, available - taken)
    if not okSet then
        return 0
    end
    return taken
end

-- Hand back fluid the network turned out not to be able to take. Open water needs no refund (we
-- never actually removed anything), but a well would otherwise quietly lose the difference.
function Pump.refundToSource(source, amount)
    if not source or (amount or 0) <= 0 or source.kind == "water" then
        return
    end

    local container = source.object and source.object.getFluidContainer
        and source.object:getFluidContainer() or nil
    if not container or not container.getAmount then
        return
    end

    local okAmount, current = pcall(container.getAmount, container)
    if not okAmount then
        return
    end

    local capacity = container.getCapacity and container:getCapacity() or nil
    local restored = current + amount
    if capacity then
        restored = math.min(restored, capacity)
    end
    pcall(container.adjustAmount, container, restored)
end

-- ===== Readout =====

-- Everything the status dialog and the context menu need, in one call.
--
-- NetworkAccess is deliberately NOT required at the top of this file: it already requires Pump, and
-- closing that loop would make the pair a recursive require. Anything asking for a status runs long
-- after both modules are loaded, so it is resolved off the WaterPipes table here instead.
function Pump.getStatus(pumpObject)
    if not Pump.isPump(pumpObject) then
        return nil
    end
    local square = pumpObject.getSquare and pumpObject:getSquare() or nil
    if not square then
        return nil
    end

    local status = {
        enabled = Pump.isEnabled(pumpObject),
        hasPower = Pump.hasPower(pumpObject),
    }
    status.running = status.enabled and status.hasPower

    -- Intake side. Finding a source is about WHERE the pump stands, so it answers even while the pump
    -- is off -- "there is a well right here, you just have it switched off" is the useful answer.
    local source = Pump.findSource(pumpObject)
    status.sourceKind = source and source.kind or nil     -- "well" | "water" | nil
    status.drawing = status.running and source ~= nil

    -- Pressure side. `outlet` is what the line actually holds at this tile right now; `inlet` is what
    -- it would hold WITHOUT this pump. A zone's lift is max(pump head, municipal supply floor), so a
    -- pump standing on a mains-fed run can be adding nothing at all -- which is exactly what the
    -- player is trying to find out. Taking the difference between the two lifts says so honestly,
    -- where subtracting a nominal 25.0 would invent a contribution the pump is not making.
    local NetworkAccess = WaterPipes.NetworkAccess
    local report = NetworkAccess and NetworkAccess.getPressureReport(square) or nil
    if report then
        status.pressureEnabled = report.enabled

        local own = Pressure.pumpHead()
        local supply = report.supplyHead or 0
        -- headForPumps only counts POWERED pumps, so this already excludes us while we are off.
        local others = report.pumpHead or 0
        if status.running then
            others = math.max(others - own, 0)
        end
        local delta = math.max(others + own, supply) - math.max(others, supply)

        local tap = report.kinds and report.kinds[Constants.PRESSURE_KIND_TAP] or nil
        local outlet = tap and tap.head or nil
        status.outlet = outlet
        if outlet then
            status.inlet = status.running and math.max(outlet - delta, 0) or outlet
        end
        -- What flipping the switch would buy, so an idle pump can justify itself.
        status.wouldGain = (not status.running) and delta or 0
    end

    return status
end

return Pump
