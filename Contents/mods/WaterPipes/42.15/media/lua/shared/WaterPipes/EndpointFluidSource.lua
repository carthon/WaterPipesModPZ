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

-- The plumbed endpoint keeps its OWN FluidContainer component mirroring the connected pipe network.
-- Using the vanilla "own container" path (usesExternalWaterSource = false) means the engine serves
-- Drink/Wash/Fill straight from it, and consumption is reconciled back through NetworkAccess.useFluid.

local function isAuthoritative()
    if isServer and isServer() then
        return true
    end

    return not (isClient and isClient())
end

-- Sandbox toggle: when ON, taps stop auto-purifying tainted water (it must be run through a
-- purifier tile first). Default OFF preserves the classic behaviour (the tap purifies rainwater).
local function realisticPurification()
    local sv = SandboxVars and SandboxVars.WaterPipes
    return sv and sv.RealisticPurification == true or false
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

local function readNumber(owner, methodName)
    if not owner or not owner[methodName] then
        return nil
    end
    local ok, value = pcall(owner[methodName], owner)
    return ok and type(value) == "number" and value or nil
end

-- What the fixture itself can hold. The mirror is written into the tank the fixture ALREADY has and
-- never into one we attach: attaching a FluidContainer turns the object into an entity, and the engine
-- leaves the original on the tile, so every fixture connected came out as two -- two sprites, two fluid
-- menus, and a second one that survived being disconnected.
local function ownCapacity(endpoint)
    return readNumber(endpoint, "getFluidCapacity")
        or readNumber(getFluidContainer(endpoint), "getCapacity")
        or 0
end

-- Ours, not the fixture's. A tank we attached is one we also SIZE to the network; a fixture's own tank
-- is left at whatever the fixture says it holds.
local OUR_TANK_KEY = "waterpipesOwnTank"

-- What the tank should read, recorded on the object so it travels as modData. A FluidContainer does
-- NOT replicate: its capacity reaches a client only with the whole object, and sending a fixture whole
-- puts a second copy of it in the client's world. So the numbers go over as data and each client fills
-- its own copy of the tank from them.
local MIRROR_KEY = "waterpipesMirror"

local function objectsOnTile(endpoint)
    local square = endpoint and endpoint.getSquare and endpoint:getSquare() or nil
    local objects = square and square.getObjects and square:getObjects() or nil
    return objects and objects.size and objects:size() or -1
end

-- Plenty of vanilla fixtures hold no fluid at all until something gives them a tank, and without one
-- there is nowhere to mirror the network and the engine shows no fluid menu. So attach one.
--
-- It is the only thing here that can change what is ON the tile, and a sink dumped either side of a
-- pass came back as two objects -- so the tile is counted across the call and said out loud. If the
-- count moves, this is what moved it.
local function attachTank(endpoint, capacity)
    if not GameEntityFactory or not GameEntityFactory.AddComponent
        or not ComponentType or not ComponentType.FluidContainer then
        return nil
    end
    local component = ComponentType.FluidContainer.CreateComponent
        and ComponentType.FluidContainer:CreateComponent() or nil
    if not component then
        return nil
    end
    if component.setCapacity then
        component:setCapacity(math.max(capacity or 1, 1))
    end

    local before = objectsOnTile(endpoint)
    pcall(GameEntityFactory.AddComponent, endpoint, true, component)
    local after = objectsOnTile(endpoint)
    Logger.log(("EndpointFluidSource: gave %s a tank of its own (it had none); objects on the tile %d -> %d")
        :format(describeObject(endpoint), before, after))

    -- NOT transmitted whole. Sending the complete item works for an object a client has never seen --
    -- a pipe we just created -- but a fixture is already in the client's world, and it ADDS the copy
    -- rather than replacing what it has: the server kept one sink and the client showed two, each with
    -- its own fluid menu, and the spare survived being disconnected. The per-write sync is what carries
    -- the tank's contents to clients.

    local modData = getModData(endpoint)
    if modData then
        modData[OUR_TANK_KEY] = true
    end
    return getFluidContainer(endpoint)
end

-- Said once per fixture: the refresh comes round every minute and a fixture that cannot take a tank
-- will not take one next time either.
local warnedNoTank = {}
local function warnNoTank(endpoint)
    local key = tostring(endpoint)
    if warnedNoTank[key] then
        return
    end
    warnedNoTank[key] = true
    Logger.warn("EndpointFluidSource: " .. describeObject(endpoint)
        .. " has no tank and could not be given one, so it has nothing to serve.")
end

local function hasOurTank(endpoint)
    local modData = getModData(endpoint)
    return modData and modData[OUR_TANK_KEY] == true or false
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
    local amount = readNumber(endpoint, "getFluidAmount")
        or readNumber(getFluidContainer(endpoint), "getAmount")
    return math.max(amount or 0, 0)
end

