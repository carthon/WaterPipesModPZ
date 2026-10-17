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
-- A rescan walks the square around the player a few rows per tick, so it never lands in one frame
-- (61 x 61 tiles). A full pass takes about half a second.
local SCAN_ROWS_PER_TICK = 2
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
    o.naming = {}          -- "x,y,z" -> true while that valve's name box is open
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
    if not Signals.mayTouch(self.character, square) then
        return "blocked", "safehouse"
    end
    return "free"
end

local function scanRow(self, pass, x)
    for y = pass.cy - SCAN_RADIUS, pass.cy + SCAN_RADIUS do
        local square = World.squareAt(x, y, pass.cz)
        if square and square:getSpecialObjects():size() > 0 then
            local valve = Valve.findOnSquare(square)
            if valve then
                pass.valves[#pass.valves + 1] = { valve = valve, x = x, y = y, z = pass.cz, kind = self:classify(valve) }
            end
        end
    end
end

local function newPass(self)
    return {
        cx = math.floor(self.character:getX()), cy = math.floor(self.character:getY()),
        cz = math.floor(self.character:getZ()), x = nil, valves = {},
    }
end

-- Every valve around the player, with what a click on it would do, in one go (when picking starts).
function methods:scan()
    local pass = newPass(self)
    for x = pass.cx - SCAN_RADIUS, pass.cx + SCAN_RADIUS do
        scanRow(self, pass, x)
    end
    self.valves = pass.valves
    self.pass = nil
end

-- A few rows of the running rescan; the finished pass replaces the list.
function methods:stepScan()
    local pass = self.pass
    if not pass then
        pass = newPass(self)
        pass.x = pass.cx - SCAN_RADIUS
        self.pass = pass
    end
    local rows = 0
    while pass.x <= pass.cx + SCAN_RADIUS and rows < SCAN_ROWS_PER_TICK do
        scanRow(self, pass, pass.x)
        pass.x = pass.x + 1
        rows = rows + 1
    end
    if pass.x > pass.cx + SCAN_RADIUS then
        self.valves = pass.valves
        self.pass = nil
    end
end

-- The links changed: recolour the valves already found, and those the running pass has found so far.
function methods:reclassify()
    for _, entry in ipairs(self.valves) do
        entry.kind = self:classify(entry.valve)
    end
    for _, entry in ipairs(self.pass and self.pass.valves or {}) do
        entry.kind = self:classify(entry.valve)
    end
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
    Signals.request(win.playerObj, "link", {
        x = win.px, y = win.py, z = win.pz,
        vx = square:getX(), vy = square:getY(), vz = square:getZ(), name = name,
    })
end

local function keyOfSquare(square)
    return Signals.key(square:getX(), square:getY(), square:getZ())
end

local function onNamed(target, button, cursor, square)
    cursor.naming[keyOfSquare(square)] = nil
    if button.internal ~= "OK" then
        return
    end
    sendLink(cursor.window, square, button.parent.entry:getText())
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
        Signals.request(win.playerObj, "unlink", { x = win.px, y = win.py, z = win.pz, vx = x, vy = y, vz = z })
    elseif kind == "free" then
        if Signals.valveName(valve) then
            sendLink(win, square, nil)
        elseif not self.naming[keyOfSquare(square)] then
            -- one name box per valve, however often it is clicked before the answer comes back
            self.naming[keyOfSquare(square)] = true
            local w, h = 280, 180
            local modal = ISTextBox:new((getCore():getScreenWidth() - w) / 2, (getCore():getScreenHeight() - h) / 2,
                w, h, getText("IGUI_WaterPipesSignalNameValve"), "", nil, onNamed, self.player, self, square)
            modal:initialise()
            modal:addToUIManager()
        end
    end
    return nil
end

function methods:deactivate()
    self.valves = {}
    self.pass = nil
    if active[self.player] == self then
        active[self.player] = nil
    end
    -- only the window's own cursor speaks for it: a replaced one must not undo the new one's state
    local win = self.window
    if win and win.cursor == self then
        win.selecting = false
        win.cursor = nil
    end
end

local function onTick()
    for playerNum, cursor in pairs(active) do
        if getCell():getDrag(playerNum) ~= cursor then
            cursor:deactivate()
        else
            cursor:stepScan()
        end
    end
end

function Cursor.start(playerObj, window)
    Cursor.stop(playerObj)
    local cursor = newCursor(playerObj, window)
    if not cursor then
        return
    end
    active[cursor.player] = cursor
    window.selecting = true
    window.cursor = cursor
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
        cursor:reclassify()
    end
end

if Events and Events.OnTick then
    Events.OnTick.Add(onTick)
end

return Cursor
