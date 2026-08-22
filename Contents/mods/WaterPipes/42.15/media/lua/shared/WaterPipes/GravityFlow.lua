WaterPipes = WaterPipes or {}
WaterPipes.GravityFlow = WaterPipes.GravityFlow or {}

require "WaterPipes/ContainerAdapter"

local Adapter = WaterPipes.ContainerAdapter
local GravityFlow = WaterPipes.GravityFlow

-- Gravity settle for one weakly-connected component (single fluid; mixed networks are skipped by the
-- caller). Water only moves DOWN across floors and pools at the lowest containers first ("relocation"):
-- we group the component's containers by z-level and pour the component's total water into the LOWEST
-- level first (equalized within the level), overflowing upward. A single-floor component is exactly the
-- classic per-pool equalization, so nothing changes on one floor. Conservation-safe: exactly the input
-- water is written back, capped at total capacity.
--
-- This is the v1 model. Tap-side reachability (a consumer reached only by climbing stays dry) lives in
-- the gravity-aware NetworkAccess pass, where it actually matters; here we only relocate stored water.

function GravityFlow.settle(containers, totalWater, fluidTypeName)
    if not containers or #containers == 0 then
        return
    end

    -- Group containers by z-level.
    local levels = {}
    local zList = {}
    for _, descriptor in ipairs(containers) do
        local z = descriptor.z
        local level = levels[z]
        if not level then
            level = { capacity = 0, descriptors = {} }
            levels[z] = level
            zList[#zList + 1] = z
        end
        level.capacity = level.capacity + math.max(descriptor.capacity or 0, 0)
        level.descriptors[#level.descriptors + 1] = descriptor
    end

    -- Lowest floor first.
    table.sort(zList)

    -- `carry` is what a vessel did not take, rolled into the next one: either because it clamped at
    -- its capacity, or because the change was too small for Adapter.writeDescriptorWaterAmount to
    -- think it worth a write. Without it this relocation would not conserve -- a settle that declines
    -- a hundredth of a litre per vessel is a hundredth of a litre lost, every ten in-game minutes,
    -- forever. It is a relocation, so the litres have to come out the same as they went in.
    local remaining = math.max(totalWater or 0, 0)
    local carry = 0
    for _, z in ipairs(zList) do
        local level = levels[z]
        local give = math.min(remaining, level.capacity)
        local ratio = level.capacity > 0 and (give / level.capacity) or 0
        for _, descriptor in ipairs(level.descriptors) do
            local capacity = math.max(descriptor.capacity or 0, 0)
            local share = capacity * ratio
            local target = math.min(math.max(share + carry, 0), capacity)
            local before = math.max(descriptor.waterAmount or 0, 0)

            local ok, wrote = Adapter.writeDescriptorWaterAmount(descriptor, target, fluidTypeName)
            local landed = before
            if ok and wrote then
                landed = target
                descriptor.waterAmount = target
                descriptor.fluidType = target > 0 and fluidTypeName or nil
            end
            carry = carry + share - landed
        end
        remaining = remaining - give
    end
end

return GravityFlow
