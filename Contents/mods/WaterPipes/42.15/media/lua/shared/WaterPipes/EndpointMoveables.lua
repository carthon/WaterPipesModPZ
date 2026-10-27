-- Plumbed fixtures in vanilla's moveables action. A plumbed fixture carries a tank we attached, sized
-- to the whole network and filled with its water; vanilla moves an object's components onto the item it
-- picks up, so without this the player walked off with a container as big as the network, full.
--
-- Picked up: unplumbed first (water drawn is charged to the network), then the tank comes off.
-- Placed: an item picked up before this fix still carries the tank; it is dropped before vanilla
-- moves it onto the new object.

require "Moveables/ISMoveableSpriteProps"
require "WaterPipes/EndpointFluidSource"
require "WaterPipes/EndpointObjects"
require "WaterPipes/EndpointPlumbing"
require "WaterPipes/Logger"

WaterPipes = WaterPipes or {}
WaterPipes.EndpointMoveables = WaterPipes.EndpointMoveables or {}

local EndpointMoveables = WaterPipes.EndpointMoveables
local EndpointObjects = WaterPipes.EndpointObjects
local EndpointPlumbing = WaterPipes.EndpointPlumbing
local FluidSource = WaterPipes.EndpointFluidSource
local Logger = WaterPipes.Logger

local function authoritative()
    return not (isClient and isClient())
end

-- Our tanks are always input-locked, and no vanilla water-piped tile ships a tank of its own.
local function carriesStrayTank(spriteProps, item)
    if not spriteProps or not spriteProps:has(IsoFlagType.waterPiped) then
        return false
    end
    local fluidContainer = item and item.getFluidContainer and item:getFluidContainer() or nil
    return fluidContainer ~= nil and fluidContainer:isInputLocked() == true
end

-- Water drawn since the last refresh is charged to the network by the unplumb, before the tank goes.
local function releaseFixture(object)
    if not object or not EndpointObjects.isEndpointCandidate(object) then
        return
    end
    if EndpointPlumbing.isPlumbed(object) then
        EndpointPlumbing.unplumb(object)
    end
    FluidSource.detachTank(object)
end

-- Hooks vanilla once its classes are there; the same wrapping twice would chain.
function EndpointMoveables.install()
    if EndpointMoveables.installed or not ISMoveableSpriteProps then
        return false
    end
    EndpointMoveables.installed = true

    -- The outer call, not pickUpMoveableInternal: for a multi-tile fixture vanilla empties each tank
    -- before the inner one runs, and unplumbing then would charge that water to the network.
    local pickUp = ISMoveableSpriteProps.pickUpMoveable
    function ISMoveableSpriteProps:pickUpMoveable(_character, _square, _createItem, _forceAllow)
        if authoritative() and self.isMoveable and instanceof(_square, "IsoGridSquare") then
            if self.isMultiSprite then
                for _, member in ipairs(self:getSpriteGridInfo(_square, true) or {}) do
                    if not member.sprInstance then
                        releaseFixture(member.object)
                    end
                end
            else
                local object, sprInstance = self:findOnSquare(_square, self.spriteName)
                if not sprInstance then
                    releaseFixture(object)
                end
            end
        end
        return pickUp(self, _character, _square, _createItem, _forceAllow)
    end

    local place = ISMoveableSpriteProps.placeMoveableInternal
    function ISMoveableSpriteProps:placeMoveableInternal(_character, _square, _item, _spriteName)
        if authoritative() and carriesStrayTank(self.spriteProps, _item) and GameEntityFactory then
            Logger.log(("EndpointMoveables: dropped a %.2f L network tank from a placed %s")
                :format(_item:getFluidContainer():getCapacity(), tostring(_spriteName)))
            GameEntityFactory.RemoveComponentType(_item, ComponentType.FluidContainer)
        end
        return place(self, _character, _square, _item, _spriteName)
    end
    return true
end

if not EndpointMoveables.install() and Events and Events.OnGameBoot then
    Events.OnGameBoot.Add(EndpointMoveables.install)
end
