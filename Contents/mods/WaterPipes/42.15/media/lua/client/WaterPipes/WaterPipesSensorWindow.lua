-- Humidity sensor window: name, the minimum and maximum that switch the signal, invert, the battery, and the valves the
-- sensor drives (with the button that starts picking them on the map). Readings come from the sensor's
-- replicated modData; the list of valves from a snapshot the server sends back.

require "ISUI/ISCollapsableWindow"
require "ISUI/ISScrollingListBox"
require "ISUI/ISTickBox"
require "RadioCom/ISUIRadio/ISSliderPanel"
require "WaterPipes/Signals"
require "WaterPipes/World"

WaterPipes = WaterPipes or {}

local Signals = WaterPipes.Signals
local World = WaterPipes.World

WaterPipesSensorWindow = ISCollapsableWindow:derive("WaterPipesSensorWindow")
WaterPipesSensorWindow.instances = WaterPipesSensorWindow.instances or {}

local PAD = 10
local ROW = 24
local SLIDER_SPARE = 190                         -- label on the left, value and what it does on the right
local LIST_HEIGHT = 110

local COL_LABEL = { r = 0.80, g = 0.82, b = 0.85 }
local COL_ON = { r = 0.35, g = 0.85, b = 0.40 }
local COL_OFF = { r = 0.90, g = 0.45, b = 0.30 }
local COL_DIM = { r = 0.60, g = 0.62, b = 0.66 }

local function lineHeight()
    return getTextManager():getFontHeight(UIFont.Small)
end

local function percent(value)
    return string.format("%d%%", math.floor((value or 0) + 0.5))
end

function WaterPipesSensorWindow:resolveSensor()
    local square = World.squareAt(self.px, self.py, self.pz)
    return square and Signals.findSensorOnSquare(square) or nil
end

-- `playerObj`: who opened it; every request and the reach check go as that player (split screen).
function WaterPipesSensorWindow.openFor(sensor, playerObj)
    local square = sensor and sensor.getSquare and sensor:getSquare() or nil
    if not square then
        return nil
    end
    playerObj = playerObj or getPlayer()
    local x, y, z = square:getX(), square:getY(), square:getZ()
    local key = Signals.key(x, y, z)
    local existing = WaterPipesSensorWindow.instances[key]
    if existing and existing.playerObj ~= playerObj then
        -- split screen: the other player's window on this sensor gives way to a window of their own
        existing:close()
        existing = nil
    end
    if existing then
        existing:addToUIManager()
        existing:setVisible(true)
        existing:bringToTop()
        existing:requestSnapshot()
        return existing
    end
    local w, h = 380, 470
    local win = WaterPipesSensorWindow:new((getCore():getScreenWidth() - w) / 2,
        (getCore():getScreenHeight() - h) / 2, w, h, x, y, z, playerObj)
    win:initialise()
    win:addToUIManager()
    WaterPipesSensorWindow.instances[key] = win
    win:requestSnapshot()
    return win
end

function WaterPipesSensorWindow:new(x, y, width, height, px, py, pz, playerObj)
    local o = ISCollapsableWindow:new(x, y, width, height)
    setmetatable(o, self)
    self.__index = self
    o.px, o.py, o.pz = px, py, pz
    o.playerObj = playerObj or getPlayer()
    o.loaded = false            -- no snapshot yet: the list is not known
    o.title = getText("IGUI_WaterPipesSensorTitle")
    o.resizable = false
    o:setWantKeyEvents(true)
    o.links = {}
    return o
end

