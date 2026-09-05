WaterPipes = WaterPipes or {}
WaterPipes.ContainerAdapter = WaterPipes.ContainerAdapter or {}

require "WaterPipes/Constants"
require "WaterPipes/EndpointObjects"
require "WaterPipes/State"

local Constants = WaterPipes.Constants
local Adapter = WaterPipes.ContainerAdapter
local EndpointObjects = WaterPipes.EndpointObjects
local State = WaterPipes.State

local function readNumber(methodOwner, methodName)
    if not methodOwner or not methodOwner[methodName] then
        return nil
    end

    local ok, value = pcall(methodOwner[methodName], methodOwner)
    if ok and type(value) == "number" then
        return value
    end

    return nil
end

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

local function getSpriteName(worldObject)
    if not worldObject then
        return nil
    end

    if worldObject.getSprite and worldObject:getSprite() and worldObject:getSprite().getName then
        return worldObject:getSprite():getName()
    end

    if worldObject.getSpriteName then
        local ok, spriteName = pcall(worldObject.getSpriteName, worldObject)
        if ok and type(spriteName) == "string" then
            return spriteName
        end
    end

    return nil
end

local function getWorldFluidContainer(worldObject)
    if not worldObject or not worldObject.getFluidContainer then
        return nil
    end

    local ok, fluidContainer = pcall(worldObject.getFluidContainer, worldObject)
    if ok then
        return fluidContainer
    end

    return nil
end

local function isExcludedWorldObject(worldObject)
    if not worldObject or not worldObject.getModData then
        return false
    end

    local modData = worldObject:getModData()
    return modData and modData[Constants.ADAPTER_SOURCE_MODDATA_KEY] == true or false
end

-- Water appliances (washing machines) hold a FluidContainer inherited from IsoObject, so the duck-typed
-- detection below would adopt them as network STORAGE and rebalanceSummary would overwrite their water
-- every tick, so they could never reach the level they need to run. They are consumers, not vessels:
-- EndpointObjects recognises the same class list as plumbable endpoints instead.
local function isExcludedAppliance(worldObject)
    if not worldObject or not instanceof then
        return false
    end
    for _, className in ipairs(Constants.WATER_APPLIANCE_CLASSES) do
        local ok, isInstance = pcall(instanceof, worldObject, className)
        if ok and isInstance then
            return true
        end
    end
    return false
end

