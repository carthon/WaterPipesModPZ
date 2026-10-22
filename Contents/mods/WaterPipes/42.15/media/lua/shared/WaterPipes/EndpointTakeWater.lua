require "TimedActions/ISTakeWaterAction"
require "WaterPipes/EndpointPlumbing"

WaterPipes = WaterPipes or {}
WaterPipes.EndpointTakeWater = WaterPipes.EndpointTakeWater or {}

local EndpointPlumbing = WaterPipes.EndpointPlumbing
local TakeWater = WaterPipes.EndpointTakeWater

-- A plumbed fixture serves exactly what its network holds. A mod that replaces transferFluid keeps
-- its behaviour on every other fixture.
local function currentTransfer()
    return type(ISTakeWaterAction) == "table" and rawget(ISTakeWaterAction, "transferFluid") or nil
end

TakeWater.vanillaTransfer = TakeWater.vanillaTransfer or currentTransfer()

local wrappers = {}

local function wrap(current)
    local function wrapper(self, amount)
        if EndpointPlumbing.isPlumbed(self.waterObject) then
            return TakeWater.vanillaTransfer(self, amount)
        end
        return current(self, amount)
    end
    wrappers[wrapper] = true
    return wrapper
end

function TakeWater.install()
    local current = currentTransfer()
    if type(current) ~= "function" or type(TakeWater.vanillaTransfer) ~= "function" or wrappers[current] then
        return
    end
    ISTakeWaterAction.transferFluid = wrap(current)
end

TakeWater.install()

if Events then
    -- Again once every mod has loaded: some replace it as late as OnInitGlobalModData.
    if Events.OnServerStarted then
        Events.OnServerStarted.Add(TakeWater.install)
    end
    if Events.OnGameStart then
        Events.OnGameStart.Add(TakeWater.install)
    end
end

return TakeWater
