WaterPipes = WaterPipes or {}
WaterPipes.Logger = WaterPipes.Logger or {}

local Logger = WaterPipes.Logger

function Logger.log(message)
    print("[WaterPipes] " .. tostring(message))
end

function Logger.warn(message)
    print("[WaterPipes][WARN] " .. tostring(message))
end

function Logger.error(message)
    print("[WaterPipes][ERROR] " .. tostring(message))
end

-- Which build a log came from: bug reports are matched against it.
local function logVersion()
    local ok, version = pcall(function() return getModInfoByID("waterpipes"):getModVersion() end)
    local side = (isServer and isServer()) and "server"
        or ((isClient and isClient()) and "client" or "singleplayer")
    Logger.log("Water Pipes " .. tostring(ok and version or "unknown") .. " running on " .. side)
end

if Events then
    if Events.OnServerStarted then
        Events.OnServerStarted.Add(logVersion)
    end
    if Events.OnGameStart then
        Events.OnGameStart.Add(logVersion)
    end
end
