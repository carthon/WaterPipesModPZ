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

function VP.is3D() return false end
function VP.animatedSpray() return false end
function VP.showSpray() end
function VP.syncSprays() end
function VP.clearSprays() end
-- The add-on drops its own reference to a spray object stripped here.
function VP.forgetSpray() end

local strayCheck = {}

local function onLoadGridsquare(square)
    -- only a game that saves the world, and only a tile that can hold a sprinkler
    if not isClient() and square and PipeObjectUtils.squareMayHavePipe(square) then
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
            local sprite = obj and obj:getSprite()
            if sprite and sprite:getName() == VP.SPRAY_SPRITE then
                VP.forgetSpray(obj)
                square:RemoveTileObject(obj, false)
            end
        end
    end
end

Events.OnTick.Add(stripStrays)
Events.LoadGridsquare.Add(onLoadGridsquare)
