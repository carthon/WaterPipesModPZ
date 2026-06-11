-- Water pipes are B42 entities and are intentionally NOT moveable "pick up" items: moving an
-- entity through the moveable system corrupts MP sync (duplicated sinks, failed pickups). Instead
-- they are removed via the vanilla "Disassemble" option, which is driven by the tiles' Material.
--
-- The pipe tiles use the custom material "WaterPipesScrap"; here we register what disassembling it
-- yields: a Metal Pipe (the build material) at a 90% chance, with a hammer and low Woodwork.

require "Moveables/ISMoveableDefinitions"

local function registerWaterPipeScrap()
    local defs = moveableDefinitions
    if not defs and ISMoveableDefinitions and ISMoveableDefinitions.getInstance then
        defs = ISMoveableDefinitions:getInstance()
    end
    if not defs or not defs.addScrapDefinition or not defs.addScrapItem then
        return
    end

    defs.addScrapDefinition("WaterPipesScrap", { "Base.Hammer" }, {}, Perks.Woodwork, 75, "Hammering", true)
    defs.addScrapItem("WaterPipesScrap", "Base.MetalPipe", 1, 90)
end

if Events and Events.OnGameBoot then
    Events.OnGameBoot.Add(registerWaterPipeScrap)
else
    registerWaterPipeScrap()
end