-- Put `amount` of `fluidTypeName` in the tank, emptying it first. A tank the FIXTURE came with keeps
-- its own capacity -- what the player reads is a full sink rather than the whole network's litres, and
-- a fixture holding more than it can is not a thing the engine can show. A tank we attached has no
-- size of its own, so it is sized to the network.
-- The syncing flag stops our own write coming back as consumption to reconcile.
local function writeFluid(endpoint, amount, fluidTypeName, networkCapacity, localOnly)
    local fluidContainer = getFluidContainer(endpoint)
    if networkCapacity and hasOurTank(endpoint) and fluidContainer and fluidContainer.setCapacity then
        pcall(fluidContainer.setCapacity, fluidContainer, math.max(networkCapacity, 1))
    end
    local capacity = ownCapacity(endpoint)
    local effectiveAmount = math.max(math.min(amount or 0, capacity), 0)

    setSyncing(endpoint, true)

    -- Unlock input while we write, then lock it again so the player cannot pour arbitrary
    -- fluids into the network mirror (which would otherwise be silently discarded).
    if fluidContainer and fluidContainer.setInputLocked then
        pcall(fluidContainer.setInputLocked, fluidContainer, false)
    end

    if endpoint.emptyFluid then
        pcall(endpoint.emptyFluid, endpoint)
    elseif fluidContainer and fluidContainer.Empty then
        pcall(fluidContainer.Empty, fluidContainer)
    end

    if effectiveAmount > 0 and fluidTypeName then
        local fluidType = getFluidTypeByName(fluidTypeName)
        if fluidType then
            if endpoint.addFluid then
                pcall(endpoint.addFluid, endpoint, fluidType, effectiveAmount)
            elseif fluidContainer and fluidContainer.addFluid then
                pcall(fluidContainer.addFluid, fluidContainer, fluidType, effectiveAmount)
            end
        end
    end

    if fluidContainer and fluidContainer.setInputLocked then
        pcall(fluidContainer.setInputLocked, fluidContainer, true)
    end

    -- A client is filling in its OWN copy of a tank the server already owns. Announcing that would
    -- send the client's guess back over the top of the authority it came from.
    if not localOnly then
        if endpoint.sync then
            pcall(endpoint.sync, endpoint)
        end
        if endpoint.transmitModData then
            pcall(endpoint.transmitModData, endpoint)
        end
    end

    setSyncing(endpoint, false)
end

-- The network snapshot, as much of it as the tank can hold.
local function writeSnapshot(endpoint, amount, fluidTypeName, networkCapacity)
    if not endpoint or not endpoint.addFluid or not endpoint.emptyFluid then
        return false
    end
    if ownCapacity(endpoint) <= 0 and not attachTank(endpoint, networkCapacity) then
        warnNoTank(endpoint)
        return false
    end
    writeFluid(endpoint, amount, fluidTypeName, networkCapacity)
    setLastSync(endpoint, readAmount(endpoint))

    local modData = getModData(endpoint)
    if modData then
        modData[MIRROR_KEY] = { amount = readAmount(endpoint), capacity = ownCapacity(endpoint),
                                fluid = fluidTypeName }
    end
    if endpoint.transmitModData then
        pcall(endpoint.transmitModData, endpoint)
    end
    return true
end

-- The client's own copy of the tank, filled from what the server recorded. Runs on the CLIENT only:
-- the server is where the numbers come from, and it has already written them into its own object.
-- Lazy on purpose -- a fixture is refreshed when a player is about to look at it, not on a timer.
function FluidSource.mirrorForClient(endpoint)
    if not (isClient and isClient()) or isServer and isServer() then
        return false
    end
    local modData = getModData(endpoint)
    local mirror = modData and modData[MIRROR_KEY]
    if type(mirror) ~= "table" then
        return false
    end

    local capacity = math.max(tonumber(mirror.capacity) or 0, 0)
    if capacity <= 0 then
        return false
    end
    if ownCapacity(endpoint) <= 0 and not attachTank(endpoint, capacity) then
        return false
    end

    local fluidContainer = getFluidContainer(endpoint)
    if fluidContainer and fluidContainer.setCapacity and ownCapacity(endpoint) ~= capacity then
        pcall(fluidContainer.setCapacity, fluidContainer, capacity)
    end

    local amount = math.max(tonumber(mirror.amount) or 0, 0)
    if math.abs(readAmount(endpoint) - amount) > CONSUME_EPSILON then
        writeFluid(endpoint, amount, mirror.fluid, nil, true)
    end
    return true
end

