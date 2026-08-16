-- Water pipes are B42 entities and are intentionally NOT moveable "pick up" items: moving an
-- entity through the moveable system corrupts MP sync (duplicated sinks, failed pickups). Instead
-- they are removed via the vanilla "Disassemble" option, which is driven by the tiles' Material.
--
-- The pipe tiles use the custom material "WaterPipesScrap"; here we register the disassemble
-- action itself (hammer, low Woodwork). The material RETURN is deliberately NOT registered here:
-- a scrap table is keyed by tile material and cannot know whether the pipe was built from a metal
-- pipe or a clay segment. The mod's own removal hook reads the pipe's modData and drops the right
-- item at the old 90% (see WaterPipeSystem's pendingMaterialDrops).

require "Moveables/ISMoveableDefinitions"

local function registerWaterPipeScrap()
    local defs = moveableDefinitions
    if not defs and ISMoveableDefinitions and ISMoveableDefinitions.getInstance then
        defs = ISMoveableDefinitions:getInstance()
    end
    if not defs or not defs.addScrapDefinition then
        return
    end

    defs.addScrapDefinition("WaterPipesScrap", { "Base.Hammer" }, {}, Perks.Woodwork, 75, "Hammering", true)
end

if Events and Events.OnGameBoot then
    Events.OnGameBoot.Add(registerWaterPipeScrap)
else
    registerWaterPipeScrap()
end
