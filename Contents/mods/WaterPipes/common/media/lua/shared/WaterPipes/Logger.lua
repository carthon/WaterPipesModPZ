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
