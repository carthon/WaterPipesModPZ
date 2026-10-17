-- Project Viewpoint support lives in the optional add-on mod "Water Pipes - Viewpoint"
-- (Contents/mods/WaterPipesViewpoint), so its models and their .glb load only for the players who use it.
-- These are the hooks SprayFX calls; without the add-on they report no 3D view and do nothing. The
-- add-on replaces them (ViewpointCompat.lua).
--
-- The add-on's spray objects are client-only, but a single player save can catch one (teleport, crash):
-- any found when its tile loads is stripped here, with or without the add-on, since vanilla would draw
-- its model in iso.

require "WaterPipes/PipeObjectUtils"

WaterPipes = WaterPipes or {}
WaterPipes.Viewpoint = WaterPipes.Viewpoint or {}

local PipeObjectUtils = WaterPipes.PipeObjectUtils
local VP = WaterPipes.Viewpoint

VP.SPRAY_SPRITE = "waterpipes_01_107"      -- transparent, no properties: the spray objects' tile
VP.SPRAY_MODEL = "WaterPipes.SprinklerSpray"   -- spriteModel SprinklerSpray0..3 (the add-on's script)
VP.SPRAY_VARIANTS = 4

function VP.is3D() return false end
function VP.animatedSpray() return false end
function VP.showSpray() end
function VP.syncSprays() end
function VP.clearSprays() end
-- The add-on drops its own reference to a spray object stripped here.
function VP.forgetSpray() end

-- The spray's sprite models, or an empty list without the add-on (its script is not loaded then, so a
-- stray carries no model and draws nothing).
local sprayModels = nil

local function isSprayModel(model)
    if model == nil then
        return false
    end
    if sprayModels == nil then
        sprayModels = {}
        local manager = getScriptManager and getScriptManager() or nil
        for k = 0, VP.SPRAY_VARIANTS - 1 do
            local found = manager and manager:getSpriteModel(VP.SPRAY_MODEL .. k) or nil
            if found then
                sprayModels[#sprayModels + 1] = found
            end
        end
    end
    for _, known in ipairs(sprayModels) do
        if known == model then
            return true
        end
    end
    return false
end

-- A spray object: its sprite is unnamed once saved, so it is told by its model.
local function isStraySpray(obj)
    local sprite = obj:getSprite()
    if sprite and sprite:getName() == VP.SPRAY_SPRITE then
        return true
    end
    return obj.getSpriteModel ~= nil and isSprayModel(obj:getSpriteModel())
end

local strayCheck = {}
local savesWorld = nil   -- single player: the only game whose save a client-only object can reach

local function onLoadGridsquare(square)
    if savesWorld == nil then
        savesWorld = not isClient() and not isServer()
    end
    -- only a tile that can hold a sprinkler
    if savesWorld and square and PipeObjectUtils.squareMayHavePipe(square) then
        strayCheck[#strayCheck + 1] = square
    end
end

local function stripStrays()
    if #strayCheck == 0 then
        return
    end
    local list = strayCheck
    strayCheck = {}
    for _, square in ipairs(list) do
        local objects = square:getObjects()
        for i = objects:size() - 1, 0, -1 do
            local obj = objects:get(i)
            if obj and isStraySpray(obj) then
                VP.forgetSpray(obj)
                square:RemoveTileObject(obj, false)
            end
        end
    end
end

Events.OnTick.Add(stripStrays)
Events.LoadGridsquare.Add(onLoadGridsquare)
