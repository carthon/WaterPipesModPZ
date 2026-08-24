-- B42 entity build hooks for the Water Pipe buildables.
--
-- The pipes are placed through the native B42 entity build system (ISBuildIsoEntity), which is
-- multiplayer-safe: the engine validates on the server and runs :create() server-side. We only
-- supply two SpriteConfig hooks per entity:
--   OnIsValid(params) -> bool   (runs on client cursor AND server; pure validation)
--   OnCreate(params)            (runs inside :create(), i.e. on the server in MP; registers the pipe)
--
-- The hooks are referenced from the entity scripts by the dotted global path
-- "WaterPipesBuild.<fn>", so this table MUST be a global and must load before scripts are parsed.

require "WaterPipes/Constants"
require "WaterPipes/PipeObjectUtils"
require "WaterPipes/Logger"

WaterPipes = WaterPipes or {}
WaterPipes.Build = WaterPipes.Build or {}

local Constants = WaterPipes.Constants
local PipeObjectUtils = WaterPipes.PipeObjectUtils
local Logger = WaterPipes.Logger
local Build = WaterPipes.Build

-- The vertical pipe is a single rotatable entity: facing "w" -> West wall, anything else -> North.
local function edgeFromFacing(params)
    return (params and params.facing == "w") and "W" or "N"
end

-- Fixed-sprite floor variants (pump, drip, sprinkler) only have an E/W and an N/S sprite, so the
-- build-cursor facing picks the axis rather than a full four-way direction.
local function axisFromFacing(params)
    local facing = params and params.facing
    facing = type(facing) == "string" and string.lower(facing) or "n"
    if facing == "n" or facing == "s" then
        return Constants.PIPE_AXIS_NS
    end
    return Constants.PIPE_AXIS_EW
end

-- Router OUT direction from the build-cursor facing (chosen by rotating with R). The engine passes
-- facing as lowercase n/e/s/w; be tolerant of case.
local function facingToDirection(params)
    local facing = params and params.facing
    facing = type(facing) == "string" and string.lower(facing) or "n"
    if facing == "e" then return "E" end
    if facing == "s" then return "S" end
    if facing == "w" then return "W" end
    return "N"
end

local function getModData(worldObject)
    if worldObject and worldObject.getModData then
        local ok, modData = pcall(worldObject.getModData, worldObject)
        return ok and modData or nil
    end
    return nil
end

local function squareHasFloorPipe(square)
    if not square then
        return false
    end
    for _, worldObject in ipairs(PipeObjectUtils.getPipeObjectsOnSquare(square)) do
        if PipeObjectUtils.getPipePlacement(worldObject).surface == Constants.PIPE_SURFACE_FLOOR then
            return true
        end
    end
    return false
end

local function squareHasRiserEdge(square, edge)
    if not square then
        return false
    end
    for _, worldObject in ipairs(PipeObjectUtils.getPipeObjectsOnSquare(square)) do
        local modData = getModData(worldObject)
        if modData and modData[Constants.PIPE_RISER_MODDATA_KEY] == true
            and modData[Constants.PIPE_RISER_EDGE_MODDATA_KEY] == edge then
            return true
        end
    end
    return false
end

-- The gauge is not a pipe, so it is not in getPipeObjectsOnSquare; scan the square's objects instead.
local function squareHasGauge(square)
    if not square or not square.getObjects then
        return false
    end
    local ok, objects = pcall(square.getObjects, square)
    if not ok or not objects then
        return false
    end
    for i = 0, objects:size() - 1 do
        local modData = getModData(objects:get(i))
        if modData and modData[Constants.GAUGE_MODDATA_KEY] then
            return true
        end
    end
    return false
end

-- ===== OnIsValid (both sides) =====

-- One floor pipe per square (any orientation) -- they auto-connect.
function Build.floorOnIsValid(params)
    return not squareHasFloorPipe(params and params.square)
end

