WaterPipes = WaterPipes or {}
WaterPipes.EndpointPlumbing = WaterPipes.EndpointPlumbing or {}

require "WaterPipes/Constants"
require "WaterPipes/EndpointAdapterSource"
require "WaterPipes/EndpointFluidSource"
require "WaterPipes/EndpointObjects"
require "WaterPipes/Logger"
require "WaterPipes/NetworkAccess"
require "WaterPipes/PipeObjectUtils"

-- AdapterSource is kept only to clean up the legacy hidden adapter object from older saves.
local AdapterSource = WaterPipes.EndpointAdapterSource
local FluidSource = WaterPipes.EndpointFluidSource
local Constants = WaterPipes.Constants
local EndpointObjects = WaterPipes.EndpointObjects
local EndpointPlumbing = WaterPipes.EndpointPlumbing
local Logger = WaterPipes.Logger
local NetworkAccess = WaterPipes.NetworkAccess
local PipeObjectUtils = WaterPipes.PipeObjectUtils

local function getModData(worldObject)
    if not worldObject or not worldObject.getModData then
        return nil
    end

    return worldObject:getModData()
end

local function describeObject(worldObject)
    if not worldObject then
        return "nil"
    end

    local name = worldObject.getName and worldObject:getName() or "?"
    local spriteName = (worldObject.getSprite and worldObject:getSprite() and worldObject:getSprite():getName()) or "?"
    local objectIndex = worldObject.getObjectIndex and worldObject:getObjectIndex() or "?"
    local square = worldObject.getSquare and worldObject:getSquare() or nil
    local squareText = square and (tostring(square:getX()) .. "," .. tostring(square:getY()) .. "," .. tostring(square:getZ())) or "?, ?, ?"
    return tostring(name) .. " sprite=" .. tostring(spriteName) .. " index=" .. tostring(objectIndex) .. " square=" .. squareText
end

-- Stamp of the old capacity-based classification. Only cleared now: it marked moved sinks, washers and
-- the deluxe shower as external too, and missed Take A Bath And Shower's showers.
-- Declared up here rather than beside its readers because the diagnostics below print it, and a local
-- used above its declaration is a nil GLOBAL in Lua -- silent, and shipped from this repo three times.
local EXTERNAL_FIXTURE_KEY = "waterpipesExternalFixture"

-- Take A Bath And Shower reads modData canBeWaterPiped=true as "not piped", the opposite of the engine,
-- so its baths and showers are the only fixtures handled apart. Asked of TABAS itself, by sprite, the
-- way its own plumbing patch does; without TABAS, or if its module moves, nothing is treated apart.
local TABAS_MOD_ID = "TakeABathAndShowerNew"
local tabasIso = false          -- false: not looked up yet; nil: TABAS not available

local function getTabasIso()
    if tabasIso == false then
        tabasIso = nil
        local okActive, active = pcall(function() return getActivatedMods():contains(TABAS_MOD_ID) end)
        if okActive and active then
            local okIso, iso = pcall(require, "TABAS_Iso")
            if okIso and type(iso) == "table" and iso.isBathObject and iso.isShowerObject then
                tabasIso = iso
            end
        end
    end
    return tabasIso
end

local function isExternalWaterFixture(worldObject)
    local iso = getTabasIso()
    if not iso or not worldObject then
        return false
    end
    local ok, yes = pcall(function()
        return iso.isBathObject(worldObject) or iso.isShowerObject(worldObject, true)
    end)
    return ok and yes == true
end

local function describeTank(worldObject)
    local ok, text = pcall(function()
        local tank = worldObject:getFluidContainer()
        if not tank then
            return "none"
        end
        return ("%.2f of %.2f L"):format(tank:getAmount(), tank:getCapacity())
    end)
    return ok and text or "?"
end

