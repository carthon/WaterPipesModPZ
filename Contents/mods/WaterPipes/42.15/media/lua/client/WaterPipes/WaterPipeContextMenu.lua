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
require "WaterPipes/WaterPipesPurifierSound"
require "WaterPipes/ISRepairWaterPurifier"
require "WaterPipes/ISOpenWaterPurifier"

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

-- The square the player actually right-clicked, taken from the menu's own click position rather than
-- the live mouse. ISContextMenu.get stores those coords as requestX/requestY; .x/.y drift once the
-- menu slides into place, so they are only a fallback.
local function squareFromClick(player, context)
    if not context or not screenToIsoX or not screenToIsoY or not getCell then
        return nil
    end
    local character = getSpecificPlayer(player)
    if not character then
        return nil
    end
    local cx = context.requestX or context.x
    local cy = context.requestY or context.y
    if not cx or not cy then
        return nil
    end
    local z = character:getZ()
    local ok, square = pcall(function()
        return getCell():getGridSquare(math.floor(screenToIsoX(player, cx, cy, z)),
                                       math.floor(screenToIsoY(player, cx, cy, z)), z)
    end)
    return ok and square or nil
end

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

-- The purifier is a 2x2 tank whose modData lives only on the ANCHOR (min-corner / back) tile, but the
-- player will often right-click the visible body (a non-anchor tile). The footprint extends +x/+y from
-- the anchor, so from any of the four tiles the anchor sits within the 2x2 block up-and-left of it --
-- scan that block so "Open Purifier" shows from anywhere on the tank.
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

-- Open the purifier readout window (buffers, running status, filtering rate).
function ContextMenu.openPurifier(playerObj, purifierObject)
    if not purifierObject or not WaterPipesPurifierWindow then
        return
    end
    -- Resolve the router/anchor tile of the purifier's 2x2 footprint so the window reads the SAME buffers
    -- the server processes on that tile (findForRouterSquare). The footprint extends +x/+y from the anchor
    -- (which carries the router), so from any tank tile the anchor is this tile or up-and-left of it.
    local anchorSquare = nil
    local sq = purifierObject.getSquare and purifierObject:getSquare() or nil
    local cell = getCell and getCell() or nil
    if sq then
        for _, off in ipairs({ { 0, 0 }, { -1, 0 }, { 0, -1 }, { -1, -1 } }) do
            local nsq = sq
            if off[1] ~= 0 or off[2] ~= 0 then
                nsq = cell and cell:getGridSquare(sq:getX() + off[1], sq:getY() + off[2], sq:getZ())
            end
            if nsq and Router.hasRouterOnSquare(nsq) and Purifier.findForRouterSquare(nsq) then
                anchorSquare = nsq
                break
            end
        end
    end

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

-- Debug pressure readout. Unlike the gauge, this works on ANY square -- no fixture, no pipe needed --
-- and shows every term that produced the number rather than just the number, so a wrong reading can
-- be traced to the source, hop count, pump or router ceiling behind it. Debug strings stay English,
-- like the rest of this menu.
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

    add(" ")
    add("Head by consumer (best source, after ceiling):")
    for _, kind in ipairs({ Constants.PRESSURE_KIND_TAP, Constants.PRESSURE_KIND_DRIP,
        Constants.PRESSURE_KIND_SPRINKLER }) do
        local entry = report.kinds[kind]
        if entry then
            add("  %-9s %6.2f  (needs %.1f, friction %.3f/tile)  %s",
                kind, entry.head or 0, entry.minimum, entry.friction,
                entry.ok and "OK" or "NOT ENOUGH")
        end
    end

    add(" ")
    add("Sources (head delivered here at tap flow):")
    if #report.sources == 0 then
        add("  none")
    end
    for _, source in ipairs(report.sources) do
        -- A source reached through a regulator shows the ceiling that capped it, so a surprising
        -- head can be traced to the router responsible.
        add("  z=%d hops=%d  %.1f/%.1f %s  %s->  %6.2f",
            source.z or 0, source.hops or 0, source.amount or 0, source.capacity or 0,
            tostring(source.fluidType),
            source.ceiling and string.format("[cap %.1f] ", source.ceiling) or "",
            source.head or 0)
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

