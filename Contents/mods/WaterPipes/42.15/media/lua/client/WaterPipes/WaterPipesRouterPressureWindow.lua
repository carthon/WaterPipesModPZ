-- Router pressure-limit dialog: a slider for feeling out a value plus a typed field for hitting an
-- exact one. The old context submenu only offered steps of 5, which is too coarse for a setting the
-- player tunes against real thresholds (a drip emitter bursts above 15.0, a sprinkler needs 20.0).
--
-- Nothing is committed until Apply, so dragging the slider does not spam the server with commands.

require "ISUI/ISCollapsableWindow"
require "RadioCom/ISUIRadio/ISSliderPanel"
require "WaterPipes/Constants"
require "WaterPipes/NetworkAccess"
require "WaterPipes/Router"

WaterPipes = WaterPipes or {}

local Constants = WaterPipes.Constants
local NetworkAccess = WaterPipes.NetworkAccess
local Router = WaterPipes.Router

WaterPipesRouterPressureWindow = ISCollapsableWindow:derive("WaterPipesRouterPressureWindow")
WaterPipesRouterPressureWindow.instances = WaterPipesRouterPressureWindow.instances or {}

local PAD = 10
local ROW = 24

-- Reading the live pressure means flooding the network, which is far too much work to redo on every
-- frame of a window that just sits open. Once every this many update ticks is still instant to a
-- player turning a dial.
local LIVE_REFRESH_TICKS = 30

local function lineHeight()
    return getTextManager():getFontHeight(UIFont.Small)
end

local function keyForSquare(x, y, z)
    return tostring(x) .. ":" .. tostring(y) .. ":" .. tostring(z)
end

-- The router can be destroyed or picked up while the window is open, so every use re-resolves it
-- from the world rather than holding a stale reference.
function WaterPipesRouterPressureWindow:resolveRouter()
    local cell = getCell and getCell() or nil
    local square = cell and cell.getGridSquare and cell:getGridSquare(self.px, self.py, self.pz) or nil
    return square and Router.findOnSquare(square) or nil
end

-- The head arriving at the valve, measured on its IN side. Asking on the router's own tile would see
-- both sides at once; asking from the IN side sees only the upstream network, because a router is
-- crossed one way and this is the wrong way round.
function WaterPipesRouterPressureWindow:readInletHead()
    local router = self:resolveRouter()
    local out = router and Router.getOutOffset(router)
    local cell = getCell and getCell() or nil
    if not out or not cell or not cell.getGridSquare then
        return nil
    end
    local inlet = cell:getGridSquare(self.px - out.dx, self.py - out.dy, self.pz)
    return inlet and NetworkAccess.getPressureAtSquare(inlet, Constants.PRESSURE_KIND_TAP) or nil
end

function WaterPipesRouterPressureWindow.openFor(routerObject)
    local square = routerObject and routerObject.getSquare and routerObject:getSquare() or nil
    if not square then
        return nil
    end
    local x, y, z = square:getX(), square:getY(), square:getZ()
    local key = keyForSquare(x, y, z)

    local existing = WaterPipesRouterPressureWindow.instances[key]
    if existing then
        existing:addToUIManager()
        existing:setVisible(true)
        existing:bringToTop()
        return existing
    end

    local w, h = 300, 224
    local px = (getCore():getScreenWidth() - w) / 2
    local py = (getCore():getScreenHeight() - h) / 2
    local win = WaterPipesRouterPressureWindow:new(px, py, w, h, x, y, z)
    win:initialise()
    win:addToUIManager()
    WaterPipesRouterPressureWindow.instances[key] = win
    return win
end

function WaterPipesRouterPressureWindow:new(x, y, width, height, px, py, pz)
    local o = ISCollapsableWindow:new(x, y, width, height)
    setmetatable(o, self)
    self.__index = self
    o.px, o.py, o.pz = px, py, pz
    o.title = getText("IGUI_WaterPipesRouterPressureTitle")
    o.resizable = false
    o:setWantKeyEvents(true)
    -- Working value, only pushed to the world on Apply. nil means "no limit".
    o.value = nil
    -- Live inlet head, refreshed on a timer rather than per frame (see LIVE_REFRESH_TICKS).
    o.inletHead = nil
    o.ticks = 0
    return o
end

function WaterPipesRouterPressureWindow:createChildren()
    ISCollapsableWindow.createChildren(self)

    local top = self:titleBarHeight() + PAD
    local innerWidth = self.width - PAD * 2

    self.slider = ISSliderPanel:new(PAD, top + ROW, innerWidth - 70, ROW, self, self.onSliderChange)
    self.slider:initialise()
    self:addChild(self.slider)
    self.slider:setValues(0, Constants.ROUTER_PRESSURE_MAX, 0.5, 0.5)

    -- Deliberately NOT setOnlyNumbers: that flag is only ever read back by its own getter, so it
    -- filters nothing here, and wherever it IS honoured it would likely reject the decimal point and
    -- make values like 12.5 impossible to type. We validate on commit instead.
    self.entry = ISTextEntryBox:new("", PAD + innerWidth - 60, top + ROW, 60, ROW)
    self.entry:initialise()
    self.entry:instantiate()
    self.entry.onCommandEntered = function() self:onEntryCommitted() end
    self:addChild(self.entry)

    local buttonWidth = (innerWidth - PAD * 2) / 3
    local buttonY = self.height - ROW - PAD

    self.noLimitButton = ISButton:new(PAD, buttonY, buttonWidth, ROW,
        getText("IGUI_WaterPipesRouterPressureNoLimit"), self, self.onNoLimit)
    self.noLimitButton:initialise()
    self:addChild(self.noLimitButton)

    self.applyButton = ISButton:new(PAD + buttonWidth + PAD, buttonY, buttonWidth, ROW,
        getText("IGUI_WaterPipesRouterPressureApply"), self, self.onApply)
    self.applyButton:initialise()
    self:addChild(self.applyButton)

    self.closeButton = ISButton:new(PAD + (buttonWidth + PAD) * 2, buttonY, buttonWidth, ROW,
        getText("IGUI_WaterPipesClose"), self, self.onCloseButton)
    self.closeButton:initialise()
    self:addChild(self.closeButton)

    -- Seed from whatever the router currently holds.
    self:setValue(Router.getPressureCeiling(self:resolveRouter()))
    self.inletHead = self:readInletHead()
