WaterPipes = WaterPipes or {}
WaterPipes.Debug = WaterPipes.Debug or {}

local Logger = WaterPipes.Logger
local State = WaterPipes.State

function WaterPipes.Debug.dumpState()
    local state = State.ensure()
    local count = 0
    for _ in pairs(state.pipes or {}) do
        count = count + 1
    end

    Logger.log("Registered pipes: " .. tostring(count))

    for key, pipeData in pairs(state.pipes or {}) do
        Logger.log("Pipe " .. key .. " -> (" .. tostring(pipeData.x) .. "," .. tostring(pipeData.y) .. "," .. tostring(pipeData.z) .. ")")
    end
end

local function onGameStart()
    Logger.log("Client debug loaded")
end

if Events and Events.OnGameStart then
    Events.OnGameStart.Add(onGameStart)
end
