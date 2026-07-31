-- Water pump status dialog (client UI). Opened from the pump's context menu; also carries the
-- on/off switch, so the player never has to close it to act on what it just told them.
--
-- It is a LIVE readout: the pump object is re-resolved FROM ITS TILE rather than held as a reference
-- (IsoObject references go stale when the engine re-instantiates objects on chunk stream / build
-- finalize), and the reading is refreshed on a timer. The timer matters: reading pressure walks the
-- whole network, which is far too much work to redo every frame -- same reasoning as the router
-- pressure window.

require "ISUI/ISCollapsableWindow"
require "WaterPipes/Constants"
require "WaterPipes/Pump"

WaterPipes = WaterPipes or {}

local Constants = WaterPipes.Constants
local Pump = WaterPipes.Pump

WaterPipesPumpWindow = ISCollapsableWindow:derive("WaterPipesPumpWindow")
WaterPipesPumpWindow.instances = WaterPipesPumpWindow.instances or {}

local PAD = 12
local ROW = 24
local LIVE_REFRESH_TICKS = 30

local COL_LABEL = { r = 0.80, g = 0.82, b = 0.85 }
local COL_VALUE = { r = 0.80, g = 0.90, b = 1.00 }
local COL_RUNNING = { r = 0.35, g = 0.85, b = 0.40 }
local COL_STOPPED = { r = 0.85, g = 0.45, b = 0.30 }
local COL_WARN = { r = 0.90, g = 0.70, b = 0.20 }

local function lineHeight()
    return getTextManager():getFontHeight(UIFont.Small)
end

local function keyForSquare(x, y, z)
    return tostring(x) .. ":" .. tostring(y) .. ":" .. tostring(z)
end

local function formatHead(value)
    return string.format("%.1f", value or 0)
end

function WaterPipesPumpWindow:resolvePump()
    local cell = getCell and getCell() or nil
    local square = cell and cell.getGridSquare and cell:getGridSquare(self.px, self.py, self.pz) or nil
    return square and Pump.findOnSquare(square) or nil
end

function WaterPipesPumpWindow.openFor(pumpObject)
    local square = pumpObject and pumpObject.getSquare and pumpObject:getSquare() or nil
    if not square then
        return nil
    end
    local x, y, z = square:getX(), square:getY(), square:getZ()
    local key = keyForSquare(x, y, z)

    local existing = WaterPipesPumpWindow.instances[key]
    if existing then
        existing:addToUIManager()
        existing:setVisible(true)
        existing:bringToTop()
        return existing
    end

    local w, h = 320, 226
    local px = (getCore():getScreenWidth() - w) / 2
    local py = (getCore():getScreenHeight() - h) / 2
    local win = WaterPipesPumpWindow:new(px, py, w, h, x, y, z)
    win:initialise()
    win:addToUIManager()
    WaterPipesPumpWindow.instances[key] = win
    return win
end

function WaterPipesPumpWindow:new(x, y, width, height, px, py, pz)
    local o = ISCollapsableWindow:new(x, y, width, height)
    setmetatable(o, self)
    self.__index = self
    o.px, o.py, o.pz = px, py, pz
    -- The window is titled with the item's own name, so it matches the context menu entry that
    -- opened it in every language.
    o.title = getText("IGUI_WaterPipesPumpName")
    o.resizable = false
    o:setWantKeyEvents(true)
    o.status = nil
    o.ticks = 0
    return o
end

function WaterPipesPumpWindow:refresh()
    local pump = self:resolvePump()
    self.status = pump and Pump.getStatus(pump) or nil
end

function WaterPipesPumpWindow:createChildren()
    ISCollapsableWindow.createChildren(self)

    local innerWidth = self.width - PAD * 2
    local buttonWidth = (innerWidth - PAD) / 2
    local buttonY = self.height - ROW - PAD

    self.toggleButton = ISButton:new(PAD, buttonY, buttonWidth, ROW, "", self, self.onToggle)
    self.toggleButton:initialise()
    self:addChild(self.toggleButton)

    self.closeButton = ISButton:new(PAD + buttonWidth + PAD, buttonY, buttonWidth, ROW,
        getText("IGUI_WaterPipesClose"), self, self.onCloseButton)
    self.closeButton:initialise()
    self:addChild(self.closeButton)

    self:refresh()
end

function WaterPipesPumpWindow:onToggle()
    local pump = self:resolvePump()
    if not pump then
        self:close()
        return
    end
    WaterPipes.ContextMenu.togglePump(getPlayer(), pump, not Pump.isEnabled(pump))
end

function WaterPipesPumpWindow:onCloseButton()
    self:close()
end

