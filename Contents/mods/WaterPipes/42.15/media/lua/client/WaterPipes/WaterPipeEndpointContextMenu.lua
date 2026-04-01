require "ISUI/ISWorldObjectContextMenu"
require "ISUI/ISContextMenu"
require "Fluids/ISFluidContainer"
require "Fluids/ISFluidInfoUI"
require "Fluids/ISFluidPanelAction"
require "WaterPipes/EndpointAdapterSource"

local AdapterSource = WaterPipes.EndpointAdapterSource
local ClientHooks = WaterPipes.ClientHooks or {}
local queueActions = ISTimedActionQueue and ISTimedActionQueue.queueActions or nil

WaterPipes.ClientHooks = ClientHooks
ClientHooks.originalCreateMenu = ClientHooks.originalCreateMenu or ISWorldObjectContextMenu.createMenu
ClientHooks.originalOnFluidInfo = ClientHooks.originalOnFluidInfo or ISWorldObjectContextMenu.onFluidInfo

local function filterAdapterWorldObjects(worldobjects)
    if not worldobjects then
        return worldobjects
    end

    local filtered = {}
    for _, worldObject in ipairs(worldobjects) do
        if not AdapterSource.isAdapterObject(worldObject) then
            filtered[#filtered + 1] = worldObject
        end
    end

    return filtered
end

local function isAdapterSquareContext(worldobjects)
    if not worldobjects then
        return false
    end

    for _, worldObject in ipairs(worldobjects) do
        local square = worldObject and worldObject.getSquare and worldObject:getSquare() or nil
        if square and AdapterSource.squareHasAdapter(square) then
            return true
        end
    end

    return false
end

local function getOptionArg(option, index)
    if not option or type(index) ~= "number" or index < 1 then
        return nil
    end

    local offset = 0
    if option.onSelect == ISContextMenu.onGetUpAndThen or option.onSelect == queueActions then
        offset = 1
    end

    return option["param" .. tostring(index + offset)]
end

local function valueContainsAdapterReference(value, depth)
    if not value or depth > 2 then
        return false
    end

    local valueType = type(value)
    if valueType ~= "table" and valueType ~= "userdata" then
        return false
    end

    if AdapterSource.isAdapterObject(value) then
        return true
    end

    if value.getGameEntity then
        local ok, entity = pcall(value.getGameEntity, value)
        if ok and entity and AdapterSource.isAdapterObject(entity) then
            return true
        end
    end

    if value.getOwner then
        local ok, owner = pcall(value.getOwner, value)
        if ok and owner and AdapterSource.isAdapterObject(owner) then
            return true
        end
    end

    if valueType == "table" then
        for _, nested in ipairs(value) do
            if valueContainsAdapterReference(nested, depth + 1) then
                return true
            end
        end
    end

    return false
end

local function optionTargetsAdapterSource(option)
    if not option then
        return false
    end

    if valueContainsAdapterReference(option.target, 0) then
        return true
    end

    for index = 1, 10 do
        if valueContainsAdapterReference(getOptionArg(option, index), 0) then
            return true
        end
    end

    return false
end

local function pruneAdapterEntriesFromMenu(menu)
    if not menu or not menu.options then
        return
    end

    for index = #menu.options, 1, -1 do
        local option = menu.options[index]
        local subMenu = option and option.subOption and menu:getSubMenu(option.subOption) or nil
        if subMenu then
            pruneAdapterEntriesFromMenu(subMenu)
            if not subMenu.options or #subMenu.options == 0 then
                table.remove(menu.options, index)
                menu.numOptions = math.max(menu.numOptions - 1, 1)
            end
        elseif optionTargetsAdapterSource(option) then
            table.remove(menu.options, index)
            menu.numOptions = math.max(menu.numOptions - 1, 1)
        end
    end

    for index, option in ipairs(menu.options) do
        option.id = index
    end

    menu:calcHeight()
    menu:setWidth(menu:calcWidth())
end

local function pruneAdapterWaterMenus(context)
    if not context or not context.options then
        return
    end
    pruneAdapterEntriesFromMenu(context)
end

ISWorldObjectContextMenu.createMenu = function(player, worldobjects, x, y, test)
    local adapterSquareContext = isAdapterSquareContext(worldobjects)
    if adapterSquareContext then
        worldobjects = filterAdapterWorldObjects(worldobjects)
    end

    local context = ClientHooks.originalCreateMenu(player, worldobjects, x, y, test)
    if adapterSquareContext then
        pruneAdapterWaterMenus(context)
    end
    return context
end

ISWorldObjectContextMenu.onFluidInfo = function(player, fluidcontainer)
    local entity = fluidcontainer and fluidcontainer.getGameEntity and fluidcontainer:getGameEntity() or nil
    if entity and AdapterSource.isAdapterObject(entity) then
        return
    end

    if entity and instanceof(entity, "IsoObject") then
        local playerObj = getSpecificPlayer(player)
        if luautils.walkAdjObject(playerObj, entity, true) then
            local container = ISFluidContainer:new(fluidcontainer)
            ISTimedActionQueue.add(ISFluidPanelAction:new(playerObj, container, ISFluidInfoUI))
        end
        return
    end

    return ClientHooks.originalOnFluidInfo(player, fluidcontainer)
end