end

-- Single place that keeps the working value, the slider and the typed field agreeing.
function WaterPipesRouterPressureWindow:setValue(value, skipSlider, skipEntry)
    if value then
        value = math.max(0, math.min(value, Constants.ROUTER_PRESSURE_MAX))
    end
    self.value = value

    if not skipSlider and self.slider then
        self.slider:setCurrentValue(value or 0, true)
    end
    if not skipEntry and self.entry then
        self.entry:setText(value and string.format("%.1f", value) or "")
    end
end

function WaterPipesRouterPressureWindow:onSliderChange(newValue)
    self:setValue(newValue, true, false)
end

function WaterPipesRouterPressureWindow:onEntryCommitted()
    local text = self.entry:getInternalText() or ""
    if text:match("^%s*$") then
        -- A blank field is the natural way to say "no limit".
        self:setValue(nil)
        return
    end

    local typed = tonumber(text)
    if not typed then
        -- Typo rather than intent: put the field back to the working value instead of silently
        -- throwing the limit away.
        self:setValue(self.value)
        return
    end

    -- Rewrite the field too, so a clamped or reformatted value is visible before Apply.
    self:setValue(typed)
end

function WaterPipesRouterPressureWindow:commit(value)
    local router = self:resolveRouter()
    if not router then
        self:close()
        return
    end
    WaterPipes.ContextMenu.setRouterPressure(getPlayer(), router,
        value or Constants.ROUTER_PRESSURE_UNSET)
end

function WaterPipesRouterPressureWindow:onApply()
    -- Read the field first: a player who typed a number and clicked Apply without pressing Enter
    -- still gets the value they can see.
    self:onEntryCommitted()
    self:commit(self.value)
    self:close()
end

function WaterPipesRouterPressureWindow:onNoLimit()
    self:setValue(nil)
    self:commit(nil)
    self:close()
end

function WaterPipesRouterPressureWindow:onCloseButton()
    self:close()
end

function WaterPipesRouterPressureWindow:prerender()
    ISCollapsableWindow.prerender(self)

    local top = self:titleBarHeight() + PAD
    self:drawText(getText("IGUI_WaterPipesRouterPressureHint"), PAD, top - 2, 0.8, 0.8, 0.8, 1, UIFont.Small)

    local y = top + ROW * 2 + 6
    local step = lineHeight() + 2

    -- Live reading of what is actually set on the router, so Apply's effect is visible.
    local current = Router.getPressureCeiling(self:resolveRouter())
    local currentText = current and string.format("%.1f", current)
        or getText("IGUI_WaterPipesRouterPressureNoLimit")
    self:drawText(getText("IGUI_WaterPipesRouterPressureCurrent", currentText),
        PAD, y, 1, 1, 1, 1, UIFont.Small)
    y = y + step + 4

    -- What the valve is actually working with right now. Without this the player is setting a limit
    -- blind: a ceiling of 15 on a line that only carries 4 does nothing at all, and there was no way
    -- to tell from in here.
    local inlet = self.inletHead
    if not inlet then
        self:drawText(getText("IGUI_WaterPipesRouterPressureNoSupply"), PAD, y, 0.85, 0.6, 0.6, 1, UIFont.Small)
        return
    end

    self:drawText(getText("IGUI_WaterPipesRouterPressureInlet", string.format("%.1f", inlet)),
        PAD, y, 0.8, 0.9, 1, 1, UIFont.Small)
    y = y + step

    -- The outlet is the working value, not the committed one, so dragging the slider previews what
    -- Apply would leave the branch running at.
    local outlet = inlet
    if self.value and self.value < outlet then
        outlet = self.value
    end
    self:drawText(getText("IGUI_WaterPipesRouterPressureOutlet", string.format("%.1f", outlet)),
        PAD, y, 0.8, 0.9, 1, 1, UIFont.Small)
end

function WaterPipesRouterPressureWindow:update()
    ISCollapsableWindow.update(self)

    -- Close if the router is gone, or if the player walked away, matching the purifier window.
    local player = getPlayer()
    if not player or not self:resolveRouter() then
        self:close()
        return
    end

    self.ticks = (self.ticks or 0) + 1
    if self.ticks % LIVE_REFRESH_TICKS == 0 then
        self.inletHead = self:readInletHead()
    end

    local dx = math.abs(player:getX() - self.px)
    local dy = math.abs(player:getY() - self.py)
    if math.floor(player:getZ()) ~= self.pz or dx > Constants.GAUGE_READ_DISTANCE + 1
        or dy > Constants.GAUGE_READ_DISTANCE + 1 then
        self:close()
    end
end

function WaterPipesRouterPressureWindow:close()
    WaterPipesRouterPressureWindow.instances[keyForSquare(self.px, self.py, self.pz)] = nil
    self:setVisible(false)
    self:removeFromUIManager()
    ISCollapsableWindow.close(self)
end

function WaterPipesRouterPressureWindow:onKeyRelease(key)
    if key == Keyboard.KEY_ESCAPE then
        self:close()
    end
end

return WaterPipesRouterPressureWindow