-- Catch-all reconciliation: any drop of the mirror's amount since the last sync is charged to the
-- network. This covers every drain path, not only the ones raising OnWaterAmountChange -- the "Transfer
-- Fluids" UI moves liquid at the FluidContainer level and never fires that event. Reconciling the delta
-- against the recorded last-sync value keeps it idempotent, so a drain is never charged twice.
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
    local detail = ""
    -- Only when the draw came up SHORT. "applied" says what the draw believed, and that is enough while
    -- it got everything it asked for; the litres it could not find are the ones worth naming vessels over.
    if applied < consumed - CONSUME_EPSILON then
        detail = " | short by " .. string.format("%.2f", consumed - applied)
            .. " -- vessels: " .. NetworkAccess.describeVessels(endpoint)
    end
    Logger.log("Endpoint reconciled consumption: " .. describeObject(endpoint)
        .. " consumed=" .. tostring(consumed) .. " applied=" .. tostring(applied) .. detail)
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
        writeSnapshot(endpoint, 0, nil, summary and summary.totalCapacity or nil)
        return false
    end

    -- Mixed-fluid networks: dry, rather than serving a random fluid.
    if summary.isMixed then
        writeSnapshot(endpoint, 0, nil, summary.totalCapacity)
        return true
    end

    local visibleAmount = math.max(summary.totalAmount or 0, 0)
    -- Any single fluid in the network can be drawn from the tap. By default the tap purifies rain water:
    -- TaintedWater is served as clean Water, while the stored water stays tainted. With the "Realistic water
    -- purification" sandbox option ON it is served as-is and must be cleaned by a purifier tile. Every
    -- other fluid is always served as-is.
    local servedType = summary.fluidTypeName
    if servedType == "TaintedWater" and not realisticPurification() then
        servedType = "Water"
    end
    return writeSnapshot(endpoint, visibleAmount, servedType, summary.totalCapacity)
end

local function readContainerState(endpoint)
    local state = { capacity = ownCapacity(endpoint), amount = readAmount(endpoint),
                    fluidType = nil, inputLocked = false }

    -- Through the adapter, which is the one place that knows tainted water is the Water fluid carrying
    -- a flag. Asking the container directly reads "Water" for both, and a capture with no type at all
    -- restores an empty fixture -- the water it had when we took it over, gone.
    -- Resolved off the WaterPipes table rather than required: NetworkAccess already loads it.
    local Adapter = WaterPipes.ContainerAdapter
    if state.amount > 0 and Adapter and Adapter.readWorldFluidType then
        state.fluidType = Adapter.readWorldFluidType(endpoint)
    end

    local fluidContainer = getFluidContainer(endpoint)
    if fluidContainer and fluidContainer.isInputLocked then
        local ok, value = pcall(fluidContainer.isInputLocked, fluidContainer)
        if ok then state.inputLocked = value and true or false end
    end

    return state
end

-- Snapshot the fixture's own FluidContainer state before the network mirror overwrites it.
-- Captured once on plumb; restored verbatim on unplumb.
function FluidSource.captureOriginalState(endpoint)
    if not isAuthoritative() or not endpoint then
        return
    end

    local modData = getModData(endpoint)
    if not modData or modData[Constants.ENDPOINT_ORIGINAL_FLUID_KEY] ~= nil then
        return
    end

    local state = readContainerState(endpoint)
    -- Also snapshot the fixture's pre-plumb water-source flags so unplumb can restore them: a
    -- kitchen sink that was an infinite city-mains tap (canBeWaterPiped absent) must become one
    -- again, and a fixture using a rain barrel must keep using it.
    state.canBeWaterPiped = modData.canBeWaterPiped
    state.usesExternalWaterSource = false
    if endpoint.getUsesExternalWaterSource then
        local ok, value = pcall(endpoint.getUsesExternalWaterSource, endpoint)
        if ok then
            state.usesExternalWaterSource = value and true or false
        end
    end

    modData[Constants.ENDPOINT_ORIGINAL_FLUID_KEY] = state
    if endpoint.transmitModData then
        pcall(endpoint.transmitModData, endpoint)
    end
end

-- Restore the fixture's own FluidContainer to the captured pre-plumb state (used on unplumb), so
-- it no longer shows the network's capacity/mirror.
function FluidSource.restoreOriginalState(endpoint)
    if not isAuthoritative() or not endpoint then
        return
    end

    local modData = getModData(endpoint)
    local state = modData and modData[Constants.ENDPOINT_ORIGINAL_FLUID_KEY] or nil

    -- The water it held before we took it over. Its capacity was never ours to change, so there is
    -- nothing to put back but the litres.
    writeFluid(endpoint, state and state.amount or 0, state and state.fluidType or nil)
    local fluidContainer = getFluidContainer(endpoint)
    if fluidContainer and fluidContainer.setInputLocked then
        pcall(fluidContainer.setInputLocked, fluidContainer, (state and state.inputLocked) and true or false)
    end

    -- Restore the pre-plumb water-source flags. canBeWaterPiped governs the engine's infinite
    -- city-mains water: leaving it nil/false makes the fixture an infinite tap again (if the water
    -- service is on), which is exactly the pre-plumb behaviour we want back.
    if modData then
        modData.canBeWaterPiped = state and state.canBeWaterPiped
    end
    if endpoint.setUsesExternalWaterSource then
        pcall(endpoint.setUsesExternalWaterSource, endpoint, (state and state.usesExternalWaterSource) and true or false)
    end
    if endpoint.transmitModData then
        pcall(endpoint.transmitModData, endpoint)
    end
    if endpoint.sync then
        pcall(endpoint.sync, endpoint)
    end

    if modData then
        modData[Constants.ENDPOINT_ORIGINAL_FLUID_KEY] = nil
    end
    setLastSync(endpoint, 0)
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
