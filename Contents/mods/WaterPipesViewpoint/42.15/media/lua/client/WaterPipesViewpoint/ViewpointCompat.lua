-- Water Pipes in Project Viewpoint's 3D view. Fills in the hooks Water Pipes leaves empty
-- (WaterPipes/WaterPipesViewpoint.lua): the model pack in common/media/viewpoint draws the pieces, and
-- watering sprinklers get an animated spray (a vanilla SpriteModel, scripts/WaterPipesViewpoint_Spray.txt).
-- Viewpoint's isometric view and players without Viewpoint keep the sprites and the UI-layer spray.

require "WaterPipes/Constants"
require "WaterPipes/Logger"
require "WaterPipes/WaterPipesViewpoint"

local Constants = WaterPipes.Constants
local Logger = WaterPipes.Logger
local VP = WaterPipes.Viewpoint

local MOD_ID = "waterpipesviewpoint"
local MANIFEST = "media/viewpoint/waterpipes.properties"

local registered = false

local function register()
    if registered or not (Viewpoint and Viewpoint.ModelPacks) then
        return
    end
    registered = Viewpoint.ModelPacks.register(MOD_ID, MANIFEST) == true
    if registered then
        Logger.log("Viewpoint model pack registered")
    else
        Logger.warn("Viewpoint model pack not registered: " .. MANIFEST)
    end
end

-- True while Viewpoint draws the world in 3D (first or third person). View.next() names the view a
-- cycle would switch to: "first" only from its isometric view.
function VP.is3D()
    local view = registered and Viewpoint.View or nil
    return view ~= nil and type(view.next) == "function" and view.next() ~= "first"
end

local SPRAY = Constants.SPRINKLER_SPRAY_SPRITES
local HEAD = {}
for head, spray in pairs(SPRAY) do
    HEAD[spray] = head
end

-- Swap a sprinkler's head between idle and watering (the still spray, when the animated one is missing).
-- Local only, never transmitted: the watering head looks the same in iso.
local swapped = {}                             -- object -> true while it shows the watering head

function VP.showSpray(object, on)
    if not registered then
        return
    end
    local overlay = object and object.getOverlaySprite and object:getOverlaySprite() or nil
    local name = overlay and overlay:getName() or nil
    local wanted = name and (on and SPRAY[name] or (not on and HEAD[name])) or nil
    if wanted then
        object:setOverlaySprite(wanted, false)
        swapped[object] = on or nil
    end
end

-- Every watering head back to the idle one: a save must not keep the swap.
local function restoreHeads()
    for object in pairs(swapped) do
        local overlay = object.getOverlaySprite and object:getOverlaySprite() or nil
        local head = overlay and HEAD[overlay:getName()] or nil
        if head then
            object:setOverlaySprite(head, false)
        end
    end
    swapped = {}
end

-- ===== Animated spray (vanilla SpriteModel, 3D view only) =====
-- A client-only object on a watering sprinkler's tile carries SprinklerSpray<k>: AddTileObject and
-- RemoveTileObject(obj, false) stay on this client and fire no OnObjectAdded, the server never knows it.
-- Kept LAST on its square so server-indexed objects keep the server's indices.

local SPRAY_MODEL = VP.SPRAY_MODEL
local VARIANTS = VP.SPRAY_VARIANTS             -- turned 0/90/180/270 and phase-shifted
local LOOP_FRAMES = 24                         -- keys in the Spray clip, 1 s
local MS_PER_FRAME = 1000 / LOOP_FRAMES

local sprays = {}                              -- "x,y,z" -> object
local count = 0
local models = nil                             -- SpriteModel per variant, or false when missing
local lastFrame = -1

local function variants()
    if models == nil then
        local manager = getScriptManager and getScriptManager() or nil
        local lookup = manager and manager.getSpriteModel or nil
        local found = {}
        for k = 0, VARIANTS - 1 do
            local model = lookup and lookup(manager, SPRAY_MODEL .. k) or nil
            found[k] = model and model.setAnimationTime and model or nil
            if not found[k] then
                found = false
                Logger.warn("Viewpoint: " .. SPRAY_MODEL .. k .. " missing, sprinklers use the still spray")
                break
            end
        end
        models = found
    end
    return models or nil
end

-- Single player only. On an MP client a local object on a server tile would sit among the objects the
-- server counts by index; the still spray only swaps the head and adds nothing.
function VP.animatedSpray()
    return registered and not isClient() and variants() ~= nil
end

local function keyOf(x, y, z)
    return x .. "," .. y .. "," .. z
end

