-- Purifier readout window (client UI). Opened from the purifier's context menu ("Open Purifier").
-- Shows the two internal buffers (IN intake / OUT output) as fluid gauges, the electrical-grid
-- connection, the operating status, and the filtering rate.
--
-- It is a LIVE readout: every frame it re-resolves the purifier object FROM ITS SQUARE (never a cached
-- reference -- IsoObject references go stale when the engine re-instantiates objects on chunk stream /
-- build finalize, which would freeze the gauges) and re-reads its modData (kept in sync by the server
-- via transmitModData). So it needs no events of its own.

require "ISUI/ISCollapsableWindow"
require "WaterPipes/Constants"
require "WaterPipes/Purifier"

WaterPipes = WaterPipes or {}

local Constants = WaterPipes.Constants
local Purifier = WaterPipes.Purifier

WaterPipesPurifierWindow = ISCollapsableWindow:derive("WaterPipesPurifierWindow")
WaterPipesPurifierWindow.instances = WaterPipesPurifierWindow.instances or {}

-- Fluid gauge colours (a, r, g, b handled at draw time).
local COL_TAINTED = { r = 0.42, g = 0.52, b = 0.20 }   -- murky green-brown
local COL_CLEAN = { r = 0.24, g = 0.54, b = 0.95 }     -- clean blue
local COL_EMPTY = { r = 0.16, g = 0.17, b = 0.19 }     -- empty tank
local COL_LABEL = { r = 0.80, g = 0.82, b = 0.85 }
local COL_RUNNING = { r = 0.35, g = 0.85, b = 0.40 }
local COL_STOPPED = { r = 0.85, g = 0.45, b = 0.30 }

local PAD = 14
local GAUGE_W = 66
local GAUGE_H = 108
local GAUGE_GAP = 40

local function font()
    return UIFont and UIFont.Small or 1
end

local function lineH()
    return getTextManager():getFontHeight(font())
end

local function getSquareAt(x, y, z)
    if x == nil or not getCell then
        return nil
    end
    local cell = getCell()
    return cell and cell.getGridSquare and cell:getGridSquare(x, y, z) or nil
end

-- ===== instance identity: one window per purifier tile (keyed by square, not by object ref) =====

local function keyForSquare(x, y, z)
    return string.format("%d:%d:%d", x or 0, y or 0, z or 0)
end

function WaterPipesPurifierWindow.openFor(purifierObject)
    if not purifierObject then
        return nil
    end
    local sq = purifierObject.getSquare and purifierObject:getSquare() or nil
    if not sq then
        return nil
    end
    local x, y, z = sq:getX(), sq:getY(), sq:getZ()
    local key = keyForSquare(x, y, z)

    local existing = WaterPipesPurifierWindow.instances[key]
    if existing then
        existing:addToUIManager()
        existing:setVisible(true)
        existing:bringToTop()
        return existing
    end

    local w, h = 292, 312
    local px = (getCore():getScreenWidth() - w) / 2
    local py = (getCore():getScreenHeight() - h) / 2
    local win = WaterPipesPurifierWindow:new(px, py, w, h, x, y, z)
    win:initialise()
    win:addToUIManager()
    WaterPipesPurifierWindow.instances[key] = win
    return win
end

function WaterPipesPurifierWindow:new(x, y, width, height, px, py, pz)
    local o = ISCollapsableWindow:new(x, y, width, height)
    setmetatable(o, self)
    self.__index = self
    o.px, o.py, o.pz = px, py, pz   -- the purifier tile; the object is re-resolved from here each frame
    o.purifier = nil
    o.title = getText("IGUI_WaterPipesPurifierWindowTitle")
    o.resizable = false
    o.drawFrame = true
    o:setWantKeyEvents(true)
    return o
end

function WaterPipesPurifierWindow:createChildren()
    ISCollapsableWindow.createChildren(self)
end

local function drawGauge(self, x, top, amount, capacity, colFluid, caption, fluidName)
    -- caption above
    self:drawTextCentre(caption, x + GAUGE_W / 2, top - lineH() - 3, COL_LABEL.r, COL_LABEL.g, COL_LABEL.b, 1, font())
    -- tank body: empty background + border
    self:drawRect(x, top, GAUGE_W, GAUGE_H, 1, COL_EMPTY.r, COL_EMPTY.g, COL_EMPTY.b)
    local ratio = capacity > 0 and math.min(math.max(amount / capacity, 0), 1) or 0
    local fillH = math.floor(GAUGE_H * ratio)
    if fillH > 0 then
        self:drawRect(x, top + (GAUGE_H - fillH), GAUGE_W, fillH, 0.92, colFluid.r, colFluid.g, colFluid.b)
    end
    self:drawRectBorder(x, top, GAUGE_W, GAUGE_H, 1, 0.45, 0.47, 0.50)
    -- amount / capacity below the tank
    local amountText = string.format("%d / %d", math.floor(amount + 0.5), math.floor(capacity + 0.5))
    self:drawTextCentre(amountText, x + GAUGE_W / 2, top + GAUGE_H + 4, COL_LABEL.r, COL_LABEL.g, COL_LABEL.b, 1, font())
    -- fluid name below the amount
    self:drawTextCentre(fluidName, x + GAUGE_W / 2, top + GAUGE_H + 4 + lineH() + 2,
        math.min(colFluid.r + 0.15, 1), math.min(colFluid.g + 0.15, 1), math.min(colFluid.b + 0.15, 1), 1, font())
