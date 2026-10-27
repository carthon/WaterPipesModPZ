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

-- FluidUtil.MIN_CONTAINER_CAPACITY: setCapacity never goes below it.
local ENGINE_MIN_CAPACITY = 0.05

-- The plumbed endpoint keeps its OWN FluidContainer component mirroring the connected pipe network.
-- Using the vanilla "own container" path (usesExternalWaterSource = false) means the engine serves
-- Drink/Wash/Fill straight from it, and consumption is reconciled back through NetworkAccess.useFluid.

-- Counters for the profiler, resolved off the global table so this module keeps no dependency on a
-- debug tool.
local function countPhase(name, amount)
    local Profiler = WaterPipes.Profiler
    if Profiler and Profiler.count then
        Profiler.count(name, amount or 1)
    end
end

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

-- The tank itself, never the IsoObject getters: those answer for whatever the engine would serve
-- instead -- the barrel above, the town mains (10000), the tile's 20 L reserve, or that reserve when
-- the tank is empty.
local function ownCapacity(endpoint)
    return readNumber(getFluidContainer(endpoint), "getCapacity") or 0
end

-- No vanilla fixture ships with a tank; one that does declares it in its entity script.
local function shipsWithTank(endpoint)
    local ok, ships = pcall(function()
        local script = endpoint:getEntityScript()
        return script ~= nil and script:containsComponent(ComponentType.FluidContainer) == true
    end)
    return ok and ships == true
end

-- The size that script gives it, to undo a version that sized it to the network.
local function shippedCapacity(endpoint)
    local ok, capacity = pcall(function()
        return endpoint:getEntityScript():getComponentScriptFor(ComponentType.FluidContainer):getCapacity()
    end)
    return ok and type(capacity) == "number" and capacity > 0 and capacity or nil
end

-- Any tank on a fixture that ships without one is ours, and is sized to the network.
local function hasOurTank(endpoint)
    return getFluidContainer(endpoint) ~= nil and not shipsWithTank(endpoint)
end

-- Ownership mark of 0.10.0/0.10.1, superseded by the rule above; only cleared now.
local OUR_TANK_KEY = "waterpipesOwnTank"

-- What the tank should read, recorded on the object so it travels as modData. Its contents reach a
-- client with sync(); the CAPACITY of a tank we attached does not, short of sending the whole object,
-- which puts a second copy of the fixture in the client's world. So each client sizes its own copy.
local MIRROR_KEY = "waterpipesMirror"

-- The capacity a tank we attached was given back on unplumb. With the mirror gone it is the only
-- thing that tells a client's copy of the tank to shrink too.
local RESTORED_KEY = "waterpipesTankRestored"

local reportedClient = {}

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
    -- The SIZE is the network's storage at this moment, which is nothing at all until something on the
    -- line holds water -- so a tank born at 1 L means the pipes reach no vessel yet, not a broken tank.
    Logger.log(("EndpointFluidSource: gave %s a %.2f L tank (it had none); objects on the tile %d -> %d")
        :format(describeObject(endpoint), math.max(capacity or 1, 1), before, after))

    -- NOT transmitted whole. Sending the complete item works for an object a client has never seen --
    -- a pipe we just created -- but a fixture is already in the client's world, and it ADDS the copy
    -- rather than replacing what it has: the server kept one sink and the client showed two, each with
    -- its own fluid menu, and the spare survived being disconnected. The per-write sync is what carries
    -- the tank's contents to clients.

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

-- One transmit, and only on a change. This runs on every plumbed fixture every minute, and announcing
-- numbers nobody moved is steady multiplayer traffic for nothing.
local function setLastSync(endpoint, amount, mirror)
    local modData = getModData(endpoint)
    if not modData then
        return
    end

    local previous = modData[MIRROR_KEY]
    local moved = modData[Constants.ENDPOINT_FLUID_LAST_SYNC_KEY] ~= amount
    if mirror and (type(previous) ~= "table"
        or previous.amount ~= mirror.amount
        or previous.capacity ~= mirror.capacity
        or previous.fluid ~= mirror.fluid) then
        modData[MIRROR_KEY] = mirror
        moved = true
    end
    modData[Constants.ENDPOINT_FLUID_LAST_SYNC_KEY] = amount
    modData[Constants.ENDPOINT_FLUID_LAST_SYNC_LEGACY_KEY] = nil

    if moved and endpoint.transmitModData then
        pcall(endpoint.transmitModData, endpoint)
    end