function WaterPipesSensorWindow:createChildren()
    ISCollapsableWindow.createChildren(self)
    local sensor = self:resolveSensor()
    local inner = self.width - PAD * 2
    local y = self:titleBarHeight() + PAD

    self.nameEntry = ISTextEntryBox:new(Signals.sensorName(sensor) or "", PAD + 70, y, inner - 70, ROW)
    self.nameEntry:initialise()
    self.nameEntry:instantiate()
    self.nameEntry:setMaxTextLength(Signals.NAME_MAX)
    self:addChild(self.nameEntry)
    self.nameY = y

    -- readings are drawn in prerender, between the name and the range
    self.readingY = y + ROW + PAD
    y = self.readingY + (lineHeight() + 2) * 4 + PAD

    local lo, hi, invert = Signals.sensorRange(sensor)
    self.rangeY = y
    self.minSlider = ISSliderPanel:new(PAD + 70, y, inner - SLIDER_SPARE, ROW, self, self.onMinChange)
    self.minSlider:initialise()
    self:addChild(self.minSlider)
    self.minSlider:setValues(0, 100, 1, 10)
    self.minSlider:setCurrentValue(lo, true)
    y = y + ROW + 4
    self.maxSlider = ISSliderPanel:new(PAD + 70, y, inner - SLIDER_SPARE, ROW, self, self.onMaxChange)
    self.maxSlider:initialise()
    self:addChild(self.maxSlider)
    self.maxSlider:setValues(0, 100, 1, 10)
    self.maxSlider:setCurrentValue(hi, true)
    self.min, self.max = lo, hi
    y = y + ROW + 4

    self.invertBox = ISTickBox:new(PAD, y, inner, ROW, "", nil, nil)
    self.invertBox:initialise()
    self.invertBox:instantiate()
    self.invertBox:addOption(getText("IGUI_WaterPipesSensorInvert"))
    self.invertBox:setSelected(1, invert)
    self:addChild(self.invertBox)
    self.shown = { name = self.nameEntry:getText(), min = lo, max = hi, invert = invert == true }
    y = y + ROW + PAD

    local third = (inner - PAD * 2) / 3
    self.batteryButton = ISButton:new(PAD, y, third * 2 + PAD, ROW, "", self, self.onBattery)
    self.batteryButton:initialise()
    self:addChild(self.batteryButton)
    self.applyButton = ISButton:new(PAD + (third + PAD) * 2, y, third, ROW,
        getText("IGUI_WaterPipesSensorApply"), self, self.onApply)
    self.applyButton:initialise()
    self:addChild(self.applyButton)
    y = y + ROW + PAD

    self.listY = y
    y = y + lineHeight() + 4
    self.list = ISScrollingListBox:new(PAD, y, inner, LIST_HEIGHT)
    self.list:initialise()
    self.list:instantiate()
    self.list.itemheight = lineHeight() + 6
    self.list.font = UIFont.Small
    self.list.drawBorder = true
    self:addChild(self.list)
    y = y + LIST_HEIGHT + PAD

    self.linkButton = ISButton:new(PAD, y, third, ROW, getText("IGUI_WaterPipesSensorLink"), self, self.onLink)
    self.linkButton:initialise()
    self:addChild(self.linkButton)
    self.unlinkButton = ISButton:new(PAD + third + PAD, y, third, ROW,
        getText("IGUI_WaterPipesSensorUnlink"), self, self.onUnlink)
    self.unlinkButton:initialise()
    self:addChild(self.unlinkButton)
    self.closeButton = ISButton:new(PAD + (third + PAD) * 2, y, third, ROW, getText("IGUI_WaterPipesClose"),
        self, self.onCloseButton)
    self.closeButton:initialise()
    self:addChild(self.closeButton)

    self:setHeight(y + ROW + PAD)
end

function WaterPipesSensorWindow:requestSnapshot()
    Signals.request(self.playerObj, "snapshot", { x = self.px, y = self.py, z = self.pz })
end

-- Has the player changed a field since the window last showed the sensor's settings?
function WaterPipesSensorWindow:isEdited()
    local shown = self.shown
    return self.nameEntry:getText() ~= shown.name or self.min ~= shown.min or self.max ~= shown.max
        or self.invertBox:isSelected(1) ~= shown.invert
end

-- The sensor's settings into the fields: another player's change, or what the server kept of ours.
function WaterPipesSensorWindow:showSettings(snapshot)
    local lo, hi = tonumber(snapshot.min), tonumber(snapshot.max)
    if not lo or not hi then
        return
    end
    local name = snapshot.name or ""
    self.nameEntry:setText(name)
    self.minSlider:setCurrentValue(lo, true)
    self.maxSlider:setCurrentValue(hi, true)
    self.min, self.max = lo, hi
    self.invertBox:setSelected(1, snapshot.invert == true)
    self.shown = { name = name, min = lo, max = hi, invert = snapshot.invert == true }
end

function WaterPipesSensorWindow:onMinChange(value)
    self.min = value
end

function WaterPipesSensorWindow:onMaxChange(value)
    self.max = value
end

function WaterPipesSensorWindow:onApply()
    -- the answer shows what the server kept (it swaps a minimum above the maximum)
    self.applying = true
    Signals.request(self.playerObj, "configure", {
        x = self.px, y = self.py, z = self.pz,
        name = self.nameEntry:getText(),
        min = self.min, max = self.max,
        invert = self.invertBox:isSelected(1),
    })
end

-- The fullest battery the player carries.
local function bestBattery(playerObj)
    local inventory = playerObj and playerObj:getInventory()
    local items = inventory and inventory:getAllTypeRecurse(Signals.BATTERY_ITEM)
    local best, bestCharge = nil, 0
    for i = 0, (items and items:size() or 0) - 1 do
        local item = items:get(i)
        local charge = item:getCurrentUsesFloat()
        if charge > bestCharge then
            best, bestCharge = item, charge
        end
    end
    return best
end

