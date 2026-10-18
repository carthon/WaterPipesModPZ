-- Picking the receivers a sensor drives, on the map. While it is active the floor under every receiver
-- around the player is tinted, as the dismantle cursor does: green can be linked, yellow is linked (click
-- unlinks), red cannot be (too far, or in a safehouse you are not a member of). Esc or right-click ends
-- it, as with any build cursor. Every registered receiver kind is offered (Signals.receiversOnSquare).

require "ISUI/ISTextBox"
require "WaterPipes/Signals"
require "WaterPipes/World"

WaterPipes = WaterPipes or {}

local Signals = WaterPipes.Signals
local World = WaterPipes.World

-- ISBuildingObject lives in lua/server, which loads after the client: the cursor class is derived on
-- first use, not at load.
WaterPipesSignalLinkCursor = WaterPipesSignalLinkCursor or {}
local Cursor = WaterPipesSignalLinkCursor
local methods = {}

local SCAN_RADIUS = Signals.LINK_REACH          -- the server refuses links to receivers further off
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
    o.receivers = {}
    o.naming = {}          -- receiver key -> true while that receiver's name box is open
    return o
end

-- The receiver a click on this square acts on, wrapped, or nil: with several kinds on one tile, the
-- first one still free, else the first linked, so repeated clicks reach each of them.
local function receiverOn(cursor, square)
    local found = square and Signals.receiversOnSquare(square) or {}
    local linked = nil
    for _, receiver in ipairs(found) do
        local state = cursor:classify(receiver)
        if state == "free" then
            return receiver
        elseif state == "linked" and not linked then
            linked = receiver
        end
    end
    return linked or found[1]
end

-- "linked", "free" or "blocked" for a receiver, with the reason it is blocked.
function methods:classify(receiver)
    local square = receiver.object:getSquare()
    local x, y, z = square:getX(), square:getY(), square:getZ()
    local win = self.window
    if win:isLinked(x, y, z, receiver.kind) then
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
            for _, receiver in ipairs(Signals.receiversOnSquare(square)) do
                pass.receivers[#pass.receivers + 1] = { receiver = receiver, x = x, y = y, z = pass.cz,
                                                        kind = self:classify(receiver) }
            end
        end
    end
end

local function newPass(self)
    return {
        cx = math.floor(self.character:getX()), cy = math.floor(self.character:getY()),
        cz = math.floor(self.character:getZ()), x = nil, receivers = {},
    }
end

-- Every receiver around the player, with what a click on it would do, in one go (when picking starts).
function methods:scan()
    local pass = newPass(self)
    for x = pass.cx - SCAN_RADIUS, pass.cx + SCAN_RADIUS do
        scanRow(self, pass, x)
    end
    self.receivers = pass.receivers
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
        self.receivers = pass.receivers
        self.pass = nil
    end
end

-- The links changed: recolour the receivers already found, and those the running pass has found so far.
function methods:reclassify()
    for _, entry in ipairs(self.receivers) do
        entry.kind = self:classify(entry.receiver)
    end
    for _, entry in ipairs(self.pass and self.pass.receivers or {}) do
        entry.kind = self:classify(entry.receiver)
    end
end

function methods:isValid(square)
    local receiver = receiverOn(self, square)
    return receiver ~= nil and self:classify(receiver) ~= "blocked"
end

function methods:render(x, y, z, square)
    local floor = self:getFloorCursorSprite()
    for _, entry in ipairs(self.receivers) do
        if entry.x ~= x or entry.y ~= y or entry.z ~= z then
            local c = COLORS[entry.kind]
            floor:RenderGhostTileColor(entry.x, entry.y, entry.z, c.r, c.g, c.b, TILE_ALPHA)
        end
    end
    local receiver = receiverOn(self, square)
    local c = COLORS[receiver and self:classify(receiver) or "blocked"]
    floor:RenderGhostTileColor(x, y, z, c.r, c.g, c.b, HOVER_ALPHA)
    local sprite = receiver and receiver.object:getSprite() or nil
    if sprite then
        sprite:RenderGhostTileColor(x, y, z, c.r, c.g, c.b, HOVER_ALPHA)
    end
end

local function sendLink(win, square, kind, name)
    Signals.request(win.playerObj, "link", {
        x = win.px, y = win.py, z = win.pz,
        vx = square:getX(), vy = square:getY(), vz = square:getZ(), kind = kind, name = name,
    })
end

local function keyOf(square, kind)
    return Signals.receiverKey(kind, square:getX(), square:getY(), square:getZ())
end

local function onNamed(target, button, cursor, square, kind)
    cursor.naming[keyOf(square, kind)] = nil
    if button.internal ~= "OK" then
        return
    end
    sendLink(cursor.window, square, kind, button.parent.entry:getText())
end

-- A click: unlink a linked receiver, link a free one (asking its name the first time).
function methods:tryBuild(x, y, z)
    local square = World.squareAt(x, y, z)
    local receiver = receiverOn(self, square)
    if not receiver then
        return nil
    end
    local win = self.window
    local state = self:classify(receiver)
    if state == "linked" then
        Signals.request(win.playerObj, "unlink",
            { x = win.px, y = win.py, z = win.pz, vx = x, vy = y, vz = z, kind = receiver.kind })
    elseif state == "free" then
        if receiver:savedName() then
            sendLink(win, square, receiver.kind, nil)
        elseif not self.naming[keyOf(square, receiver.kind)] then
            -- one name box per receiver, however often it is clicked before the answer comes back
            self.naming[keyOf(square, receiver.kind)] = true
            local w, h = 280, 180
            local modal = ISTextBox:new((getCore():getScreenWidth() - w) / 2, (getCore():getScreenHeight() - h) / 2,
                w, h, getText(receiver.NAME_PROMPT), "", nil, onNamed, self.player, self, square, receiver.kind)
            modal:initialise()
            modal:addToUIManager()
        end
    end
    return nil
end

function methods:deactivate()
    self.receivers = {}
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
