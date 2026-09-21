WaterPipes = WaterPipes or {}

require "WaterPipes/ContainerAdapter"
require "WaterPipes/Logger"
require "WaterPipes/PipeObjectUtils"

local Adapter = WaterPipes.ContainerAdapter
local Logger = WaterPipes.Logger
local PipeObjectUtils = WaterPipes.PipeObjectUtils

-- A vessel the player hangs on a pipe is added CLIENT-side and replicated, and the server's Lua is
-- never told: on wptest the client logged OnObjectAdded for the amphora at 8049:11561:0 and the server
-- logged nothing at all, so its taps kept serving 1 L until the ten-minute drift verifier caught up
-- 158 s later. A forced network tick did not help either, because nothing had dropped the server's
-- classification of that tile. So the client says so, and the server refreshes that network.
--
-- The tile must already carry pipe, which is what keeps this off the path of every object dropped
-- anywhere in the world, and the object must actually hold fluid.

local function announce(object)
    if not object or not object.getSquare then
        return
    end
    local ok, square = pcall(object.getSquare, object)
    if not ok or not square then
        return
    end
    if not PipeObjectUtils.getPipeOnSquare(square) then
        return
    end
    -- Read off the object itself, never off the tile memo: the memo is the thing this event says is
    -- out of date.
    if not Adapter.getWorldFluidKind(object) then
        return
    end

    local player = getPlayer and getPlayer() or nil
    if not player then
        return
    end
    sendClientCommand(player, "WaterPipes", "vesselChanged",
        { x = square:getX(), y = square:getY(), z = square:getZ() })
end

local function onVesselChanged(object)
    local ok, err = pcall(announce, object)
    if not ok then
        Logger.error("Vessel notice failed: " .. tostring(err))
    end
end

if Events and isClient and isClient() then
    if Events.OnObjectAdded then
        Events.OnObjectAdded.Add(onVesselChanged)
    end
    if Events.OnObjectAboutToBeRemoved then
        Events.OnObjectAboutToBeRemoved.Add(onVesselChanged)
    end
end
