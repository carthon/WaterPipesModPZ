WaterPipes = WaterPipes or {}
WaterPipes.IrrigationDebug = WaterPipes.IrrigationDebug or {}

require "WaterPipes/Constants"
require "WaterPipes/Irrigation"
require "WaterPipes/WaterPipesTileRegistry"
require "WaterPipes/World"

local Constants = WaterPipes.Constants
local Irrigation = WaterPipes.Irrigation
local Registry = WaterPipes.TileRegistry
local IrrigationDebug = WaterPipes.IrrigationDebug
local World = WaterPipes.World

-- A debug overlay that makes irrigation visible. Every crop near the player is tinted by its water
-- level (red = dry, green = full) and every emitter by whether it can water right now (green = active,
-- yellow = has water but not enough pressure or nothing thirsty, red = no supply, magenta = burst).
-- Both are read live each refresh.
-- Client-side, reading modData the crop already syncs, so it needs no farming-system access.

IrrigationDebug.enabled = false

local SCAN_RADIUS = 15          -- tiles around the player scanned each refresh
local REFRESH_TICKS = 15        -- ~4 refreshes/second; cheap enough for a debug tool
local tickCounter = 0

-- Objects we are currently tinting, so we can clear exactly them when they leave range or the overlay
-- is switched off. Keyed by the object; value is the player number it was highlighted for.
local highlighted = {}

local COLORS = {
    active    = { r = 0.2, g = 1.0, b = 0.2, a = 1.0 },   -- emitter watering
    idle      = { r = 1.0, g = 0.9, b = 0.2, a = 1.0 },   -- has pressure/water but nothing to do
    starved   = { r = 1.0, g = 0.2, b = 0.2, a = 1.0 },   -- no supply / not enough pressure
    burst     = { r = 1.0, g = 0.2, b = 1.0, a = 1.0 },   -- blown-out drip
}

-- Crop tint: lerp red -> green by water level.
local function waterColor(level)
    local t = math.max(0, math.min((level or 0) / Constants.IRRIGATION_MAX_WATER_LEVEL, 1))
    return { r = 1 - t, g = t, b = 0.1, a = 1.0 }
end

local function setHighlight(worldObject, playerNum, on, color)
    if not worldObject or not worldObject.setHighlighted then
        return
    end
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
end

local function clearAll()
    for worldObject, playerNum in pairs(highlighted) do
        setHighlight(worldObject, playerNum, false, nil)
    end
    highlighted = {}
end

local function modDataOf(worldObject)
    if not worldObject or not worldObject.getModData then
        return nil
    end
    local ok, modData = pcall(worldObject.getModData, worldObject)
    return ok and modData or nil
end

-- A planted crop (not bare tilled soil) carries state + nbOfGrow + waterLvl in its own modData.
local function cropWaterLevel(worldObject)
    local modData = modDataOf(worldObject)
    if not modData or modData.state == nil or modData.nbOfGrow == nil then
        return nil
    end
    if modData.state == "plow" then
        return nil
    end
    return tonumber(modData.waterLvl) or 0
end

local function colorForEmitter(found, stamp)
    -- Through the registry's cache: the overlay refreshes four times a second and the status is
    -- derived from a full network walk, which only changes when the server's minute pass runs.
    local status = Registry.statusFor(found, stamp)
    if not status then
        return nil
    end
    if status.burst then
        return COLORS.burst
    end
    if not status.reaches or not status.hasWater then
        return COLORS.starved
    end
    return COLORS.active   -- reachable + has water: it will water anything thirsty under it
    -- (COLORS.idle is reserved for a future "reachable but nothing thirsty" refinement.)
end

local function refresh()
    local player = getPlayer()
    if not player then
        return
    end
    local playerNum = player:getPlayerNum()
    local px, py, pz = player:getX(), player:getY(), player:getZ()
    local nextHighlighted = {}

    local function tint(worldObject, color)
        setHighlight(worldObject, playerNum, true, color)
        nextHighlighted[worldObject] = playerNum
        highlighted[worldObject] = nil   -- claimed; whatever's left in `highlighted` gets cleared
    end

    -- Emitters first: they are the thing being tested. Taken from the registry, so the overlay no
    -- longer asks every pipe object on 961 tiles whether it happens to be an emitter.
    local stamp = Registry.stamp()
    for _, found in ipairs(Registry.near("emitters", math.floor(px), math.floor(py),
                                         math.floor(pz), SCAN_RADIUS)) do
        local color = colorForEmitter(found, stamp)
        if color then
            tint(found.object, color)
        end
    end

    -- Crops still need the area sweep: they are not pipe objects and nothing indexes them.
    for dx = -SCAN_RADIUS, SCAN_RADIUS do
        for dy = -SCAN_RADIUS, SCAN_RADIUS do
            local square = World.squareAt(math.floor(px) + dx, math.floor(py) + dy, math.floor(pz))
            if square then
                if square.getObjects then
                    local ok, objects = pcall(square.getObjects, square)
                    if ok and objects then
                        for i = 0, objects:size() - 1 do
                            local worldObject = objects:get(i)
                            local level = cropWaterLevel(worldObject)
                            if level ~= nil then
                                tint(worldObject, waterColor(level))
                            end
                        end
                    end
                end
            end
        end
    end

    -- Anything still in `highlighted` was tinted last pass but not this one: clear it.
    for worldObject, num in pairs(highlighted) do
        setHighlight(worldObject, num, false, nil)
    end
    highlighted = nextHighlighted
end

local function onTick()
    if not IrrigationDebug.enabled then
        return
    end
    tickCounter = tickCounter + 1
    if tickCounter < REFRESH_TICKS then
        return
    end
    tickCounter = 0
    pcall(refresh)
end

function IrrigationDebug.isEnabled()
    return IrrigationDebug.enabled
end

function IrrigationDebug.setEnabled(on)
    on = on and true or false
    if on == IrrigationDebug.enabled then
        return
    end
    IrrigationDebug.enabled = on
    -- The overlay owns the watering log too: turning the overlay on lights up console.txt with each
    -- watering event, so the visual and the text agree.
    Irrigation.debugLog = on
    if not on then
        clearAll()
    end
    if getPlayer() and HaloTextHelper then
        HaloTextHelper.addText(getPlayer(),
            on and "Water Pipes: irrigation overlay ON" or "Water Pipes: irrigation overlay OFF")
    end
end

function IrrigationDebug.toggle()
    IrrigationDebug.setEnabled(not IrrigationDebug.enabled)
end

if Events and Events.OnTick then
    Events.OnTick.Add(onTick)
end

return IrrigationDebug
