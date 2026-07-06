WaterPipes = WaterPipes or {}
WaterPipes.Router = WaterPipes.Router or {}

require "WaterPipes/Constants"
require "WaterPipes/PipeObjectUtils"

local Constants = WaterPipes.Constants
local PipeObjectUtils = WaterPipes.PipeObjectUtils
local Router = WaterPipes.Router

-- A fluid router is a floor pipe flagged in modData. It is a network BOUNDARY: the graph and the
-- gravity traversal never conduct through it, so the IN-side pipes and OUT-side pipes stay two
-- separate networks. The active IN->container->OUT transfer (with the direction) lands in step 4.

local function getModData(worldObject)
    if not worldObject or not worldObject.getModData then
        return nil
    end
    local ok, modData = pcall(worldObject.getModData, worldObject)
    return ok and modData or nil
end

function Router.isRouter(worldObject)
    local modData = getModData(worldObject)
    return modData and modData[Constants.ROUTER_MODDATA_KEY] == true or false
end

function Router.spriteFor(worldObject)
    -- Single placeholder sprite for now; direction-specific arrow sprites arrive with the art.
    return Constants.ROUTER_SPRITE
end

function Router.findOnSquare(square)
    if not square then
        return nil
    end
    for _, worldObject in ipairs(PipeObjectUtils.getPipeObjectsOnSquare(square)) do
        if Router.isRouter(worldObject) then
            return worldObject
        end
    end
    return nil
end

function Router.hasRouterOnSquare(square)
    return Router.findOnSquare(square) ~= nil
end

return Router
