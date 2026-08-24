WaterPipes = WaterPipes or {}
WaterPipes.Constants = WaterPipes.Constants or {}

local Constants = WaterPipes.Constants

Constants.MOD_DATA_KEY = "WaterPipes"
Constants.STATE_VERSION = 1

Constants.NODE_KIND_PIPE = "pipe"
Constants.NODE_KIND_CONTAINER = "container"

Constants.REDISTRIBUTION_INTERVAL_MINUTES = 10

Constants.PIPE_OBJECT_NAME = "Water Pipe"
Constants.PIPE_BUILD_ENTITY_NAME = "WaterPipe"
Constants.PIPE_BUILD_ENTITY_FULL_NAME = "WaterPipes.WaterPipe"
Constants.PIPE_ITEM_TYPE = "Base.Pipe"
Constants.PIPE_TOOL_TYPE = "Base.PipeWrench"
Constants.PIPE_MODDATA_KEY = "waterpipesPipe"
Constants.PIPE_SURFACE_MODDATA_KEY = "waterpipesSurface"
Constants.PIPE_AXIS_MODDATA_KEY = "waterpipesAxis"
-- What the pipe was built FROM. Only set when it is not the default metal ("clay" today), so
-- every pipe built before this key existed reads as metal -- which is what it was.
-- Dismantling reads it to decide whether anything comes back at all: metal is salvage, clay is
-- spent the moment it is laid (see WaterPipeSystem's schedulePipeRemoval).
Constants.PIPE_MATERIAL_MODDATA_KEY = "waterpipesMaterial"
Constants.PIPE_MATERIAL_CLAY = "clay"
Constants.PIPE_CLAY_ITEM_TYPE = "Base.ClayPipeSegment"
Constants.PLUMBED_ENDPOINT_MODDATA_KEY = "waterpipesEndpointPlumbed"
Constants.PLUMBED_ENDPOINT_SOURCE_MODDATA_KEY = "waterpipesEndpointSource"
-- Snapshot of the endpoint's own FluidContainer before we overwrite it with the network mirror,
-- so we can restore the fixture to its original state on unplumb.
Constants.ENDPOINT_ORIGINAL_FLUID_KEY = "waterpipesEndpointOriginalFluid"

-- Generator fuel consumers: a plumbed generator pulls Petrol from the network into its tank.
Constants.GENERATOR_PLUMBED_MODDATA_KEY = "waterpipesGeneratorPlumbed"
Constants.GENERATOR_FUEL_FLUID = "Petrol"
-- Auto-refuel defaults (fractions of max fuel). Overridable PER-SAVE via Sandbox Options
-- (WaterPipes.GeneratorRefuelThreshold / GeneratorRefuelTarget); these remain the fallback.
Constants.GENERATOR_REFUEL_THRESHOLD = 0.25   -- start refuelling once fuel drops below this
Constants.GENERATOR_REFUEL_TARGET = 1.0       -- fill the tank up to this fraction
Constants.ADAPTER_SOURCE_MODDATA_KEY = "waterpipesAdapterSource"
Constants.ADAPTER_SOURCE_ENDPOINT_X_KEY = "waterpipesAdapterEndpointX"
Constants.ADAPTER_SOURCE_ENDPOINT_Y_KEY = "waterpipesAdapterEndpointY"
Constants.ADAPTER_SOURCE_ENDPOINT_Z_KEY = "waterpipesAdapterEndpointZ"
Constants.ADAPTER_SOURCE_ENDPOINT_INDEX_KEY = "waterpipesAdapterEndpointIndex"
Constants.ADAPTER_SOURCE_LAST_SYNC_AMOUNT_KEY = "waterpipesAdapterLastSyncAmount"
Constants.ADAPTER_SOURCE_OBJECT_NAME = "Water Pipes Adapter Source"
Constants.ADAPTER_SOURCE_MAX_CAPACITY = 600
-- Endpoint-owned FluidContainer mirror (replaces the hidden adapter object).
-- The plumbed endpoint (sink/tap) carries its own FluidContainer that mirrors the
-- connected network, so no phantom world object is needed.
Constants.ENDPOINT_FLUID_LAST_SYNC_KEY = "waterpipesEndpointLastSync"
Constants.ENDPOINT_FLUID_SYNCING_KEY = "waterpipesEndpointSyncing"
Constants.PIPE_SURFACE_FLOOR = "floor"
Constants.PIPE_SURFACE_WALL = "wall"
Constants.PIPE_SURFACE_WALLCOVER = "wallcover"   -- decorative vertical pipe drawn on a wall
Constants.PIPE_AXIS_EW = "ew"
Constants.PIPE_AXIS_NS = "ns"
-- Sprites exported by this mod's waterpipes tileset.
-- The current build cursor still exposes 4 placement modes only:
-- floor EW, floor NS, wall EW and wall NS.
-- Keep these IDs aligned with the sprites actually present in
-- media/texturepacks/waterpipes.pack.
Constants.PIPE_FLOOR_WEST_SPRITE = "waterpipes_01_8"   -- straight E/W
Constants.PIPE_FLOOR_NORTH_SPRITE = "waterpipes_01_9"  -- straight N/S
Constants.PIPE_WALL_WEST_SPRITE = "waterpipes_01_24"
Constants.PIPE_WALL_NORTH_SPRITE = "waterpipes_01_25"
-- Floor auto-connect sprites (generated tileset). Directions: N=-y, E=+x, S=+y, W=-x.
Constants.PIPE_FLOOR_CORNER_NE_SPRITE = "waterpipes_01_10"
Constants.PIPE_FLOOR_CORNER_ES_SPRITE = "waterpipes_01_11"
Constants.PIPE_FLOOR_CORNER_SW_SPRITE = "waterpipes_01_12"
Constants.PIPE_FLOOR_CORNER_WN_SPRITE = "waterpipes_01_13"
Constants.PIPE_FLOOR_T_NOW_SPRITE = "waterpipes_01_14"  -- T junction, no West arm
Constants.PIPE_FLOOR_T_NOE_SPRITE = "waterpipes_01_15"  -- T junction, no East arm
Constants.PIPE_FLOOR_T_NOS_SPRITE = "waterpipes_01_16"  -- T junction, no South arm
Constants.PIPE_FLOOR_T_NON_SPRITE = "waterpipes_01_17"  -- T junction, no North arm
Constants.PIPE_FLOOR_CROSS_SPRITE = "waterpipes_01_18"
Constants.PIPE_FLOOR_END_W_SPRITE = "waterpipes_01_19"
Constants.PIPE_FLOOR_END_N_SPRITE = "waterpipes_01_21"
Constants.PIPE_FLOOR_END_E_SPRITE = "waterpipes_01_22"
Constants.PIPE_FLOOR_END_S_SPRITE = "waterpipes_01_23"
-- Wall risers: floor stub toward an edge + vertical climb. PZ tiles only have N and W walls
-- (S/E walls belong to the neighbouring tile), so risers exist only for the North and West walls.
Constants.PIPE_WALL_RISER_N_SPRITE = "waterpipes_01_24"
Constants.PIPE_WALL_RISER_W_SPRITE = "waterpipes_01_25"
Constants.PIPE_RISER_MODDATA_KEY = "waterpipesRiser"
Constants.PIPE_RISER_EDGE_MODDATA_KEY = "waterpipesRiserEdge"
-- Concealed ("invisible") pipe variant: full network functionality, but rendered with a fully
-- transparent tile client-side. The flag is baked in at build time (modData, synced) and never
-- toggled at runtime, so no extra network sync is needed -- each client just paints it transparent.
Constants.PIPE_HIDDEN_MODDATA_KEY = "waterpipesHidden"
Constants.PIPE_HIDDEN_SPRITE = "waterpipes_01_20"   -- fully transparent tile in the tileset
-- Purifier: a NON-pipe tank placed on a router tile that turns the connected network's tainted water
-- clean while it is "working" (electric-only: the tile must have power). The tier is baked in at build
-- time (modData, synced). The legacy filter/fire tier strings are still recognised by getTier so old
-- saves keep working, but only the electric tier is buildable now.
Constants.PURIFIER_MODDATA_KEY = "waterpipesPurifier"       -- value = tier string below
Constants.PURIFIER_TIER_FILTER = "filter"
Constants.PURIFIER_TIER_FIRE = "fire"
Constants.PURIFIER_TIER_ELECTRIC = "electric"
-- Filter condition (maintenance): the carbon/cloth filter medium wears out with USE, not idle time.
-- Every unit of tainted water actually converted to clean spends FILTER_WEAR_PER_UNIT of condition.
-- At 0 the purifier can no longer clean tainted water (clean water still passes) until it is repaired
-- (Charcoal + RippedSheets). Condition lives in the anchor's modData, server-authoritative, synced.
Constants.PURIFIER_FILTER_CONDITION_KEY = "waterpipesFilterCondition"
Constants.PURIFIER_FILTER_MAX_CONDITION = 100              -- % scale; a fresh/repaired filter starts here
-- Base wear per unit of tainted water filtered. Scaled PER-SAVE by the Sandbox Option
-- WaterPipes.PurifierFilterWear (percentage: 100 = this base, 0 = never wears); this stays the fallback.
Constants.PURIFIER_FILTER_WEAR_PER_UNIT = 0.02            -- % lost per unit of tainted water filtered
Constants.PURIFIER_FILTER_WARN_CONDITION = 25             -- UI turns amber at/below this (repair soon)
-- Repair kit: consumed by the "Repair Filter" timed action to restore condition to MAX.
-- A repair entry matches by `tag`, by one `type`, or by a list of interchangeable `types`.
--
-- CHARCOAL IS MATCHED BY TAG, NEVER BY ITEM NAME. Vanilla ships two charcoals -- Base.Charcoal,
-- which you scavenge, and Base.CharcoalCrafted, which you burn yourself in a pit -- and both carry
-- base:charcoal, as does any charcoal another mod adds. A type list can only ever name the ones we
-- knew about when we wrote it; the tag catches the rest for free, and it is the same thing the build
-- recipes ask for (tags[base:charcoal]), so the two halves of the mod agree on what charcoal is.
--
-- `displayType` is the item the tooltip NAMES. Presentation only -- nothing is ever matched against
-- it -- and it exists because a tag has no name a player would recognise.
Constants.PURIFIER_REPAIR_ITEMS = {
    { tag = "CHARCOAL", displayType = "Base.Charcoal", count = 1 },
    { type = "Base.RippedSheets", count = 2 },
}

-- The item types a repair entry MATCHES, whichever shape it was written in. Empty for a tag-only
-- entry, which is correct: it matches by tag and by nothing else.
function Constants.repairTypes(entry)
    return entry and (entry.types or { entry.type }) or {}
end

-- The item types a repair entry is DESCRIBED by in the UI. Same list, except a tag-only entry falls
-- back to its displayType so the tooltip can name something instead of showing an empty requirement.
function Constants.repairLabelTypes(entry)
    local types = Constants.repairTypes(entry)
    if #types == 0 and entry and entry.displayType then
        return { entry.displayType }
    end
    return types
end

-- An entry may name an ItemTag member, which catches anything carrying that tag -- including
-- charcoal added by other mods, which an explicit list never will.
--
-- Resolved by NAME because Lua cannot spell an enum member it was handed as a string. ItemTag.CHARCOAL
-- does exist -- checked against the ItemTag enum in the shipped projectzomboid.jar, alongside the
-- base:charcoal tag on both vanilla charcoal items -- so this resolves on a stock B42.
--
-- Still guarded, and now loud about it. A tag-only entry that fails to resolve matches NOTHING, which
-- would leave the filter permanently unrepairable with no clue why; a line in console.txt is the
-- difference between a five-minute diagnosis and a bug report nobody can reproduce.
local warnedMissingTags = {}
function Constants.repairTag(entry)
    local name = entry and entry.tag
    if not name then
        return nil
    end

    local value = nil
    if ItemTag then
        local ok, resolved = pcall(function() return ItemTag[name] end)
        value = ok and resolved or nil
    end

    if not value and not warnedMissingTags[name] then
        warnedMissingTags[name] = true
        if WaterPipes.Logger and WaterPipes.Logger.warn then
            WaterPipes.Logger.warn("ItemTag." .. tostring(name)
                .. " did not resolve -- any repair entry matching only that tag will never be satisfied")
        end
    end

    return value
end

-- How many of `entry` the inventory holds, by type and by tag.
--
-- The MAXIMUM of the two, never the sum. An entry naming both would otherwise count the same item
-- twice -- a tagged item is usually in the type list too -- and let a repair start with half the
-- materials. A tag-only entry (charcoal) just returns the tag count.
function Constants.countRepairItems(inventory, entry)
    if not inventory or not entry then
        return 0
    end

    local byType = 0
    for _, itemType in ipairs(Constants.repairTypes(entry)) do
        byType = byType + (inventory:getCountTypeRecurse(itemType) or 0)
    end

    local tag = Constants.repairTag(entry)
    if not tag then
        return byType
    end

    local ok, list = pcall(inventory.getAllTagRecurse, inventory, tag, ArrayList.new())
    local byTag = (ok and list and list.size) and list:size() or 0
    return math.max(byType, byTag)
end

-- One item matching `entry`, ready to be consumed. Types first: they are the exact things the recipe
-- names, and the tag is the wider net.
function Constants.takeRepairItem(inventory, entry)
    if not inventory or not entry then
        return nil
    end

    for _, itemType in ipairs(Constants.repairTypes(entry)) do
        local item = inventory:getFirstTypeRecurse(itemType)
        if item then
            return item
        end
    end

    local tag = Constants.repairTag(entry)
    if tag then
        local ok, item = pcall(inventory.getFirstTagRecurse, inventory, tag)
        if ok and item then
            return item
        end
    end

    return nil
end
Constants.PURIFIER_REPAIR_TIME = 150                       -- timed-action ticks (build is 200)
-- Purifier-container is a NON-pipe object placed on a router tile. It holds two internal buffers
-- (modData): IN (tainted intake) and OUT (clean output). The router drives intake -> convert -> output.
Constants.PURIFIER_IN_AMOUNT_KEY = "waterpipesPurIn"
Constants.PURIFIER_IN_TAINTED_KEY = "waterpipesPurInTainted"
Constants.PURIFIER_OUT_AMOUNT_KEY = "waterpipesPurOut"
-- Did the purifier actually move any fluid on the last server tick? The readout used to infer this
-- from the buffer levels, which got it wrong in the one case the player most wants to see: a tank
-- sitting full while it is busy pushing clean water out reads as "full", and full was reported as
-- Stopped. The server knows the truth, so it writes it down instead.
Constants.PURIFIER_PROCESSING_KEY = "waterpipesPurBusy"
Constants.PURIFIER_BUFFER_CAPACITY = 50
-- Rates are per IN-GAME MINUTE (the server sub-steps them by elapsed game-time each tick, so throughput
-- is the same whatever the framerate). Intake is FASTER than convert on purpose: the IN buffer fills
-- faster than the filter processes it, so it visibly holds a level instead of draining to 0.
--
-- There is no OUTPUT rate any more. The OUT buffer is storage belonging to the clean network now, not
-- a tank that pushes into it, so its level simply evens out with whatever else is on that side -- the
-- way two connected vessels do. Throughput is unchanged: the convert rate is still what limits how
-- fast clean water appears, and that was always the real bottleneck.
Constants.PURIFIER_INTAKE_RATE = 20
Constants.PURIFIER_CONVERT_RATE = 10
-- Electric purifier tank: a 2x2 multi-tile object. The vanilla industry_02 cylinder is split into
-- four perspective quadrants (industry 72/73/74/75), tinted electric-blue and packed into atlas
-- cells 36-39. The entity script (WaterPurifierElectric, face S) lays them on the footprint:
--   (0,0) top->36   (1,0) right->37   (0,1) left->39   (1,1) body/front->38
Constants.PURIFIER_TANK_TOP_SPRITE = "waterpipes_01_36"    -- industry 74, back tile (0,0)
Constants.PURIFIER_TANK_RIGHT_SPRITE = "waterpipes_01_37"  -- industry 75, tile (1,0)
Constants.PURIFIER_TANK_LEFT_SPRITE = "waterpipes_01_39"   -- industry 72, tile (0,1)
Constants.PURIFIER_TANK_BODY_SPRITE = "waterpipes_01_38"   -- industry 73, front tile (1,1)
-- The anchor/front body sprite doubles as the purifier's identity sprite.
Constants.PURIFIER_ELECTRIC_SPRITE = Constants.PURIFIER_TANK_BODY_SPRITE
-- Fluid router: a directional floor pipe that acts as a BOUNDARY between two separate networks (the
-- IN side and the OUT side never merge), bridged only through a container on its tile. Baked in at
-- build time (modData, synced). The IN->OUT direction is set later via the context menu (step 4).
Constants.ROUTER_MODDATA_KEY = "waterpipesRouter"
Constants.ROUTER_DIRECTION_KEY = "waterpipesRouterDir"   -- "N"/"E"/"S"/"W" = the OUT side
Constants.ROUTER_SPRITE = "waterpipes_01_13"             -- placeholder until the arrow art is packed
Constants.ROUTER_DEFAULT_DIRECTION = "N"
Constants.ROUTER_TRANSFER_RATE = 30                      -- max fluid units moved IN->OUT per minute tick
Constants.ADAPTER_SOURCE_SPRITE = "carpentry_02_54"
Constants.ADAPTER_SOURCE_HIDDEN_SPRITE = "waterpipes_01_20"
Constants.MAX_FINITE_FLUID_CAPACITY = 9999

-- ===== Pressure model =====
-- Pressure is measured in METRES OF WATER COLUMN (m.c.a.), the unit real irrigation uses:
-- 1 m.c.a. = 0.098 bar. Municipal mains run 20-40, a garden sprinkler needs ~20, gravity drip
-- works at 1-2. Keeping the unit real means every constant below can be sanity-checked against
-- a plumbing table instead of being a made-up number.
--
-- The pressure a source delivers to a consumer is:
--     P = CONTAINER_BASE_PRESSURE
--       + PRESSURE_PER_LEVEL * (z_source - z_consumer)     -- falling gains, climbing costs
--       - friction(consumer) * hops                        -- distance always costs
--
-- The elevation term telescopes (it depends only on the endpoints, not the route), so the only
-- path-dependent term is friction, which is uniform per hop. Minimising loss is therefore just
-- minimising hop count -- the existing BFS with a distance counter, no Dijkstra needed. This
-- stops holding once pumps add head at a node (they break the telescoping); see the pump phase.
Constants.PRESSURE_PER_LEVEL = 3.0          -- a PZ floor is ~2.4-3 m tall; 1 m of water = 0.098 bar
Constants.CONTAINER_BASE_PRESSURE = 1.0     -- a full ~1 m tall barrel pushes 1 m.c.a. at its base
-- Friction scales with flow squared (Darcy-Weisbach), so a barely-open tap loses far less head per
-- tile than a sprinkler running wide open. Modelling that is what keeps existing bases alive: a tap
-- reaches 20 tiles on the flat (1.0 / 0.05), where one flat rate would have cut it to 5.
Constants.PRESSURE_FRICTION_DRIP = 0.02     -- trickle flow
Constants.PRESSURE_FRICTION_TAP = 0.05      -- taps, generators: low flow
Constants.PRESSURE_FRICTION_SPRINKLER = 0.2 -- wide-open flow through scavenged pipe
-- Minimum pressure a consumer needs to draw at all.
Constants.PRESSURE_MIN_TAP = 0.0
Constants.PRESSURE_MIN_DRIP = 0.0
Constants.PRESSURE_MIN_SPRINKLER = 20.0     -- a real sprinkler head needs ~2 bar
-- Consumer kinds, used to pick a friction coefficient.
Constants.PRESSURE_KIND_TAP = "tap"
Constants.PRESSURE_KIND_DRIP = "drip"
Constants.PRESSURE_KIND_SPRINKLER = "sprinkler"
-- Sandbox PressureModel enum values (WaterPipes.PressureModel).
Constants.PRESSURE_MODEL_REALISTIC = 1      -- full model: height, distance, pumps
Constants.PRESSURE_MODEL_SIMPLE = 2         -- height only: no distance loss
Constants.PRESSURE_MODEL_OFF = 3            -- pre-pressure behaviour: pure gravity reachability

-- ===== Hydraulic solver (demand-aware head field) =====
--
-- The block above prices a run as `friction(kind) * hops`, where `kind` is the CONSUMER'S OWN flow
-- rate. That is right for one consumer and wrong for a field: thirty sprinklers on one line each
-- computed their loss as if they were the only thing drawing, so two pumps fed all thirty and the
-- line never noticed. The pipe does not care who is asking -- it cares how many litres per hour are
-- going through it -- so the loss belongs to the EDGE, not to the consumer.
--
-- The solver (Hydraulics.lua) therefore works in piezometric head, the way real hydraulics does:
--
--     H[node]                              -- total head at a node, m.c.a. above the z=0 datum
--     H[source] = PRESSURE_PER_LEVEL * z + CONTAINER_BASE_PRESSURE
--     H[child]  = H[parent] - HYDRAULIC_FRICTION_K * Q(edge) ^ HYDRAULIC_FRICTION_EXPONENT
--     P[node]   = H[node] - PRESSURE_PER_LEVEL * z            -- what a consumer there can use
--
-- Elevation drops out of the loss term entirely (it lives in the datum), which is what lets one
-- forward sweep price height, distance, pumps and regulators in a single pass -- and is why the
-- regulator CHAIN machinery could go: running the walk in the water's direction turns "the tightest
-- valve behind me" into a running minimum.
--
-- CALIBRATION. Q is in litres per in-game hour, and the coefficient is not invented: it is read back
-- out of the friction constants above. A sprinkler draws SPRINKLER_WATER_PER_HOUR * SPRINKLER_WASTE_
-- TILES * IRRIGATION_LITRES_PER_WATER_LEVEL = 1.8 L/h and was priced at 0.2/tile; a drip draws 0.2
-- L/h and was priced at 0.02/tile. 0.2/1.8 = 0.111 and 0.02/0.2 = 0.100 -- the old table was already
-- almost exactly LINEAR in flow, it just had no way to add two consumers together. So K = 0.111 with
-- exponent 1 reproduces both old coefficients to within 11%, and the promise that buys is worth
-- stating plainly: A NETWORK WITH ONE EMITTER BEHAVES EXACTLY AS IT DID BEFORE. What changed is that
-- the thirty-first sprinkler now costs the thirty before it something.
Constants.HYDRAULIC_FRICTION_K = 0.111      -- m.c.a. lost per tile, per litre/hour through it
-- Real pipe loss is superlinear (Hazen-Williams uses 1.85, Darcy-Weisbach 2). Left at 1 because that
-- is what the constants it replaces actually encode, and because raising it makes a shared line
-- collapse far faster than it makes it realistic. Exposed so a save can ask for the harsher curve.
Constants.HYDRAULIC_FRICTION_EXPONENT = 1.0
-- Nominal flow for a consumer with no rate of its own (taps, generators, the router's own transfers).
-- Back-derived the same way: PRESSURE_FRICTION_TAP / HYDRAULIC_FRICTION_K = 0.05 / 0.111.
Constants.HYDRAULIC_TAP_FLOW = 0.45         -- litres per in-game hour

-- How much of the SHARED demand an edge is charged for. This is the one knob that spans the old
-- model and the new one, and it is a real dial rather than a fudge:
--   1.0 -> the edge carries everything flowing through it. Full demand realism.
--   0.0 -> the edge carries only the single largest consumer downstream of it, which is precisely
--          the old per-consumer arithmetic. Existing saves can have their old behaviour back.
-- Anything between scales the crowding effect linearly, so a server that wants sprinkler fields to
-- cost something without making them impossible has somewhere to sit.
Constants.HYDRAULIC_DEMAND_SCALE = 1.0

-- Starved consumers stop drawing, which frees head for the rest, so who runs is a fixed point rather
-- than a single calculation. Hydraulics finds it with a monotone binary search over "how many of the
-- easiest-to-serve consumers can run at once", which needs no tuning constant and cannot oscillate --
-- see the comment on that search for why the obvious iterate-until-stable version does oscillate, and
-- why capping its iteration count merely hides that.

-- Sweeps the head relaxation is allowed before it gives up (see Hydraulics' phase 5). Head propagates
-- by relaxation rather than by a single ordered walk, because a node that supplies itself -- a barrel
-- sitting on the line -- still has to be able to receive a pump's head from its neighbour. Alternating
-- the sweep direction converges on grid-shaped networks in two or three rounds; the cap is what stops
-- a pathological layout from spinning, and the loop exits early the moment nothing moves.
Constants.HYDRAULIC_RELAX_PASSES = 12

-- ===== Water pump =====
-- A pump is a pipe variant that needs power. Where you PUT it decides what it does, exactly like a
-- real self-priming surface pump:
--   * sitting on a pipe that already has water -> a booster; it just adds head.
--   * next to a well / open water / a container -> an extractor; it also injects fluid.
-- The asymmetry between the two numbers below is the real physics that makes one device do both
-- jobs: a surface pump can only SUCK water up about 7 m (atmospheric pressure caps it at 10.33 m,
-- ~7-8 m in practice) but can PUSH it 25 m and more. That is why deep wells use submersible pumps.
Constants.PUMP_MODDATA_KEY = "waterpipesPump"
-- The manual switch, flipped from the pump's context menu. ABSENT MEANS ON: pumps built before the
-- switch existed carry no key, and they must keep running after an update rather than silently
-- stopping every network in every existing save.
Constants.PUMP_ENABLED_KEY = "waterpipesPumpOn"
-- Our OWN tiles, not vanilla ones. The art is the same machine copied into the waterpipes atlas;
-- what changed is who owns the tiledef. The vanilla originals (industry_02_52/53) carry an
-- AmbientSound property, and a sprite with AmbientSound is rebuilt down the engine's ambient-emitter
-- path on chunk load, which never resolves a modded entity script -- so every saved pump came back
-- as "EntityScript not found". Same story for the gauge below.
Constants.PUMP_SPRITE_EW = "waterpipes_01_28"   -- floor machine, E/W axis
Constants.PUMP_SPRITE_NS = "waterpipes_01_29"   -- ...and its N/S mirror
Constants.PUMP_HEAD = 25.0                  -- m.c.a. added; a domestic pressure set is ~2.5 bar
Constants.PUMP_SUCTION_LIMIT = 7.0          -- m.c.a. it can lift a source from below (~2 floors)
Constants.PUMP_INTAKE_RATE = 20             -- litres per in-game minute; a real pump does 33-50
-- Natural sources the extractor mode can tap. A well is a plain IsoObject carrying a FluidContainer
-- component (10 000 L of CLEAN water, refilled only by rain at RainFactor 0.1 -- so it is a big
-- reservoir, not an infinite tap). Open water is identified the way vanilla does it, by the floor
-- tile's `water` flag, and is infinite but TAINTED -- which is what gives the purifier a job.
-- A well is identified by its ENTITY name. B42 entity objects answer getEntityScript():getName(),
-- which yields the bare name inside the module ("Well"), and that is how vanilla itself reads them
-- -- see ISOpenCloseLid.lua:35 doing exactly this on a barrel. getScriptName() is the VEHICLE
-- accessor and returns the string "none" on an entity object, so the fully-qualified form below is
-- only kept as a fallback for builds where it does answer.
Constants.WELL_ENTITY_NAME = "Well"
Constants.WELL_SCRIPT_NAME = "Base.Well"
-- Both wells (10 000) and water tiles (10 000) sit above MAX_FINITE_FLUID_CAPACITY on purpose: they
-- must never join the network as ordinary containers, or rebalanceSummary would smear 10 000 L
-- across every pipe and the network would read as permanently full. The pump INJECTS from them at a
-- bounded rate instead, the same shape as the purifier's intake step.

-- ===== Fire hydrants =====
-- A vanilla street hydrant (a decorative moveable with no water of its own) becomes a network source
-- once a pipe is laid on its tile and it is opened with a pipe wrench. While the town water service is
-- still running it is mains-fed and effectively bottomless; the day the water is cut it keeps only the
-- reserve left in the local main (HYDRANT_RESERVE litres) and drains as it is used. Clean water.
Constants.HYDRANT_SPRITE = "street_decoration_01_12"     -- vanilla Mov_FireHydrant
Constants.HYDRANT_OPEN_KEY = "waterpipesHydrantOpen"      -- modData: opened with the wrench
Constants.HYDRANT_RESERVE_KEY = "waterpipesHydrantReserve" -- modData: litres left once the mains is cut
Constants.HYDRANT_RESERVE = 1000            -- litres held in the local main after the shutoff
Constants.HYDRANT_FLOW_RATE = 60            -- litres per in-game minute an open hydrant delivers
-- Pressure an open, mains-fed hydrant floors the network at, m.c.a. A hydrant is a high-flow main tap,
-- so it runs above the household mains (25.0) and comfortably above a sprinkler's 20.0 -- opening one
-- runs sprinklers far from any barrel with no pump, until the day the water is cut.
Constants.HYDRANT_HEAD = 40.0

-- ===== Water stagnation =====
-- Standing water goes bad. Every water container carries the world-age hour of its last movement
-- (any consumption, transfer, rain or mains inflow, caught through OnWaterAmountChange). Once a
-- container has sat still past its limit it turns tainted, and the contamination rule then spreads it
-- to the rest of its network -- so a whole plumbed system stagnates together, at the pace of its most
-- exposed vessel. An actively used network never gets there, because drawing from it keeps stamping.
--
-- Open vs closed is read straight off the vessel's rain-catcher factor (FluidContainer.getRainCatcher,
-- the RainFactor from its script): anything that collects rain is open to the air and spoils faster.
-- Rain is the sharp edge: while it rains, any OPEN container that is also OUTSIDE has its whole
-- network tainted at once, so uncovered collection is a gamble every time the weather turns. This
-- mirrors vanilla, whose rain barrels already fill with tainted water.
Constants.STAGNATION_STAMP_KEY = "waterpipesLastMove"   -- modData: world-age hours of last movement
Constants.STAGNATION_DAYS_CLOSED = 30       -- sealed tanks, pipes, a lidded amphora: weeks
Constants.STAGNATION_DAYS_OPEN = 10         -- rain barrels, an open amphora: days

-- ===== Town water supply (the mains) =====
-- Plumbing a fixture turns the engine's infinite city water off on it, so before this the network
-- could only ever LOSE from the mains. Now a plumbed fixture is an inlet while the service runs: it
-- fills the network at a bounded rate and holds the whole zone at mains pressure, which is what makes
-- the shutoff day an event instead of a footnote. See Mains.lua for how the service is detected.
-- The mains is a PRESSURE FLOOR, not another pump. A utility holds its main at a set pressure and
-- every connection to it sits at that pressure, so a live inlet puts the whole zone at this number
-- whatever the distance -- it is not added on top of a source's own head, and two inlets are still
-- one supply. A regulator can still hold it down, because a valve regulates what flows THROUGH it.
Constants.MAINS_HEAD = 25.0                 -- m.c.a.; real municipal mains run 20-40
Constants.MAINS_INTAKE_RATE = 60            -- litres per in-game minute: the fattest source there is
Constants.MAINS_INFINITE_AMOUNT = 10000     -- the marker isWaterInfinite() reports (see Mains.lua)
Constants.MAINS_PROBE_TTL_MS = 5000         -- how long a "is the service on?" answer is reused

-- ===== Router pressure regulator =====
-- A router already splits the network in two, so pressure cannot cross it either. That makes it the
-- natural place to REGULATE: the player sets a ceiling and the OUT-side zone runs at it.
-- It can only ever reduce (P_out = min(P_in, setting)) -- exactly what a real pressure-reducing
-- valve does, and the reason a router can never replace a pump.
Constants.ROUTER_PRESSURE_KEY = "waterpipesRouterPressure"
Constants.ROUTER_PRESSURE_UNSET = -1        -- "no ceiling": pass the incoming head through untouched
Constants.ROUTER_PRESSURE_MAX = 100         -- ceiling the context menu offers
Constants.ROUTER_PRESSURE_STEP = 5          -- granularity of the context-menu options

-- ===== Irrigation =====
-- Both emitters are PIPE variants: they sit on the line, conduct water onward, and water as it
-- passes. Chaining them along a furrow is exactly what real drip tape is.
--
-- Vanilla farming numbers this is built on (all verified against B42 source):
--   * a crop's waterLvl runs 0-100; one "use" adds 10 and costs 200 mL = 0.2 network litres
--     (ZomboidGlobals.farmingFluidContainerMillilitresPerUse, shared/defines.lua)
--   * crops die only at waterLvl <= 0, and drain just 1 per 5 in-game hours by default
--   * rain only reaches crops with exterior == true -- INDOOR crops get nothing, which is the real
--     reason to build this
--   * tainted water waters crops exactly like clean water (ISFarmingMenu whitelists both)
Constants.DRIP_MODDATA_KEY = "waterpipesDrip"
Constants.DRIP_SPRITE_EW = "waterpipes_01_40"   -- short pipe stub, E/W axis
Constants.DRIP_SPRITE_NS = "waterpipes_01_41"   -- ...and its N/S mirror
Constants.DRIP_WATER_PER_HOUR = 10            -- waterLvl per in-game hour on its own tile
-- Real drip emitters are built for ~1-1.5 bar and blow out above that, which is why every real drip
-- line has a pressure regulator ahead of it. Over this head the emitter bursts: it stops watering
-- but still conducts, exactly like a spent purifier filter still passes clean water.
Constants.DRIP_BURST_PRESSURE = 15.0
Constants.DRIP_CONDITION_KEY = "waterpipesDripCondition"
Constants.DRIP_MAX_CONDITION = 100
Constants.DRIP_REPAIR_ITEMS = {
    { type = "Base.DuctTape", count = 1 },
}
Constants.DRIP_REPAIR_TIME = 80

Constants.SPRINKLER_MODDATA_KEY = "waterpipesSprinkler"
Constants.SPRINKLER_SPRITE_EW = "waterpipes_01_42"   -- upright elbow: reads as a spray head
Constants.SPRINKLER_SPRITE_NS = "waterpipes_01_43"
Constants.SPRINKLER_RADIUS = 1                     -- 1 = the 3x3 around it
Constants.SPRINKLER_WATER_PER_HOUR = 10            -- waterLvl per in-game hour, per covered tile
-- A sprinkler sprays the whole 3x3 whether or not there is a crop under it, so it wastes most of
-- what it draws. That inefficiency IS the balance: water cost alone can never balance irrigation
-- (crops drain far too slowly), so the drip-vs-sprinkler choice has to be paid for somewhere else.
Constants.SPRINKLER_WASTE_TILES = 9                -- litres are charged for all 9, crops or not
Constants.SPRINKLER_NOISE_RADIUS = 12              -- zombie attraction while running
Constants.SPRINKLER_NOISE_VOLUME = 8

-- Litres of network fluid per +1 waterLvl. 10 waterLvl = 1 use = 200 mL, so 1 waterLvl = 0.02 L.
Constants.IRRIGATION_LITRES_PER_WATER_LEVEL = 0.02
Constants.IRRIGATION_MAX_WATER_LEVEL = 100

-- ===== Fluid writes =====
-- Litres below which writing a vessel is not worth doing. A write is NOT cheap: it resolves the
-- sprite-grid target, empties the FluidContainer, refills it, sync()s the object, transmitModData()s
-- it and fires OnWaterAmountChange for external mods. Doing all that to move a hundredth of a litre
-- is pure cost -- and on a farm network it is that cost, multiplied by vessels x emitters, that the
-- player feels as a stall. Anything the guard skips is carried to the next vessel by the caller
-- (see rebalanceSummary), so conservation is exact whatever this is set to.
Constants.FLUID_WRITE_EPSILON = 0.01

-- The most emitters one frame may process while an irrigation pass drains (see Irrigation.beginPass).
-- A CEILING, not a target: the real limit is the millisecond budget below.
Constants.IRRIGATION_EMITTERS_PER_TICK = 4

-- ...and how long that frame may actually spend on them.
--
-- A count is a proxy for cost, and this one drifted: four emitters was cheap when the head field was
-- cheap, and measured at 37 ms a frame once the field became the expensive part -- every one of the
-- twelve frames of a pass over the visible-stutter line. The count could be lowered, and would drift
-- again the next time anything under it changes.
--
-- So the budget is stated in the units the problem is actually in. At least one emitter is always
-- processed, so a pass always advances however expensive a single one turns out to be; after that the
-- clock decides. Eight milliseconds leaves room under the ~16 ms where a stutter becomes visible for
-- everything the game itself does in the same frame.
--
-- Same correction as the tick-based pacing in the spray FX and the tile registry: measuring frames
-- when you mean time gets you a cost that depends on the machine instead of on the work.
Constants.IRRIGATION_MS_PER_TICK = 8

-- ===== Pressure gauge =====
-- Pressure is otherwise an invisible number; this is the only way the player can see it.
Constants.GAUGE_MODDATA_KEY = "waterpipesGauge"
Constants.GAUGE_SPRITE_N = "waterpipes_01_30"   -- vented wall box, North wall (see PUMP_SPRITE_EW)
Constants.GAUGE_SPRITE_W = "waterpipes_01_31"   -- ...and the West wall mirror
Constants.GAUGE_READ_DISTANCE = 2             -- matches ISFluidUtil.isoMaxPanelDist

-- Appliances that use water to run but manage it themselves (a washing machine only needs its own
-- FluidContainer non-empty to start a cycle, and its cycle logic never touches fluid). They carry the
-- waterPiped flag, so in principle the endpoint detection already sees them -- but that flag is read
-- from the live sprite and is not reliable on every washer model, which let them slip through to the
-- storage path where the network overwrote their water. Matched by class instead:
--   * container detection EXCLUDES them (never storage),
--   * endpoint detection INCLUDES them (a plumbable consumer, like a sink),
-- so a pipe on a washer's tile lets you plumb it and it draws its wash water from the network.
--
-- Known limitation (accepted): once the mirror puts water into the washer's own FluidContainer, the
-- vanilla RIGHT-CLICK menu suppresses the washer's Turn On / change-mode submenu (its context-menu
-- builder bails out early when the tile "has something to interact with", i.e. drawable water). The
-- washer is still fully operable from the inventory/loot window, where those controls remain -- so
-- this is a cosmetic loss of the redundant right-click path, not a loss of function. Feeding it
-- without a filled container would require a phantom water-source object above the tile, which the
-- mod deliberately removed (WorldDictionary risk); not worth it for a redundant menu.
Constants.WATER_APPLIANCE_CLASSES = {
    "IsoClothingWasher",
    "IsoCombinationWasherDryer",
    "IsoStackedWasherDryer",
}

Constants.CARDINAL_OFFSETS = {
    { x = 1, y = 0, z = 0 },
    { x = -1, y = 0, z = 0 },
    { x = 0, y = 1, z = 0 },
    { x = 0, y = -1, z = 0 },
}

Constants.VERTICAL_OFFSETS = {
    { x = 0, y = 0, z = 1 },
    { x = 0, y = 0, z = -1 },
}

Constants.NETWORK_NEIGHBOR_OFFSETS = {
    { x = 1, y = 0, z = 0 },
    { x = -1, y = 0, z = 0 },
    { x = 0, y = 1, z = 0 },
    { x = 0, y = -1, z = 0 },
    { x = 0, y = 0, z = 1 },
    { x = 0, y = 0, z = -1 },
}
