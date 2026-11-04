WaterPipes = WaterPipes or {}
WaterPipes.ElectricOverhaulCompat = WaterPipes.ElectricOverhaulCompat or {}

require "WaterPipes/World"

-- Electric Overhaul, when it runs: the pump, the purifier and the moisture sensor join its cable networks
-- as loads, and a tile its cable feeds counts as powered. Everything here goes through its public
-- ElectricOverhaulAPI, guarded: without it nothing applies and power is the tile's electricity, as always.
local Compat = WaterPipes.ElectricOverhaulCompat
local World = WaterPipes.World

-- What each piece draws while on, in the game's generator scale (Electric Overhaul's fridge is 0.08).
-- Resolved at call time: this file loads before Pump, Purifier and Signals.
Compat.KINDS = {
    {
        kind = "waterPipesPump", name = "IGUI_WaterPipesPumpName", draw = 0.08,
        classify = function(obj) return WaterPipes.Pump.isPump(obj) end,
        isOn = function(obj) return WaterPipes.Pump.isEnabled(obj) end,
    },
    {
        kind = "waterPipesPurifier", name = "IGUI_WaterPipesPurifierWindowTitle", draw = 0.05,
        classify = function(obj) return WaterPipes.Purifier.isPurifier(obj) end,
    },
    {
        kind = "waterPipesMoistureSensor", name = "IGUI_WaterPipesSensorTitle", draw = 0.005,
        classify = function(obj) return WaterPipes.Signals.isSensor(obj) end,
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

local kindsRegistered, sensorHooked = false, false

-- Each part once, on whichever of file load and OnGameBoot finds what it needs first.
function Compat.register()
    local found = api()
    if not found then
        return
    end
    if not kindsRegistered then
        kindsRegistered = true
        for _, spec in ipairs(Compat.KINDS) do
            local ok, accepted, why = pcall(found.registerLoad, spec)
            if not (ok and accepted) then
                print("[WaterPipes] Electric Overhaul refused " .. spec.kind .. ": "
                    .. tostring(ok and why or accepted))
            end
        end
    end
    local signals = WaterPipes.Signals
    if not sensorHooked and signals and signals.addPowerSource then
        sensorHooked = true
        signals.addPowerSource(Compat.poweredAt)
    end
end

-- True while Electric Overhaul's cable feeds a piece on this square.
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

-- A piece on this square was switched: Electric Overhaul reads its draw again now.
function Compat.refresh(square)
    local found = api()
    if not found then
        return
    end
    local x, y, z = World.coordsOf(square)
    if x then
        pcall(found.refreshAt, x, y, z)
    end
end

Compat.register()
if Events and Events.OnGameBoot then
    Events.OnGameBoot.Add(Compat.register)
end

return Compat