function WaterPipesSensorWindow:onBattery()
    local sensor = self:resolveSensor()
    if not sensor then
        return
    end
    local playerObj = self.playerObj
    if Signals.batteryCharge(sensor) then
        Signals.request(playerObj, "removeBattery", { x = self.px, y = self.py, z = self.pz })
        return
    end
    local battery = bestBattery(playerObj)
    if battery then
        Signals.request(playerObj, "insertBattery",
            { x = self.px, y = self.py, z = self.pz, itemId = battery:getID() })
    end
end

function WaterPipesSensorWindow:onLink()
    if WaterPipesSignalLinkCursor and not self.selecting then
        WaterPipesSignalLinkCursor.start(self.playerObj, self)
    end
end

function WaterPipesSensorWindow:onUnlink()
    local row = self.list.items[self.list.selected]
    local link = row and row.item
    if not link then
        return
    end
    Signals.request(self.playerObj, "unlink",
        { x = self.px, y = self.py, z = self.pz, vx = link.x, vy = link.y, vz = link.z, kind = link.kind })
end

function WaterPipesSensorWindow:onCloseButton()
    self:close()
end

-- Is this receiver linked to the sensor (selection mode asks).
function WaterPipesSensorWindow:isLinked(x, y, z, kind)
    for _, link in ipairs(self.links) do
        if link.x == x and link.y == y and link.z == z and link.kind == kind then
            return true
        end
    end
    return false
end

function WaterPipesSensorWindow:setSnapshot(snapshot)
    self.loaded = true
    if self.applying or not self:isEdited() then
        self:showSettings(snapshot)
    end
    self.applying = false
    self.links = snapshot.links or {}
    local selected = self.list.selected
    self.list:clear()
    for _, link in ipairs(self.links) do
        local distance = math.floor(math.sqrt((link.x - self.px) ^ 2 + (link.y - self.py) ^ 2) + 0.5)
        local state
        if not link.switchOn then
            state = getText("IGUI_WaterPipesSensorValveSwitchOff")
        elseif link.on then
            state = getText("IGUI_WaterPipesSensorValveOpen")
        else
            state = getText("IGUI_WaterPipesSensorValveClosed")
        end
        self.list:addItem(getText("IGUI_WaterPipesSensorValveRow",
            link.name or getText("IGUI_WaterPipesSensorValveUnnamed"), tostring(distance), state), link)
    end
    if selected and selected > 0 and selected <= #self.list.items then
        self.list.selected = selected
    end
    if self.selecting and WaterPipesSignalLinkCursor then
        WaterPipesSignalLinkCursor.refresh()
    end
end

function WaterPipesSensorWindow.onSnapshot(snapshot)
    local win = snapshot and WaterPipesSensorWindow.instances[Signals.key(snapshot.x, snapshot.y, snapshot.z)]
    if win then
        win:setSnapshot(snapshot)
    end
end

function WaterPipesSensorWindow.onSensorChanged(args)
    local win = args and WaterPipesSensorWindow.instances[Signals.key(args.x, args.y, args.z)]
    if win then
        win:requestSnapshot()
    end
end

