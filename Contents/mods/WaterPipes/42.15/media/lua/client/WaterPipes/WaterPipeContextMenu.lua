require "ISUI/ISWorldObjectContextMenu"
require "WaterPipes/Constants"
require "WaterPipes/EndpointObjects"
require "WaterPipes/EndpointPlumbing"
require "WaterPipes/ISPlumbWaterPipeEndpoint"
require "WaterPipes/ISPlumbWaterPipeGenerator"
require "WaterPipes/GeneratorFuel"
require "WaterPipes/PipeObjectUtils"
require "WaterPipes/Purifier"
require "WaterPipes/Router"
require "WaterPipes/NetworkAccess"
require "WaterPipes/Pressure"
require "WaterPipes/Pump"
require "WaterPipes/Hydrant"
require "WaterPipes/ISToggleHydrant"
require "WaterPipes/ISTogglePump"
require "WaterPipes/ISOpenWaterPump"
require "WaterPipes/Irrigation"
require "WaterPipes/WaterPipesIrrigationDebug"
require "WaterPipes/WaterPipesRouterPressureWindow"
require "WaterPipes/ISRepairWaterDrip"
require "WaterPipes/Logger"
-- Client-side: loads PipeAutotile so it registers its OnObjectAdded/LoadGridsquare hooks and each
-- client recomputes pipe connection sprites locally (the shape is never sent over the network).
require "WaterPipes/PipeAutotile"
require "WaterPipes/API"
require "WaterPipes/WaterPipesPurifierWindow"
require "WaterPipes/WaterPipesPumpWindow"
require "WaterPipes/WaterPipesPurifierSound"
require "WaterPipes/ISRepairWaterPurifier"
require "WaterPipes/ISOpenWaterPurifier"
require "WaterPipes/Profiler"
require "WaterPipes/RemovalAudit"

WaterPipes = WaterPipes or {}
WaterPipes.ContextMenu = WaterPipes.ContextMenu or {}

local Constants = WaterPipes.Constants
local EndpointObjects = WaterPipes.EndpointObjects
local EndpointPlumbing = WaterPipes.EndpointPlumbing
local GeneratorFuel = WaterPipes.GeneratorFuel
local Logger = WaterPipes.Logger
local NetworkAccess = WaterPipes.NetworkAccess
local PipeObjectUtils = WaterPipes.PipeObjectUtils
local Purifier = WaterPipes.Purifier
local Router = WaterPipes.Router
local Hydrant = WaterPipes.Hydrant
local Pump = WaterPipes.Pump
local Pressure = WaterPipes.Pressure
local Irrigation = WaterPipes.Irrigation
local IrrigationDebug = WaterPipes.IrrigationDebug
local PipeAutotile = WaterPipes.PipeAutotile
local ContextMenu = WaterPipes.ContextMenu
ContextMenu.originalOnPlumbItem = ContextMenu.originalOnPlumbItem or ISWorldObjectContextMenu.onPlumbItem
ContextMenu.DEBUG_ROOT_NAME = "Water Pipes"

-- Display name used to mirror the sink's "Plumb <name>" / "Unplumb <name>" wording for generators.
local function getGeneratorDisplayName()
    return getText("IGUI_WaterPipesGenerator")
end

-- Same icon the engine puts on the vanilla sink "Plumb" option (the pipe wrench).
local function applyPlumbOptionIcon(option)
    if option then
        option.iconTexture = getTexture("Item_PipeWrench")
    end
    return option
end

local function findGeneratorInWorldObjects(worldobjects)
    if not worldobjects then
        return nil
    end
    for _, worldObject in ipairs(worldobjects) do
        if GeneratorFuel.isGenerator(worldObject) then
            return worldObject
        end
        if worldObject and worldObject.getSquare and worldObject:getSquare() then
            local objects = worldObject:getSquare():getObjects()
            for i = 0, objects:size() - 1 do
                local candidate = objects:get(i)
                if GeneratorFuel.isGenerator(candidate) then
                    return candidate
                end
            end
        end
    end
    return nil
end

local function isDebugActive()
    return getDebug and getDebug()
end

-- ===== Network visualization (right-click a pipe) =====
-- red = pipes, green = fluid-providing objects (containers), blue = consumers (sinks/generators).
ContextMenu.highlightedObjects = ContextMenu.highlightedObjects or {}
-- Concealed pipes temporarily revealed for the duration of a network visualization.
ContextMenu.revealedHiddenPipes = ContextMenu.revealedHiddenPipes or {}
local HIGHLIGHT_TICKS = 480 -- ~8s at 60fps; auto-clears the highlight
local COLOR_PIPE = { r = 0.95, g = 0.20, b = 0.20, a = 1.0 }      -- red
local COLOR_SOURCE = { r = 0.20, g = 0.95, b = 0.30, a = 1.0 }    -- green: provides fluid
local COLOR_CONSUMER = { r = 0.30, g = 0.60, b = 1.00, a = 1.0 }  -- blue: draws fluid (out-network)
local COLOR_ROUTER = { r = 1.00, g = 0.75, b = 0.10, a = 1.0 }    -- amber: fluid router (boundary)

local function findPipeInWorldObjects(worldobjects)
    if not worldobjects then
        return nil
    end
    for _, worldObject in ipairs(worldobjects) do
        if PipeObjectUtils.isPipeObject(worldObject) then
            return worldObject
        end
        if worldObject and worldObject.getSquare and worldObject:getSquare() then
            local pipe = PipeObjectUtils.getPipeOnSquare(worldObject:getSquare())
            if pipe then
                return pipe
            end
        end
    end
    return nil
end

-- ===== Purifier tiles (status readout + filter-cartridge replacement) =====

-- The purifier is a 2x2 tank whose modData lives only on the ANCHOR (min-corner) tile, but the player
-- will often right-click the visible body. The footprint extends +x/+y from the anchor, so from any of
-- the four tiles the anchor sits within the 2x2 block up-and-left of it.
local PURIFIER_BLOCK_OFFSETS = { { 0, 0 }, { -1, 0 }, { 0, -1 }, { -1, -1 } }

local function findPurifierInWorldObjects(worldobjects)
    if not worldobjects then
        return nil
    end
    local cell = getCell and getCell() or nil
    for _, worldObject in ipairs(worldobjects) do
        if Purifier.isPurifier(worldObject) then
            return worldObject
        end
        local square = worldObject and worldObject.getSquare and worldObject:getSquare() or nil
        if square then
            for _, off in ipairs(PURIFIER_BLOCK_OFFSETS) do
                local nsq = square
                if off[1] ~= 0 or off[2] ~= 0 then
                    nsq = cell and cell:getGridSquare(square:getX() + off[1], square:getY() + off[2], square:getZ())
                end
                local purifier = nsq and Purifier.findOnSquare(nsq)
                if purifier then
                    return purifier
                end
            end
        end
    end
    return nil
end

-- The anchor of a purifier's 2x2 footprint: the router tile the SERVER processes the tank on, and
-- therefore the only object whose modData holds its real state. The other three carry a purifier object
-- with empty modData, so anything reading state comes through here or silently reads defaults.
-- Resolved exactly the way the server does it, so client and server agree on which object they mean.
local function resolvePurifierAnchor(purifierObject)
    local square = purifierObject and purifierObject.getSquare and purifierObject:getSquare() or nil
    local cell = getCell and getCell() or nil
    if not square or not cell then
        return nil, nil
    end

    for _, off in ipairs(PURIFIER_BLOCK_OFFSETS) do
        local nsq = square
        if off[1] ~= 0 or off[2] ~= 0 then
            nsq = cell:getGridSquare(square:getX() + off[1], square:getY() + off[2], square:getZ())
        end
        if nsq and Router.hasRouterOnSquare(nsq) then
            local anchor = Purifier.findForRouterSquare(nsq)
            if anchor then
                return anchor, nsq
            end
        end
    end
    return nil, nil
end

