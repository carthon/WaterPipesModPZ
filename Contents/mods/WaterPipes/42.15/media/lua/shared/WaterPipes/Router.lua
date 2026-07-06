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

-- ===== Direction (IN -> OUT) =====
-- The stored direction is the OUT side. Isometric mapping matches PipeAutotile: N=-y, E=+x, S=+y, W=-x.
local DIR_OFFSET = {
    N = { dx = 0, dy = -1 },
    E = { dx = 1, dy = 0 },
    S = { dx = 0, dy = 1 },
    W = { dx = -1, dy = 0 },
}

local function isValidDirection(dir)
    return dir == "N" or dir == "E" or dir == "S" or dir == "W"
end

function Router.getDirection(worldObject)
    local modData = getModData(worldObject)
    local dir = modData and modData[Constants.ROUTER_DIRECTION_KEY]
    if isValidDirection(dir) then
        return dir
    end
    return Constants.ROUTER_DEFAULT_DIRECTION
end

-- {dx,dy} of the OUT side; the IN side is the opposite.
function Router.getOutOffset(worldObject)
    return DIR_OFFSET[Router.getDirection(worldObject)]
end

function Router.nextDirection(dir)
    if dir == "N" then return "E" end
    if dir == "E" then return "S" end
    if dir == "S" then return "W" end
    return "N"
end

-- Authoritative callers only (server / single-player).
function Router.setDirection(worldObject, dir)
    local modData = getModData(worldObject)
    if not modData then
        return
    end
    modData[Constants.ROUTER_DIRECTION_KEY] = isValidDirection(dir) and dir or Constants.ROUTER_DEFAULT_DIRECTION
    if worldObject.transmitModData then
        pcall(worldObject.transmitModData, worldObject)
    end
end

return Router