-- Sinks: connecting uses the VANILLA "Plumb <name>" option (intercepted by onVanillaPlumbItem so
-- it joins our network). Once plumbed, the engine often KEEPS showing that "Plumb" option, so we
-- turn it in-place into our "Unplumb <name>" (no add/remove -> no menu glitches). If the engine
-- shows none, we add our own Unplumb (vanilla provides no unplumb).
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
    end
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
            local name = getItemNameFromFullType(entry.type) or entry.type
            lines[#lines + 1] = "  " .. (entry.count or 1) .. " x " .. name
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

-- The gauge is a readout, not a machine: everything it knows fits in a tooltip, so it needs no
-- window of its own. Pressure is otherwise an invisible number -- this is where the player sees it.
--
-- It reports the pressure and nothing else. It used to also advise on sprinklers and drip emitters,
-- but a gauge cannot know what is downstream of it: it read the pressure on ITS tile and then talked
-- about crops that might be twenty tiles and a regulator away. Emitters answer for themselves now --
-- see buildEmitterTooltip.
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

-- Emitters diagnose themselves. The pressure that decides whether a drip or a sprinkler runs is the
-- pressure ON ITS OWN TILE at ITS OWN flow rate -- a sprinkler loses head four times faster than a
-- tap, so a gauge reading taken elsewhere never answered the question the player was actually asking.
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
        lines[#lines + 1] = status.pressure
            and getText("IGUI_WaterPipesEmitterPressure", formatHead(status.pressure))
            or getText("IGUI_WaterPipesEmitterNoSupply")

        if not status.reaches then
            lines[#lines + 1] = getText("IGUI_WaterPipesEmitterLow", formatHead(status.minimum))
        elseif not status.hasWater then
            -- Pressure is fine, the pipes are simply empty. Different problem, different fix.
            lines[#lines + 1] = getText("IGUI_WaterPipesEmitterDry")
        else
            lines[#lines + 1] = getText("IGUI_WaterPipesEmitterWatering")
        end

        -- Only worth mentioning on a drip, and only while the line is genuinely over the limit.
        local burst = Irrigation.burstPressure()
        if Irrigation.isDrip(emitterObject) and burst and (status.pressure or 0) > burst then
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

-- The ceiling is set in its own little dialog (slider plus a typed field) rather than a menu of
-- fixed steps: the useful values sit against real thresholds -- a drip emitter bursts above 15.0,
-- a sprinkler needs 20.0 -- so the player needs to land on an exact number, not the nearest five.
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
            lines[#lines + 1] = "  " .. (entry.count or 1) .. " x "
                .. (getItemNameFromFullType(entry.type) or entry.type)
        end
    end
    tooltip.description = table.concat(lines, " <LINE> ")
    return tooltip
end

-- A concealed pipe renders as the empty tile, so the engine picks nothing on that square -- and
-- createMenu RETURNS on `fetch.c == 0` before it ever fires OnFillWorldObjectContextMenu. The menu
-- below therefore never ran on a concealed pipe, which is why "Show pipe network" only appeared once
-- the pipe was already revealed. OnPreFillWorldObjectContextMenu fires BEFORE that bail, and the
-- context is already visible by then (ISContextMenu.get shows it), so options added here do appear.
--
-- It owns the network options outright rather than deferring to the main menu when a pipe looks
-- reachable: whether the main menu runs at all depends on the engine's own fetch count, which we
-- cannot see from here. Adding them here unconditionally and flagging it is the only ordering that
-- works in both cases; the main menu below skips them when the flag is set.
local preAddedNetworkOptions = false

function ContextMenu.doPreMenu(player, context, worldobjects, test)
    preAddedNetworkOptions = false
    if test then
        return
    end
    local playerObj = getSpecificPlayer(player)
    if not playerObj or playerObj:getVehicle() then
        return
    end

    local clicked = squareFromClick(player, context)
    local pipe = findPipeInWorldObjects(worldobjects)
        or PipeObjectUtils.getPipeOnSquare(clicked)

    if getDebug and getDebug() then
        print(string.format(
            "[WaterPipes menu] worldobjects=%d  clickedSquare=%s  pipeFound=%s",
            worldobjects and #worldobjects or -1,
            clicked and (clicked:getX() .. "," .. clicked:getY() .. "," .. clicked:getZ()) or "nil",
            tostring(pipe ~= nil)))
    end

    if not pipe then
        return
    end

    context:addOption(getText("ContextMenu_WaterPipesShowNetwork"), playerObj, ContextMenu.showNetwork, pipe)
    if #ContextMenu.highlightedObjects > 0 then
        context:addOption(getText("ContextMenu_WaterPipesHideNetwork"), playerObj, ContextMenu.hideNetwork)
    end
    preAddedNetworkOptions = true
end

function ContextMenu.doMenu(player, context, worldobjects, test)
    if test and ISWorldObjectContextMenu.Test then
        return true
    end

    local playerObj = getSpecificPlayer(player)
    if not playerObj or playerObj:getVehicle() then
        return false
    end

    -- Fall back to the clicked square: a tile holding only a concealed pipe gives the engine nothing
    -- to pick, so worldobjects arrives empty and we would bail before ever looking for the pipe.
    local clickedSquare = PipeObjectUtils.getSquareFromWorldObjects(worldobjects)
        or squareFromClick(player, context)
    if not clickedSquare then
        return false
    end

    local endpointObject = EndpointObjects.findInWorldObjects(worldobjects)
    -- Sinks/fixtures: connecting normally uses the VANILLA "Plumb" option (intercepted by
    -- onVanillaPlumbItem so it joins our network). We don't duplicate it. But the engine hides that
    -- option for fixtures that already use a water source (or have no vanilla source in the room),
    -- so when it's absent we add our OWN "Plumb" so any piped fixture can still be connected.
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
    -- Concealed pipes are invisible and never reach worldobjects, so fall back to the clicked square
    -- -- otherwise the one pipe you most need the network view for is the one you cannot ask.
    local pipeObject = findPipeInWorldObjects(worldobjects)
        or PipeObjectUtils.getPipeOnSquare(clickedSquare)
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
        and not hasEmitterOption and not hasHydrantOption
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

    if hasShowNetworkOption and not preAddedNetworkOptions then
        context:addOption(getText("ContextMenu_WaterPipesShowNetwork"), playerObj, ContextMenu.showNetwork, pipeObject)
    end

    if hasHideNetworkOption and not preAddedNetworkOptions then
        context:addOption(getText("ContextMenu_WaterPipesHideNetwork"), playerObj, ContextMenu.hideNetwork)
    end

    if hasPurifierOption then
        addPurifierOptions(context, playerObj, purifierObject)

        -- "Repair filter" appears only once the filter has worn below full. Enabled when the player
        -- carries a pipe wrench and the repair kit; otherwise shown disabled with a requirements tooltip.
        if Purifier.needsRepair(purifierObject) then
            local option = context:addOption(getText("ContextMenu_WaterPipesRepairFilter"),
                playerObj, ContextMenu.repairPurifier, purifierObject)
            local hasWrench = playerHasPipeWrench(playerObj)
            local hasKit = ISRepairWaterPurifier.hasRepairKit(playerObj:getInventory())
            if not hasWrench or not hasKit then
                option.notAvailable = true
                option.toolTip = buildRepairTooltip(purifierObject, hasKit, hasWrench)
            end
        end
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

-- Pre-fill runs first and is the only one that fires on a tile the engine picked nothing on. Guarded
-- because losing this whole file to a missing event would take every option in the mod with it.
if Events.OnPreFillWorldObjectContextMenu then
    Events.OnPreFillWorldObjectContextMenu.Add(ContextMenu.doPreMenu)
end
Events.OnFillWorldObjectContextMenu.Add(ContextMenu.doMenu)
ISWorldObjectContextMenu.onPlumbItem = ContextMenu.onVanillaPlumbItem

if Events and Events.OnServerCommand then
    Events.OnServerCommand.Add(onServerCommand)
end
