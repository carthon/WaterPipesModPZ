require "Entity/ISUI/BuildRecipe/ISBuildPanel"
require "WaterPipes/Constants"
require "WaterPipes/ISWaterPipe"

WaterPipes = WaterPipes or {}
WaterPipes.BuildMenu = WaterPipes.BuildMenu or {}

local BuildMenu = WaterPipes.BuildMenu
local Constants = WaterPipes.Constants

BuildMenu.ENTITY_NAME = Constants.PIPE_BUILD_ENTITY_NAME
BuildMenu.ENTITY_FULL_NAME = Constants.PIPE_BUILD_ENTITY_FULL_NAME

local function getPlayerObject(player)
    if not player then
        return nil
    end

    if type(player) == "number" then
        return getSpecificPlayer(player)
    end

    return player
end

local function getInventory(player)
    local playerObj = getPlayerObject(player)
    return playerObj and playerObj:getInventory() or nil
end

local function hasPipeTool(player)
    local inventory = getInventory(player)
    return inventory and inventory:containsTypeRecurse(Constants.PIPE_TOOL_TYPE) or false
end

local function hasPipeItem(player)
    local inventory = getInventory(player)
    return inventory and inventory:containsTypeRecurse(Constants.PIPE_ITEM_TYPE) or false
end

local function canBuildPipe(player)
    return hasPipeTool(player) and hasPipeItem(player)
end

local function getSelectedBuildObject(buildPanel)
    if not buildPanel or not buildPanel.logic or not buildPanel.logic.getSelectedBuildObject then
        return nil
    end

    return buildPanel.logic:getSelectedBuildObject()
end

local function getScriptName(objectInfo)
    local script = objectInfo and objectInfo.getScript and objectInfo:getScript() or nil
    if not script or not script.getName then
        return nil
    end

    return script:getName()
end

local function isPipeBuildObject(objectInfo)
    if not objectInfo then
        return false
    end

    local objectName = objectInfo.getName and objectInfo:getName() or nil
    local scriptName = getScriptName(objectInfo)

    return objectName == BuildMenu.ENTITY_NAME
        or scriptName == BuildMenu.ENTITY_NAME
        or scriptName == BuildMenu.ENTITY_FULL_NAME
end

local function createOrRefreshPipeCursor(buildPanel, dontSetDrag)
    local playerObj = buildPanel and buildPanel.player or nil
    if not playerObj then
        return
    end

    local selectedBuildObject = getSelectedBuildObject(buildPanel)
    local needsNewCursor = buildPanel.buildEntity == nil
        or not buildPanel.buildEntity.isWaterPipeBuildCursor
        or buildPanel.buildEntity.objectInfo ~= selectedBuildObject

    if needsNewCursor then
        local pipeCursor = WaterPipes.ISWaterPipe:new()
        pipeCursor.player = playerObj:getPlayerNum()
        pipeCursor.character = playerObj
        pipeCursor.objectInfo = selectedBuildObject
        pipeCursor.isWaterPipeBuildCursor = true
        buildPanel.buildEntity = pipeCursor
    end

    buildPanel.buildEntity.blockBuild = not canBuildPipe(playerObj)

    if not dontSetDrag then
        getCell():setDrag(buildPanel.buildEntity, playerObj:getPlayerNum())
    end
end

BuildMenu.originalCreateBuildIsoEntity = BuildMenu.originalCreateBuildIsoEntity or ISBuildPanel.createBuildIsoEntity

function ISBuildPanel:createBuildIsoEntity(dontSetDrag)
    local objectInfo = getSelectedBuildObject(self)
    if isPipeBuildObject(objectInfo) then
        createOrRefreshPipeCursor(self, dontSetDrag)
        return
    end

    if self.buildEntity and self.buildEntity.isWaterPipeBuildCursor then
        self.buildEntity = nil
    end

    if BuildMenu.originalCreateBuildIsoEntity then
        return BuildMenu.originalCreateBuildIsoEntity(self, dontSetDrag)
    end
end