-- The server will not let this player work the sensor (gone, out of reach, someone else's safehouse).
function WaterPipesSensorWindow.onRefused(args)
    local win = args and args.sensor and WaterPipesSensorWindow.instances[Signals.key(args.x, args.y, args.z)]
    if win then
        win:close()
    end
end

-- Whether the player carries a battery, looked up twice a second rather than every frame.
local BATTERY_CHECK_MS = 500

function WaterPipesSensorWindow:carriesBattery()
    local now = getTimestampMs()
    if not self.batteryCheckedAt or now - self.batteryCheckedAt > BATTERY_CHECK_MS then
        self.batteryCheckedAt = now
        self.hasBattery = bestBattery(self.playerObj) ~= nil
    end
    return self.hasBattery
end

local REASONS = { atMin = true, atMax = true, towardMax = true, towardMin = true, noEdge = true, noCrop = true,
                  noPower = true }

function WaterPipesSensorWindow:prerender()
    ISCollapsableWindow.prerender(self)
    local sensor = self:resolveSensor()
    if not sensor then
        return
    end
    local modData = sensor:getModData()
    local step = lineHeight() + 2
    local name = Signals.sensorName(sensor)
    self.title = name or getText("IGUI_WaterPipesSensorTitle")

    self:drawText(getText("IGUI_WaterPipesSensorName"), PAD, self.nameY + 4, COL_LABEL.r, COL_LABEL.g, COL_LABEL.b, 1,
        UIFont.Small)

    local y = self.readingY
    local reading = modData[Signals.SENSOR_READING_KEY]
    if type(reading) == "number" then
        self:drawText(getText("IGUI_WaterPipesSensorReading", percent(reading)), PAD, y, 1, 1, 1, 1, UIFont.Small)
    else
        self:drawText(getText("IGUI_WaterPipesSensorNoCrop"), PAD, y, COL_DIM.r, COL_DIM.g, COL_DIM.b, 1, UIFont.Small)
    end
    y = y + step

    local on = Signals.sensorState(sensor) == "on"
    local col = on and COL_ON or COL_OFF
    self:drawText(getText(on and "IGUI_WaterPipesSensorSignalOn" or "IGUI_WaterPipesSensorSignalOff"), PAD, y,
        col.r, col.g, col.b, 1, UIFont.Small)
    y = y + step
    local reason = modData[Signals.SENSOR_REASON_KEY]
    if REASONS[reason] then
        self:drawText(getText("IGUI_WaterPipesSensorReason_" .. reason), PAD, y, COL_DIM.r, COL_DIM.g, COL_DIM.b, 1,
            UIFont.Small)
    end
    y = y + step

    local charge = Signals.batteryCharge(sensor)
    local source = modData[Signals.SENSOR_SOURCE_KEY]
    local power
    if source == "grid" then
        power = getText("IGUI_WaterPipesSensorPowerGrid")
    elseif charge and charge > 0 then
        power = getText("IGUI_WaterPipesSensorPowerBattery", percent(charge * 100))
    elseif charge then
        power = getText("IGUI_WaterPipesSensorPowerFlat")
    else
        power = getText("IGUI_WaterPipesSensorPowerNone")
    end
    self:drawText(power, PAD, y, COL_LABEL.r, COL_LABEL.g, COL_LABEL.b, 1, UIFont.Small)

    -- each end says what reaching it does, following the invert box before it is applied
    local invert = self.invertBox:isSelected(1)
    local valueX = PAD + 70 + (self.width - PAD * 2 - SLIDER_SPARE) + PAD
    self:drawText(getText("IGUI_WaterPipesSensorMin"), PAD, self.rangeY + 4, COL_LABEL.r, COL_LABEL.g, COL_LABEL.b, 1,
        UIFont.Small)
    self:drawText(percent(self.min) .. " - " .. getText(invert and "IGUI_WaterPipesSensorOff"
        or "IGUI_WaterPipesSensorOn"), valueX, self.rangeY + 4, 1, 1, 1, 1, UIFont.Small)
    self:drawText(getText("IGUI_WaterPipesSensorMax"), PAD, self.rangeY + ROW + 8, COL_LABEL.r, COL_LABEL.g,
        COL_LABEL.b, 1, UIFont.Small)
    self:drawText(percent(self.max) .. " - " .. getText(invert and "IGUI_WaterPipesSensorOn"
        or "IGUI_WaterPipesSensorOff"), valueX, self.rangeY + ROW + 8, 1, 1, 1, 1, UIFont.Small)

    self.batteryButton:setTitle(getText(charge and "IGUI_WaterPipesSensorRemoveBattery"
        or "IGUI_WaterPipesSensorInsertBattery"))
    self.batteryButton:setEnable(charge ~= nil or self:carriesBattery())

    local header = getText("IGUI_WaterPipesSensorLinked")
    if self.selecting then
        header = getText("IGUI_WaterPipesSensorSelecting")
    elseif self.loaded and #self.links == 0 then
        header = getText("IGUI_WaterPipesSensorNoLinks")
    end
    self.linkButton:setEnable(not self.selecting)
    self:drawText(header, PAD, self.listY, COL_LABEL.r, COL_LABEL.g, COL_LABEL.b, 1, UIFont.Small)
    self.unlinkButton:setEnable(self.list.items[self.list.selected] ~= nil)
end

function WaterPipesSensorWindow:update()
    ISCollapsableWindow.update(self)
    local player = self.playerObj
    if not player or not self:resolveSensor() then
        self:close()
        return
    end
    local reach = Signals.CONFIG_REACH
    if math.floor(player:getZ()) ~= self.pz or math.abs(player:getX() - self.px) > reach + 1
        or math.abs(player:getY() - self.py) > reach + 1 then
        self:close()
    end
end

function WaterPipesSensorWindow:close()
    WaterPipesSensorWindow.instances[Signals.key(self.px, self.py, self.pz)] = nil
    if self.cursor and WaterPipesSignalLinkCursor then
        WaterPipesSignalLinkCursor.stop(self.playerObj)
    end
    self:setVisible(false)
    self:removeFromUIManager()
    ISCollapsableWindow.close(self)
end

function WaterPipesSensorWindow:onKeyRelease(key)
    if key == Keyboard.KEY_ESCAPE and not self.selecting then
        self:close()
    end
end

return WaterPipesSensorWindow
