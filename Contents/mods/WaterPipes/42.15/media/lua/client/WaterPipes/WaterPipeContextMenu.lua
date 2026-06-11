require "ISUI/ISWorldObjectContextMenu"
require "WaterPipes/Constants"
require "WaterPipes/EndpointObjects"
require "WaterPipes/EndpointPlumbing"
require "WaterPipes/ISPlumbWaterPipeEndpoint"
require "WaterPipes/ISPlumbWaterPipeGenerator"
require "WaterPipes/GeneratorFuel"
require "WaterPipes/PipeObjectUtils"
require "WaterPipes/NetworkAccess"
require "WaterPipes/Logger"
-- Client-side: loads PipeAutotile so it registers its OnObjectAdded/LoadGridsquare hooks and each
-- client recomputes pipe connection sprites locally (the shape is never sent over the network).
require "WaterPipes/PipeAutotile"

WaterPipes = WaterPipes or {}
WaterPipes.ContextMenu = WaterPipes.ContextMenu or {}

local Constants = WaterPipes.Constants
local EndpointObjects = WaterPipes.EndpointObjects
local EndpointPlumbing = WaterPipes.EndpointPlumbing
local GeneratorFuel = WaterPipes.GeneratorFuel
local Logger = WaterPipes.Logger
local NetworkAccess = WaterPipes.NetworkAccess
local PipeObjectUtils = WaterPipes.PipeObjectUtils
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
local HIGHLIGHT_TICKS = 480 -- ~8s at 60fps; auto-clears the highlight
local COLOR_PIPE = { r = 0.95, g = 0.20, b = 0.20, a = 1.0 }      -- red
local COLOR_SOURCE = { r = 0.20, g = 0.95, b = 0.30, a = 1.0 }    -- green: provides fluid
local COLOR_CONSUMER = { r = 0.30, g = 0.60, b = 1.00, a = 1.0 }  -- blue: draws fluid (out-network)

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

    -- Pipes (red).
    for _, sq in ipairs(pipeSquares or {}) do
        for _, pipe in ipairs(PipeObjectUtils.getPipeObjectsOnSquare(sq)) do
            trackAndHighlight(pipe, playerNum, COLOR_PIPE)
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

local function addDebugMenu(context, subMenu, playerObj, endpointObject)
    if not isDebugActive() then
        return
    end

    local debugOption = subMenu:addOption("Debug", nil, nil)
    local debugSubMenu = ISContextMenu:getNew(context)
    subMenu:addSubMenu(debugOption, debugSubMenu)

    debugSubMenu:addOption("Force Global Water Shutoff", playerObj, ContextMenu.forceGlobalWaterShutoff)
    debugSubMenu:addOption("Force Network Tick", playerObj, ContextMenu.forceNetworkTick)
    if endpointObject then
        debugSubMenu:addOption("Dump Plumbing Diagnostics", playerObj, ContextMenu.dumpPlumbingDiagnostics, endpointObject)
        debugSubMenu:addOption("Dump Adapter Diagnostics", playerObj, ContextMenu.dumpAdapterDiagnostics, endpointObject)
    end
end

local function addDebugRootMenu(context, playerObj, endpointObject)
    local rootOption = context:addOption(ContextMenu.DEBUG_ROOT_NAME, nil, nil)
    local subMenu = context:getNew(context)
    context:addSubMenu(rootOption, subMenu)
    addDebugMenu(context, subMenu, playerObj, endpointObject)
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

function ContextMenu.doMenu(player, context, worldobjects, test)
    if test and ISWorldObjectContextMenu.Test then
        return true
    end

    local playerObj = getSpecificPlayer(player)
    if not playerObj or playerObj:getVehicle() then
        return false
    end

    if not PipeObjectUtils.getSquareFromWorldObjects(worldobjects) then
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
    local pipeObject = findPipeInWorldObjects(worldobjects)
    local hasShowNetworkOption = pipeObject ~= nil
    local hasHideNetworkOption = #ContextMenu.highlightedObjects > 0

    if not hasUnplumbOption and not hasModPlumbOption
        and not hasGeneratorPlumbOption and not hasGeneratorUnplumbOption
        and not hasShowNetworkOption and not hasHideNetworkOption
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

    if isDebugActive() then
        addDebugRootMenu(context, playerObj, endpointObject)
    end
end

Events.OnFillWorldObjectContextMenu.Add(ContextMenu.doMenu)
ISWorldObjectContextMenu.onPlumbItem = ContextMenu.onVanillaPlumbItem

if Events and Events.OnServerCommand then
    Events.OnServerCommand.Add(onServerCommand)
end