end

local function getLastSync(endpoint)
    local modData = getModData(endpoint)
    local value = modData and modData[Constants.ENDPOINT_FLUID_LAST_SYNC_KEY]
    return type(value) == "number" and value or nil
end

local function readAmount(endpoint)
    return math.max(readNumber(getFluidContainer(endpoint), "getAmount") or 0, 0)
end

-- Put `amount` of `fluidTypeName` in the tank, emptying it first. A tank the FIXTURE came with keeps
-- its own capacity -- what the player reads is a full sink rather than the whole network's litres, and
-- a fixture holding more than it can is not a thing the engine can show. A tank we attached has no
-- size of its own, so it is sized to the network.
-- The syncing flag stops our own write coming back as consumption to reconcile.
local function writeFluid(endpoint, amount, fluidTypeName, networkCapacity)
    local fluidContainer = getFluidContainer(endpoint)
    if networkCapacity and hasOurTank(endpoint) and fluidContainer and fluidContainer.setCapacity then
        local wanted = math.max(networkCapacity, 1)
        if math.abs(ownCapacity(endpoint) - wanted) > CONSUME_EPSILON then
            -- Only on a real change: the tank follows the network's storage, and saying so is how a
            -- tank stuck at its birth size can be told from one the network never grew.
            Logger.log(("EndpointFluidSource: %s tank resized %.2f -> %.2f L")
                :format(describeObject(endpoint), ownCapacity(endpoint), wanted))
            pcall(fluidContainer.setCapacity, fluidContainer, wanted)
        end
    end
    local capacity = ownCapacity(endpoint)
    local effectiveAmount = math.max(math.min(amount or 0, capacity), 0)

    setSyncing(endpoint, true)

    -- Unlock input while we write, then lock it again so the player cannot pour arbitrary
    -- fluids into the network mirror (which would otherwise be silently discarded).
    if fluidContainer and fluidContainer.setInputLocked then
        pcall(fluidContainer.setInputLocked, fluidContainer, false)
    end

    -- Into the tank itself: IsoObject.emptyFluid/addFluid would write the barrel above or the tile's
    -- reserve instead. The tank raises no OnWaterAmountChange; the mute stays as a guard.
    -- One pcall around the whole muted stretch: an error inside must not leave the mod deaf.
    local muted = WaterPipes._suppressWaterEvent
    WaterPipes._suppressWaterEvent = true
    local okWrite, errWrite = pcall(function()
        if fluidContainer and fluidContainer.Empty then
            fluidContainer:Empty()
        end
        if fluidContainer and fluidContainer.addFluid and effectiveAmount > 0 and fluidTypeName then
            local fluidType = getFluidTypeByName(fluidTypeName)
            if fluidType then
                fluidContainer:addFluid(fluidType, effectiveAmount)
            end
        end
    end)
    WaterPipes._suppressWaterEvent = muted
    if not okWrite then
        Logger.error("EndpointFluidSource: write to " .. describeObject(endpoint) .. " failed: " .. tostring(errWrite))
    end

    if fluidContainer and fluidContainer.setInputLocked then
        pcall(fluidContainer.setInputLocked, fluidContainer, true)
    end

    -- The litres travel with sync(). The modData goes once, from the caller, with the mirror in it.
    if endpoint.sync then
        pcall(endpoint.sync, endpoint)
    end

    setSyncing(endpoint, false)
end

