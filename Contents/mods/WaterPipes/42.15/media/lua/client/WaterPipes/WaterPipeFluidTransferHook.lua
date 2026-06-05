require "Fluids/ISFluidTransferAction"
require "WaterPipes/EndpointFluidSource"
require "WaterPipes/EndpointPlumbing"

-- The vanilla "Transfer Fluids" UI moves liquid at the FluidContainer level
-- (FluidContainer.Transfer) and only calls owner:sync(); it never raises the IsoObject-level
-- OnWaterAmountChange event. Without this hook the network would only catch up on the next
-- periodic refresh (up to 1 minute later). Here we reconcile the involved plumbed endpoint
-- immediately when the transfer action completes. syncForEndpoint is authoritative-guarded,
-- so on a multiplayer client this is a no-op and the server reconciles instead.

WaterPipes = WaterPipes or {}
WaterPipes.FluidTransferHook = WaterPipes.FluidTransferHook or {}

local FluidSource = WaterPipes.EndpointFluidSource
local EndpointPlumbing = WaterPipes.EndpointPlumbing
local Hook = WaterPipes.FluidTransferHook

Hook.originalComplete = Hook.originalComplete or ISFluidTransferAction.complete

local function reconcileContainerOwner(fluidContainer)
    if not fluidContainer or not fluidContainer.getOwner then
        return
    end

    local ok, owner = pcall(fluidContainer.getOwner, fluidContainer)
    if ok and owner and EndpointPlumbing.isPlumbed(owner) then
        pcall(FluidSource.syncForEndpoint, owner)
    end
end

function ISFluidTransferAction:complete()
    local result = Hook.originalComplete(self)

    -- Either side of the transfer could be a plumbed endpoint; reconcile whichever applies.
    reconcileContainerOwner(self.source)
    reconcileContainerOwner(self.target)

    return result
end