-- One riser per edge (N/W) per square; the edge follows the rotation (facing).
function Build.riserOnIsValid(params)
    return not squareHasRiserEdge(params and params.square, edgeFromFacing(params))
end

-- Did this build consume a fired clay pipe segment instead of a metal pipe?
--
-- CraftRecipeData exposes the build's items through several lists that do not all populate in every
-- situation, so we ask each in turn rather than trusting one. getAllRecordedConsumedItems is the
-- narrowest (vanilla's barricade code checks it for emptiness before using it, so it is known to come
-- back blank); getAllInputItems is what vanilla's own lamp-on-pillar OnCreate uses to identify which
-- item went into a build, which is exactly our question. First list that names the clay segment wins.
--
-- Getting this wrong is not loud: the pipe silently reads as metal and hands a metal pipe back when
-- dismantled, which is precisely how it shipped broken once. Hence the warning at the bottom -- if no
-- accessor yields a single item, something about the build path has changed and we want to know.
local CRAFT_ITEM_ACCESSORS = {
    "getAllRecordedConsumedItems",
    "getAllConsumedItems",
    "getAllInputItems",
}

local function listNamesClay(items)
    if not items or not items.size then
        return false, 0
    end
    local ok, count = pcall(items.size, items)
    if not ok or not count or count <= 0 then
        return false, 0
    end
    for index = 0, count - 1 do
        local okGet, item = pcall(items.get, items, index)
        if okGet and item then
            local okType, fullType = pcall(item.getFullType, item)
            if okType and fullType == Constants.PIPE_CLAY_ITEM_TYPE then
                return true, count
            end
        end
    end
    return false, count
end