local function addUniqueObject(results, seen, worldObject)
    if not worldObject then
        return
    end

    local key = tostring(worldObject)
    if seen[key] then
        return
    end

    seen[key] = true
    results[#results + 1] = worldObject
end

local function collectRelatedWorldObjects(worldObject)
    local results = {}
    local seen = {}

    addUniqueObject(results, seen, worldObject)

    if worldObject and worldObject.getSpriteGridObjectsIncludingSelf and ArrayList and ArrayList.new then
        local objects = ArrayList.new()
        local ok = pcall(worldObject.getSpriteGridObjectsIncludingSelf, worldObject, objects)
        if ok and objects and objects.size then
            for index = 0, objects:size() - 1 do
                addUniqueObject(results, seen, objects:get(index))
            end
        end
    end

    return results
end

local function getRawWorldFluidCapacity(worldObject)
    return readNumber(worldObject, "getFluidCapacity")
        or readNumber(worldObject, "getReserveWaterMax")
        or readNumber(getWorldFluidContainer(worldObject), "getCapacity")
end

local function getRawWorldFluidAmount(worldObject)
    return readNumber(worldObject, "getFluidAmount")
        or readNumber(worldObject, "getReserveWaterAmount")
        or readNumber(getWorldFluidContainer(worldObject), "getAmount")
        or 0
end

-- Tainted water is (usually) the plain "Water" fluid carrying a tainted flag, set via setTaintedWater(),
-- so getFluidTypeString() reports "Water" and the taint is invisible unless the flag is read too. It can
-- live on the world object, its FluidContainer, or the primary fluid.
local function isTaintedFlagSet(worldObject, fluidContainer, primaryFluid)
    if readBoolean(worldObject, "isTaintedWater") == true then return true end
    if readBoolean(fluidContainer, "isTaintedWater") == true then return true end
    if readBoolean(primaryFluid, "isTaintedWater") == true then return true end
    if readBoolean(primaryFluid, "isTainted") == true then return true end
    return false
end

-- Normalise a fluid type string so tainted water always resolves to "TaintedWater", whether it is a
-- distinct "TaintedWater" fluid or "Water" + a tainted flag. Returns the (possibly corrected) type.
local function normalizeFluidType(typeString, worldObject, fluidContainer, primaryFluid)
    if type(typeString) == "string" and typeString ~= "" then
        if string.find(string.lower(typeString), "tainted") then
            return "TaintedWater"
        end
        if typeString == "Water" and isTaintedFlagSet(worldObject, fluidContainer, primaryFluid) then
            return "TaintedWater"
        end
        return typeString
    end
    if isTaintedFlagSet(worldObject, fluidContainer, primaryFluid) then
        return "TaintedWater"
    end
    return nil
end

local function readRawWorldFluidType(worldObject)
    local fluidContainer = getWorldFluidContainer(worldObject)
    local typeString, primaryFluid = nil, nil
    if fluidContainer and fluidContainer.getPrimaryFluid then
        local ok, pf = pcall(fluidContainer.getPrimaryFluid, fluidContainer)
        if ok and pf then
            primaryFluid = pf
            if pf.getFluidTypeString then
                local okType, fts = pcall(pf.getFluidTypeString, pf)
                if okType and type(fts) == "string" then
                    typeString = fts
                end
            end
        end
    end

    local normalized = normalizeFluidType(typeString, worldObject, fluidContainer, primaryFluid)
    if normalized then
        return normalized
    end

    if getRawWorldFluidAmount(worldObject) > 0 and readBoolean(worldObject, "hasWater") then
        return "Water"
    end

    return nil
end

local function getDirectWorldFluidKind(worldObject)
    if not worldObject then
        return false
    end

    if isExcludedWorldObject(worldObject) then
        return false
    end

    if instanceof and instanceof(worldObject, "IsoWorldInventoryObject") then
        return false
    end

    if isExcludedAppliance(worldObject) then
        return false
    end

    local fluidContainer = getWorldFluidContainer(worldObject)
    local hasReserveWater = worldObject.getReserveWaterMax or worldObject.getReserveWaterAmount or worldObject.setReserveWaterAmount
    if not fluidContainer and not hasReserveWater then
        return false
    end

    local capacity = getRawWorldFluidCapacity(worldObject)
    if not capacity or capacity <= 0 or capacity >= Constants.MAX_FINITE_FLUID_CAPACITY then
        return false
    end

    if fluidContainer or hasReserveWater then
        return "worldFluid"
    end

    return false
end

local function resolveFluidTarget(worldObject)
    if isExcludedWorldObject(worldObject) then
        return worldObject
    end

    local bestObject = nil
    local bestCapacity = -1

    for _, candidate in ipairs(collectRelatedWorldObjects(worldObject)) do
        local capacity = getRawWorldFluidCapacity(candidate)
        if capacity and capacity > bestCapacity then
            bestObject = candidate
            bestCapacity = capacity
        elseif not bestObject then
            local hasFluidContainer = getWorldFluidContainer(candidate) ~= nil
            local hasFluidMethod = candidate.getFluidCapacity or candidate.getReserveWaterMax or candidate.setReserveWaterAmount
            if hasFluidContainer or hasFluidMethod then
                bestObject = candidate
            end
        end
    end

    return bestObject or worldObject
end

local function getObjectContainerAt(worldObject, containerIndex)
    if worldObject.getContainerByIndex then
        local ok, container = pcall(worldObject.getContainerByIndex, worldObject, containerIndex)
        if ok then
            return container
        end
    end

    if containerIndex == 0 and worldObject.getContainer then
        local ok, container = pcall(worldObject.getContainer, worldObject)
        if ok then
            return container
        end
    end

    return nil
end

local function getObjectContainerCount(worldObject)
    if worldObject.getContainerCount then
        local ok, count = pcall(worldObject.getContainerCount, worldObject)
        if ok and type(count) == "number" then
            return count
        end
    end

    if worldObject.getContainer then
        local container = getObjectContainerAt(worldObject, 0)
        if container then
            return 1
        end
    end

    return 0
end

function Adapter.getWorldFluidKind(worldObject)
    if not worldObject then
        return false
    end

    worldObject = resolveFluidTarget(worldObject)

    if isExcludedWorldObject(worldObject) then
        return false
    end

    if instanceof and instanceof(worldObject, "IsoWorldInventoryObject") then
        return false
    end

    if isExcludedAppliance(worldObject) then
        return false
    end

    if not getWorldFluidContainer(worldObject) and not worldObject.getFluidCapacity then
        return false
    end

    local capacity = Adapter.readWorldFluidCapacity(worldObject)
    if not capacity or capacity <= 0 or capacity >= Constants.MAX_FINITE_FLUID_CAPACITY then
        return false
    end

    local spriteName = getSpriteName(worldObject)
    local props = worldObject.getSprite and worldObject:getSprite() and worldObject:getSprite():getProperties() or nil

    if props and (props:has("CustomName") or props:has("GroupName") or props:has("IsMoveAble")) then
        return "worldFluid"
    end

    if spriteName then
        return "worldFluid"
    end

    if worldObject.getName and worldObject:getName() then
        return "worldFluid"
    end

    if worldObject.getFluidUiName then
        return "worldFluid"
    end

    return false
end

function Adapter.readWorldFluidCapacity(worldObject)
    worldObject = resolveFluidTarget(worldObject)
    return getRawWorldFluidCapacity(worldObject)
end

function Adapter.readWorldFluidAmount(worldObject)
    worldObject = resolveFluidTarget(worldObject)
    return getRawWorldFluidAmount(worldObject)
end

function Adapter.readWorldFluidType(worldObject)
    worldObject = resolveFluidTarget(worldObject)
    local fluidContainer = getWorldFluidContainer(worldObject)
    local typeString, primaryFluid = nil, nil
    if fluidContainer and fluidContainer.getPrimaryFluid then
        local ok, pf = pcall(fluidContainer.getPrimaryFluid, fluidContainer)
        if ok and pf then
            primaryFluid = pf
            if pf.getFluidTypeString then
                local okType, fts = pcall(pf.getFluidTypeString, pf)
                if okType and type(fts) == "string" then
                    typeString = fts
                end
            end
        end
    end

    local normalized = normalizeFluidType(typeString, worldObject, fluidContainer, primaryFluid)
    if normalized then
        return normalized
    end

    if Adapter.readWorldFluidAmount(worldObject) > 0 and readBoolean(worldObject, "hasWater") then
        return "Water"
    end

    return nil
end

-- Notify EXTERNAL listeners that a world container we wrote to changed, so mods keying off
-- OnWaterAmountChange refresh (Useful Barrels' fill-level sprite, vanilla rain collectors). The vanilla
-- FluidContainer write does not raise this event. Guarded by WaterPipes._suppressWaterEvent so our own
-- handler early-returns on the echo: it is purely an outward signal. Save/restore rather than
-- true/false stays correct if a listener re-enters; pcall keeps the flag clean if one errors.

-- The head field cares WHETHER a vessel holds water, never how much: a barrel with a litre in it
-- supplies exactly the head a full one does. So it only goes stale when a vessel crosses between empty
-- and not, and that crossing is the only thing about water movement it needs told.
-- This is what replaces dropping the whole field once a minute on the chance something ran dry. A farm
-- whose barrels stay wet never invalidates at all; one that runs dry invalidates once.
-- Scoped to the tile, so a barrel emptying on one network leaves every other network's field standing.
local function noteEmptinessCrossing(worldObject, prevAmount, newAmount)
    local wasEmpty = (prevAmount or 0) <= 0
    local isEmpty = (newAmount or 0) <= 0
    if wasEmpty == isEmpty then
        return
    end

    local Hydraulics = WaterPipes.Hydraulics
    if not Hydraulics then
        return
    end

    -- The SUPPLY form, not the general one. Water moving cannot have moved a pipe, so the zone keeps its
    -- shape and only has to be re-priced, which skips the world walk entirely. This is the common
    -- invalidation by a wide margin: 211 of 215 in a measured window.
    local invalidate = Hydraulics.invalidateSupplyAroundSquare or Hydraulics.invalidateAroundSquare
    if not invalidate then
        return
    end

    local ok, square = pcall(worldObject.getSquare, worldObject)
    if ok and square then
        pcall(invalidate, square)
    end
end

function Adapter.noteEmptinessCrossing(worldObject, prevAmount, newAmount)
    if worldObject then
        noteEmptinessCrossing(worldObject, prevAmount, newAmount)
    end
end

local function fireExternalWaterChange(worldObject, prevAmount)
    if not worldObject or not worldObject.getModData then
        return
    end
    if not LuaEventManager or not LuaEventManager.triggerEvent then
        return
    end
    local now = Adapter.readWorldFluidAmount(worldObject) or 0
    if math.abs(now - (prevAmount or 0)) <= 0.001 then
        return
    end
    WaterPipes = WaterPipes or {}
    local saved = WaterPipes._suppressWaterEvent
    WaterPipes._suppressWaterEvent = true
    pcall(LuaEventManager.triggerEvent, "OnWaterAmountChange", worldObject, prevAmount or 0)
    WaterPipes._suppressWaterEvent = saved
end

function Adapter.writeWorldFluidAmount(worldObject, fluidAmount, fluidTypeName)
    if not worldObject then
        return false
    end

    worldObject = resolveFluidTarget(worldObject)
    local prevAmount = Adapter.readWorldFluidAmount(worldObject) or 0

    if worldObject.setReserveWaterAmount or worldObject.getReserveWaterMax then
        local reserveCapacity = readNumber(worldObject, "getReserveWaterMax") or 0
        local clampedAmount = math.max(math.min(fluidAmount or 0, reserveCapacity > 0 and reserveCapacity or (fluidAmount or 0)), 0)

        if worldObject.setReserveWaterAmount then
            local ok = pcall(worldObject.setReserveWaterAmount, worldObject, clampedAmount)
            if not ok then
                return false
            end
        else
            return false
        end

        if worldObject.setTaintedWater then
            pcall(worldObject.setTaintedWater, worldObject, clampedAmount > 0 and fluidTypeName == "TaintedWater")
        end

        if worldObject.sync then
            pcall(worldObject.sync, worldObject)
        end

        if worldObject.transmitModData then
            pcall(worldObject.transmitModData, worldObject)
        end

        noteEmptinessCrossing(worldObject, prevAmount, clampedAmount)
        fireExternalWaterChange(worldObject, prevAmount)
        return true
    end

    local fluidContainer = getWorldFluidContainer(worldObject)
    local cleared = false

    if worldObject.emptyFluid then
        cleared = pcall(worldObject.emptyFluid, worldObject)
    elseif fluidContainer and fluidContainer.removeFluid then
        cleared = pcall(fluidContainer.removeFluid, fluidContainer)
    end

    if not cleared then
        return false
    end

    if fluidAmount > 0 and fluidTypeName then
        local fluidType = nil
        if fluidTypeName == "Water" then
            fluidType = (FluidType and FluidType.Water) or (Fluid and Fluid.Water)
        elseif fluidTypeName == "TaintedWater" then
            fluidType = (FluidType and FluidType.TaintedWater) or (Fluid and Fluid.TaintedWater)
        elseif FluidType.FromNameLower then
            fluidType = FluidType.FromNameLower(string.lower(fluidTypeName))
        elseif Fluid and Fluid.FromNameLower then
            fluidType = Fluid.FromNameLower(string.lower(fluidTypeName))
        end

        if not fluidType then
            return false
        end

        local ok = false
        if worldObject.addFluid then
            ok = pcall(worldObject.addFluid, worldObject, fluidType, fluidAmount)
        elseif fluidContainer and fluidContainer.addFluid then
            ok = pcall(fluidContainer.addFluid, fluidContainer, fluidType, fluidAmount)
        end

        if not ok then
            return false
        end
    end

    if worldObject.sync then
        pcall(worldObject.sync, worldObject)
    end

    if worldObject.transmitModData then
        pcall(worldObject.transmitModData, worldObject)
    end

    fireExternalWaterChange(worldObject, prevAmount)
    return true
end

function Adapter.readCapacity(container)
    return readNumber(container, "getCapacity")
        or readNumber(container, "getMaxCapacity")
end

function Adapter.readWaterAmount(container)
    return readNumber(container, "getWaterAmount")
        or readNumber(container, "getFluidAmount")
        or 0
end

function Adapter.writeWaterAmount(container, waterAmount)
    if container.setWaterAmount then
        local ok = pcall(container.setWaterAmount, container, waterAmount)
        if ok then
            return true
        end
    end

    if container.setFluidAmount then
        local ok = pcall(container.setFluidAmount, container, waterAmount)
        if ok then
            return true
        end
    end

    return false
end

-- The purifier's clean OUT buffer, written as an ordinary network container. It is a modData number
-- rather than a FluidContainer, so it is written by hand here.
-- Only ever holds clean Water: the outlet descriptor is left out of any network already carrying
-- tainted water, so a rebalance can never arrive with anything else. Refused loudly rather than stored
-- silently, because a wrong answer here is water conjured or destroyed.
local function writePurifierOutAmount(purifierObject, fluidAmount, fluidTypeName)
    if not purifierObject or not purifierObject.getModData then
        return false
    end
    if fluidAmount > 0 and fluidTypeName and fluidTypeName ~= "Water" then
        return false
    end

    local ok, modData = pcall(purifierObject.getModData, purifierObject)
    if not ok or not modData then
        return false
    end

    modData[Constants.PURIFIER_OUT_AMOUNT_KEY] =
        math.min(math.max(fluidAmount or 0, 0), Constants.PURIFIER_BUFFER_CAPACITY)

    if purifierObject.transmitModData then
        pcall(purifierObject.transmitModData, purifierObject)
    end
    return true
end

-- Would writing `fluidAmount` of `fluidTypeName` change anything a player could see? Descriptors carry
-- the amount and type read when the summary was built, so this is answered without touching the world.
-- The TYPE half is not optional: stagnation and rain contamination write the SAME amount back with a
-- new type, and comparing litres alone would silently skip those.
local function writeIsNoOp(descriptor, fluidAmount, fluidTypeName)
    local current = descriptor.waterAmount
    if not current then
        return false   -- unknown current amount: never assume, just write
    end

    local target = fluidAmount or 0
    if math.abs(current - target) > Constants.FLUID_WRITE_EPSILON then
        return false
    end

    -- An empty vessel staying empty has no meaningful type either way.
    if target <= 0 and current <= 0 then
        return true
    end

    return descriptor.fluidType == fluidTypeName
end

-- Returns (ok, touchedTheWorld).
-- The second value is what lets a caller keep its books straight. `ok` means "the vessel is in the state
-- you asked for", which is ALSO true when the request was close enough that writing was not worth it --
-- and then the vessel still holds its old amount. A caller doing conservation arithmetic has to know
-- the difference, or it credits itself litres that never moved.
-- `force` overrides the no-op guard, for a draw that has already promised its caller the litres.
function Adapter.writeDescriptorWaterAmount(descriptor, fluidAmount, fluidTypeName, force)
    if not descriptor then
        return false, false
    end

    -- Nothing worth doing. Reported as success because the vessel is already in the requested state to
    -- within a hundredth of a litre; the caller carries the remainder to the next vessel.
    if not force and writeIsNoOp(descriptor, fluidAmount, fluidTypeName) then
        return true, false
    end

    if descriptor.fluidMode == "purifierOut" then
        local ok = writePurifierOutAmount(descriptor.object, fluidAmount, fluidTypeName)
        return ok, ok
    end

    if descriptor.fluidMode == "worldObject" then
        local ok = Adapter.writeWorldFluidAmount(descriptor.object, fluidAmount, fluidTypeName)
        return ok, ok
    end

    if descriptor.container then
        local ok = Adapter.writeWaterAmount(descriptor.container, fluidAmount)
        if ok and descriptor.container.setTaintedWater then
            pcall(descriptor.container.setTaintedWater, descriptor.container, fluidTypeName == "TaintedWater")
        end
        return ok, ok
    end

    return false, false
end

-- Compat (Take A Bath And Shower): its "TubFluidContainer" must NEVER be managed by the network --
-- doing so causes unstable behaviour. Matched by getName(), per the mod author.
local EXCLUDED_CONTAINER_NAMES = { TubFluidContainer = true }

local function isExcludedByName(namedThing)
    if namedThing and namedThing.getName then
        local ok, name = pcall(namedThing.getName, namedThing)
        if ok and name and EXCLUDED_CONTAINER_NAMES[name] then
            return true
        end
    end
    return false
end

function Adapter.isWaterCandidate(container)
    if not container then
        return false
    end

    if isExcludedByName(container) then
        return false
    end

    local capacity = Adapter.readCapacity(container)
    if not capacity or capacity <= 0 then
        return false
    end

    if container.isWaterSource then
        local ok, isWaterSource = pcall(container.isWaterSource, container)
        if ok and isWaterSource then
            return true
        end
    end

    if container.getType then
        local ok, containerType = pcall(container.getType, container)
        if ok and type(containerType) == "string" then
            local lowered = string.lower(containerType)
            if string.find(lowered, "water", 1, true) then
                return true
            end
        end
    end

    return Adapter.readWaterAmount(container) >= 0
end

-- ===== Per-frame vessel memo =====
-- Deciding whether one IsoObject is network storage is the most repeated question in the mod, and it
-- costs roughly twenty pcall'd Java calls -- isEndpointCandidate alone runs three instanceof checks and
-- pulls the sprite's property list. It is asked about EVERY object on EVERY pipe tile, on every network
-- summary: a farm with 32 sprinklers on a 200-tile network asked it about a million times in a frame.
-- The answer only changes when an object appears on or leaves the tile, and both raise events. So the
-- CLASSIFICATION is memoised -- which objects are vessels, their capacity, index and key -- while the
-- AMOUNT and FLUID TYPE are re-read on every call, because those are what the arithmetic is made of.
-- Descriptors themselves are deliberately NOT cached: callers decorate them per query with hop counts
-- measured from their own tile, so sharing one would have the second caller overwrite the first's.
local vesselMemo = {}

local function vesselMemoKey(square)
    return tostring(square:getX()) .. ":" .. tostring(square:getY()) .. ":" .. tostring(square:getZ())
end

function Adapter.invalidateVesselCache()
    vesselMemo = {}
end

function Adapter.invalidateSquareVessels(square)
    if square and square.getX then
        vesselMemo[vesselMemoKey(square)] = nil
    end
end

-- The expensive half, run once per square per frame. Returns the fixed facts about each vessel found;
-- never the fluid it holds.
local function classifySquareVessels(square)
    local vessels = {}

    local objects = square:getObjects()
    if not objects or not objects.size then
        return vessels
    end

    local x = square:getX()
    local y = square:getY()
    local z = square:getZ()
    local squareKey = State.squareKey(x, y, z)

    for objectIndex = 0, objects:size() - 1 do
        local worldObject = objects:get(objectIndex)
        if not EndpointObjects.isEndpointCandidate(worldObject) and not isExcludedByName(worldObject) then
            local fluidKind = getDirectWorldFluidKind(worldObject)

            if fluidKind then
                local capacity = getRawWorldFluidCapacity(worldObject)
                if capacity and capacity > 0 then
                    vessels[#vessels + 1] = {
                        key = squareKey .. ":" .. tostring(objectIndex) .. ":fluid",
                        squareKey = squareKey,
                        x = x,
                        y = y,
                        z = z,
                        objectIndex = objectIndex,
                        capacity = capacity,
                        object = worldObject,
                    }
                end
            end
        end
    end

    return vessels
end

-- The memo is keyed on the square and the object INDEX is part of every descriptor key, so anything
-- that renumbers the tile's object list has to drop it. Add/remove do exactly that and both raise an
-- event; the per-frame clear is the backstop for any path not thought of.
local function classifySquareVesselsCached(square)
    local key = vesselMemoKey(square)
    local cached = vesselMemo[key]
    if not cached then
        cached = classifySquareVessels(square)
        vesselMemo[key] = cached
    end
    return cached
end

-- (Defined here, below classifySquareVessels, and not beside the other invalidation helpers: it closes
-- over that local, and a function compiled above it would bind the name to a nil GLOBAL instead --
-- silently, since that is valid Lua and luac -p cannot see it. test_container_cache.lua now calls it.)
-- Recompute ONE tile and compare it against what was remembered. True when they agree.
-- This replaces the periodic wholesale drop. The drop assumed the memo was wrong and paid to rebuild
-- every tile of every network -- ~190 ms of client work per in-game minute, in one frame. This assumes
-- the memo is RIGHT, checks a few tiles, and says so when it is not. The memo is left holding the fresh
-- answer either way, so a disagreement is also a repair.
-- A disagreement means an object left a tile without OnObjectAboutToBeRemoved firing, which nobody has
-- ever observed. Evidence instead of nerve -- see docs/removal-events.md.
function Adapter.verifySquareVessels(square)
    if not square or not square.getX then
        return true
    end

    local key = vesselMemoKey(square)
    local remembered = vesselMemo[key]
    if not remembered then
        return true          -- nothing cached here, so nothing can be stale
    end

    vesselMemo[key] = nil
    local fresh = classifySquareVessels(square)
    vesselMemo[key] = fresh

    if #fresh ~= #remembered then
        return false
    end
    for index = 1, #fresh do
        -- Object identity AND position in the list: the index is baked into every descriptor key, so a renumber
        -- is just as wrong as a substitution even when the same objects are present.
        if fresh[index].object ~= remembered[index].object
            or fresh[index].objectIndex ~= remembered[index].objectIndex then
            return false
        end
    end
    return true
end
-- Is there any network vessel on this square at all? The router walk asks this per crossing and does not
-- care what is inside, so it never pays for a fluid read.
function Adapter.hasSquareContainers(square)
    if not square or not square.getObjects then
        return false
    end
    return #classifySquareVesselsCached(square) > 0
end

function Adapter.collectSquareContainers(square)
    local result = {}

    if not square or not square.getObjects then
        return result
    end

    for _, vessel in ipairs(classifySquareVesselsCached(square)) do
        result[vessel.key] = {
            key = vessel.key,
            squareKey = vessel.squareKey,
            x = vessel.x,
            y = vessel.y,
            z = vessel.z,
            objectIndex = vessel.objectIndex,
            containerIndex = -1,
            capacity = vessel.capacity,
            -- Read fresh, every time. See the memo's note above.
            waterAmount = getRawWorldFluidAmount(vessel.object) or 0,
            fluidType = readRawWorldFluidType(vessel.object),
            kind = "worldFluid",
            fluidMode = "worldObject",
            object = vessel.object,
        }
    end

    return result
end

-- The vessel memo's invalidation: an object appearing on or leaving a square renumbers that square's
-- object list, and the index is baked into every descriptor key -- so that square is dropped at once,
-- and only that square.
-- It does NOT need to fire on water moving. Amounts and fluid types are never memoised, so a barrel
-- filling or emptying is seen by the very next query. What is remembered is only WHICH objects are
-- containers.
-- There used to be a per-frame clear here, and it cost more than everything above it saved: classifying
-- a tile is the most expensive per-square routine in the mod, and finding a zone's vessels means
-- classifying every tile of it -- 77% of a spray-FX rebuild, three times a second.
-- What it was really guarding is a square re-created underneath us by chunk streaming, which has its own
-- event and is hooked directly; the per-minute pass drops the lot as a backstop.
if Events then
    local function invalidateForObject(object)
        local square = object and object.getSquare and object:getSquare() or nil
        if square then
            Adapter.invalidateSquareVessels(square)
        else
            Adapter.invalidateVesselCache()
        end
    end

    if Events.OnObjectAdded then Events.OnObjectAdded.Add(invalidateForObject) end
    if Events.OnObjectAboutToBeRemoved then Events.OnObjectAboutToBeRemoved.Add(invalidateForObject) end
    if Events.LoadGridsquare then Events.LoadGridsquare.Add(Adapter.invalidateSquareVessels) end
end