local function describePlumbingDiagnostics(worldObject)
    if not worldObject then
        return "nil"
    end

    local modData = getModData(worldObject)
    local sprite = worldObject.getSprite and worldObject:getSprite() or nil
    local props = sprite and sprite.getProperties and sprite:getProperties() or nil
    local function prop(name)
        local ok, value = pcall(function() return props:get(name) end)
        return ok and value or nil
    end
    local waterAmountProp = props and prop("waterAmount") or nil
    local waterMaxProp = props and prop("waterMaxAmount") or nil
    local waterPipedProp = false
    if props then
        if IsoFlagType and props.has then
            waterPipedProp = props:has(IsoFlagType.waterPiped)
        elseif props.Is then
            waterPipedProp = props:Is("waterPiped")
        end
    end

    local amount = worldObject.getFluidAmount and select(2, pcall(worldObject.getFluidAmount, worldObject)) or nil
    local capacity = worldObject.getFluidCapacity and select(2, pcall(worldObject.getFluidCapacity, worldObject)) or nil
    local reserveAmount = worldObject.getReserveWaterAmount and select(2, pcall(worldObject.getReserveWaterAmount, worldObject)) or nil
    local reserveMax = worldObject.getReserveWaterMax and select(2, pcall(worldObject.getReserveWaterMax, worldObject)) or nil
    local usesExternal = worldObject.getUsesExternalWaterSource and select(2, pcall(worldObject.getUsesExternalWaterSource, worldObject)) or nil

    return "props{waterAmount="
        .. tostring(waterAmountProp)
        .. ",waterMaxAmount="
        .. tostring(waterMaxProp)
        .. ",waterPiped="
        .. tostring(waterPipedProp)
        .. "} methods{getFluidAmount="
        .. tostring(worldObject.getFluidAmount ~= nil)
        .. ",getFluidCapacity="
        .. tostring(worldObject.getFluidCapacity ~= nil)
        .. ",emptyFluid="
        .. tostring(worldObject.emptyFluid ~= nil)
        .. ",addFluid="
        .. tostring(worldObject.addFluid ~= nil)
        .. ",getReserveWaterAmount="
        .. tostring(worldObject.getReserveWaterAmount ~= nil)
        .. ",getReserveWaterMax="
        .. tostring(worldObject.getReserveWaterMax ~= nil)
        .. ",setReserveWaterAmount="
        .. tostring(worldObject.setReserveWaterAmount ~= nil)
        .. ",setSourceGrid="
        .. tostring(worldObject.setSourceGrid ~= nil)
        .. ",hasExternalWaterSource="
        .. tostring(worldObject.hasExternalWaterSource ~= nil)
        .. ",getUsesExternalWaterSource="
        .. tostring(worldObject.getUsesExternalWaterSource ~= nil)
        .. ",hasFluid="
        .. tostring(worldObject.hasFluid ~= nil)
        .. ",hasWater="
        .. tostring(worldObject.hasWater ~= nil)
        .. "} values{fluidAmount="
        .. tostring(amount)
        .. ",fluidCapacity="
        .. tostring(capacity)
        .. ",reserveAmount="
        .. tostring(reserveAmount)
        .. ",reserveMax="
        .. tostring(reserveMax)
        .. ",usesExternal="
        .. tostring(usesExternal)
        .. ",hasExternal="
        .. tostring(worldObject.hasExternalWaterSource and select(2, pcall(worldObject.hasExternalWaterSource, worldObject)) or nil)
        .. ",hasFluid="
        .. tostring(worldObject.hasFluid and select(2, pcall(worldObject.hasFluid, worldObject)) or nil)
        .. ",hasWater="
        .. tostring(worldObject.hasWater and select(2, pcall(worldObject.hasWater, worldObject)) or nil)
        -- The fixture's own tank: the getters above answer for whatever the engine would serve.
        .. "} tank{"
        .. describeTank(worldObject)
        .. "} ours{external="
        .. tostring(isExternalWaterFixture(worldObject))
        .. ",plumbed="
        .. tostring(modData ~= nil and modData[Constants.PLUMBED_ENDPOINT_MODDATA_KEY] == true)
        .. "}"
end

local function describeSquare(square)
    if not square then
        return "nil"
    end

    local isPlumbed = square.isPlumbed and select(2, pcall(square.isPlumbed, square)) or nil
    local room = square.getRoom and square:getRoom() or nil
    local roomName = room and room.getName and room:getName() or nil
    return "square{"
        .. "x=" .. tostring(square:getX())
        .. ",y=" .. tostring(square:getY())
        .. ",z=" .. tostring(square:getZ())
        .. ",isOutside=" .. tostring(square.isOutside and square:isOutside() or nil)
        .. ",isPlumbed=" .. tostring(isPlumbed)
        .. ",room=" .. tostring(roomName)
        .. "}"
