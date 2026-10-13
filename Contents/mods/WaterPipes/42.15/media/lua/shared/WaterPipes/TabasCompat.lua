WaterPipes = WaterPipes or {}
WaterPipes.TabasCompat = WaterPipes.TabasCompat or {}

-- Take A Bath And Shower, the one mod whose fixtures are handled apart. Everything this mod knows about
-- it lives here, asked of TABAS itself and inside pcall: without TABAS, or if TABAS_Iso moves, nothing
-- here applies and its fixtures are treated like any other.
local TabasCompat = WaterPipes.TabasCompat

local MOD_ID = "TakeABathAndShowerNew"
local modules = {}              -- name -> module, or false when unavailable

local function isActive()
    if TabasCompat._active == nil then
        local ok, active = pcall(function() return getActivatedMods():contains(MOD_ID) end)
        TabasCompat._active = ok and active == true
    end
    return TabasCompat._active
end

local function load(name)
    if modules[name] == nil then
        local ok, module = pcall(require, name)
        modules[name] = ok and type(module) == "table" and module or false
    end
    return modules[name] or nil
end

local function ask(fn)
    local ok, answer = pcall(fn)
    return ok and answer == true
end

local function isBath(object)
    local iso = isActive() and load("TABAS_Iso")
    return iso ~= nil and object ~= nil and ask(function() return iso.isBathObject(object) end)
end

local function isShower(object)
    local iso = isActive() and load("TABAS_Iso")
    return iso ~= nil and object ~= nil and ask(function() return iso.isShowerObject(object, true) end)
end

-- A bath or shower TABAS manages: it reads modData canBeWaterPiped=true as "not piped".
function TabasCompat.isFixture(object)
    return isBath(object) or isShower(object)
end

return TabasCompat