local function removeSpray(key)
    local obj = sprays[key]
    sprays[key] = nil
    count = count - 1
    local square = obj and obj:getSquare() or nil
    if square then
        square:RemoveTileObject(obj, false)
    end
end

local function addSpray(square, key)
    local x, y = square:getX(), square:getY()
    local obj = IsoObject.new(square, VP.SPRAY_SPRITE)
    obj:setSpriteModelName(SPRAY_MODEL .. ((x * 7 + y * 13) % VARIANTS))
    obj:setAnimating(true)
    square:AddTileObject(obj)
    sprays[key] = obj
    count = count + 1
end

-- `watering`: { {square = ..., x, y, z}, ... } -- the sprinklers that should spray now (empty to clear).
function VP.syncSprays(watering)
    local wanted = {}
    for _, entry in ipairs(watering) do
        wanted[keyOf(entry.x, entry.y, entry.z)] = entry.square
    end
    for key in pairs(sprays) do
        if not wanted[key] then
            removeSpray(key)
        end
    end
    for key, square in pairs(wanted) do
        if not sprays[key] then
            addSpray(square, key)
        end
    end
end

function VP.clearSprays()
    for key in pairs(sprays) do
        removeSpray(key)
    end
end

function VP.forgetSpray(obj)
    for key, tracked in pairs(sprays) do
        if tracked == obj then
            sprays[key] = nil
            count = count - 1
            return
        end
    end
end

-- The game samples the clip only on its keys: one shared time per variant, quarter loop apart.
local function onTick()
    if count == 0 then
        return
    end
    if not VP.is3D() then
        VP.clearSprays()          -- back in iso: the vanilla renderer would draw the model
        return
    end
    -- folded first: Kahlua's % breaks on epoch milliseconds (see SprayFX.animationFrame)
    local ms = getTimestampMs()
    local frame = math.floor((ms - math.floor(ms / 1048576) * 1048576) / MS_PER_FRAME) % LOOP_FRAMES
    if frame == lastFrame then
        return
    end
    lastFrame = frame
    for k, model in pairs(variants() or {}) do
        model:setAnimationTime(((frame + k * LOOP_FRAMES / VARIANTS) % LOOP_FRAMES) / LOOP_FRAMES)
    end
end

-- A server add lands at the server's index, in front of ours; anything else appended after it would
-- shift the indices the server uses for that square.
local function onObjectAdded(object)
    local square = count > 0 and object and object:getSquare() or nil
    local obj = square and sprays[keyOf(square:getX(), square:getY(), square:getZ())] or nil
    if not obj or obj == object then
        return
    end
    local objects = square:getObjects()
    if objects:get(objects:size() - 1) ~= obj then
        square:RemoveTileObject(obj, false)
        square:AddTileObject(obj)
    end
end

-- ===== Build previews (Viewpoint Placement Fix) =====
-- The build cursor draws unnamed copies of its sprites. Placement Fix finds the tile by texture name and
-- takes a FloorOverlay tile (floor pipe, router) for a floor: an outline, no model. Named, the copy
-- resolves straight to its pack bind. ISBuildIsoEntity is lua/server: wrapped once the game is up.
local function nameFloorGhosts(cursor)
    for name, ghost in pairs(cursor.spriteCache or {}) do
        local tile = string.sub(name, 1, 11) == "waterpipes_" and not ghost:getName() and getSprite(name) or nil
        local props = tile and tile:getProperties() or nil
        if props and props:has(IsoFlagType.FloorOverlay) then
            ghost:setName(name)
        end
    end
end

local function hookBuildCursor()
    if not ISBuildIsoEntity or ISBuildIsoEntity.waterPipesNamesGhosts then
        return
    end
    local cacheSprites = ISBuildIsoEntity.cacheSprites
    ISBuildIsoEntity.cacheSprites = function(self, face)
        cacheSprites(self, face)
        nameFloorGhosts(self)
    end
    ISBuildIsoEntity.waterPipesNamesGhosts = true
end

-- A new game starts from nothing: nothing tracked survives from the last one.
local function resetSession()
    sprays = {}
    count = 0
    swapped = {}
    lastFrame = -1
end

-- never saved: out before a save (single player), back on the next rescan
local function beforeSave()
    VP.clearSprays()
    restoreHeads()
end

Events.OnGameBoot.Add(register)
Events.OnGameStart.Add(resetSession)
Events.OnGameStart.Add(register)
Events.OnGameStart.Add(hookBuildCursor)
Events.OnTick.Add(onTick)
Events.OnObjectAdded.Add(onObjectAdded)
Events.OnSave.Add(beforeSave)