-- The network snapshot, as much of it as the tank can hold.
local function writeSnapshot(endpoint, amount, fluidTypeName, networkCapacity)
    if not endpoint or not endpoint.getFluidContainer then
        return false
    end
    local tankModData = getModData(endpoint)
    if tankModData then
        tankModData[RESTORED_KEY] = nil
        tankModData[OUR_TANK_KEY] = nil
    end
    -- A tank already there is reused, whatever size an older version left it: attaching a second
    -- component is what duplicates a fixture.
    if not getFluidContainer(endpoint) and not attachTank(endpoint, networkCapacity) then
        warnNoTank(endpoint)
        return false
    end
    -- A tank the fixture ships with keeps the size its script gives it.
    local shipped = shipsWithTank(endpoint) and shippedCapacity(endpoint)
    local tank = getFluidContainer(endpoint)
    if shipped and tank.setCapacity and math.abs(ownCapacity(endpoint) - shipped) > CONSUME_EPSILON then
        Logger.log(("EndpointFluidSource: %s own tank restored %.2f -> %.2f L (resized by an older version)")
            :format(describeObject(endpoint), ownCapacity(endpoint), shipped))
        pcall(tank.setCapacity, tank, shipped)
    end
    -- Already reading what it should? Touch nothing. The write empties the tank and refills it, and
    -- every step of that syncs and transmits -- once a minute per plumbed fixture, for numbers nobody
    -- moved. Most refreshes on a settled base have nothing to do.
    local modData = getModData(endpoint)
    local previous = modData and modData[MIRROR_KEY]
    local wantedCapacity = ownCapacity(endpoint)
    if networkCapacity and hasOurTank(endpoint) then
        wantedCapacity = math.max(networkCapacity, 1)
    end
    local wanted = math.max(math.min(amount or 0, wantedCapacity), 0)
    -- Checked against the tank itself as well as the recorded mirror: a tank left at another size by
    -- an older version can carry a mirror that already reads right.
    local settled = type(previous) == "table"
        and previous.fluid == fluidTypeName
        and math.abs((tonumber(previous.capacity) or -1) - wantedCapacity) <= CONSUME_EPSILON
        and math.abs(ownCapacity(endpoint) - math.max(wantedCapacity, ENGINE_MIN_CAPACITY)) <= CONSUME_EPSILON
        and math.abs(readAmount(endpoint) - wanted) <= CONSUME_EPSILON

    -- Written against already-right: a settled base should be almost all of the second.
    countPhase(settled and "endpoints: mirror already right" or "endpoints: mirror written")
    if not settled then
        writeFluid(endpoint, amount, fluidTypeName, networkCapacity)
    end
    local landed = readAmount(endpoint)
    setLastSync(endpoint, landed,
        { amount = landed, capacity = ownCapacity(endpoint), fluid = fluidTypeName })
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
    -- Said whenever the ANSWER changes, not once per fixture: once-only hid the very moment this is
    -- about -- a tank that reads 1 L while the network it was told about has since grown to 300.
    local answer = ("%s|%.2f"):format(
        type(mirror) == "table"
            and ("%.0f of %.0f L"):format(tonumber(mirror.amount) or 0, tonumber(mirror.capacity) or 0)
            or "nothing yet",
        ownCapacity(endpoint))
    local said = tostring(endpoint)
    if reportedClient[said] ~= answer then
        reportedClient[said] = answer
        Logger.log(("EndpointFluidSource: client tank for %s -- server says %s, this side holds %.0f L")
            :format(describeObject(endpoint),
                type(mirror) == "table"
                    and ("%.0f of %.0f L"):format(tonumber(mirror.amount) or 0, tonumber(mirror.capacity) or 0)
                    or "nothing yet",
                ownCapacity(endpoint)))
    end
    if type(mirror) ~= "table" then
        -- Unplumbed: a tank we attached went back to what the fixture held, so this copy does too.
        local restored = modData and tonumber(modData[RESTORED_KEY])
        local fluidContainer = restored and getFluidContainer(endpoint)
        local target = math.max(restored or 0, ENGINE_MIN_CAPACITY)
        if fluidContainer and fluidContainer.setCapacity
            and math.abs(ownCapacity(endpoint) - target) > CONSUME_EPSILON then
            pcall(fluidContainer.setCapacity, fluidContainer, target)
        end
        return false
    end

    local capacity = math.max(tonumber(mirror.capacity) or 0, 0)
    if capacity <= 0 then
        return false
    end
    if ownCapacity(endpoint) <= 0 then
        if not attachTank(endpoint, capacity) then
            return false
        end
        -- A tank attached after the server's last sync() reads empty until something moves: ask for one.
        local square = endpoint.getSquare and endpoint:getSquare() or nil
        local player = getPlayer and getPlayer() or nil
        if square and player and sendClientCommand then
            sendClientCommand(player, "WaterPipes", "syncFixture",
                { x = square:getX(), y = square:getY(), z = square:getZ() })
        end
    end

    -- Only the size. The litres come with the server's sync(); a fluid write on a client does nothing.
    local fluidContainer = getFluidContainer(endpoint)
    if fluidContainer and fluidContainer.setCapacity and ownCapacity(endpoint) ~= capacity then
        pcall(fluidContainer.setCapacity, fluidContainer, capacity)
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
    -- Without a tank of its own it held nothing; a tank found there is one we left.
    if not shipsWithTank(endpoint) then
        return { capacity = 0, amount = 0, fluidType = nil, inputLocked = false }
    end
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

