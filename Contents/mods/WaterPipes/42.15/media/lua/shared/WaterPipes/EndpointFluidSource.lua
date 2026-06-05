WaterPipes = WaterPipes or {}
WaterPipes.EndpointFluidSource = WaterPipes.EndpointFluidSource or {}

require "WaterPipes/Constants"
require "WaterPipes/Logger"
require "WaterPipes/NetworkAccess"

local Constants = WaterPipes.Constants
local Logger = WaterPipes.Logger
local NetworkAccess = WaterPipes.NetworkAccess
local FluidSource = WaterPipes.EndpointFluidSource

local CONSUME_EPSILON = 0.001

-- The plumbed endpoint (sink/tap/shower) keeps its OWN FluidContainer component that
-- mirrors the connected pipe network. Because we use the vanilla "own container" path
-- (usesExternalWaterSource = false), the engine serves Drink/Wash/Fill straight from this
-- container -- no phantom world object is required. Consumption is reconciled back to the
-- network storage containers through NetworkAccess.useFluid.

local function isAuthoritative()
    if isServer and isServer() then
        return true
    end

    return not (isClient and isClient())
end

local function getModData(worldObject)
    if not worldObject or not worldObject.getModData then
        return nil
    end

    local ok, modData = pcall(worldObject.getModData, worldObject)
    return ok and modData or nil
end

local function describeObject(worldObject)
    if not worldObject then
        return "nil"
    end

    local name = worldObject.getName and worldObject:getName() or "?"
    local spriteName = (worldObject.getSprite and worldObject:getSprite() and worldObject:getSprite():getName()) or "?"
    local square = worldObject.getSquare and worldObject:getSquare() or nil
    local squareText = square and (tostring(square:getX()) .. "," .. tostring(square:getY()) .. "," .. tostring(square:getZ())) or "?, ?, ?"
    return tostring(name) .. " sprite=" .. tostring(spriteName) .. " square=" .. squareText
end

local function getFluidContainer(endpoint)
    if not endpoint or not endpoint.getFluidContainer then
        return nil
    end

    local ok, fluidContainer = pcall(endpoint.getFluidContainer, endpoint)
    return ok and fluidContainer or nil
end

local function getFluidTypeByName(fluidTypeName)
    if fluidTypeName == "Water" then
        return (FluidType and FluidType.Water) or (Fluid and Fluid.Water)
    end

    if fluidTypeName == "TaintedWater" then
        return (FluidType and FluidType.TaintedWater) or (Fluid and Fluid.TaintedWater)
    end

    if FluidType and FluidType.FromNameLower then
        return FluidType.FromNameLower(string.lower(fluidTypeName))
    end

    if Fluid and Fluid.FromNameLower then
        return Fluid.FromNameLower(string.lower(fluidTypeName))
    end

    return nil
end

local function ensureComponent(endpoint, capacity)
    local fluidContainer = getFluidContainer(endpoint)
    if fluidContainer then
        return fluidContainer
    end

    if not GameEntityFactory or not GameEntityFactory.AddComponent or not ComponentType or not ComponentType.FluidContainer then
        return nil
    end

    local component = ComponentType.FluidContainer.CreateComponent and ComponentType.FluidContainer:CreateComponent() or nil
    if not component then
        return nil
    end

    if component.setCapacity then
        component:setCapacity(math.max(capacity or 1, 1))
    end

    pcall(GameEntityFactory.AddComponent, endpoint, true, component)

    -- Newly attached component: push the full object so multiplayer clients receive it.
    if endpoint.transmitCompleteItemToClients then
        pcall(endpoint.transmitCompleteItemToClients, endpoint)
    end

    return getFluidContainer(endpoint)
end

local function setSyncing(endpoint, value)
    local modData = getModData(endpoint)
    if modData then
        modData[Constants.ENDPOINT_FLUID_SYNCING_KEY] = value and true or nil
    end
end

local function isSyncing(endpoint)
    local modData = getModData(endpoint)
    return modData and modData[Constants.ENDPOINT_FLUID_SYNCING_KEY] == true or false
end

local function setLastSync(endpoint, amount)
    local modData = getModData(endpoint)
    if modData then
        modData[Constants.ENDPOINT_FLUID_LAST_SYNC_KEY] = amount
    end

    if endpoint.transmitModData then
        pcall(endpoint.transmitModData, endpoint)
    end
end

local function getLastSync(endpoint)
    local modData = getModData(endpoint)
    local value = modData and modData[Constants.ENDPOINT_FLUID_LAST_SYNC_KEY]
    return type(value) == "number" and value or nil
end

local function readAmount(endpoint)
    local fluidContainer = getFluidContainer(endpoint)
    if fluidContainer and fluidContainer.getAmount then
        local ok, amount = pcall(fluidContainer.getAmount, fluidContainer)
        if ok and type(amount) == "number" then
            return math.max(amount, 0)
        end
    end

    return 0
end