end

function WaterPipesPurifierWindow:prerender()
    ISCollapsableWindow.prerender(self)

    -- Resolve the LIVE purifier object from its tile each frame (never a cached ref).
    local sq = getSquareAt(self.px, self.py, self.pz)
    if not sq then
        return   -- tile not currently loaded; keep the window and retry next frame
    end
    local obj = Purifier.findOnSquare(sq)
    if not obj then
        self:close()   -- the purifier was removed
        return
    end
    self.purifier = obj

    local cap = Constants.PURIFIER_BUFFER_CAPACITY
    local inAmount = Purifier.getInAmount(obj)
    local inTainted = Purifier.isInTainted(obj)
    local outAmount = Purifier.getOutAmount(obj)
    local connected = Purifier.isWorking(obj)   -- isWorking == the tile has electricity available

    local contentTop = self:titleBarHeight() + PAD

    -- Line 1: electrical-grid connection.
    local gridText = getText(connected and "IGUI_WaterPipesPurifierGridOn" or "IGUI_WaterPipesPurifierGridOff")
    local gridCol = connected and COL_RUNNING or COL_STOPPED
    self:drawTextCentre(gridText, self.width / 2, contentTop, gridCol.r, gridCol.g, gridCol.b, 1, font())

    -- Line 2: operating status. Only "Filtering" when powered AND there is tainted water to convert;
    -- powered with nothing tainted to clean = "Idle"; no power = "Stopped".
    local filtering = connected and inTainted and inAmount > 0
    local statusKey, statusCol
    if not connected then
        statusKey, statusCol = "IGUI_WaterPipesPurifierStopped", COL_STOPPED
    elseif filtering then
        statusKey, statusCol = "IGUI_WaterPipesPurifierFiltering", COL_RUNNING
    else
        statusKey, statusCol = "IGUI_WaterPipesPurifierIdle", COL_LABEL
    end
    local statusY = contentTop + lineH() + 4
    self:drawTextCentre(getText(statusKey), self.width / 2, statusY, statusCol.r, statusCol.g, statusCol.b, 1, UIFont.Medium)

    -- Two gauges: IN (intake, may be tainted or clean) and OUT (always clean water).
    local gaugesTop = statusY + getTextManager():getFontHeight(UIFont.Medium) + PAD + lineH()
    local totalGaugesW = GAUGE_W * 2 + GAUGE_GAP
    local leftX = (self.width - totalGaugesW) / 2

    local inCol, inName
    if inAmount <= 0 then
        inCol, inName = COL_EMPTY, getText("IGUI_WaterPipesFluidEmpty")
    elseif inTainted then
        inCol, inName = COL_TAINTED, getText("IGUI_WaterPipesFluidTainted")
    else
        inCol, inName = COL_CLEAN, getText("IGUI_WaterPipesFluidClean")
    end

    local outCol = outAmount > 0 and COL_CLEAN or COL_EMPTY
    local outName = outAmount > 0 and getText("IGUI_WaterPipesFluidClean") or getText("IGUI_WaterPipesFluidEmpty")

    drawGauge(self, leftX, gaugesTop, inAmount, cap, inCol,
        getText("IGUI_WaterPipesPurifierIntake"), inName)
    drawGauge(self, leftX + GAUGE_W + GAUGE_GAP, gaugesTop, outAmount, cap, outCol,
        getText("IGUI_WaterPipesPurifierOutput"), outName)

    -- Filtering rate: the tainted->clean conversion rate while actually filtering (0 otherwise).
    local rate = filtering and Constants.PURIFIER_CONVERT_RATE or 0
    local rateText = getText("IGUI_WaterPipesPurifierRate", rate)
    local rateY = gaugesTop + GAUGE_H + 4 + (lineH() + 2) * 2 + PAD
    self:drawTextCentre(rateText, self.width / 2, rateY, COL_LABEL.r, COL_LABEL.g, COL_LABEL.b, 1, font())
end

function WaterPipesPurifierWindow:close()
    WaterPipesPurifierWindow.instances[keyForSquare(self.px, self.py, self.pz)] = nil
    self:setVisible(false)
    self:removeFromUIManager()
end

-- Close on Escape for convenience.
function WaterPipesPurifierWindow:onKeyRelease(key)
    if key == Keyboard.KEY_ESCAPE then
        self:close()
    end
end

return WaterPipesPurifierWindow