-- Give the fixture back as it was before plumbing (used on unplumb), so it no longer shows the network.
-- Returns the captured state: the caller restores usesExternalWaterSource, which clients must be told.
function FluidSource.restoreOriginalState(endpoint)
    if not isAuthoritative() or not endpoint then
        return nil
    end

    -- What the player took since the last refresh is the network's, like any other draw.
    reconcileConsumption(endpoint)

    local modData = getModData(endpoint)
    local state = modData and modData[Constants.ENDPOINT_ORIGINAL_FLUID_KEY] or nil
    local ours = hasOurTank(endpoint)

    -- Our tank goes back to holding nothing: the fixture had no water of its own, whatever an older
    -- version captured. A tank it ships with gets its own water back, at its own size.
    local fluidContainer = getFluidContainer(endpoint)
    if ours then
        writeFluid(endpoint, 0, nil)
        if fluidContainer and fluidContainer.setCapacity then
            pcall(fluidContainer.setCapacity, fluidContainer, 0)
        end
    else
        writeFluid(endpoint, state and state.amount or 0, state and state.fluidType or nil)
        if fluidContainer and fluidContainer.setInputLocked then
            pcall(fluidContainer.setInputLocked, fluidContainer, (state and state.inputLocked) and true or false)
        end
    end

    -- Restore the pre-plumb water-source flags. canBeWaterPiped governs the engine's infinite
    -- city-mains water: leaving it nil/false makes the fixture an infinite tap again (if the water
    -- service is on), which is exactly the pre-plumb behaviour we want back.
    -- Cleared before the one transmit, so the clients forget the mirror too.
    if modData then
        modData.canBeWaterPiped = state and state.canBeWaterPiped
        modData[Constants.ENDPOINT_ORIGINAL_FLUID_KEY] = nil
        modData[OUR_TANK_KEY] = nil
        modData[MIRROR_KEY] = nil
        modData[Constants.ENDPOINT_FLUID_LAST_SYNC_KEY] = 0
        modData[Constants.ENDPOINT_FLUID_LAST_SYNC_LEGACY_KEY] = nil
        modData[RESTORED_KEY] = ours and 0 or nil
    end
    if endpoint.transmitModData then
        pcall(endpoint.transmitModData, endpoint)
    end
    if endpoint.sync then
        pcall(endpoint.sync, endpoint)
    end
    return state
end

-- Takes a tank we attached off the fixture. Picking a fixture up hands its components to the item
-- before anything else runs, so a tank left on it leaves as a container the size of the network.
function FluidSource.detachTank(endpoint)
    if not isAuthoritative() or not hasOurTank(endpoint)
        or not GameEntityFactory or not GameEntityFactory.RemoveComponentType then
        return false
    end
    local capacity = ownCapacity(endpoint)
    pcall(GameEntityFactory.RemoveComponentType, endpoint, ComponentType.FluidContainer)
    local modData = getModData(endpoint)
    if modData then
        modData[MIRROR_KEY] = nil
        modData[RESTORED_KEY] = nil
    end
    Logger.log(("EndpointFluidSource: took the %.2f L tank off %s"):format(capacity, describeObject(endpoint)))
    return getFluidContainer(endpoint) == nil
end

-- Empties the mirror and unlocks input (used on unplumb / pipe removal).
function FluidSource.clearForEndpoint(endpoint)
    if not isAuthoritative() or not endpoint then
        return
    end

    -- What was drawn since the last refresh is the network's, before the tank is emptied.
    reconcileConsumption(endpoint)

    local modData = getModData(endpoint)
    if modData then
        modData[MIRROR_KEY] = nil
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

    -- The modData goes once, with every key already in its final state.
    setSyncing(endpoint, false)
    if modData then
        modData[Constants.ENDPOINT_FLUID_LAST_SYNC_KEY] = 0
        modData[Constants.ENDPOINT_FLUID_LAST_SYNC_LEGACY_KEY] = nil
    end
    if endpoint.transmitModData then
        pcall(endpoint.transmitModData, endpoint)
    end
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