-- What each accessor actually returned, as one line for console.txt. Logged once per session on the
-- first pipe built, because which of these lists populates is a property of the running build of the
-- game and cannot be settled by reading our own code -- and when it changes, the symptom is a silent
-- wrong material rather than an error.
local function describeCraftInputs(data)
    local parts = {}
    for _, accessor in ipairs(CRAFT_ITEM_ACCESSORS) do
        if not data[accessor] then
            parts[#parts + 1] = accessor .. "=absent"
        else
            local ok, items = pcall(data[accessor], data)
            if not ok or not items or not items.size then
                parts[#parts + 1] = accessor .. "=nil"
            else
                local okCount, count = pcall(items.size, items)
                count = (okCount and count) or 0
                local types = {}
                for index = 0, count - 1 do
                    local okGet, item = pcall(items.get, items, index)
                    -- Each pcall on its own statement. `a and b and pcall(f)` truncates to ONE value,
                    -- so folding these into a chain silently throws the type away and reports every
                    -- item as nil -- which is exactly what this line did on its first outing.
                    local fullType = nil
                    if okGet and item then
                        local okType, resolved = pcall(item.getFullType, item)
                        fullType = okType and resolved or nil
                    end
                    types[#types + 1] = fullType and tostring(fullType) or "?"
                end
                parts[#parts + 1] = accessor .. "=[" .. table.concat(types, " ") .. "]"
            end
        end
    end
    return table.concat(parts, "  ")
end

local warnedNoInputs = false
-- Reported once per OUTCOME, not once per session: a player testing this builds one of each, and
-- both lines have to land or the log cannot tell "clay was detected" from "clay was never tried".
-- Two lines a session, and they are the only thing that answers "did the stamp work" without
-- dismantling the pipe to find out.
local describedOutcome = { [true] = false, [false] = false }

local function reportMaterial(data, isClay)
    if describedOutcome[isClay] then
        return
    end
    describedOutcome[isClay] = true
    if WaterPipes.Logger and WaterPipes.Logger.log then
        WaterPipes.Logger.log("build material = " .. (isClay and "CLAY" or "metal")
            .. " | " .. describeCraftInputs(data))
    end
end

local function consumedClay(params)
    local data = params and params.craftRecipeData
    if not data then
        return false
    end

    local sawAnyItem = false
    for _, accessor in ipairs(CRAFT_ITEM_ACCESSORS) do
        if data[accessor] then
            local ok, items = pcall(data[accessor], data)
            if ok then
                local isClay, count = listNamesClay(items)
                if count > 0 then
                    sawAnyItem = true
                end
                if isClay then
                    reportMaterial(data, true)
                    return true
                end
            end
        end
    end

    reportMaterial(data, false)

    -- Every accessor came back empty. That is not "a metal pipe was used" -- it is "we could not
    -- tell", and the two are indistinguishable downstream, so say so once.
    if not sawAnyItem and not warnedNoInputs then
        warnedNoInputs = true
        if WaterPipes.Logger and WaterPipes.Logger.warn then
            WaterPipes.Logger.warn(
                "build: craftRecipeData listed no input items -- pipe build material cannot be read, "
                .. "every pipe will read as metal. Accessors tried: "
                .. table.concat(CRAFT_ITEM_ACCESSORS, ", "))
        end
    end

    return false
end

-- ===== OnCreate (server / single-player) =====

-- opts: surface, riser, edge, hidden, router, routerDirection, pump, drip, sprinkler, axis.
-- Every pipe variant goes through here so they all land on the network the same way; what makes a
-- router / pump / drip / sprinkler special is one extra modData flag, never a separate object type.
local function markAndRegister(thumpable, opts)
    if not thumpable then
        return
    end
    opts = opts or {}

    local modData = getModData(thumpable)
    if modData then
        modData[Constants.PIPE_MODDATA_KEY] = true
        modData[Constants.PIPE_SURFACE_MODDATA_KEY] = opts.surface
        modData[Constants.PIPE_AXIS_MODDATA_KEY] = opts.axis or Constants.PIPE_AXIS_EW
        -- Build material: only stamped when it is not the metal default, so old pipes stay metal.
        modData[Constants.PIPE_MATERIAL_MODDATA_KEY] = opts.clay and Constants.PIPE_MATERIAL_CLAY or nil
        modData[Constants.PIPE_RISER_MODDATA_KEY] = opts.riser and true or nil
        modData[Constants.PIPE_RISER_EDGE_MODDATA_KEY] = opts.edge or nil
        -- Concealed variant: baked in at build; clients render it with a transparent tile.
        modData[Constants.PIPE_HIDDEN_MODDATA_KEY] = opts.hidden and true or nil
        -- Router variant: a flow boundary; the OUT direction is chosen by rotating (R) at build time.
        modData[Constants.ROUTER_MODDATA_KEY] = opts.router and true or nil
        if opts.router then
            modData[Constants.ROUTER_DIRECTION_KEY] = opts.routerDirection or Constants.ROUTER_DEFAULT_DIRECTION
            modData[Constants.ROUTER_PRESSURE_KEY] = Constants.ROUTER_PRESSURE_UNSET
        end
        -- Pump variant: powered; raises its zone's pressure and can inject from a well or open water.
        modData[Constants.PUMP_MODDATA_KEY] = opts.pump and true or nil
        -- Emitters: pipes that water as fluid passes through them.
        modData[Constants.DRIP_MODDATA_KEY] = opts.drip and true or nil
        if opts.drip then
            modData[Constants.DRIP_CONDITION_KEY] = Constants.DRIP_MAX_CONDITION
        end
        modData[Constants.SPRINKLER_MODDATA_KEY] = opts.sprinkler and true or nil
    end
    if thumpable.transmitModData then
        pcall(thumpable.transmitModData, thumpable)
    end

    local square = thumpable.getSquare and thumpable:getSquare() or nil
    if square and WaterPipes.System and WaterPipes.System.registerPipeAt then
        if opts.riser then
            Logger.log(string.format("Placed vertical pipe (wall cover) edge=%s at %d:%d:%d",
                tostring(opts.edge), square:getX(), square:getY(), square:getZ()))
        end
        -- registerPipeAt rebuilds the network, refreshes plumbed endpoints and runs the autotile.
        --
        -- The WHOLE kind goes into the registry, not just the router flag. Everything here is already
        -- known -- it was just written to the object's modData a dozen lines up -- and passing only
        -- `router` meant every periodic pass that wanted pumps or emitters had to rediscover them by
        -- asking the world about every pipe in the base. That is exactly why processRouters, which can
        -- filter, costs nothing per minute, while processPumps, which could not, cost 56 ms.
        --
        -- `kinds` marks the entry as carrying the full set. Without it a pass cannot tell "not a pump"
        -- from "registered before this was recorded", and a save from an older build would have its
        -- pumps quietly filtered out of existence. See reconcilePipeKinds.
        WaterPipes.System.registerPipeAt(square:getX(), square:getY(), square:getZ(), {
            kinds = true,
            router = opts.router and true or nil,
            pump = opts.pump and true or nil,
            drip = opts.drip and true or nil,
            sprinkler = opts.sprinkler and true or nil,
            riser = opts.riser and true or nil,
        })
    end
end

function Build.floorOnCreate(params)
    markAndRegister(params and params.thumpable, {
        surface = Constants.PIPE_SURFACE_FLOOR, clay = consumedClay(params),
    })
end

function Build.riserOnCreate(params)
    markAndRegister(params and params.thumpable, {
        surface = Constants.PIPE_SURFACE_WALLCOVER, riser = true, edge = edgeFromFacing(params),
        clay = consumedClay(params),
    })
end

-- Concealed variants: identical placement/registration, but flagged hidden so each client renders
-- them invisible. Network, auto-connect and verticality are unaffected (detection is modData-based).
function Build.floorHiddenOnCreate(params)
    markAndRegister(params and params.thumpable, {
        surface = Constants.PIPE_SURFACE_FLOOR, hidden = true, clay = consumedClay(params),
    })
end

function Build.riserHiddenOnCreate(params)
    markAndRegister(params and params.thumpable, {
        surface = Constants.PIPE_SURFACE_WALLCOVER, riser = true, edge = edgeFromFacing(params), hidden = true,
        clay = consumedClay(params),
    })
end

-- Pump / emitters: floor-pipe variants that keep a fixed sprite chosen by the build-cursor axis
-- rather than autotiling into corners (there is only one sprite pair for each).
function Build.pumpOnCreate(params)
    markAndRegister(params and params.thumpable, {
        surface = Constants.PIPE_SURFACE_FLOOR, pump = true, axis = axisFromFacing(params),
    })
end

function Build.dripOnCreate(params)
    markAndRegister(params and params.thumpable, {
        surface = Constants.PIPE_SURFACE_FLOOR, drip = true, axis = axisFromFacing(params),
    })
end

function Build.sprinklerOnCreate(params)
    markAndRegister(params and params.thumpable, {
        surface = Constants.PIPE_SURFACE_FLOOR, sprinkler = true, axis = axisFromFacing(params),
    })
end

-- Purifier-containers: NON-pipe objects placed on a router tile. They hold two buffers (IN tainted /
-- OUT clean) and the router purifies water in transit through them; they never register as pipes.
local function markPurifierContainer(thumpable, tier)
    if not thumpable then
        return
    end
    local modData = getModData(thumpable)
    if modData then
        modData[Constants.PURIFIER_MODDATA_KEY] = tier
        modData[Constants.PURIFIER_IN_AMOUNT_KEY] = 0
        modData[Constants.PURIFIER_OUT_AMOUNT_KEY] = 0
        modData[Constants.PURIFIER_FILTER_CONDITION_KEY] = Constants.PURIFIER_FILTER_MAX_CONDITION
    end
    if thumpable.transmitModData then
        pcall(thumpable.transmitModData, thumpable)
    end

    -- Record where it is. Nothing else needs to go looking for it afterwards.
    local square = thumpable.getSquare and thumpable:getSquare() or nil
    local State = WaterPipes.State
    if square and State and State.registerPurifier then
        pcall(State.registerPurifier, square:getX(), square:getY(), square:getZ())
    end
end

function Build.electricContainerOnCreate(params)
    markPurifierContainer(params and params.thumpable, Constants.PURIFIER_TIER_ELECTRIC)
end

-- The tall tank clips through anything overhead: refuse placement if a floor sits on the tile directly
-- above. (Pipes and routers are floor-level and CAN hide under structures; the visible tank cannot.)
local function hasStructureAbove(square)
    if not square or not getCell then
        return false
    end
    local cell = getCell()
    if not cell or not cell.getGridSquare then
        return false
    end
    local above = cell:getGridSquare(square:getX(), square:getY(), square:getZ() + 1)
    if not above or not above.getFloor then
        return false
    end
    local ok, floor = pcall(above.getFloor, above)
    return ok and floor ~= nil
end

-- The purifier is a 2x2 multi-tile tank. The engine validates EVERY footprint tile and requires ALL
-- of them to pass, so the router requirement must apply to exactly ONE tile -- the anchor -- not to all
-- four (otherwise the player would need a router under every tile). The anchor is the cursor/origin tile
-- (grid 0,0), which draws the top/back quadrant sprite (_36); it is where OnCreate tags the purifier and
-- where the runtime pairs router<->purifier on the SAME square. The other three tiles only need to be
-- clear, which the engine already checks -- for them we just return true.
function Build.purifierContainerOnIsValid(params)
    local square = params and params.square
    if not square then
        return false
    end
    -- Identify the anchor tile by the per-tile sprite the engine is validating.
    local tileInfo = params.tileInfo
    local spriteName = tileInfo and tileInfo.getSpriteName and tileInfo:getSpriteName()
    if spriteName ~= Constants.PURIFIER_TANK_TOP_SPRITE then
        return true   -- a non-anchor footprint tile: no router needed here
    end
    -- Anchor tile: needs the (single, central) router, no existing purifier, and clear headroom so the
    -- tall tank does not clip through a floor above.
    local Router = WaterPipes.Router
    local Purifier = WaterPipes.Purifier
    if not Router or not Router.hasRouterOnSquare(square) then
        return false
    end
    if Purifier and Purifier.findOnSquare(square) then
        return false
    end
    if hasStructureAbove(square) then
        return false
    end
    return true
end

-- Fluid router: a floor pipe that is a flow boundary (splits the network into IN and OUT sides). The
-- OUT direction comes from the build-cursor facing (rotate with R while placing).
function Build.routerOnCreate(params)
    markAndRegister(params and params.thumpable, {
        surface = Constants.PIPE_SURFACE_FLOOR, router = true, routerDirection = facingToDirection(params),
    })
end

-- The pump is an ordinary floor pipe as far as placement goes: one per tile, like any other.
Build.pumpOnIsValid = Build.floorOnIsValid
Build.sprinklerOnIsValid = Build.floorOnIsValid

-- The drip emitter is deliberately NOT gated on being clear of crops: it is meant to be laid down
-- the furrow, on top of what it waters. floorOnIsValid only refuses a second floor pipe on the tile,
-- which is exactly the rule we want here too -- so this is an alias for intent, not for behaviour.
Build.dripOnIsValid = Build.floorOnIsValid

-- The gauge is a dial that sits on a pipe at floor level -- it reads the network but never carries
-- fluid, so it never registers and never affects the graph. It needs a pipe under it to read, and
-- there is room for only one per tile.
function Build.gaugeOnIsValid(params)
    local square = params and params.square
    return squareHasFloorPipe(square) and not squareHasGauge(square)
end

function Build.gaugeOnCreate(params)
    local thumpable = params and params.thumpable
    if not thumpable then
        return
    end
    local modData = getModData(thumpable)
    if modData then
        modData[Constants.GAUGE_MODDATA_KEY] = true
    end
    if thumpable.transmitModData then
        pcall(thumpable.transmitModData, thumpable)
    end
end

-- Global alias used by the entity SpriteConfig OnCreate/OnIsValid dotted paths.
WaterPipesBuild = Build

return Build
