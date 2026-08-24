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
-- What the pipe was built FROM. Only set when it is not the default metal ("clay" today), so a pipe
-- built before this key existed reads as metal, which is what it was. Dismantling reads it: metal is
-- salvage, clay is spent the moment it is laid.
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
-- Endpoint-owned FluidContainer mirror: the plumbed fixture carries its own container mirroring the
-- connected network, so no phantom world object is needed.
Constants.ENDPOINT_FLUID_LAST_SYNC_KEY = "waterpipesEndpointLastSync"
Constants.ENDPOINT_FLUID_SYNCING_KEY = "waterpipesEndpointSyncing"
Constants.PIPE_SURFACE_FLOOR = "floor"
Constants.PIPE_SURFACE_WALL = "wall"
Constants.PIPE_SURFACE_WALLCOVER = "wallcover"   -- decorative vertical pipe drawn on a wall
Constants.PIPE_AXIS_EW = "ew"
Constants.PIPE_AXIS_NS = "ns"
-- Sprites from this mod's waterpipes tileset. The build cursor exposes 4 placement modes: floor EW,
-- floor NS, wall EW, wall NS. Keep these IDs aligned with media/texturepacks/waterpipes.pack.
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
-- Concealed pipe variant: full network functionality, rendered with a transparent tile client-side.
-- Baked in at build time and never toggled at runtime, so no extra network sync is needed.
Constants.PIPE_HIDDEN_MODDATA_KEY = "waterpipesHidden"
Constants.PIPE_HIDDEN_SPRITE = "waterpipes_01_20"   -- fully transparent tile in the tileset
-- Purifier: a NON-pipe tank on a router tile that cleans the connected network's tainted water while
-- powered. The tier is baked in at build time. The legacy filter/fire tiers are still recognised by
-- getTier so old saves keep working, but only the electric tier is buildable.
Constants.PURIFIER_MODDATA_KEY = "waterpipesPurifier"       -- value = tier string below
Constants.PURIFIER_TIER_FILTER = "filter"
Constants.PURIFIER_TIER_FIRE = "fire"
Constants.PURIFIER_TIER_ELECTRIC = "electric"
-- Filter condition: the medium wears with USE, not idle time. Every unit of tainted water converted
-- spends FILTER_WEAR_PER_UNIT. At 0 it can no longer clean tainted water (clean still passes) until it
-- is repaired. Lives in the anchor's modData, server-authoritative, synced.
Constants.PURIFIER_FILTER_CONDITION_KEY = "waterpipesFilterCondition"
Constants.PURIFIER_FILTER_MAX_CONDITION = 100              -- % scale; a fresh/repaired filter starts here
-- Base wear per unit of tainted water filtered. Scaled PER-SAVE by the Sandbox Option
-- WaterPipes.PurifierFilterWear (percentage: 100 = this base, 0 = never wears); this stays the fallback.
Constants.PURIFIER_FILTER_WEAR_PER_UNIT = 0.02            -- % lost per unit of tainted water filtered
Constants.PURIFIER_FILTER_WARN_CONDITION = 25             -- UI turns amber at/below this (repair soon)
-- Repair kit for the "Repair Filter" action. An entry matches by `tag`, by one `type`, or by a list.
-- CHARCOAL IS MATCHED BY TAG, NEVER BY ITEM NAME: vanilla ships Base.Charcoal and Base.CharcoalCrafted
-- and both carry base:charcoal, as does any charcoal another mod adds. It is also what the build
-- recipes ask for, so both halves of the mod agree on what charcoal is.
-- `displayType` is the item the tooltip NAMES -- presentation only, never matched against.
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

-- Resolved by NAME because Lua cannot spell an enum member handed to it as a string. ItemTag.CHARCOAL
-- exists on a stock B42, checked against the enum in the shipped jar alongside the base:charcoal tag on
-- both vanilla charcoals.
-- Still guarded, and loud about it: a tag-only entry that fails to resolve matches NOTHING, which would
-- leave the filter permanently unrepairable with no clue why.
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