end

-- The network an endpoint on this tile actually resolves to. Two fixtures a player reads as one can
-- sit on two networks, and a fixture whose network holds no vessel shows the 1 L floor a mirror needs
-- -- which looks like a broken tank rather than an empty line. Naming the network tells them apart.
local function describeEndpointNetwork(object)
    if not EndpointObjects.isEndpointCandidate(object) then
        return nil
    end
    local summary = NetworkAccess.getSummary(object)
    if not summary then
        return "net{none}"
    end
    return "net{amount=" .. tostring(summary.totalAmount)
        .. ",capacity=" .. tostring(summary.totalCapacity)
        .. ",vessels=" .. tostring(summary.descriptors and #summary.descriptors or 0)
        .. ",fluid=" .. tostring(summary.fluidTypeName) .. "}"
end

local function logSquareObjects(label, square)
    Logger.log(label .. ": " .. describeSquare(square))
    if not square or not square.getObjects then
        return
    end

    local objects = square:getObjects()
    for index = 0, objects:size() - 1 do
        local object = objects:get(index)
        local network = describeEndpointNetwork(object)
        Logger.log(label .. " object[" .. tostring(index) .. "]: " .. describeObject(object) .. " "
            .. describePlumbingDiagnostics(object) .. (network and (" " .. network) or ""))
    end
end

function EndpointPlumbing.dumpAdapterSquareDiagnostics(worldObject)
    if not worldObject or not worldObject.getSquare then
        Logger.log("Diagnostics adapter square: nil")
        return
    end

    local square = worldObject:getSquare()
    local squareAbove = square and square.getSquareAbove and square:getSquareAbove() or nil
    logSquareObjects("Diagnostics adapter square", squareAbove)

    local adapterObject = AdapterSource.findForEndpoint(worldObject)
    if adapterObject then
        Logger.log("Diagnostics adapter square flags: " .. AdapterSource.describeHiddenFlags(adapterObject))
    else
        Logger.log("Diagnostics adapter square flags: nil")
    end
end

function EndpointPlumbing.dumpDiagnostics(worldObject)
    Logger.log("Diagnostics target: " .. describeObject(worldObject))
    Logger.log("Diagnostics target detail: " .. describePlumbingDiagnostics(worldObject))

    local square = worldObject and worldObject.getSquare and worldObject:getSquare() or nil
    logSquareObjects("Diagnostics current square", square)

    local squareAbove = square and square.getSquareAbove and square:getSquareAbove() or nil
    logSquareObjects("Diagnostics square above", squareAbove)

    local adapterObject = AdapterSource.findForEndpoint(worldObject)
    if adapterObject then
        Logger.log("Diagnostics adapter flags: " .. AdapterSource.describeHiddenFlags(adapterObject))
    else
        Logger.log("Diagnostics adapter flags: nil")
    end

    local summary = NetworkAccess.getSummary(worldObject)
    if not summary then
        Logger.log("Diagnostics network summary: nil")
        return
    end

    Logger.log(
        "Diagnostics network summary: totalAmount="
            .. tostring(summary.totalAmount)
            .. " totalCapacity="
            .. tostring(summary.totalCapacity)
            .. " descriptorCount="
            .. tostring(summary.descriptors and #summary.descriptors or 0)
            .. " mixed="
            .. tostring(summary.isMixed)
    )
    for index, descriptor in ipairs(summary.descriptors or {}) do
        local objectText = describeObject(descriptor.object)
        Logger.log("Diagnostics descriptor[" .. tostring(index) .. "]: object=" .. objectText .. " fluidType=" .. tostring(descriptor.fluidType) .. " amount=" .. tostring(descriptor.waterAmount) .. " capacity=" .. tostring(descriptor.capacity) .. " tainted=" .. tostring(descriptor.tainted))
    end
end

-- Same shape as EndpointObjects.readBoolean: nil unless the method exists AND returns a boolean, so a
-- missing getter and a false answer never look alike.
local function readBoolean(methodOwner, methodName)
    if not methodOwner or not methodOwner[methodName] then
        return nil
    end

    local ok, value = pcall(methodOwner[methodName], methodOwner)
    if ok and type(value) == "boolean" then
        return value
    end

    return nil
end

local function transmitObjectState(worldObject)
    if not worldObject then
        return
    end

    if worldObject.transmitModData then
        pcall(worldObject.transmitModData, worldObject)
    end

    if worldObject.sync then
        pcall(worldObject.sync, worldObject)
    end
end

local function sendExternalWaterSourceChange(worldObject, value)
    if not worldObject or not worldObject.sendObjectChange then
        return
    end

    local changeName = IsoObjectChange and IsoObjectChange.USES_EXTERNAL_WATER_SOURCE or "usesExternalWaterSource"
    pcall(worldObject.sendObjectChange, worldObject, changeName, { value = value and true or false })
end

-- The flag as the ENGINE holds it, which is what EndpointObjects and Mains both read. Our modData is a
-- mirror of it. nil means the object exposes no getter: unknown, which is not the same as "matches".
local function readUsesExternalWaterSource(worldObject)
    local value = readBoolean(worldObject, "isUsesExternalWaterSource")
    if value == nil then
        value = readBoolean(worldObject, "getUsesExternalWaterSource")
    end
    return value
end

-- The flag is re-asserted on every refresh, and the assertion used to drag a sendObjectChange, a
-- transmitModData and a sync along with it -- every minute, to tell clients a value they already had.
-- Measured at 310 ms of a 381 ms endpoint refresh: 81 % of it, 13 % of everything the mod did.
--
-- What is guarded is the ANNOUNCEMENT, not the assertion. The modData write and the engine setter still
-- run every time: they are a table write and one bridge call, and they are what keeps a fixture from
-- drifting back to city mains. Skipping THOSE would trade a real behaviour for a saving that is not
-- theirs -- the cost was always the three network calls.
--
-- "Changed" is read off the engine when it answers and off our mirror when it does not. A measured
-- fixture has getUsesExternalWaterSource present and returning nil: the getter exists, the value is not
-- readable. On such an object the mirror is the only state there is, and trusting it forfeits no drift
-- detection that was ever possible -- an unreadable flag cannot be compared however carefully we ask.
-- Same rule canBeWaterPiped above already follows, for the same reason.
local function setUsesExternalWaterSource(worldObject, value)
    if not worldObject then
        return
    end

    local wanted = value and true or false
    local modData = getModData(worldObject)
    local live = readUsesExternalWaterSource(worldObject)

    local changed
    if live ~= nil then
        changed = live ~= wanted or modData == nil or modData.usesExternalWaterSource ~= wanted
    elseif modData ~= nil then
        changed = modData.usesExternalWaterSource ~= wanted
    else
        changed = true          -- nothing readable anywhere: say it, as before
    end

    if modData then
        modData.usesExternalWaterSource = wanted
    end

    if worldObject.setUsesExternalWaterSource then
        pcall(worldObject.setUsesExternalWaterSource, worldObject, wanted)
    end

    if changed then
        sendExternalWaterSourceChange(worldObject, wanted)
        transmitObjectState(worldObject)
    end
end

local function setCanBeWaterPiped(worldObject, value)
    local modData = getModData(worldObject)
    if modData then
        modData.canBeWaterPiped = value and true or false
    end
end

-- Drops the old stamp from a save. The classification is read off the sprite now, so a fixture the
-- stamp got wrong (a moved sink, a washer) is no longer kept on the town water by it.
-- Returns true when it changed this fixture.
function EndpointPlumbing.reclassifyExternalFixture(worldObject)
    local modData = getModData(worldObject)
    if not modData or modData[EXTERNAL_FIXTURE_KEY] == nil then
        return false
    end
    modData[EXTERNAL_FIXTURE_KEY] = nil
    Logger.log("Endpoint re-classified: dropped the old external-water stamp (Take A Bath And Shower: "
        .. tostring(isExternalWaterFixture(worldObject)) .. ") -- " .. describeObject(worldObject))
    return true
end

-- The canBeWaterPiped modData the fixture should carry right now:
--   any fixture -> true: engine mains off, our mirror serves it.
--   a Take A Bath And Shower bath or shower -> false ONLY while the network actually
--   has water (so that mod treats it as connected); true when the network is dry, so it reports
--   "not connected" instead of handing out free water.
local function desiredCanBeWaterPiped(worldObject)
    if isExternalWaterFixture(worldObject) then
        return not NetworkAccess.hasWater(worldObject)
    end
    return true
end

-- The tile a fixture stands on, for the endpoint registry. Nil when it cannot be established, which
-- is treated as "do not record" rather than "record nothing": a claim we cannot place is worse than
-- no claim, because the periodic re-index would then never be able to correct it.
local function registrySquare(worldObject)
    if not worldObject or not worldObject.getSquare then
        return nil
    end
    local ok, square = pcall(worldObject.getSquare, worldObject)
    if not ok or not square or not square.getX then
        return nil
    end
    return square
end

local function noteEndpointTile(worldObject)
    local State = WaterPipes.State
    local square = State and State.registerEndpoint and registrySquare(worldObject)
    if square then
        pcall(State.registerEndpoint, square:getX(), square:getY(), square:getZ())
    end
end

-- Plumbing or unplumbing changes WHAT STANDS on that tile in the only sense the hydraulic field cares
-- about: a plumbed fixture with live town water behind it is an inlet, and the field remembers where
-- its inlets are rather than searching on every solve.
-- Nothing else announces it -- a modData change fires no object event, and the periodic passes stopped
-- dropping the field on a timer.
local function noteHydraulicChange(worldObject)
    pcall(WaterPipes.Invalidate.headAroundSquare, registrySquare(worldObject))
end

function EndpointPlumbing.isPlumbed(worldObject)
    local modData = getModData(worldObject)
    return modData and modData[Constants.PLUMBED_ENDPOINT_MODDATA_KEY] == true or false
end

function EndpointPlumbing.hasPipeOnEndpointSquare(worldObject)
    local square = worldObject and worldObject.getSquare and worldObject:getSquare() or nil
    return square and PipeObjectUtils.getPipeOnSquare(square) ~= nil or false
end

function EndpointPlumbing.canPlumb(worldObject)
    return EndpointObjects.isEndpointCandidate(worldObject)
        and not EndpointPlumbing.isPlumbed(worldObject)
        and EndpointPlumbing.hasPipeOnEndpointSquare(worldObject)
end

function EndpointPlumbing.canUnplumb(worldObject)
    return EndpointPlumbing.isPlumbed(worldObject)
end

function EndpointPlumbing.refreshEndpointSource(worldObject)
    if not EndpointPlumbing.isPlumbed(worldObject) then
        return false
    end

    local modData = getModData(worldObject)
    if modData then
        modData[Constants.PLUMBED_ENDPOINT_SOURCE_MODDATA_KEY] = nil
    end

    -- Legacy cleanup: remove the hidden adapter object created by older mod versions.
    AdapterSource.removeForEndpoint(worldObject, "migrateToFluidSource")

    if not EndpointPlumbing.hasPipeOnEndpointSquare(worldObject) then
        -- Hybrid disconnect: losing the pipe on the fixture's OWN tile fully unplumbs it and
        -- restores its original fluid state. (A break further down the chain, while a pipe is still
        -- on this tile, instead leaves it connected-but-dry below and reconnects automatically.)
        EndpointPlumbing.unplumb(worldObject)
        return false
    end

    -- canBeWaterPiped=true keeps the engine's infinite city-mains water OFF so the fixture serves our
    -- network mirror; re-asserted every tick (mains water would creep back otherwise). Take A Bath And
    -- Shower's baths and showers must stay FALSE here too -- that mod reads the same modData as
    -- "connected". See EndpointPlumbing.plumb for the full rationale.
    local wantedPiped = desiredCanBeWaterPiped(worldObject)
    local currentData = getModData(worldObject)
    local pipedChanged = currentData ~= nil and currentData.canBeWaterPiped ~= wantedPiped
    setCanBeWaterPiped(worldObject, wantedPiped)
    -- Own-container path: the engine reads water from the endpoint's own FluidContainer.
    setUsesExternalWaterSource(worldObject, false)
    -- Push the flip to clients when it actually changes: external mods (e.g. Take A Bath And Shower)
    -- read canBeWaterPiped CLIENT-side to decide if the fixture is usable, so a stale value would
    -- otherwise let/deny use incorrectly in multiplayer. Only on change -> no per-tick spam.
    if pipedChanged then
        transmitObjectState(worldObject)
    end
    return FluidSource.syncForEndpoint(worldObject)
end

function EndpointPlumbing.releaseReservation(worldObject)
    if not EndpointPlumbing.isPlumbed(worldObject) then
        return 0
    end

    FluidSource.clearForEndpoint(worldObject)
    return 0
end

function EndpointPlumbing.plumb(worldObject)
    if not EndpointPlumbing.canPlumb(worldObject) then
        Logger.warn("Plumb rejected for endpoint: " .. describeObject(worldObject))
        return false
    end

    local modData = getModData(worldObject)
    if modData then
        modData[Constants.PLUMBED_ENDPOINT_MODDATA_KEY] = true
        modData[EXTERNAL_FIXTURE_KEY] = nil
    end

    -- Recorded here because this is the moment it becomes true. The per-minute refresh then reads the
    -- registry instead of sweeping every pipe tile's neighbourhood looking for fixtures.
    noteEndpointTile(worldObject)
    noteHydraulicChange(worldObject)

    Logger.log("Plumbing endpoint to pipe network: " .. describeObject(worldObject))
    Logger.log("Plumbing diagnostics: " .. describePlumbingDiagnostics(worldObject))
    -- Snapshot the fixture's own fluid state + water-source flags before we take it over.
    FluidSource.captureOriginalState(worldObject)
    -- canBeWaterPiped=true DISABLES the engine's infinite city-mains water so our network mirror serves the
    -- fixture. The town water is not lost: while the service runs, Mains.lua reads it back off this same
    -- fixture and feeds it into the network.
    -- Take A Bath And Shower's baths and showers must stay FALSE: that mod reads true as "not piped".
    -- We still charge the network on use.
    setCanBeWaterPiped(worldObject, desiredCanBeWaterPiped(worldObject))
    setUsesExternalWaterSource(worldObject, false)
    EndpointPlumbing.refreshEndpointSource(worldObject)

    if buildUtil and buildUtil.setHaveConstruction and worldObject.getSquare then
        pcall(buildUtil.setHaveConstruction, worldObject:getSquare(), true)
    end

    transmitObjectState(worldObject)
    return true
end

function EndpointPlumbing.unplumb(worldObject)
    if not EndpointPlumbing.canUnplumb(worldObject) then
        Logger.warn("Unplumb rejected for endpoint: " .. describeObject(worldObject))
        return false
    end

    local modData = getModData(worldObject)
    if modData then
        modData[Constants.PLUMBED_ENDPOINT_MODDATA_KEY] = nil
        modData[Constants.PLUMBED_ENDPOINT_SOURCE_MODDATA_KEY] = nil
        modData[EXTERNAL_FIXTURE_KEY] = nil
    end

    -- Restore the fixture's pre-plumb fluid state AND water-source flags (capacity/contents +
    -- canBeWaterPiped/usesExternalWaterSource). This is what makes a former city-mains tap go back
    -- to infinite water if the water service is still on, instead of staying dry.
    local original = FluidSource.restoreOriginalState(worldObject)
    -- A barrel it drew from through vanilla plumbing; clients must be told, or they keep serving our tank.
    setUsesExternalWaterSource(worldObject, original ~= nil and original.usesExternalWaterSource == true)
    AdapterSource.removeForEndpoint(worldObject, "unplumb")
    noteHydraulicChange(worldObject)

    -- Deliberately NOT unregistering the tile here. A tile can carry more than one fixture, and this
    -- object cannot see the others -- so removing the claim would silently strand a sink standing
    -- beside the one just unplumbed. The registry is a claim, not a fact: the refresh visits the tile,
    -- finds nothing plumbed on it, and drops it there, where the whole tile is in view.
    Logger.log("Unplumbed endpoint from pipe network: " .. describeObject(worldObject))

    if buildUtil and buildUtil.setHaveConstruction and worldObject.getSquare then
        pcall(buildUtil.setHaveConstruction, worldObject:getSquare(), true)
    end

    transmitObjectState(worldObject)
    return true
end
