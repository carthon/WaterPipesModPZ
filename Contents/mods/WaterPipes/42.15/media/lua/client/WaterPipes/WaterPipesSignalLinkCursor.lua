-- Picking the valves a sensor drives, on the map. While it is active the floor under every valve around
-- the player is tinted, as the dismantle cursor does: green can be linked, yellow is linked (click
-- unlinks), red cannot be (too far, or in a safehouse you are not a member of). Esc or right-click ends
-- it, as with any build cursor.

require "ISUI/ISTextBox"
require "WaterPipes/Signals"
require "WaterPipes/Valve"
require "WaterPipes/World"

WaterPipes = WaterPipes or {}

local Signals = WaterPipes.Signals
local Valve = WaterPipes.Valve
local World = WaterPipes.World

-- ISBuildingObject lives in lua/server, which loads after the client: the cursor class is derived on
-- first use, not at load.
WaterPipesSignalLinkCursor = WaterPipesSignalLinkCursor or {}
local Cursor = WaterPipesSignalLinkCursor
local methods = {}

local SCAN_RADIUS = Signals.LINK_REACH          -- the server refuses links to valves further off
local SCAN_EVERY_TICKS = 30
local COLORS = {
    free = { r = 0.20, g = 0.95, b = 0.30 },
    linked = { r = 1.00, g = 0.85, b = 0.10 },
    blocked = { r = 0.95, g = 0.20, b = 0.20 },
}
local TILE_ALPHA = 0.55
local HOVER_ALPHA = 0.8

local active = {}   -- playerNum -> cursor

local function cursorClass()
    if Cursor.class then
        return Cursor.class
    end
    if not ISBuildingObject then
        return nil
    end
    local class = ISBuildingObject:derive("WaterPipesSignalLinkCursor")
    for name, fn in pairs(methods) do
        class[name] = fn
    end
    Cursor.class = class
    return class
end

local function newCursor(playerObj, window)
    local class = cursorClass()
    if not class then
        return nil
    end
    local o = {}
    setmetatable(o, class)
    class.__index = class
    o:init()
    o.player = playerObj:getPlayerNum()
    o.character = playerObj
    o.window = window
    o.skipBuildAction = true
    o.noNeedHammer = true
    o.dragNilAfterPlace = false
    o:setSprite(Signals.SENSOR_GHOST_SPRITE)
    o.valves = {}
    o.ticks = 0
    return o
end

-- "linked", "free" or "blocked" for a valve, with the reason it is blocked.
function methods:classify(valve)
    local square = valve:getSquare()
    local x, y, z = square:getX(), square:getY(), square:getZ()
    local win = self.window
    if win:isLinked(x, y, z) then
        return "linked"
    end
    local range = Signals.linkRange()
    if range > 0 and (math.abs(x - win.px) > range or math.abs(y - win.py) > range) then
        return "blocked", "outOfRange"
    end
    local level = self.character:getAccessLevel()
    local admin = level ~= nil and level ~= "None" and level ~= ""
    if not admin and SafeHouse and SafeHouse.isSafeHouse(square, self.character:getUsername(), true) then
        return "blocked", "safehouse"
    end
    return "free"
end

-- Every valve around the player, with what a click on it would do.
function methods:scan()
    local valves = {}
    local cx, cy = math.floor(self.character:getX()), math.floor(self.character:getY())
    local cz = math.floor(self.character:getZ())
    for x = cx - SCAN_RADIUS, cx + SCAN_RADIUS do
        for y = cy - SCAN_RADIUS, cy + SCAN_RADIUS do
            local square = World.squareAt(x, y, cz)
            if square and square:getSpecialObjects():size() > 0 then
                local valve = Valve.findOnSquare(square)
                if valve then
                    valves[#valves + 1] = { valve = valve, x = x, y = y, z = cz, kind = self:classify(valve) }
                end
            end
        end
    end
    self.valves = valves
end

function methods:isValid(square)
    local valve = square and Valve.findOnSquare(square) or nil
    return valve ~= nil and self:classify(valve) ~= "blocked"
end

function methods:render(x, y, z, square)
    local floor = self:getFloorCursorSprite()
    for _, entry in ipairs(self.valves) do
        if entry.x ~= x or entry.y ~= y or entry.z ~= z then
            local c = COLORS[entry.kind]
            floor:RenderGhostTileColor(entry.x, entry.y, entry.z, c.r, c.g, c.b, TILE_ALPHA)
        end
    end
    local valve = square and Valve.findOnSquare(square) or nil
    local c = COLORS[valve and self:classify(valve) or "blocked"]
    floor:RenderGhostTileColor(x, y, z, c.r, c.g, c.b, HOVER_ALPHA)
    if valve and valve:getSprite() then
        valve:getSprite():RenderGhostTileColor(x, y, z, c.r, c.g, c.b, HOVER_ALPHA)
    end
end

local function sendLink(win, square, name)
    Signals.request(getPlayer(), "link", {
        x = win.px, y = win.py, z = win.pz,
        vx = square:getX(), vy = square:getY(), vz = square:getZ(), name = name,
    })
end

local function onNamed(target, button, win, square)
    if button.internal ~= "OK" then
        return
    end
    sendLink(win, square, button.parent.entry:getText())
end

-- A click: unlink a linked valve, link a free one (asking its name the first time).
function methods:tryBuild(x, y, z)
    local square = World.squareAt(x, y, z)
    local valve = square and Valve.findOnSquare(square) or nil
    if not valve then
        return nil
    end
    local win = self.window
    local kind = self:classify(valve)
    if kind == "linked" then
        Signals.request(getPlayer(), "unlink", { x = win.px, y = win.py, z = win.pz, vx = x, vy = y, vz = z })
    elseif kind == "free" then
        if Signals.valveName(valve) then
            sendLink(win, square, nil)
        else
            local modal = ISTextBox:new(0, 0, 280, 180, getText("IGUI_WaterPipesSignalNameValve"), "", nil,
                onNamed, self.player, win, square)
            modal:initialise()
            modal:addToUIManager()
        end
    end
    return nil
end

function methods:deactivate()
    self.valves = {}
    if active[self.player] == self then
        active[self.player] = nil
    end
    if self.window then
        self.window.selecting = false
    end
end

local function onTick()
    for playerNum, cursor in pairs(active) do
        if getCell():getDrag(playerNum) ~= cursor then
            cursor:deactivate()
        else
            cursor.ticks = cursor.ticks + 1
            if cursor.ticks % SCAN_EVERY_TICKS == 0 then
                cursor:scan()
            end
        end
    end
end

function Cursor.start(playerObj, window)
    local cursor = newCursor(playerObj, window)
    if not cursor then
        return
    end
    active[cursor.player] = cursor
    window.selecting = true
    getCell():setDrag(cursor, cursor.player)
    cursor:scan()
end

function Cursor.stop(playerObj)
    local playerNum = playerObj and playerObj:getPlayerNum()
    local cursor = playerNum and active[playerNum]
    if cursor then
        getCell():setDrag(nil, playerNum)
        cursor:deactivate()
    end
end

-- The list changed (a link made or undone): recolour now rather than at the next scan.
function Cursor.refresh()
    for _, cursor in pairs(active) do
        cursor:scan()
    end
end

if Events and Events.OnTick then
    Events.OnTick.Add(onTick)
end

return Cursor