-- How many of `entry` the inventory holds. The MAXIMUM of the type count and the tag count, never the
-- sum: an entry naming both would count the same item twice -- a tagged item is usually in the type
-- list as well -- and let a repair start with half the materials.
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
-- Did the purifier move any fluid on the last server tick? The readout used to infer this from the
-- buffer levels, which reported a tank sitting full while busy pushing clean water out as "Stopped".
Constants.PURIFIER_PROCESSING_KEY = "waterpipesPurBusy"
Constants.PURIFIER_BUFFER_CAPACITY = 50
-- Rates are per IN-GAME MINUTE (the server sub-steps them by elapsed game time, so throughput does not
-- depend on framerate). Intake is FASTER than convert on purpose, so the IN buffer visibly holds a level
-- instead of draining to 0.
-- There is no OUTPUT rate: the OUT buffer is storage belonging to the clean network now, so its level
-- simply evens out with whatever else is on that side. The convert rate still limits throughput.
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
-- Fluid router: a directional floor pipe that BOUNDS two separate networks (IN and OUT never merge),
-- bridged only through a container on its tile. The IN->OUT direction is set from the context menu.
Constants.ROUTER_MODDATA_KEY = "waterpipesRouter"
Constants.ROUTER_DIRECTION_KEY = "waterpipesRouterDir"   -- "N"/"E"/"S"/"W" = the OUT side
Constants.ROUTER_SPRITE = "waterpipes_01_13"             -- placeholder until the arrow art is packed
Constants.ROUTER_DEFAULT_DIRECTION = "N"
Constants.ROUTER_TRANSFER_RATE = 30                      -- max fluid units moved IN->OUT per minute tick
Constants.ADAPTER_SOURCE_SPRITE = "carpentry_02_54"
Constants.ADAPTER_SOURCE_HIDDEN_SPRITE = "waterpipes_01_20"
Constants.MAX_FINITE_FLUID_CAPACITY = 9999

