WaterPipes = WaterPipes or {}
WaterPipes.ElectricOverhaulCompat = WaterPipes.ElectricOverhaulCompat or {}

require "WaterPipes/World"

-- Electric Overhaul, when it runs: the pump and the purifier join its cable as loads, the shut-off valve as
-- a receiver (IN, S, R, T: open, close, toggle), the moisture sensor as a sensor (IN, OUT: current on OUT
-- while its signal is on). A tile its cable feeds counts as powered. Everything goes through its public
-- ElectricOverhaulAPI, guarded: without it nothing applies and power is the tile's electricity, as always.
local Compat = WaterPipes.ElectricOverhaulCompat
local World = WaterPipes.World

-- The vanilla Battery a sensor runs on. Electric Overhaul keeps it for when its cable carries voltages.
Compat.SENSOR_BATTERY_VOLTS = 1.5

-- What an order from the cable does to a valve: a hand on its switch (SignalBus.setReceiverSwitch), so its
-- moisture sensors keep deciding as they do for a hand. False when it cannot be done now (tile away, or a
-- client): Electric Overhaul gives it again when the tile loads.
function Compat.orderValve(x, y, z, order)
    local Signals, Bus, Valve = WaterPipes.Signals, WaterPipes.SignalBus, WaterPipes.Valve
    if not (Signals and Bus and Bus.setReceiverSwitch and Valve) or (isClient and isClient()) then
        return false
    end
    local square = World.squareAt(x, y, z)
    local valve = square and Valve.findOnSquare(square)
    if not valve then
        return false
    end
    local receiver = Signals.ValveReceiver:new(valve)
    local open = order == "on" or (order == "toggle" and not receiver:isSwitchOn())
    Bus.setReceiverSwitch(receiver, open)
    return true
end

-- What each piece draws, in the game's generator scale (Electric Overhaul's fridge is 0.08); `as` the API
-- function it registers with, then the one it falls back to on an Electric Overhaul without it. Resolved at
-- call time: this file loads before Pump, Purifier, Valve and Signals.
Compat.KINDS = {
    {
        as = { "registerLoad" },
        kind = "waterPipesPump", name = "IGUI_WaterPipesPumpName", draw = 0.08,
        classify = function(obj) return WaterPipes.Pump.isPump(obj) end,
        isOn = function(obj) return WaterPipes.Pump.isEnabled(obj) end,
    },
    {
        as = { "registerLoad" },
        kind = "waterPipesPurifier", name = "IGUI_WaterPipesPurifierWindowTitle", draw = 0.05,
        classify = function(obj) return WaterPipes.Purifier.isPurifier(obj) end,
    },
    {
        as = { "registerReceiver" },
        kind = "waterPipesValve", name = "IGUI_WaterPipesValveName", draw = 0.005,
        classify = function(obj) return WaterPipes.Valve.isValve(obj) end,
        onCommand = function(x, y, z, order) return Compat.orderValve(x, y, z, order) end,
    },
    {
        as = { "registerSensor", "registerLoad" },
        kind = "waterPipesMoistureSensor", name = "IGUI_WaterPipesSensorTitle", draw = 0.005,
        voltage = Compat.SENSOR_BATTERY_VOLTS,
        classify = function(obj) return WaterPipes.Signals.isSensor(obj) end,
        isActive = function(obj)
            local Signals = WaterPipes.Signals
            return Signals.modDataOf(obj)[Signals.SENSOR_STATE_KEY] == "on"
        end,
        hasBattery = function(obj) return (WaterPipes.Signals.batteryCharge(obj) or 0) > 0 end,
    },
}

local function api()
    local found = ElectricOverhaulAPI
    if type(found) == "table" and found.VERSION == 1 then
        return found
    end
    return nil
end

function Compat.isActive()
    return api() ~= nil
end

local function registerKind(found, spec)
    for _, name in ipairs(spec.as) do
        local register = found[name]
        if type(register) == "function" then
            local ok, accepted, why = pcall(register, spec)
            if not (ok and accepted) then
                print("[WaterPipes] Electric Overhaul refused " .. spec.kind .. ": " .. tostring(ok and why or accepted))
            end
            return
        end
    end
end

-- A tile on Electric Overhaul's cable whose piece changed: it reads the piece again now.
function Compat.refreshAt(x, y, z)
    local found = api()
    if found and x then
        pcall(found.refreshAt, x, y, z)
    end
end

function Compat.refresh(square)
    Compat.refreshAt(World.coordsOf(square))
end

local kindsRegistered, signalsHooked = false, false

-- Each part once, on whichever of file load and OnGameBoot finds what it needs first.
function Compat.register()
    local found = api()
    if not found then
        return
    end
    if not kindsRegistered then
        kindsRegistered = true
        for _, spec in ipairs(Compat.KINDS) do
            registerKind(found, spec)
        end
    end
    local signals = WaterPipes.Signals
    if not signalsHooked and signals and signals.addPowerSource and signals.addSensorListener then
        signalsHooked = true
        signals.addPowerSource(Compat.poweredAt)
        signals.addSensorListener(Compat.refreshAt)
    end
end

-- True while Electric Overhaul's cable feeds a piece on this square (a sensor: current on its IN).
function Compat.poweredAt(square)
    local found = api()
    if not found then
        return false
    end
    local x, y, z = World.coordsOf(square)
    if not x then
        return false
    end
    local ok, powered = pcall(found.isPoweredAt, x, y, z)
    return ok and powered == true
end

Compat.register()
if Events and Events.OnGameBoot then
    Events.OnGameBoot.Add(Compat.register)
end

return Compat