-- Open the purifier readout window (buffers, running status, filtering rate).
function ContextMenu.openPurifier(playerObj, purifierObject)
    if not purifierObject or not WaterPipesPurifierWindow then
        return
    end
    -- The window has to read the SAME buffers the server writes, so it keys off the anchor tile
    -- rather than whichever of the four the player clicked.
    local _anchor, anchorSquare = resolvePurifierAnchor(purifierObject)

    -- Walk the character over to the tank, then open the window on arrival. If it is unreachable, just
    -- open it in place so the readout is never blocked.
    if luautils.walkAdjObject(playerObj, purifierObject, true) then
        ISTimedActionQueue.add(ISOpenWaterPurifier:new(playerObj, purifierObject, anchorSquare))
    else
        WaterPipesPurifierWindow.openFor(purifierObject, anchorSquare)
    end
end

local function addPurifierOptions(context, playerObj, purifierObject)
    context:addOption(getText("ContextMenu_WaterPipesOpenPurifier"), playerObj, ContextMenu.openPurifier, purifierObject)
end

local function setHighlight(worldObject, playerNum, on, color)
    if not worldObject or not worldObject.setHighlighted then
        return
    end
    pcall(function()
        worldObject:setHighlighted(playerNum, on, false)
        if on and color then
            worldObject:setHighlightColor(playerNum, color.r, color.g, color.b, color.a)
        end
        if worldObject.setOutlineHighlight then
            worldObject:setOutlineHighlight(playerNum, on)
            if on and color and worldObject.setOutlineHighlightCol then
                worldObject:setOutlineHighlightCol(playerNum, color.r, color.g, color.b, color.a)
            end
        end
    end)
end

local function clearNetworkHighlight()
    for _, entry in ipairs(ContextMenu.highlightedObjects) do
        setHighlight(entry.object, entry.player, false, nil)
    end
    ContextMenu.highlightedObjects = {}
    ContextMenu.highlightTicksLeft = 0

    -- Re-conceal any pipes we temporarily revealed for the visualization.
    if PipeAutotile and PipeAutotile.rehidePipe then
        for _, pipe in ipairs(ContextMenu.revealedHiddenPipes) do
            PipeAutotile.rehidePipe(pipe)
        end
    end
    ContextMenu.revealedHiddenPipes = {}
end
ContextMenu.clearNetworkHighlight = clearNetworkHighlight

local function onHighlightTick()
    ContextMenu.highlightTicksLeft = (ContextMenu.highlightTicksLeft or 0) - 1
    if ContextMenu.highlightTicksLeft <= 0 then
        clearNetworkHighlight()
        if Events and Events.OnTick then
            Events.OnTick.Remove(onHighlightTick)
        end
    end
end