-- ===== Pressure model =====
-- Pressure is in METRES OF WATER COLUMN (m.c.a.), the unit real irrigation uses: 1 m.c.a. = 0.098 bar.
-- Municipal mains run 20-40, a garden sprinkler needs ~20, gravity drip works at 1-2. Keeping the unit
-- real means every constant below can be sanity-checked against a plumbing table.
--
--     P = CONTAINER_BASE_PRESSURE
--       + PRESSURE_PER_LEVEL * (z_source - z_consumer)     -- falling gains, climbing costs
--       - friction(consumer) * hops                        -- distance always costs
--
-- The elevation term telescopes, so the only path-dependent term is friction and minimising loss is
-- just minimising hops. This stops holding once pumps add head at a node; see the block below.
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
-- The block above prices a run as friction(kind) * hops, where `kind` is the CONSUMER'S OWN flow rate.
-- That is right for one consumer and wrong for a field: thirty sprinklers each computed their loss as
-- if they were alone on the line. The pipe cares how many litres an hour go through it, not who is
-- asking, so the loss belongs to the EDGE.
--
--     H[node]                              -- total head at a node, m.c.a. above the z=0 datum
--     H[source] = PRESSURE_PER_LEVEL * z + CONTAINER_BASE_PRESSURE
--     H[child]  = H[parent] - HYDRAULIC_FRICTION_K * Q(edge) ^ HYDRAULIC_FRICTION_EXPONENT
--     P[node]   = H[node] - PRESSURE_PER_LEVEL * z            -- what a consumer there can use
--
-- Elevation drops out of the loss term entirely (it lives in the datum), which is what lets one forward
-- sweep price height, distance, pumps and regulators in a single pass.
--
-- CALIBRATION. Q is litres per in-game hour, and K is read back out of the friction constants above
-- rather than invented: a sprinkler draws 1.8 L/h and was priced at 0.2/tile, a drip draws 0.2 L/h at
-- 0.02/tile -- 0.111 and 0.100, so the old table was already almost exactly LINEAR in flow. K = 0.111
-- with exponent 1 reproduces both to within 11%, and the promise that buys is worth stating: A NETWORK
-- WITH ONE EMITTER BEHAVES EXACTLY AS IT DID BEFORE. What changed is that the thirty-first sprinkler
-- now costs the thirty before it something.
Constants.HYDRAULIC_FRICTION_K = 0.111      -- m.c.a. lost per tile, per litre/hour through it
-- Real pipe loss is superlinear (Hazen-Williams uses 1.85, Darcy-Weisbach 2). Left at 1 because that
-- is what the constants it replaces actually encode, and because raising it makes a shared line
-- collapse far faster than it makes it realistic. Exposed so a save can ask for the harsher curve.
Constants.HYDRAULIC_FRICTION_EXPONENT = 1.0
-- Nominal flow for a consumer with no rate of its own (taps, generators, the router's own transfers).
-- Back-derived the same way: PRESSURE_FRICTION_TAP / HYDRAULIC_FRICTION_K = 0.05 / 0.111.
Constants.HYDRAULIC_TAP_FLOW = 0.45         -- litres per in-game hour

-- How much of the SHARED demand an edge is charged for. A real dial, not a fudge:
--   1.0 -> the edge carries everything flowing through it. Full demand realism.
--   0.0 -> the edge carries only the single largest consumer downstream, which is precisely the old
--          per-consumer arithmetic, so an existing save can have its old behaviour back.
-- Anything between scales the crowding effect linearly.
Constants.HYDRAULIC_DEMAND_SCALE = 1.0

-- Starved consumers stop drawing, which frees head for the rest, so who runs is a fixed point rather
-- than a single calculation. Hydraulics finds it with a monotone binary search over "how many of the
-- easiest-to-serve consumers can run at once", which needs no tuning constant and cannot oscillate.

-- Sweeps the head relaxation is allowed before it gives up (Hydraulics phase 5). Head propagates by
-- relaxation rather than one ordered walk, because a node that supplies itself -- a barrel sitting on
-- the line -- still has to be able to receive a pump's head from its neighbour. The cap stops a
-- pathological layout spinning; the loop exits early the moment nothing moves.
Constants.HYDRAULIC_RELAX_PASSES = 12

-- ===== Water pump =====
-- A pipe variant that needs power, and where you PUT it decides what it does:
--   * on a pipe that already has water -> a booster; it just adds head.
--   * next to a well, open water or a container -> an extractor; it also injects fluid.
-- The asymmetry between the two numbers below is the real physics that makes one device do both jobs: a
-- surface pump can only SUCK water up about 7 m (atmospheric pressure caps it at 10.33 m) but can PUSH
-- it 25 m and more. That is why deep wells use submersible pumps.
Constants.PUMP_MODDATA_KEY = "waterpipesPump"
-- The manual switch, flipped from the pump's context menu. ABSENT MEANS ON: pumps built before the
-- switch existed carry no key, and they must keep running after an update rather than silently
-- stopping every network in every existing save.
Constants.PUMP_ENABLED_KEY = "waterpipesPumpOn"
-- Our OWN tiles, not vanilla ones -- the same art, a different tiledef owner. The vanilla originals
-- (industry_02_52/53) carry an AmbientSound property, and a sprite with AmbientSound is rebuilt down the
-- engine's ambient-emitter path on chunk load, which never resolves a modded entity script: every saved
-- pump came back as "EntityScript not found". Same story for the gauge below.
Constants.PUMP_SPRITE_EW = "waterpipes_01_28"   -- floor machine, E/W axis
Constants.PUMP_SPRITE_NS = "waterpipes_01_29"   -- ...and its N/S mirror
Constants.PUMP_HEAD = 25.0                  -- m.c.a. added; a domestic pressure set is ~2.5 bar
Constants.PUMP_SUCTION_LIMIT = 7.0          -- m.c.a. it can lift a source from below (~2 floors)
Constants.PUMP_INTAKE_RATE = 20             -- litres per in-game minute; a real pump does 33-50
-- Natural sources the extractor mode can tap. A well is a plain IsoObject with a FluidContainer
-- (10 000 L of CLEAN water, refilled only by rain -- a big reservoir, not an infinite tap). Open water
-- is identified the way vanilla does it, by the floor tile's `water` flag, and is infinite but TAINTED,
-- which is what gives the purifier a job.
-- A well is identified by its ENTITY name: getEntityScript():getName() yields the bare name inside the
-- module ("Well"), which is how vanilla itself reads them. getScriptName() is the VEHICLE accessor and
-- returns "none" on an entity object, so the qualified form below is only a fallback.
Constants.WELL_ENTITY_NAME = "Well"
Constants.WELL_SCRIPT_NAME = "Base.Well"
-- Both wells and water tiles sit above MAX_FINITE_FLUID_CAPACITY on purpose: they must never join the
-- network as ordinary containers, or rebalanceSummary would smear 10 000 L across every pipe and the
-- network would read as permanently full. The pump INJECTS from them at a bounded rate instead.

-- ===== Fire hydrants =====
-- A vanilla street hydrant becomes a network source once a pipe is laid on its tile and it is opened
-- with a pipe wrench. While the town water service runs it is mains-fed and effectively bottomless; the
-- day the water is cut it keeps only HYDRANT_RESERVE litres and drains as it is used. Clean water.
Constants.HYDRANT_SPRITE = "street_decoration_01_12"     -- vanilla Mov_FireHydrant
Constants.HYDRANT_OPEN_KEY = "waterpipesHydrantOpen"      -- modData: opened with the wrench
Constants.HYDRANT_RESERVE_KEY = "waterpipesHydrantReserve" -- modData: litres left once the mains is cut
Constants.HYDRANT_RESERVE = 1000            -- litres held in the local main after the shutoff
Constants.HYDRANT_FLOW_RATE = 60            -- litres per in-game minute an open hydrant delivers
-- Pressure an open, mains-fed hydrant floors the network at. A hydrant is a high-flow main tap, so it
-- runs above the household mains (25.0) and comfortably above a sprinkler's 20.0 -- opening one runs
-- sprinklers far from any barrel with no pump, until the day the water is cut.
Constants.HYDRANT_HEAD = 40.0

-- ===== Water stagnation =====
-- Every water container carries the world-age hour of its last movement (any consumption, transfer,
-- rain or mains inflow, caught through OnWaterAmountChange). Once it has sat still past its limit it
-- turns tainted, and the contamination rule spreads that to the rest of its network -- so a plumbed
-- system stagnates together, at the pace of its most exposed vessel. An actively used network never
-- gets there, because drawing from it keeps stamping.
-- Open vs closed is read straight off the vessel's rain-catcher factor: anything that collects rain is
-- open to the air and spoils faster. While it rains, any OPEN container that is also OUTSIDE has its
-- whole network tainted at once, which mirrors vanilla's already-tainted rain barrels.
Constants.STAGNATION_STAMP_KEY = "waterpipesLastMove"   -- modData: world-age hours of last movement
Constants.STAGNATION_DAYS_CLOSED = 30       -- sealed tanks, pipes, a lidded amphora: weeks
Constants.STAGNATION_DAYS_OPEN = 10         -- rain barrels, an open amphora: days

-- ===== Town water supply (the mains) =====
-- Plumbing a fixture turns the engine's infinite city water off on it, so the network could once only
-- LOSE from the mains. A plumbed fixture is now an inlet while the service runs: it fills the network at
-- a bounded rate and holds the whole zone at mains pressure, which is what makes the shutoff day an
-- event instead of a footnote. See Mains.lua for how the service is detected.
-- The mains is a PRESSURE FLOOR, not another pump. Every connection sits at that pressure whatever the
-- distance; it is not added on top of a source's own head, and two inlets are still one supply. A
-- regulator can still hold it down, because a valve regulates what flows THROUGH it.
Constants.MAINS_HEAD = 25.0                 -- m.c.a.; real municipal mains run 20-40
Constants.MAINS_INTAKE_RATE = 60            -- litres per in-game minute: the fattest source there is
Constants.MAINS_INFINITE_AMOUNT = 10000     -- the marker isWaterInfinite() reports (see Mains.lua)
Constants.MAINS_PROBE_TTL_MS = 5000         -- how long a "is the service on?" answer is reused

-- ===== Router pressure regulator =====
-- A router already splits the network in two, so pressure cannot cross it either -- which makes it the
-- natural place to REGULATE: the player sets a ceiling and the OUT-side zone runs at it. It can only
-- ever reduce (P_out = min(P_in, setting)), exactly what a real pressure-reducing valve does, and the
-- reason a router can never replace a pump.
Constants.ROUTER_PRESSURE_KEY = "waterpipesRouterPressure"
Constants.ROUTER_PRESSURE_UNSET = -1        -- "no ceiling": pass the incoming head through untouched
Constants.ROUTER_PRESSURE_MAX = 100         -- ceiling the context menu offers
Constants.ROUTER_PRESSURE_STEP = 5          -- granularity of the context-menu options

-- ===== Irrigation =====
-- Both emitters are PIPE variants: they sit on the line, conduct water onward, and water as it passes.
-- Chaining them along a furrow is exactly what real drip tape is.
-- Vanilla farming numbers this is built on (all verified against B42 source):
--   * a crop's waterLvl runs 0-100; one "use" adds 10 and costs 200 mL = 0.2 network litres
--   * crops die only at waterLvl <= 0, and drain just 1 per 5 in-game hours by default
--   * rain only reaches crops with exterior == true -- INDOOR crops get nothing, which is the real
--     reason to build this
--   * tainted water waters crops exactly like clean water
Constants.DRIP_MODDATA_KEY = "waterpipesDrip"
Constants.DRIP_SPRITE_EW = "waterpipes_01_40"   -- short pipe stub, E/W axis
Constants.DRIP_SPRITE_NS = "waterpipes_01_41"   -- ...and its N/S mirror
Constants.DRIP_WATER_PER_HOUR = 10            -- waterLvl per in-game hour on its own tile
-- Real drip emitters are built for ~1-1.5 bar and blow out above that, which is why every real drip line
-- has a pressure regulator ahead of it. Over this head the emitter bursts: it stops watering but still
-- conducts, exactly like a spent purifier filter still passes clean water.
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
-- A sprinkler sprays the whole 3x3 whether or not there is a crop under it, so it wastes most of what it
-- draws. That inefficiency IS the balance: crops drain far too slowly for water cost alone to price the
-- drip-versus-sprinkler choice.
Constants.SPRINKLER_WASTE_TILES = 9                -- litres are charged for all 9, crops or not
Constants.SPRINKLER_NOISE_RADIUS = 12              -- zombie attraction while running
Constants.SPRINKLER_NOISE_VOLUME = 8

-- Litres of network fluid per +1 waterLvl. 10 waterLvl = 1 use = 200 mL, so 1 waterLvl = 0.02 L.
Constants.IRRIGATION_LITRES_PER_WATER_LEVEL = 0.02
Constants.IRRIGATION_MAX_WATER_LEVEL = 100

-- ===== Fluid writes =====
-- Litres below which writing a vessel is not worth doing. A write resolves the sprite-grid target,
-- empties the FluidContainer, refills it, sync()s the object, transmitModData()s it and fires
-- OnWaterAmountChange for external mods -- all to move a hundredth of a litre, multiplied by vessels x
-- emitters on a farm network.
-- Anything the guard skips is carried to the next vessel by the caller (see rebalanceSummary), so
-- conservation is exact whatever this is set to.
Constants.FLUID_WRITE_EPSILON = 0.01

-- The most emitters one frame may process while an irrigation pass drains (see Irrigation.beginPass).
-- A CEILING, not a target: the real limit is the millisecond budget below.
Constants.IRRIGATION_EMITTERS_PER_TICK = 4

-- ...and how long that frame may actually spend on them.
-- A count is a proxy for cost, and this one drifted: four emitters was cheap when the head field was
-- cheap, and measured at 37 ms a frame once the field became the expensive part. Lowering the count
-- would only drift again the next time anything under it changed.
-- So the budget is stated in the units the problem is in. At least one emitter is always processed, so a
-- pass always advances however expensive a single one turns out to be; after that the clock decides.
-- Eight milliseconds leaves room under the ~16 ms where a stutter becomes visible.
Constants.IRRIGATION_MS_PER_TICK = 8

-- ===== Pressure gauge =====
-- Pressure is otherwise an invisible number; this is the only way the player can see it.
Constants.GAUGE_MODDATA_KEY = "waterpipesGauge"
Constants.GAUGE_SPRITE_N = "waterpipes_01_30"   -- vented wall box, North wall (see PUMP_SPRITE_EW)
Constants.GAUGE_SPRITE_W = "waterpipes_01_31"   -- ...and the West wall mirror
Constants.GAUGE_READ_DISTANCE = 2             -- matches ISFluidUtil.isoMaxPanelDist

-- Appliances that use water to run but manage it themselves (a washing machine only needs its own
-- FluidContainer non-empty to start a cycle, and its cycle logic never touches fluid). They carry the
-- waterPiped flag, but that flag is read from the live sprite and is unreliable on some washer models,
-- which let them slip through to the storage path where the network overwrote their water. Matched by
-- class instead: container detection EXCLUDES them, endpoint detection INCLUDES them.
-- Known limitation (accepted): once the mirror puts water into the washer's own FluidContainer, the
-- vanilla right-click menu suppresses its Turn On submenu -- that builder bails out early when the tile
-- has drawable water. The washer stays fully operable from the inventory window, so this is a cosmetic
-- loss of a redundant path, not a loss of function.
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
