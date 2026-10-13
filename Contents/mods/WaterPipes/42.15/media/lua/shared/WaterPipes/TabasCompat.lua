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

-- Per sprite name: TABAS_Iso answers from sprite-name tables it builds at startup. Keyed by name, not by
-- object, so a sprite TABAS swaps in place is asked about again; a lookup that failed is not kept.
local bySprite = {}

local function spriteName(object)
    local ok, name = pcall(function() return object:getSprite():getName() end)
    return ok and name or nil
end

-- A bath or shower TABAS manages: it reads modData canBeWaterPiped=true as "not piped".
function TabasCompat.isFixture(object)
    if not object or not isActive() then
        return false
    end
    local iso = load("TABAS_Iso")
    if not iso then
        return false
    end
    local name = spriteName(object)
    local known = name and bySprite[name]
    if known ~= nil then
        return known
    end
    local okBath, bath = pcall(iso.isBathObject, object)
    local okShower, shower = pcall(iso.isShowerObject, object, true)
    local answer = (okBath and bath == true) or (okShower and shower == true)
    if name and (answer or (okBath and okShower)) then
        bySprite[name] = answer
    end
    return answer
end

return TabasCompat