-- Writes the network snapshot straight into the endpoint's FluidContainer.
-- We operate on the FluidContainer component directly (not endpoint:addFluid/emptyFluid),
-- so the IsoObject-level OnWaterAmountChange event is NOT raised by our own writes and we
-- avoid a reconciliation feedback loop. The syncing flag is kept as an extra safety net.
local function writeSnapshot(endpoint, amount, capacity, fluidTypeName)
    local effectiveCapacity = math.max(capacity or 0, 1)
    local fluidContainer = ensureComponent(endpoint, effectiveCapacity)
    if not fluidContainer then
        Logger.error("EndpointFluidSource: could not attach FluidContainer to " .. describeObject(endpoint))
        return false
    end

    local effectiveAmount = math.max(math.min(amount or 0, effectiveCapacity), 0)

    setSyncing(endpoint, true)

    -- Unlock input while we write, then lock it again so the player cannot pour arbitrary
    -- fluids into the network mirror (which would otherwise be silently discarded).
    if fluidContainer.setInputLocked then
        pcall(fluidContainer.setInputLocked, fluidContainer, false)
    end

    if fluidContainer.setCapacity then
        pcall(fluidContainer.setCapacity, fluidContainer, effectiveCapacity)
    end

    if fluidContainer.Empty then
        pcall(fluidContainer.Empty, fluidContainer)
    elseif fluidContainer.removeFluid then
        pcall(fluidContainer.removeFluid, fluidContainer)
    end

    if effectiveAmount > 0 and fluidTypeName then
        local fluidType = getFluidTypeByName(fluidTypeName)
        if fluidType and fluidContainer.addFluid then
            pcall(fluidContainer.addFluid, fluidContainer, fluidType, effectiveAmount)
        end
    end

    if fluidContainer.setInputLocked then
        pcall(fluidContainer.setInputLocked, fluidContainer, true)
    end

    if endpoint.sync then
        pcall(endpoint.sync, endpoint)
    end
    if endpoint.transmitModData then
        pcall(endpoint.transmitModData, endpoint)
    end

    setSyncing(endpoint, false)
    setLastSync(endpoint, readAmount(endpoint))
    return true
end

-- Catch-all reconciliation: any drop of the mirror's amount since the last sync is charged
-- to the network. This covers every drain path -- not only the ones that raise the
-- IsoObject-level OnWaterAmountChange event (Drink/Wash), but also the "Transfer Fluids" UI,
-- which moves liquid at the FluidContainer level (FluidContainer.Transfer) and never fires
-- that event. Because we always reconcile the delta against the recorded last-sync value,
-- it stays idempotent: a drain handled immediately by the event is not charged twice here.
local function reconcileConsumption(endpoint)
    if isSyncing(endpoint) then
        return 0
    end

    local lastSync = getLastSync(endpoint)
    if type(lastSync) ~= "number" then
        return 0
    end

    local consumed = lastSync - readAmount(endpoint)
    if consumed <= CONSUME_EPSILON then
        return 0
    end

    local applied = NetworkAccess.useFluid(endpoint, consumed)
    Logger.log("Endpoint reconciled consumption: " .. describeObject(endpoint) .. " consumed=" .. tostring(consumed) .. " applied=" .. tostring(applied))
    return applied
end

-- Mirror the connected network into the endpoint's own FluidContainer.
function FluidSource.syncForEndpoint(endpoint)
    if not isAuthoritative() or not endpoint then
        return false
    end

    -- First settle any water the player already took out (any path), then refresh the mirror.
    reconcileConsumption(endpoint)

    local summary = NetworkAccess.getSummary(endpoint)
    if not summary or (summary.totalCapacity or 0) <= 0 then
        writeSnapshot(endpoint, 0, 1, nil)
        return false
    end

    -- Mixed-fluid or non-water networks: expose capacity but no usable water.
    if summary.isMixed or not summary.isWater then
        writeSnapshot(endpoint, 0, summary.totalCapacity, nil)
        return true
    end

    local capacity = math.max(summary.totalCapacity or 0, 0)
    local visibleAmount = math.min(summary.totalAmount or 0, capacity)
    -- Vanilla plumbed taps purify: water served at the endpoint is always clean, even when
    -- the network stores tainted rain water. The stored water itself stays tainted; only what
    -- comes out of the tap is purified.
    writeSnapshot(endpoint, visibleAmount, capacity, "Water")
    return true
end

-- Empties the mirror and unlocks input (used on unplumb / pipe removal).
function FluidSource.clearForEndpoint(endpoint)
    if not isAuthoritative() or not endpoint then
        return
    end

    local fluidContainer = getFluidContainer(endpoint)
    if not fluidContainer then
        setLastSync(endpoint, 0)
        return
    end

    setSyncing(endpoint, true)

    if fluidContainer.Empty then
        pcall(fluidContainer.Empty, fluidContainer)
    elseif fluidContainer.removeFluid then
        pcall(fluidContainer.removeFluid, fluidContainer)
    end
    if fluidContainer.setInputLocked then
        pcall(fluidContainer.setInputLocked, fluidContainer, false)
    end

    if endpoint.sync then
        pcall(endpoint.sync, endpoint)
    end
    if endpoint.transmitModData then
        pcall(endpoint.transmitModData, endpoint)
    end

    setSyncing(endpoint, false)
    setLastSync(endpoint, 0)
end

-- Triggered (via OnWaterAmountChange) when the player drinks/washes/fills from the endpoint.
-- Reconciliation and mirror refresh both happen inside syncForEndpoint (delta-based), so this
-- is just the immediate fast-path for event-driven drains; the periodic refresh catches the
-- rest (e.g. the Transfer Fluids UI, which does not raise this event).
function FluidSource.onEndpointWaterAmountChange(endpoint, prevAmount)
    if not isAuthoritative() or not endpoint then
        return
    end

    if isSyncing(endpoint) then
        setLastSync(endpoint, readAmount(endpoint))
        return
    end

    FluidSource.syncForEndpoint(endpoint)
end