function WaterPipesPumpWindow:prerender()
    ISCollapsableWindow.prerender(self)

    local status = self.status
    if not status then
        return
    end

    local y = self:titleBarHeight() + PAD
    local step = lineHeight() + 3

    -- Headline: what the machine is doing. "Switched off" and "no power" are different problems with
    -- different fixes, so they never collapse into one message.
    local headKey, headCol
    if not status.enabled then
        headKey, headCol = "IGUI_WaterPipesPumpOff", COL_STOPPED
    elseif not status.hasPower then
        headKey, headCol = "IGUI_WaterPipesPumpNoPower", COL_WARN
    else
        headKey, headCol = "IGUI_WaterPipesPumpRunning", COL_RUNNING
    end
    self:drawTextCentre(getText(headKey), self.width / 2, y, headCol.r, headCol.g, headCol.b, 1, UIFont.Medium)
    y = y + getTextManager():getFontHeight(UIFont.Medium) + PAD

    -- Intake. A pump beside a well is a very different machine from one on a bare run, and the player
    -- cannot see which from the outside.
    local sourceKey
    if not status.sourceKind then
        sourceKey = "IGUI_WaterPipesPumpNoSource"
    elseif status.drawing then
        sourceKey = status.sourceKind == "well"
            and "IGUI_WaterPipesPumpDrawingWell" or "IGUI_WaterPipesPumpDrawingWater"
    else
        sourceKey = status.sourceKind == "well"
            and "IGUI_WaterPipesPumpSourceWellIdle" or "IGUI_WaterPipesPumpSourceWaterIdle"
    end
    local sourceCol = status.drawing and COL_RUNNING or COL_LABEL
    self:drawText(getText(sourceKey), PAD, y, sourceCol.r, sourceCol.g, sourceCol.b, 1, UIFont.Small)
    y = y + step + 4

    -- With the pressure model off there is no head to report, and pretending otherwise would be a lie.
    if status.pressureEnabled == false then
        self:drawText(getText("IGUI_WaterPipesPressureModelOff"), PAD, y,
            COL_LABEL.r, COL_LABEL.g, COL_LABEL.b, 1, UIFont.Small)
        return
    end

    if not status.outlet then
        self:drawText(getText("IGUI_WaterPipesPumpNoSupply"), PAD, y,
            COL_STOPPED.r, COL_STOPPED.g, COL_STOPPED.b, 1, UIFont.Small)
        return
    end

    self:drawText(getText("IGUI_WaterPipesPumpInlet", formatHead(status.inlet)), PAD, y,
        COL_VALUE.r, COL_VALUE.g, COL_VALUE.b, 1, UIFont.Small)
    y = y + step
    self:drawText(getText("IGUI_WaterPipesPumpOutlet", formatHead(status.outlet)), PAD, y,
        COL_VALUE.r, COL_VALUE.g, COL_VALUE.b, 1, UIFont.Small)
    y = y + step

    -- An idle pump answers the only question worth asking about it: is it worth switching on? A pump
    -- on a mains-fed run gains nothing, and saying so beats letting the player guess.
    if not status.running and (status.wouldGain or 0) > 0 then
        self:drawText(getText("IGUI_WaterPipesPumpWouldGain", formatHead(status.wouldGain)), PAD, y,
            COL_WARN.r, COL_WARN.g, COL_WARN.b, 1, UIFont.Small)
    elseif status.running then
        self:drawText(getText("IGUI_WaterPipesPumpAdding", formatHead(status.outlet - (status.inlet or 0))),
            PAD, y, COL_LABEL.r, COL_LABEL.g, COL_LABEL.b, 1, UIFont.Small)
    end
end

function WaterPipesPumpWindow:update()
    ISCollapsableWindow.update(self)

    local player = getPlayer()
    local pump = self:resolvePump()
    if not player or not pump then
        self:close()
        return
    end

    self.ticks = (self.ticks or 0) + 1
    if self.ticks % LIVE_REFRESH_TICKS == 0 then
        self:refresh()
    end

    -- The switch label follows the live state, so a flip made from the context menu (or by another
    -- player) is reflected here without reopening.
    if self.toggleButton then
        self.toggleButton:setTitle(getText(Pump.isEnabled(pump)
            and "ContextMenu_WaterPipesPumpTurnOff" or "ContextMenu_WaterPipesPumpTurnOn"))
    end

    -- Close when the player walks away or changes floor, matching the other readout windows.
    local dx = math.abs(player:getX() - self.px)
    local dy = math.abs(player:getY() - self.py)
    if math.floor(player:getZ()) ~= self.pz
        or dx > Constants.GAUGE_READ_DISTANCE + 1
        or dy > Constants.GAUGE_READ_DISTANCE + 1 then
        self:close()
    end
end

function WaterPipesPumpWindow:close()
    WaterPipesPumpWindow.instances[keyForSquare(self.px, self.py, self.pz)] = nil
    self:setVisible(false)
    self:removeFromUIManager()
    ISCollapsableWindow.close(self)
end

function WaterPipesPumpWindow:onKeyRelease(key)
    if key == Keyboard.KEY_ESCAPE then
        self:close()
    end
end

return WaterPipesPumpWindow
