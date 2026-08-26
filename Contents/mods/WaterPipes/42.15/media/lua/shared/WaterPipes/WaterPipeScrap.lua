-- Water pipes are B42 entities and are intentionally NOT moveable "pick up" items: moving an entity
-- through the moveable system corrupts MP sync. They are removed via the vanilla "Disassemble" option,
-- driven by the tiles' Material -- CanScrap + Material -- which this registers. Two materials: the
-- pipes come apart with a hammer, the welded purifier tank with a blow torch and a welding mask.
--
-- ===== Why there is a zero-chance return item =====
--
-- Vanilla will not offer "Disassemble" for a material whose scrap definition has no return items:
-- ISMoveableDefinitions.isScrapDefinitionValid() is literally `#returnItems > 0`. Registering the
-- action without one does not mean "dismantles for nothing", it means the option never appears.
--
-- But the return cannot live here either. A scrap table is keyed by TILE material, and metal and clay
-- pipes share their tiles; only the pipe's modData knows which it was, and they do not pay out the same
-- (metal 90%, clay nothing). So this entry exists purely to make the definition valid, at a chance of
-- zero so vanilla never pays it -- addScrapItemToList rolls ZombRandFloat(0,101) < chance, which no
-- roll satisfies at 0, mod-cheat path included. With no `unusableItem`, vanilla's "gave nothing, hand
-- over scrap instead" fallback stays quiet too.
--
-- The real payout is WaterPipeSystem's schedulePipeRemoval, which reads the modData.
-- MetalPipe stays the named item even though it is never rolled: the dynamic-recipe UI reads
-- returnItems[1] when a definition has no static items.

require "Moveables/ISMoveableDefinitions"

-- Zero, and it has to stay zero. Anything above it double-pays every metal pipe (once from vanilla,
-- once from our removal hook) and hands a metal pipe back for a clay one.
local NEVER_ROLLED = 0

-- Must match the Material stamped on tank cells 36-39 by tools/texturepack/edit_tiles.py.
local PURIFIER_MATERIAL = "WaterPipesPurifierScrap"

-- Bonus added to the dismantle chance vanilla SHOWS the player (10 + MetalWelding*10 + this, capped at
-- 100). Pinned to certainty on purpose: that number only ever scales the loot roll -- the object comes
-- off the tile either way -- so anything below 100 would advertise a failure that cannot happen. What
-- the tank actually pays out is rolled per item by the removal hook.
local ALWAYS_SUCCEEDS = 90

local function registerWaterPipeScrap()
    local defs = moveableDefinitions
    if not defs and ISMoveableDefinitions and ISMoveableDefinitions.getInstance then
        defs = ISMoveableDefinitions:getInstance()
    end
    if not defs or not defs.addScrapDefinition or not defs.addScrapItem then
        return
    end

    defs.addScrapDefinition("WaterPipesScrap", { "Base.Hammer" }, {}, Perks.Woodwork, 75, "Hammering", true)
    defs.addScrapItem("WaterPipesScrap", "Base.MetalPipe", 1, NEVER_ROLLED)

    -- The purifier tank. Tools mirror the vanilla metal appliances it is cropped from: a blow torch
    -- with fuel left in it, plus a welding mask (worn or carried; the tag covers modded ones).
    --
    -- Zero-chance again, and for a SECOND reason on top of the one above: the tank is a 2x2 object, and
    -- vanilla pays a multi-sprite scrap once per footprint tile, which would refund it four times over.
    -- The real payout is WaterPipeSystem's purifier removal hook, once per tank, whichever quadrant the
    -- player clicked. UnusableMetal is the one thing vanilla itself hands over: it only appears when
    -- nothing else rolled, which here is always, and without it a dismantle that produces literally
    -- nothing is reported to the player as having FAILED.
    defs.addScrapDefinition(PURIFIER_MATERIAL, { "Base.BlowTorch" },
        { "Tag.WeldingMask", "Base.WeldingMask" }, Perks.MetalWelding, 1000, "BlowTorch", true,
        ALWAYS_SUCCEEDS, "Base.UnusableMetal")
    defs.addScrapItem(PURIFIER_MATERIAL, "Base.SheetMetal", 1, NEVER_ROLLED)
end

if Events and Events.OnGameBoot then
    Events.OnGameBoot.Add(registerWaterPipeScrap)
else
    registerWaterPipeScrap()
end