local function trackAndHighlight(worldObject, playerNum, color)
    setHighlight(worldObject, playerNum, true, color)
    ContextMenu.highlightedObjects[#ContextMenu.highlightedObjects + 1] = { object = worldObject, player = playerNum }
end

function ContextMenu.showNetwork(playerObj, pipeObject)
    if not playerObj or not pipeObject or not pipeObject.getSquare then
        return
    end
    local square = pipeObject:getSquare()
    if not square then
        return
    end

    clearNetworkHighlight()

    local playerNum = playerObj:getPlayerNum()

    local pipeSquares, descriptors = NetworkAccess.getNetworkFromSquare(square)

    -- Pipes (red). Concealed pipes are temporarily revealed so they show with their overlay.
    for _, sq in ipairs(pipeSquares or {}) do
        for _, pipe in ipairs(PipeObjectUtils.getPipeObjectsOnSquare(sq)) do
            if PipeAutotile and PipeAutotile.isPipeHidden(pipe) then
                PipeAutotile.revealPipe(pipe)
                ContextMenu.revealedHiddenPipes[#ContextMenu.revealedHiddenPipes + 1] = pipe
            end
            trackAndHighlight(pipe, playerNum, COLOR_PIPE)
        end
    end

    -- Routers bounding this network (amber). They are excluded from the traversal, so surface any
    -- router sitting on a square adjacent to a shown pipe.
    local cell = getCell and getCell() or nil
    if cell then
        local routerSeen = {}
        for _, sq in ipairs(pipeSquares or {}) do
            for _, offset in ipairs(Constants.NETWORK_NEIGHBOR_OFFSETS) do
                local nsq = cell:getGridSquare(sq:getX() + offset.x, sq:getY() + offset.y, sq:getZ() + offset.z)
                local router = nsq and Router.findOnSquare(nsq)
                if router and not routerSeen[tostring(router)] then
                    routerSeen[tostring(router)] = true
                    trackAndHighlight(router, playerNum, COLOR_ROUTER)
                end
            end
        end
    end

    -- Fluid-providing objects / containers (green).
    for _, descriptor in ipairs(descriptors or {}) do
        if descriptor.object then
            trackAndHighlight(descriptor.object, playerNum, COLOR_SOURCE)
        end
    end

    -- Consumers that draw from the network (blue): plumbed sinks/showers/toilets + generators.
    for _, sq in ipairs(pipeSquares or {}) do
        for _, endpoint in ipairs(EndpointObjects.collectOnSquare(sq)) do
            if EndpointPlumbing.isPlumbed(endpoint) then
                trackAndHighlight(endpoint, playerNum, COLOR_CONSUMER)
            end
        end
        if sq.getObjects then
            local objects = sq:getObjects()
            for i = 0, objects:size() - 1 do
                local obj = objects:get(i)
                if GeneratorFuel.isGenerator(obj) and GeneratorFuel.isPlumbed(obj) then
                    trackAndHighlight(obj, playerNum, COLOR_CONSUMER)
                end
            end
        end
    end

    ContextMenu.highlightTicksLeft = HIGHLIGHT_TICKS
    if Events and Events.OnTick then
        Events.OnTick.Remove(onHighlightTick)
        Events.OnTick.Add(onHighlightTick)
    end
end

function ContextMenu.hideNetwork(playerObj)
    clearNetworkHighlight()
    if Events and Events.OnTick then
        Events.OnTick.Remove(onHighlightTick)
    end
end

local function playerHasPipeWrench(playerObj)
    local inventory = playerObj and playerObj:getInventory()
    if not inventory then
        return false
    end

    return inventory:containsTypeRecurse(Constants.PIPE_TOOL_TYPE)
end

local function getPipeWrench(playerObj)
    local inventory = playerObj and playerObj:getInventory()
    if not inventory then
        return nil
    end

    return inventory:getFirstTypeEvalRecurse("PipeWrench", function(item)
        return item and (not item.isBroken or not item:isBroken())
    end) or inventory:getFirstTagEvalRecurse(ItemTag.PIPE_WRENCH, function(item)
        return item and (not item.isBroken or not item:isBroken())
    end)
end

function ContextMenu.plumbEndpoint(playerObj, endpointObject)
    if not playerObj or not endpointObject then
        return
    end

    local wrench = getPipeWrench(playerObj)
    if not wrench then
        return
    end

    if luautils.walkAdjObject(playerObj, endpointObject, true) then
        ISWorldObjectContextMenu.equip(playerObj, playerObj:getPrimaryHandItem(), wrench, true)
        ISTimedActionQueue.add(ISPlumbWaterPipeEndpoint:new(playerObj, endpointObject, wrench, true))
    end
end

function ContextMenu.unplumbEndpoint(playerObj, endpointObject)
    if not playerObj or not endpointObject then
        return
    end

    local wrench = getPipeWrench(playerObj)
    if not wrench then
        return
    end

    if luautils.walkAdjObject(playerObj, endpointObject, true) then
        ISWorldObjectContextMenu.equip(playerObj, playerObj:getPrimaryHandItem(), wrench, true)
        ISTimedActionQueue.add(ISPlumbWaterPipeEndpoint:new(playerObj, endpointObject, wrench, false))
    end
end

function ContextMenu.plumbGenerator(playerObj, generatorObject)
    if not playerObj or not generatorObject then
        return
    end

    local wrench = getPipeWrench(playerObj)
    if not wrench then
        return
    end

    if luautils.walkAdjObject(playerObj, generatorObject, true) then
        ISWorldObjectContextMenu.equip(playerObj, playerObj:getPrimaryHandItem(), wrench, true)
        ISTimedActionQueue.add(ISPlumbWaterPipeGenerator:new(playerObj, generatorObject, wrench, true))
    end
end

function ContextMenu.unplumbGenerator(playerObj, generatorObject)
    if not playerObj or not generatorObject then
        return
    end

    local wrench = getPipeWrench(playerObj)
    if not wrench then
        return
    end

    if luautils.walkAdjObject(playerObj, generatorObject, true) then
        ISWorldObjectContextMenu.equip(playerObj, playerObj:getPrimaryHandItem(), wrench, true)
        ISTimedActionQueue.add(ISPlumbWaterPipeGenerator:new(playerObj, generatorObject, wrench, false))
    end
end

-- Walk to the purifier, equip the wrench and queue the filter-repair action (consumes the repair kit).
function ContextMenu.repairPurifier(playerObj, purifierObject)
    if not playerObj or not purifierObject then
        return
    end

    local wrench = getPipeWrench(playerObj)
    if not wrench then
        return
    end

    if luautils.walkAdjObject(playerObj, purifierObject, true) then
        ISWorldObjectContextMenu.equip(playerObj, playerObj:getPrimaryHandItem(), wrench, true)
        ISTimedActionQueue.add(ISRepairWaterPurifier:new(playerObj, purifierObject, wrench))
    end
end

function ContextMenu.onVanillaPlumbItem(worldobjects, player, itemToPipe)
    if itemToPipe
        and EndpointObjects.isEndpointCandidate(itemToPipe)
        and EndpointPlumbing.hasPipeOnEndpointSquare(itemToPipe)
    then
        local playerObj = getSpecificPlayer(player)
        if not playerObj then
            return
        end

        local wrench = getPipeWrench(playerObj)
        if not wrench then
            return
        end

        Logger.log("Vanilla plumb intercepted for pipe-network endpoint: " .. tostring(itemToPipe))
        if luautils.walkAdjObject(playerObj, itemToPipe, true) then
            ISWorldObjectContextMenu.equip(playerObj, playerObj:getPrimaryHandItem(), wrench, true)
            ISTimedActionQueue.add(ISPlumbWaterPipeEndpoint:new(playerObj, itemToPipe, wrench, true))
        end
        return
    end

    if ContextMenu.originalOnPlumbItem then
        return ContextMenu.originalOnPlumbItem(worldobjects, player, itemToPipe)
    end
end

function ContextMenu.forceGlobalWaterShutoff(playerObj)
    if not isDebugActive() or not playerObj then
        return
    end

    sendClientCommand(playerObj, "WaterPipes", "forceGlobalWaterShutoff", {})
end

function ContextMenu.forceNetworkTick(playerObj)
    if not isDebugActive() or not playerObj then
        return
    end

    sendClientCommand(playerObj, "WaterPipes", "forceNetworkTick", {})
end

function ContextMenu.dumpPlumbingDiagnostics(playerObj, endpointObject)
    if not isDebugActive() or not endpointObject then
        return
    end

    EndpointPlumbing.dumpDiagnostics(endpointObject)
    local lastPicked = UIManager and UIManager.getLastPicked and UIManager.getLastPicked() or nil
    if lastPicked and WaterPipes.EndpointAdapterSource and WaterPipes.EndpointAdapterSource.describeHiddenFlags then
        Logger.log("Client last picked: " .. WaterPipes.EndpointAdapterSource.describeHiddenFlags(lastPicked))
    else
        Logger.log("Client last picked: " .. tostring(lastPicked))
    end
    if playerObj and HaloTextHelper then
        HaloTextHelper.addText(playerObj, "Water Pipes: diagnostics dumped at console.txt")
    end
end

function ContextMenu.dumpAdapterDiagnostics(playerObj, endpointObject)
    if not isDebugActive() or not endpointObject then
        return
    end

    EndpointPlumbing.dumpAdapterSquareDiagnostics(endpointObject)
    local lastPicked = UIManager and UIManager.getLastPicked and UIManager.getLastPicked() or nil
    if lastPicked and WaterPipes.EndpointAdapterSource and WaterPipes.EndpointAdapterSource.describeHiddenFlags then
        Logger.log("Client last picked (adapter debug): " .. WaterPipes.EndpointAdapterSource.describeHiddenFlags(lastPicked))
    else
        Logger.log("Client last picked (adapter debug): " .. tostring(lastPicked))
    end

    if playerObj and HaloTextHelper then
        HaloTextHelper.addText(playerObj, "Water Pipes: adapter diagnostics dumped at console.txt")
    end
end

-- Debug pressure readout. Unlike the gauge this works on ANY square -- no fixture, no pipe needed --
-- and shows every term that produced the number, so a wrong reading can be traced to the source, hop
-- count, pump or router ceiling behind it. Debug strings stay English, like the rest of this menu.
local function describePressureReport(report, square)
    local lines = {}
    local function add(fmt, ...)
        lines[#lines + 1] = select("#", ...) > 0 and string.format(fmt, ...) or fmt
    end

    add("Square %d,%d,%d", square:getX(), square:getY(), square:getZ())

    local MODEL_NAMES = {
        [Constants.PRESSURE_MODEL_REALISTIC] = "realistic",
        [Constants.PRESSURE_MODEL_SIMPLE] = "simple (height only)",
        [Constants.PRESSURE_MODEL_OFF] = "OFF (gravity only)",
    }
    add("Model: %s", MODEL_NAMES[report.model] or tostring(report.model))

    if report.pipeCount == 0 then
        add("No pipe network reachable from here.")
        return lines
    end

    add("Reach: %d pipes, %d containers, %d/%d pumps powered",
        report.pipeCount, report.containerCount or 0, report.poweredPumps, report.pumpCount)
    add("Pump head: +%.1f", report.pumpHead or 0)
    add("Mains: %d live inlet(s), head +%.1f", report.mainsCount or 0, report.mainsHead or 0)
    add("Hydrants: %d pressurising, supply floor %.1f",
        report.hydrantCount or 0, report.supplyHead or 0)

    add("Load: %d emitter(s), %d starved, %.2f of %.2f L/h served",
        report.emitterCount or 0, report.starvedCount or 0,
        report.servedDemand or 0, report.totalDemand or 0)
    add("Flow through this tile: %.2f L/h   (demand scale %.0f%%)",
        report.flow or 0, (report.demandScale or 1) * 100)

    add(" ")
    add("Head by consumer (at this tile, under the current load):")
    for _, kind in ipairs({ Constants.PRESSURE_KIND_TAP, Constants.PRESSURE_KIND_DRIP,
        Constants.PRESSURE_KIND_SPRINKLER }) do
        local entry = report.kinds[kind]
        if entry then
            -- "SHARED OUT" rather than "NOT ENOUGH": the head on this tile is fine, and saying otherwise next to a
            -- comfortable number would read as a bug. What is missing is room on the line.
            local verdict = "OK"
            if not entry.ok then
                verdict = report.starvedHere and "SHARED OUT" or "NOT ENOUGH"
                -- "SHARED OUT" says the search dropped it. Whether it HAD to is a different question, and the one that
                -- decides whether this is a fact about the plumbing or a fault in the search.
                if report.couldServeHere == true then
                    verdict = verdict .. "  <-- but it COULD be served; the search gave up early"
                elseif report.couldServeHere == false and report.serveBlockedBy then
                    verdict = verdict .. "  (adding it would starve " .. tostring(report.serveBlockedBy) .. ")"
                end
            end
            add("  %-9s %6.2f  (needs %.1f, friction %.3f/tile)  %s",
                kind, entry.head or 0, entry.minimum, entry.friction, verdict)
        end
    end

    add(" ")
    -- Head is a property of the TILE now, not of each (source, consumer) pair. What is still worth listing
    -- per source is what it holds and whether it sits high enough to help at all.
    add("Sources (gravity only -> pressurised, pumps included):")
    if #report.sources == 0 then
        add("  none")
    end
    for _, source in ipairs(report.sources) do
        add("  z=%d hops=%s  %.1f/%.1f %s  ->  %6.2f -> %6.2f",
            source.z or 0, source.hops and tostring(source.hops) or "-",
            source.amount or 0, source.capacity or 0,
            tostring(source.fluidType), source.staticHead or 0,
            source.supplyHead or source.staticHead or 0)
    end

    return lines
end

function ContextMenu.inspectPressure(playerObj, square)
    if not isDebugActive() or not square then
        return
    end

    local report = NetworkAccess.getPressureReport(square)
    if not report then
        return
    end

    Logger.log("=== Water Pipes pressure report ===")
    for _, line in ipairs(describePressureReport(report, square)) do
        Logger.log(line)
    end

    if playerObj and HaloTextHelper then
        local tap = report.kinds and report.kinds[Constants.PRESSURE_KIND_TAP]
        HaloTextHelper.addText(playerObj, tap and tap.head
            and string.format("Water Pipes: %.2f m of head here", tap.head)
            or "Water Pipes: no network here")
    end
end

local function buildPressureDebugTooltip(square)
    local report = NetworkAccess.getPressureReport(square)
    if not report then
        return nil
    end
    local tooltip = ISWorldObjectContextMenu.addToolTip()
    tooltip:setName("Inspect Pressure")
    tooltip.description = table.concat(describePressureReport(report, square), " <LINE> ")
    return tooltip
end

-- Real milliseconds, on this machine, for this mod's periodic work. Turning it on resets the window,
-- so the numbers describe what happened since you asked rather than since the save loaded.
function ContextMenu.toggleProfiler(playerObj)
    if not isDebugActive() then
        return
    end
    WaterPipes.Profiler.toggle()
end

function ContextMenu.dumpProfile(playerObj)
    if not isDebugActive() then
        return
    end
    WaterPipes.Profiler.dump()
end

-- One log line per removal this mod would care about, naming what left and which of the mod's tables
-- claimed its tile. See docs/removal-events.md.

-- ===== Destruction tools, for docs/removal-events.md =====
-- The open question there is whether the engine ever removes an object WITHOUT raising
-- OnObjectAboutToBeRemoved, since three periodic safety nets exist solely for that doubt.
-- Every call below is wrapped and logged rather than trusted: these are engine entry points whose
-- signatures move between builds, and a debug tool that crashes the session it is meant to observe is
-- worse than none. If a name is wrong here, the log says so and the game keeps running.
local function tryCall(label, fn, ...)
    if type(fn) ~= "function" then
        WaterPipes.Logger.warn("debug tool: " .. label .. " is not available in this build")
        return false
    end
    local ok, err = pcall(fn, ...)
    if not ok then
        WaterPipes.Logger.warn("debug tool: " .. label .. " failed -- " .. tostring(err))
        return false
    end
    WaterPipes.Logger.log("debug tool: " .. label .. " ok")
    return true
end

-- A zombie next to the pipes, so it can be led into whatever is standing on them.
function ContextMenu.spawnZombieHere(playerObj, square)
    if not isDebugActive() or not square then
        return
    end

    local x, y, z = square:getX(), square:getY(), square:getZ()
    WaterPipes.Logger.log(("debug tool: spawning a zombie at %d:%d:%d"):format(x, y, z))

    -- Two spellings, because which one exists depends on the build. The first that works wins.
    if tryCall("addZombiesInOutfit", _G.addZombiesInOutfit, x, y, z, 1, nil, 0) then
        return
    end
    tryCall("createHorde", _G.createHorde, x, y, x + 1, y + 1, z, 1, false)
end

-- Fire ON the tile. This is the interesting case: a barrel standing on a pipe tile is destructible,
-- and whether its removal raises the event is exactly what is unproven.
function ContextMenu.startFireHere(playerObj, square)
    if not isDebugActive() or not square then
        return
    end

    local x, y, z = square:getX(), square:getY(), square:getZ()
    WaterPipes.Logger.log(("debug tool: starting a fire at %d:%d:%d"):format(x, y, z))
    WaterPipes.Logger.log("debug tool: turn the Removal Audit ON first, then watch for a REMOVAL line "
        .. "for whatever burns. No line means the event never fired -- see docs/removal-events.md.")

    local manager = _G.IsoFireManager
    if not manager then
        WaterPipes.Logger.warn("debug tool: IsoFireManager is not available in this build")
        return
    end

    local cell = getCell and getCell() or nil
    -- StartFire's arity has changed across builds; try the long form first, then the short.
    if tryCall("IsoFireManager.StartFire(cell, sq, spread, life)",
        manager.StartFire, cell, square, true, 100) then
        return
    end
    tryCall("IsoFireManager.StartFire(cell, sq, spread, life, intensity)",
        manager.StartFire, cell, square, true, 100, 10)
end

function ContextMenu.toggleRemovalAudit(playerObj)
    if not isDebugActive() then
        return
    end
    WaterPipes.RemovalAudit.toggle()
end

function ContextMenu.toggleIrrigationOverlay(playerObj)
    if not isDebugActive() then
        return
    end
    IrrigationDebug.toggle()
end

-- Force an irrigation pass right now with a big dt, so crops jump instead of creeping. Server-owned
-- (the farming system lives there), so in MP it goes through a command; in SP we run it directly.
function ContextMenu.runIrrigationNow(playerObj)
    if not isDebugActive() then
        return
    end
    local dt = 2.0   -- two hours of watering in one shot: a clearly visible jump
    if isClient() then
        sendClientCommand(playerObj, "WaterPipes", "runIrrigation", { dt = dt })
    else
        pcall(Irrigation.run, dt)
    end
    if playerObj and HaloTextHelper then
        HaloTextHelper.addText(playerObj, "Water Pipes: ran irrigation pass")
    end
end

local function addDebugMenu(context, subMenu, playerObj, endpointObject, square)
    if not isDebugActive() then
        return
    end

    local debugOption = subMenu:addOption("Debug", nil, nil)
    local debugSubMenu = ISContextMenu:getNew(context)
    subMenu:addSubMenu(debugOption, debugSubMenu)

    debugSubMenu:addOption("Force Global Water Shutoff", playerObj, ContextMenu.forceGlobalWaterShutoff)
    debugSubMenu:addOption("Force Network Tick", playerObj, ContextMenu.forceNetworkTick)
    if square then
        -- Hovering shows the whole breakdown; clicking also dumps it to console.txt for copy/paste.
        local option = debugSubMenu:addOption("Inspect Pressure", playerObj, ContextMenu.inspectPressure, square)
        option.toolTip = buildPressureDebugTooltip(square)
    end
    -- Irrigation visibility: a live tint over crops (water level) and emitters (active/starved), plus
    -- an on-demand pass so you can watch crops fill without waiting for the hourly tick.
    local overlayName = IrrigationDebug.isEnabled()
        and "Irrigation Overlay: ON" or "Irrigation Overlay: OFF"
    debugSubMenu:addOption(overlayName, playerObj, ContextMenu.toggleIrrigationOverlay)
    debugSubMenu:addOption("Run Irrigation Now (+2h)", playerObj, ContextMenu.runIrrigationNow)
    local profilerName = WaterPipes.Profiler.isEnabled() and "Profiler: ON" or "Profiler: OFF"
    debugSubMenu:addOption(profilerName, playerObj, ContextMenu.toggleProfiler)
    debugSubMenu:addOption("Dump Performance Profile", playerObj, ContextMenu.dumpProfile)
    local auditName = WaterPipes.RemovalAudit.isEnabled()
        and "Removal Audit: ON" or "Removal Audit: OFF"
    debugSubMenu:addOption(auditName, playerObj, ContextMenu.toggleRemovalAudit)
    if square then
        debugSubMenu:addOption("Spawn Zombie Here", playerObj, ContextMenu.spawnZombieHere, square)
        debugSubMenu:addOption("Start Fire Here", playerObj, ContextMenu.startFireHere, square)
    end
    debugSubMenu:addOption("Check Irrigation Conservation (+2h)", playerObj,
        ContextMenu.checkIrrigationConservation)
    if endpointObject then
        debugSubMenu:addOption("Dump Plumbing Diagnostics", playerObj, ContextMenu.dumpPlumbingDiagnostics, endpointObject)
        debugSubMenu:addOption("Dump Adapter Diagnostics", playerObj, ContextMenu.dumpAdapterDiagnostics, endpointObject)
    end
end

local function addDebugRootMenu(context, playerObj, endpointObject, square)
    local rootOption = context:addOption(ContextMenu.DEBUG_ROOT_NAME, nil, nil)
    local subMenu = context:getNew(context)
    context:addSubMenu(rootOption, subMenu)
    addDebugMenu(context, subMenu, playerObj, endpointObject, square)
end

local function optionTargetsEndpoint(option, endpointObject)
    if not option or not endpointObject then
        return false
    end

    if option.target == endpointObject then
        return true
    end

    for index = 1, 10 do
        if option["param" .. tostring(index)] == endpointObject then
            return true
        end
    end

    return false
end

local function findExistingUnplumbOption(context, endpointObject)
    if not context or not context.options or not endpointObject then
        return nil
    end

    for _, option in ipairs(context.options) do
        if option.onSelect == ContextMenu.unplumbEndpoint and optionTargetsEndpoint(option, endpointObject) then
            return option
        end
    end

    return nil
end

-- The localized prefix of "Plumb %1" (e.g. "Plumb " / "Instalar "), used to find the engine's
-- vanilla plumb option (it stores a wrapped callback we can't match by onSelect).
local function getPlumbNamePrefix()
    local sentinel = "\1"
    local full = getText("ContextMenu_PlumbItem", sentinel)
    if type(full) ~= "string" then
        return nil
    end
    local prefix = full:match("^(.-)" .. sentinel)
    if prefix and prefix ~= "" then
        return prefix
    end
    return nil
end

local function findVanillaPlumbOption(context)
    local prefix = getPlumbNamePrefix()
    if not prefix or not context or not context.options then
        return nil, prefix
    end
    for _, option in ipairs(context.options) do
        if type(option.name) == "string" and #option.name >= #prefix
            and option.name:sub(1, #prefix) == prefix then
            return option, prefix
        end
    end
    return nil, prefix
end

-- The fixture's real display name (e.g. "Sink"/"Fregadero"), resolved the same way the engine
-- does it: from the sprite's CustomName/GroupName properties, run through the moveable translator.
local function getFixtureDisplayName(worldObject)
    local sprite = worldObject and worldObject.getSprite and worldObject:getSprite() or nil
    local props = sprite and sprite.getProperties and sprite:getProperties() or nil
    if not props or not props.has or not props:has("CustomName") then
        return nil
    end

    local name = props:get("CustomName")
    if props:has("GroupName") then
        name = props:get("GroupName") .. " " .. name
    end

    if Translator and Translator.getMoveableDisplayName then
        local ok, translated = pcall(Translator.getMoveableDisplayName, name)
        if ok and translated and translated ~= "" then
            return translated
        end
    end
    return name
end

-- Best available human name for a fixture, with graceful fallbacks.
local function resolveFixtureName(worldObject)
    local name = getFixtureDisplayName(worldObject)
    if name and name ~= "" then
        return name
    end
    name = worldObject and worldObject.getName and worldObject:getName() or nil
    if name and name ~= "" then
        return name
    end
    return getText("IGUI_WaterPipesFixture")
end

-- Sinks connect through the VANILLA "Plumb <name>" option (intercepted by onVanillaPlumbItem so it
-- joins our network). Once plumbed the engine often KEEPS showing it, so it is turned in place into our
-- "Unplumb <name>" -- no add/remove, no menu glitches. If the engine shows none, we add our own.
local function addTopLevelUnplumbOption(context, playerObj, endpointObject)
    if not endpointObject or not playerHasPipeWrench(playerObj) or not EndpointPlumbing.canUnplumb(endpointObject) then
        return
    end

    if findExistingUnplumbOption(context, endpointObject) then
        return
    end

    local vanillaPlumb, prefix = findVanillaPlumbOption(context)

    -- Derive the fixture name from the engine's "Plumb <name>" label when possible, else resolve it.
    local objectName = nil
    if vanillaPlumb and prefix and type(vanillaPlumb.name) == "string" then
        objectName = vanillaPlumb.name:sub(#prefix + 1)
    end
    if not objectName or objectName == "" then
        objectName = resolveFixtureName(endpointObject)
    end
    local optionName = getText("ContextMenu_WaterPipesUnplumbItem", objectName)

    if vanillaPlumb then
        -- Repurpose the engine's leftover plumb option into our unplumb.
        vanillaPlumb.name = optionName
        vanillaPlumb.target = playerObj
        vanillaPlumb.onSelect = ContextMenu.unplumbEndpoint
        vanillaPlumb.param1 = endpointObject
        for i = 2, 10 do
            vanillaPlumb["param" .. tostring(i)] = nil
        end
        vanillaPlumb.notAvailable = nil
        vanillaPlumb.isDisabled = nil
        vanillaPlumb.toolTip = nil
        applyPlumbOptionIcon(vanillaPlumb)
    else
        applyPlumbOptionIcon(context:addOption(optionName, playerObj, ContextMenu.unplumbEndpoint, endpointObject))
    end
end

-- Fallback "Plumb <name>" added by the mod ONLY when the engine does not offer its own (e.g. a
-- fixture that already uses an external water source, or no vanilla water source in the room).
-- Routes through onVanillaPlumbItem (same as the engine's option) so it joins our pipe network.
local function addModPlumbOption(context, playerObj, endpointObject, worldobjects)
    local optionName = getText("ContextMenu_PlumbItem", resolveFixtureName(endpointObject))
    applyPlumbOptionIcon(context:addOption(optionName, worldobjects, ISWorldObjectContextMenu.onPlumbItem, playerObj:getPlayerNum(), endpointObject))
end

-- The conservation check's verdict, in one line for the halo and a few for console.txt. Kept here so
-- the single-player path and the multiplayer reply render identically.
local function reportConservation(playerObj, report)
    if not report then
        return
    end
    local headline = string.format("Water Pipes: conservation %s (error %+.4f L)",
        report.ok and "OK" or "MISMATCH", report.error or 0)
    if HaloTextHelper then
        if report.ok then
            HaloTextHelper.addGoodText(playerObj, headline)
        elseif HaloTextHelper.addBadText then
            HaloTextHelper.addBadText(playerObj, headline)
        else
            HaloTextHelper.addText(playerObj, headline)
        end
    end
    Logger.log(string.format(
        "[conservation] dt=%.2fh over %d vessel(s): before %.4f L, after %.4f L",
        report.dtHours or 0, report.vessels or 0, report.before or 0, report.after or 0))
    Logger.log(string.format(
        "[conservation] network is missing %.4f L, emitters spent %.4f L, error %+.4f L -> %s",
        report.missing or 0, report.spent or 0, report.error or 0,
        report.ok and "OK" or "MISMATCH -- water was conjured or destroyed"))
end

-- Run an irrigation pass and check that the water the emitters spent is exactly the water the network
-- lost. Server-owned -- the farming system and the network state both live there -- and routed through
-- a command in single-player too, so there is one path to test rather than two.
function ContextMenu.checkIrrigationConservation(playerObj)
    if not isDebugActive() or not playerObj then
        return
    end

    sendClientCommand(playerObj, "WaterPipes", "checkIrrigationConservation", { dt = 2.0 })
    if HaloTextHelper then
        HaloTextHelper.addText(playerObj, "Water Pipes: checking conservation...")
    end
end

local function onServerCommand(module, command, args)
    if module ~= "WaterPipes" then
        return
    end

    local playerObj = getPlayer()
    if not playerObj or not HaloTextHelper then
        return
    end

    if command == "debugWaterShutoffApplied" then
        HaloTextHelper.addGoodText(playerObj, "Water Pipes: shutoff applied")
        Logger.log("Debug water shutoff applied")
    elseif command == "debugNetworkTickApplied" then
        HaloTextHelper.addGoodText(playerObj, "Water Pipes: network tick updated")
        Logger.log("Debug network tick applied")
    elseif command == "debugIrrigationConservation" then
        reportConservation(playerObj, args)
    end
end

-- An entry may accept several interchangeable items, so the requirement reads "A / B" rather than
-- pinning the player to the one they happen not to have. A tag-only entry names its displayType
-- instead: the tag has no name a player would recognise, and listing every item carrying it would grow
-- with each mod installed.
local function describeRepairEntry(entry)
    local names = {}
    for _, itemType in ipairs(Constants.repairLabelTypes(entry)) do
        names[#names + 1] = getItemNameFromFullType(itemType) or itemType
    end
    return "  " .. (entry.count or 1) .. " x " .. table.concat(names, " / ")
end

-- Tooltip for a disabled "Repair filter" option: current condition + the missing requirements.
local function buildRepairTooltip(purifierObject, hasKit, hasWrench)
    local tooltip = ISWorldObjectContextMenu.addToolTip()
    tooltip:setName(getText("ContextMenu_WaterPipesRepairFilter"))
    local lines = {}
    local condition = math.floor(Purifier.getFilterCondition(purifierObject) + 0.5)
    lines[#lines + 1] = getText("Tooltip_WaterPipesFilterCondition", condition)
    lines[#lines + 1] = " "
    lines[#lines + 1] = getText("Tooltip_WaterPipesRepairNeeds")
    if not hasWrench then
        local name = getItemNameFromFullType(Constants.PIPE_TOOL_TYPE) or "Pipe Wrench"
        lines[#lines + 1] = "  1 x " .. name
    end
    if not hasKit then
        for _, entry in ipairs(Constants.PURIFIER_REPAIR_ITEMS) do
            lines[#lines + 1] = describeRepairEntry(entry)
        end
    end
    tooltip.description = table.concat(lines, " <LINE> ")
    return tooltip
end

-- ===== Pressure devices: router regulator, drip repair, gauge =====

local function findFlaggedPipeInWorldObjects(worldobjects, predicate)
    if not worldobjects then
        return nil
    end
    for _, worldObject in ipairs(worldobjects) do
        local square = worldObject and worldObject.getSquare and worldObject:getSquare() or nil
        if square then
            for _, candidate in ipairs(PipeObjectUtils.getPipeObjectsOnSquare(square)) do
                if predicate(candidate) then
                    return candidate
                end
            end
        end
    end
    return nil
end

local function findRouterInWorldObjects(worldobjects)
    return findFlaggedPipeInWorldObjects(worldobjects, Router.isRouter)
end

local function findPumpInWorldObjects(worldobjects)
    return findFlaggedPipeInWorldObjects(worldobjects, Pump.isPump)
end

local function findDripInWorldObjects(worldobjects)
    return findFlaggedPipeInWorldObjects(worldobjects, Irrigation.isDrip)
end

local function findEmitterInWorldObjects(worldobjects)
    return findFlaggedPipeInWorldObjects(worldobjects, function(worldObject)
        return Irrigation.isDrip(worldObject) or Irrigation.isSprinkler(worldObject)
    end)
end

local function findGaugeInWorldObjects(worldobjects)
    if not worldobjects then
        return nil
    end
    for _, worldObject in ipairs(worldobjects) do
        if worldObject and worldObject.getModData then
            local ok, modData = pcall(worldObject.getModData, worldObject)
            if ok and modData and modData[Constants.GAUGE_MODDATA_KEY] then
                return worldObject
            end
        end
    end
    return nil
end

local function findHydrantInWorldObjects(worldobjects)
    if not worldobjects then
        return nil
    end
    for _, worldObject in ipairs(worldobjects) do
        if Hydrant.isHydrant(worldObject) then
            return worldObject
        end
    end
    return nil
end

-- Server-authoritative in MP so every client converges on the same regulated zone; direct in SP.
function ContextMenu.setRouterPressure(playerObj, router, pressure)
    local square = router and router:getSquare()
    if not square then
        return
    end
    if isClient() then
        sendClientCommand(playerObj, "WaterPipes", "setRouterPressure",
            { x = square:getX(), y = square:getY(), z = square:getZ(), pressure = pressure })
    else
        Router.setPressureCeiling(router, pressure)
    end
end

-- Walk to the hydrant, equip the wrench, and turn the valve as a timed action -- the actual flip is
-- server-authoritative (ISToggleHydrant sends the command; direct in SP).
function ContextMenu.setHydrantOpen(playerObj, hydrant, open)
    local square = hydrant and hydrant:getSquare()
    if not square or not playerObj then
        return
    end
    local wrench = playerObj:getInventory():getFirstTypeRecurse(Constants.PIPE_TOOL_TYPE)
    if not wrench then
        return
    end
    if luautils.walkAdj(playerObj, square, false) then
        ISWorldObjectContextMenu.equip(playerObj, playerObj:getPrimaryHandItem(), wrench, true)
        ISTimedActionQueue.add(ISToggleHydrant:new(playerObj, hydrant, wrench, open))
    end
end

-- ===== Water pump: switch + status =====

-- Flipping the switch is a physical act, so the character walks over first and the state only changes
-- when the timed action completes (ISTogglePump, where the world change is made
-- server-authoritatively). No tool: it is a switch, not plumbing.
function ContextMenu.togglePump(playerObj, pump, enable)
    if not playerObj or not pump then
        return
    end
    if luautils.walkAdjObject(playerObj, pump, true) then
        ISTimedActionQueue.add(ISTogglePump:new(playerObj, pump, enable))
    end
end

-- Walk over and read the machine. If it turns out to be unreachable, open the window in place rather
-- than leaving the player with a dead menu entry -- same fallback as the purifier.
function ContextMenu.openPump(playerObj, pump)
    if not playerObj or not pump then
        return
    end
    if luautils.walkAdjObject(playerObj, pump, true) then
        ISTimedActionQueue.add(ISOpenWaterPump:new(playerObj, pump))
    elseif WaterPipesPumpWindow then
        WaterPipesPumpWindow.openFor(pump)
    end
end

-- The pump gets a submenu of its own, titled with the machine's name. The switch entry is labelled with
-- what clicking will DO, not with what the pump currently is, so there is no doubt which way it goes.
-- The name is its own IGUI key rather than the recipe's bare "WaterPump" entry, which lives in
-- Recipes.json for the crafting UI: a getText miss there would put the raw key on screen.
local function addPumpMenu(context, playerObj, pump)
    local rootOption = context:addOption(getText("IGUI_WaterPipesPumpName"), nil, nil)
    local subMenu = ISContextMenu:getNew(context)
    context:addSubMenu(rootOption, subMenu)

    local enabled = Pump.isEnabled(pump)
    subMenu:addOption(getText(enabled and "ContextMenu_WaterPipesPumpTurnOff"
        or "ContextMenu_WaterPipesPumpTurnOn"), playerObj, ContextMenu.togglePump, pump, not enabled)
    subMenu:addOption(getText("ContextMenu_WaterPipesPumpStatus"), playerObj, ContextMenu.openPump, pump)
end

function ContextMenu.repairDrip(playerObj, drip)
    if not playerObj or not drip then
        return
    end
    local wrench = playerObj:getInventory():getFirstTypeRecurse(Constants.PIPE_TOOL_TYPE)
    if not wrench then
        return
    end
    ISWorldObjectContextMenu.equip(playerObj, playerObj:getPrimaryHandItem(), wrench, true)
    ISTimedActionQueue.add(ISRepairWaterDrip:new(playerObj, drip, wrench))
end

local function formatHead(value)
    return string.format("%.1f", value or 0)
end

-- The gauge is a readout, not a machine: everything it knows fits in a tooltip, so it needs no window.
-- It reports the pressure and nothing else. It used to advise on sprinklers and drips too, but a gauge
-- cannot know what is downstream of it -- it read the pressure on ITS tile and then talked about crops
-- twenty tiles and a regulator away. Emitters answer for themselves; see buildEmitterTooltip.
local function buildGaugeTooltip(square)
    local tooltip = ISWorldObjectContextMenu.addToolTip()
    tooltip:setName(getText("ContextMenu_WaterPipesReadGauge"))

    local lines = {}
    if not Pressure.isEnabled() then
        lines[#lines + 1] = getText("IGUI_WaterPipesPressureModelOff")
    else
        local tap = NetworkAccess.getPressureAtSquare(square, Constants.PRESSURE_KIND_TAP)
        lines[#lines + 1] = tap and getText("IGUI_WaterPipesGaugeReading", formatHead(tap))
            or getText("IGUI_WaterPipesGaugeNoSupply")
    end

    tooltip.description = table.concat(lines, " <LINE> ")
    return tooltip
end

-- Emitters diagnose themselves. What decides whether a drip or a sprinkler runs is the pressure ON ITS
-- OWN TILE at ITS OWN flow rate -- a sprinkler loses head four times faster than a tap -- so a gauge
-- reading taken elsewhere never answered the question the player was asking.
local function buildEmitterTooltip(emitterObject)
    local tooltip = ISWorldObjectContextMenu.addToolTip()
    tooltip:setName(getText("ContextMenu_WaterPipesCheckEmitter"))

    local status = Irrigation.getEmitterStatus(emitterObject, emitterObject:getSquare())
    local lines = {}

    if not status then
        lines[#lines + 1] = getText("IGUI_WaterPipesEmitterUnknown")
    elseif status.burst then
        -- A burst emitter is a plumbing fault, not a pressure reading: say so and stop.
        lines[#lines + 1] = getText("IGUI_WaterPipesEmitterBurst")
    else
        -- The head shown is the one this emitter would have WHILE RUNNING. The solved field excludes the draw
        -- of an emitter the line cannot carry, so it reads high precisely because the emitter is off -- which
        -- showed a sprinkler 37 above the line "needs 20". Re-pricing the zone costs a relaxation, so it
        -- happens HERE and nowhere else: a tooltip is opened deliberately, one emitter at a time, while the
        -- spray FX asks about every emitter in sight and keeps using the cached field.
        
        -- WHY it is not watering, and the order of these two questions is not arbitrary. WATER FIRST: with
        -- nothing in the pipes there is no supply for the field to propagate from, so the pressure gate fails
        -- for want of water, and asking about pressure first blamed a dry network on its pressure.
        local head, needed = status.pressure, nil
        if status.hasWater and not status.reaches and WaterPipes.Hydraulics then
            local square = emitterObject:getSquare()
            local solution = WaterPipes.Hydraulics.solveAt(square)

            local running = WaterPipes.Hydraulics.headIfDrawing(solution, square, status.kind)
            if running then
                head = running
            end

            -- How much more head the LINE needs, which is not how far this tile is below its own minimum. A
            -- sprinkler reading 30 against a minimum of 20 is short of nothing itself; it is off because switching
            -- it on would push a different emitter under.
            needed = WaterPipes.Hydraulics.headNeededToServe(solution, square, status.kind)
        end

        if head then
            lines[#lines + 1] = getText("IGUI_WaterPipesEmitterPressure", formatHead(head))
        elseif status.hasWater then
            lines[#lines + 1] = getText("IGUI_WaterPipesEmitterNoSupply")
        end

        if not status.hasWater then
            -- The pipes are empty. Nothing about pressure is worth saying until they are not.
            lines[#lines + 1] = getText("IGUI_WaterPipesEmitterDry")
        elseif not status.reaches and needed and needed > 0 then
            -- One sentence, one number: how much more pressure the line needs before this emitter runs. It covers
            -- both reasons an emitter is off for pressure -- its own head too low, or its draw pushing another
            -- under -- because in both cases the answer is the same figure, the worst shortfall in the set.
            lines[#lines + 1] = getText("IGUI_WaterPipesEmitterShort", formatHead(needed))
        elseif not status.reaches then
            -- There is water, and the figure could not be worked out. Nothing to say beyond the
            -- requirement itself.
            lines[#lines + 1] = getText("IGUI_WaterPipesEmitterLow", formatHead(status.minimum))
        else
            lines[#lines + 1] = getText("IGUI_WaterPipesEmitterWatering")
        end

        -- Only worth mentioning on a drip, and only while the line is genuinely over the limit.
        local burst = Irrigation.burstPressure()
        if Irrigation.isDrip(emitterObject) and burst and (head or 0) > burst then
            lines[#lines + 1] = getText("IGUI_WaterPipesEmitterBurstRisk", formatHead(burst))
        end
    end

    tooltip.description = table.concat(lines, " <LINE> ")
    return tooltip
end

-- What the hydrant will do if opened: mains-fed and bottomless while the town service runs, or the
-- finite local reserve once it is cut. Reminds the player a pipe on the tile is what connects it.
local function buildHydrantTooltip(hydrant)
    local tooltip = ISWorldObjectContextMenu.addToolTip()
    tooltip:setName(getText("ContextMenu_WaterPipesOpenHydrant"))
    local lines = {}
    if Hydrant.isMainsFed() then
        lines[#lines + 1] = getText("IGUI_WaterPipesHydrantMainsFed")
    else
        lines[#lines + 1] = getText("IGUI_WaterPipesHydrantReserve",
            string.format("%.0f", Hydrant.reserve(hydrant)))
    end
    lines[#lines + 1] = " "
    lines[#lines + 1] = getText("IGUI_WaterPipesHydrantNeedsPipe")
    tooltip.description = table.concat(lines, " <LINE> ")
    return tooltip
end

-- The ceiling is set in its own little dialog (slider plus a typed field) rather than a menu of fixed
-- steps: the useful values sit against real thresholds -- a drip bursts above 15.0, a sprinkler needs
-- 20.0 -- so the player has to land on an exact number, not the nearest five.
local function addRouterPressureMenu(context, playerObj, router)
    context:addOption(getText("ContextMenu_WaterPipesRouterPressureOpen"), playerObj,
        ContextMenu.openRouterPressure, router)
end

function ContextMenu.openRouterPressure(playerObj, router)
    if router and WaterPipesRouterPressureWindow then
        WaterPipesRouterPressureWindow.openFor(router)
    end
end

local function buildDripRepairTooltip(hasKit, hasWrench)
    local tooltip = ISWorldObjectContextMenu.addToolTip()
    tooltip:setName(getText("ContextMenu_WaterPipesRepairDrip"))
    local lines = { getText("IGUI_WaterPipesDripBurst"), " ", getText("Tooltip_WaterPipesRepairNeeds") }
    if not hasWrench then
        lines[#lines + 1] = "  1 x " .. (getItemNameFromFullType(Constants.PIPE_TOOL_TYPE) or "Pipe Wrench")
    end
    if not hasKit then
        for _, entry in ipairs(Constants.DRIP_REPAIR_ITEMS) do
            lines[#lines + 1] = describeRepairEntry(entry)
        end
    end
    tooltip.description = table.concat(lines, " <LINE> ")
    return tooltip
end

function ContextMenu.doMenu(player, context, worldobjects, test)
    if test and ISWorldObjectContextMenu.Test then
        return true
    end

    local playerObj = getSpecificPlayer(player)
    if not playerObj or playerObj:getVehicle() then
        return false
    end

    local clickedSquare = PipeObjectUtils.getSquareFromWorldObjects(worldobjects)
    if not clickedSquare then
        return false
    end

    local endpointObject = EndpointObjects.findInWorldObjects(worldobjects)
    -- Sinks normally connect through the VANILLA "Plumb" option (intercepted by onVanillaPlumbItem), which
    -- we do not duplicate. The engine hides it for fixtures that already use a water source, so when it is
    -- absent we add our own.
    local hasUnplumbOption = endpointObject
        and playerHasPipeWrench(playerObj)
        and EndpointPlumbing.canUnplumb(endpointObject)
    local hasModPlumbOption = endpointObject
        and playerHasPipeWrench(playerObj)
        and EndpointPlumbing.canPlumb(endpointObject)

    -- Generators are fuel consumers and have NO vanilla pipe option, so they use our own connect/
    -- disconnect options. A pipe on the generator's tile lets it draw Petrol from the network.
    local generatorObject = findGeneratorInWorldObjects(worldobjects)
    local hasGeneratorPlumbOption = generatorObject
        and playerHasPipeWrench(playerObj)
        and GeneratorFuel.canPlumb(generatorObject)
    local hasGeneratorUnplumbOption = generatorObject
        and playerHasPipeWrench(playerObj)
        and GeneratorFuel.canUnplumb(generatorObject)

    -- Network visualization: available on any pipe, no tool required (helps players + debugging).
    local pipeObject = findPipeInWorldObjects(worldobjects)
    local hasShowNetworkOption = pipeObject ~= nil
    local hasHideNetworkOption = #ContextMenu.highlightedObjects > 0

    -- Purifier: an "Open Purifier" option that pops the readout window (buffers / status / rate).
    local purifierObject = findPurifierInWorldObjects(worldobjects)
    local hasPurifierOption = purifierObject ~= nil

    -- Pressure devices. The router's regulator and the gauge only make sense while the model is on;
    -- with it off there is no pressure to cap or to read.
    local pressureOn = Pressure.isEnabled()
    local routerObject = pressureOn and findRouterInWorldObjects(worldobjects) or nil
    local hasRouterPressureOption = routerObject ~= nil and playerHasPipeWrench(playerObj)

    local gaugeObject = findGaugeInWorldObjects(worldobjects)
    local hasGaugeOption = gaugeObject ~= nil

    -- The pump's switch and readout stay available with the pressure model off, unlike the router
    -- regulator: the switch still stops the intake, and the readout still answers whether it has power.
    local pumpObject = findPumpInWorldObjects(worldobjects)
    local hasPumpOption = pumpObject ~= nil

    local dripObject = findDripInWorldObjects(worldobjects)
    local hasDripRepairOption = dripObject ~= nil and Irrigation.isDripBurst(dripObject)

    local emitterObject = findEmitterInWorldObjects(worldobjects)
    local hasEmitterOption = emitterObject ~= nil

    -- A street fire hydrant opens and closes with a pipe wrench; once open and piped it feeds the
    -- network. The option only shows with a wrench in hand.
    local hydrantObject = findHydrantInWorldObjects(worldobjects)
    local hasHydrantOption = hydrantObject ~= nil and playerHasPipeWrench(playerObj)

    if not hasUnplumbOption and not hasModPlumbOption
        and not hasGeneratorPlumbOption and not hasGeneratorUnplumbOption
        and not hasShowNetworkOption and not hasHideNetworkOption
        and not hasPurifierOption
        and not hasRouterPressureOption and not hasGaugeOption and not hasDripRepairOption
        and not hasEmitterOption and not hasHydrantOption and not hasPumpOption
        and not isDebugActive() then
        return false
    end

    if test then
        return ISWorldObjectContextMenu.setTest()
    end

    if hasUnplumbOption then
        addTopLevelUnplumbOption(context, playerObj, endpointObject)
    elseif hasModPlumbOption and not findVanillaPlumbOption(context) then
        -- Only add ours when the engine isn't already showing a Plumb option (avoid duplicates).
        addModPlumbOption(context, playerObj, endpointObject, worldobjects)
    end

    if hasGeneratorPlumbOption then
        local optionName = getText("ContextMenu_PlumbItem", getGeneratorDisplayName())
        applyPlumbOptionIcon(context:addOption(optionName, playerObj, ContextMenu.plumbGenerator, generatorObject))
    end

    if hasGeneratorUnplumbOption then
        local optionName = getText("ContextMenu_WaterPipesUnplumbItem", getGeneratorDisplayName())
        applyPlumbOptionIcon(context:addOption(optionName, playerObj, ContextMenu.unplumbGenerator, generatorObject))
    end

    if hasShowNetworkOption then
        context:addOption(getText("ContextMenu_WaterPipesShowNetwork"), playerObj, ContextMenu.showNetwork, pipeObject)
    end

    if hasHideNetworkOption then
        context:addOption(getText("ContextMenu_WaterPipesHideNetwork"), playerObj, ContextMenu.hideNetwork)
    end

    if hasPurifierOption then
        addPurifierOptions(context, playerObj, purifierObject)

        -- Ask the ANCHOR, not whichever of the 2x2 tiles happened to be clicked. The filter condition lives in
        -- the anchor's modData, so the other three read the default 100 -- and a worn filter offered no repair
        -- option from three quarters of the machine while the readout window showed 13%.
        local anchor = resolvePurifierAnchor(purifierObject) or purifierObject

        -- "Repair filter" appears only once the filter has worn below full. Enabled when the player
        -- carries a pipe wrench and the repair kit; otherwise shown disabled with a requirements tooltip.
        if Purifier.needsRepair(anchor) then
            local option = context:addOption(getText("ContextMenu_WaterPipesRepairFilter"),
                playerObj, ContextMenu.repairPurifier, anchor)
            local hasWrench = playerHasPipeWrench(playerObj)
            local hasKit = ISRepairWaterPurifier.hasRepairKit(playerObj:getInventory())
            if not hasWrench or not hasKit then
                option.notAvailable = true
                option.toolTip = buildRepairTooltip(anchor, hasKit, hasWrench)
            end
        end
    end

    if hasPumpOption then
        addPumpMenu(context, playerObj, pumpObject)
    end

    if hasRouterPressureOption then
        addRouterPressureMenu(context, playerObj, routerObject)
    end

    if hasHydrantOption then
        local open = Hydrant.isOpen(hydrantObject)
        local label = open and getText("ContextMenu_WaterPipesCloseHydrant")
            or getText("ContextMenu_WaterPipesOpenHydrant")
        local option = context:addOption(label, playerObj, ContextMenu.setHydrantOpen,
            hydrantObject, not open)
        option.toolTip = buildHydrantTooltip(hydrantObject)
    end

    if hasGaugeOption then
        local option = context:addOption(getText("ContextMenu_WaterPipesReadGauge"), playerObj, nil)
        option.notAvailable = true   -- a gauge is read, not operated: the tooltip IS the readout
        option.toolTip = buildGaugeTooltip(gaugeObject:getSquare())
    end

    if hasEmitterOption then
        local option = context:addOption(getText("ContextMenu_WaterPipesCheckEmitter"), playerObj, nil)
        option.notAvailable = true   -- like the gauge: this is a readout, the tooltip IS the answer
        option.toolTip = buildEmitterTooltip(emitterObject)
    end

    if hasDripRepairOption then
        local option = context:addOption(getText("ContextMenu_WaterPipesRepairDrip"),
            playerObj, ContextMenu.repairDrip, dripObject)
        local hasWrench = playerHasPipeWrench(playerObj)
        local hasKit = ISRepairWaterDrip.hasRepairKit(playerObj:getInventory())
        if not hasWrench or not hasKit then
            option.notAvailable = true
            option.toolTip = buildDripRepairTooltip(hasKit, hasWrench)
        end
    end

    if isDebugActive() then
        addDebugRootMenu(context, playerObj, endpointObject, clickedSquare)
    end
end

Events.OnFillWorldObjectContextMenu.Add(ContextMenu.doMenu)
ISWorldObjectContextMenu.onPlumbItem = ContextMenu.onVanillaPlumbItem

if Events and Events.OnServerCommand then
    Events.OnServerCommand.Add(onServerCommand)
end
