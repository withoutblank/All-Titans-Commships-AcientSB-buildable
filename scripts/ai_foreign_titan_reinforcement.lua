-- AI Foreign Titan Reinforcement Event
--
-- AI players receive one foreign Titan at 20 minutes, a second at 40
-- minutes, and all six faction Titans by 60 minutes. The native Titan is
-- left to the normal AI planner until the final stage; at that point this
-- event fills any missing type so every AI can actually reach six Titans.
--
-- The event ID is deliberately version-free and must remain stable. Behavior
-- revisions belong in metadata.event_version, never in this identifier.

local EventMetadata = require("event_metadata")

local EVENT_ID = "ai_foreign_titan_reinforcement"
local LOG_PREFIX = "[ai_foreign_titan_reinforcement] "

local CONFIG = {
    debug_enabled = false,
    stage_20_seconds = 20.0 * 60.0,
    stage_40_seconds = 40.0 * 60.0,
    stage_60_seconds = 60.0 * 60.0,
    replacement_delay_seconds = 5.0 * 60.0,
    spawn_retry_seconds = 60.0,
    hyperspace_arrival_seconds = 10.0,
    fallback_titan_supply_cost = 150.0,
}

local ALL_TITAN_TYPES = {
    "trader_loyalist_titan",
    "trader_rebel_titan",
    "advent_loyalist_titan",
    "advent_rebel_titan",
    "vasari_loyalist_titan",
    "vasari_rebel_titan",
}

local NATIVE_TITAN_BY_FACTION = {
    trader_loyalist = "trader_loyalist_titan",
    trader_rebel = "trader_rebel_titan",
    advent_loyalist = "advent_loyalist_titan",
    advent_rebel = "advent_rebel_titan",
    vasari_loyalist = "vasari_loyalist_titan",
    vasari_rebel = "vasari_rebel_titan",
}

local FACTION_IDS = {
    "trader_loyalist",
    "trader_rebel",
    "advent_loyalist",
    "advent_rebel",
    "vasari_loyalist",
    "vasari_rebel",
}

-- The native Titan is last in every faction plan. This lets the game's
-- normal Titan planner handle it before the final 60-minute reconciliation.
local TITAN_PLAN_BY_FACTION = {
    trader_loyalist = {
        "trader_rebel_titan",
        "advent_loyalist_titan",
        "advent_rebel_titan",
        "vasari_loyalist_titan",
        "vasari_rebel_titan",
        "trader_loyalist_titan",
    },
    trader_rebel = {
        "trader_loyalist_titan",
        "advent_rebel_titan",
        "advent_loyalist_titan",
        "vasari_rebel_titan",
        "vasari_loyalist_titan",
        "trader_rebel_titan",
    },
    advent_loyalist = {
        "advent_rebel_titan",
        "trader_loyalist_titan",
        "trader_rebel_titan",
        "vasari_loyalist_titan",
        "vasari_rebel_titan",
        "advent_loyalist_titan",
    },
    advent_rebel = {
        "advent_loyalist_titan",
        "trader_rebel_titan",
        "trader_loyalist_titan",
        "vasari_rebel_titan",
        "vasari_loyalist_titan",
        "advent_rebel_titan",
    },
    vasari_loyalist = {
        "vasari_rebel_titan",
        "trader_loyalist_titan",
        "trader_rebel_titan",
        "advent_loyalist_titan",
        "advent_rebel_titan",
        "vasari_loyalist_titan",
    },
    vasari_rebel = {
        "vasari_loyalist_titan",
        "trader_rebel_titan",
        "trader_loyalist_titan",
        "advent_rebel_titan",
        "advent_loyalist_titan",
        "vasari_rebel_titan",
    },
}

-- Compatibility plans are used only if an engine build exposes player.race
-- as the three broad race families instead of one of the six faction IDs.
-- Other-race Titans come first, so the 20/40 minute grants are guaranteed to
-- be foreign even while loyalist/rebel alignment is unavailable. At 60
-- minutes all six exact types are reconciled, which is deterministic and
-- cannot omit the player's true native type.
local TITAN_PLAN_BY_FAMILY = {
    trader = {
        "advent_loyalist_titan",
        "advent_rebel_titan",
        "vasari_loyalist_titan",
        "vasari_rebel_titan",
        "trader_loyalist_titan",
        "trader_rebel_titan",
    },
    advent = {
        "trader_loyalist_titan",
        "trader_rebel_titan",
        "vasari_loyalist_titan",
        "vasari_rebel_titan",
        "advent_loyalist_titan",
        "advent_rebel_titan",
    },
    vasari = {
        "trader_loyalist_titan",
        "trader_rebel_titan",
        "advent_loyalist_titan",
        "advent_rebel_titan",
        "vasari_loyalist_titan",
        "vasari_rebel_titan",
    },
}

-- Completing the listed research chain immediately before each timed grant
-- creates a known, authoritative supply ceiling. This avoids both failure
-- modes of the old implementation: blindly overfilling supply and guessing a
-- maximum from player.used_supply. Every ID below is present in both faction
-- variants of its family's current .player research tree.
local SUPPLY_SUPPORT_BY_FAMILY = {
    trader = {
        research_ids = {
            "trader_max_supply_0",
            "trader_max_supply_1",
            "trader_max_supply_2",
            "trader_max_supply_3",
            "trader_max_supply_4",
        },
        cap_after_research = {250.0, 500.0, 1000.0, 1500.0, 2000.0},
        stage_last_research_index = {
            [1] = 2,
            [2] = 3,
            [6] = 5,
        },
    },
    advent = {
        research_ids = {
            "advent_max_supply_0",
            "advent_max_supply_1",
            "advent_max_supply_2",
            "advent_max_supply_3",
            "advent_max_supply_4",
        },
        cap_after_research = {250.0, 500.0, 1000.0, 1500.0, 2000.0},
        stage_last_research_index = {
            [1] = 2,
            [2] = 3,
            [6] = 5,
        },
    },
    vasari = {
        research_ids = {
            "vasari_max_supply_0",
            "vasari_max_supply_1",
            "vasari_max_supply_2",
            "vasari_max_supply_3",
            "vasari_max_supply_4",
            "vasari_max_supply_5",
        },
        cap_after_research = {
            300.0,
            600.0,
            900.0,
            1500.0,
            2100.0,
            2400.0,
        },
        stage_last_research_index = {
            [1] = 2,
            [2] = 3,
            [6] = 6,
        },
    },
}

-- These mod-specific "native_" units are unambiguous faction markers. They
-- provide a second way to resolve loyalist/rebel alignment when player.race
-- is reduced to a broad family by a different engine/API version.
local FACTION_MARKER_UNITS = {
    trader_loyalist = {
        "native_trader_loyalist_titan",
        "native_dlc2_trader_loyalist_super_capital_ship",
    },
    trader_rebel = {
        "native_trader_rebel_titan",
        "native_dlc2_trader_rebel_super_capital_ship",
    },
    advent_loyalist = {
        "native_advent_loyalist_titan",
        "native_dlc2_advent_loyalist_super_capital_ship",
    },
    advent_rebel = {
        "native_advent_rebel_titan",
        "native_dlc2_advent_rebel_super_capital_ship",
    },
    vasari_loyalist = {
        "native_vasari_loyalist_titan",
        "native_dlc2_vasari_loyalist_super_capital_ship",
    },
    vasari_rebel = {
        "native_vasari_rebel_titan",
        "native_dlc2_vasari_rebel_super_capital_ship",
    },
}

local CANONICAL_TITAN_BY_DEFINITION = {}
for _, titan_type in ipairs(ALL_TITAN_TYPES) do
    CANONICAL_TITAN_BY_DEFINITION[titan_type] = titan_type
    CANONICAL_TITAN_BY_DEFINITION["native_" .. titan_type] = titan_type
end

local function log_info(message)
    print(LOG_PREFIX .. message)
end

local function debug_log(message)
    if CONFIG.debug_enabled then
        log_info("DEBUG: " .. message)
    end
end

local function state_key(player_index, titan_type, suffix)
    return "p" .. tostring(player_index) .. "_" .. titan_type .. "_" .. suffix
end

local function player_state_key(player_index, suffix)
    return "p" .. tostring(player_index) .. "_" .. suffix
end

local function tracker_name(player_index, titan_type)
    -- Keep the legacy tracker name for save compatibility.
    return "ai_foreign_titan_p" .. tostring(player_index) .. "_" .. titan_type
end

local function log_once(context, key, message)
    if context.shared[key] == true then
        return
    end
    context.shared[key] = true
    log_info(message)
end

local function safe_unit_id(unit)
    if unit == nil then
        return nil
    end

    local ok, value = pcall(function()
        return unit.id
    end)
    if ok and type(value) == "number" and value > 0 then
        return value
    end

    return nil
end

local function safe_unit_definition_name(unit)
    if unit == nil then
        return nil
    end

    local ok, value = pcall(function()
        return unit.def_name
    end)
    if ok and type(value) == "string" and value ~= "" then
        return value
    end

    return nil
end

local function safe_player_race(player)
    local ok, value = pcall(function()
        return player.race
    end)
    if ok and type(value) == "string" then
        return value
    end
    return ""
end

local function safe_ai_difficulty(player)
    local ok, value = pcall(function()
        return player.ai_difficulty
    end)
    if ok then
        return value
    end
    return nil
end

local function safe_player_units(player, field_name)
    local ok, value = pcall(function()
        return player[field_name]
    end)
    if ok and type(value) == "table" then
        return value
    end
    return {}
end

local function normalize_identifier(value)
    local normalized = string.lower(tostring(value or ""))
    normalized = string.gsub(normalized, "[^%w]+", "_")
    normalized = string.gsub(normalized, "^_+", "")
    normalized = string.gsub(normalized, "_+$", "")
    return normalized
end

local function get_race_family(value)
    local normalized = normalize_identifier(value)
    if string.find(normalized, "trader", 1, true)
        or string.find(normalized, "tec", 1, true)
    then
        return "trader"
    end
    if string.find(normalized, "advent", 1, true) then
        return "advent"
    end
    if string.find(normalized, "vasari", 1, true) then
        return "vasari"
    end
    return nil
end

local function safe_player_used_supply(player)
    local ok, value = pcall(function()
        return player.used_supply
    end)
    if ok and type(value) == "number" and value >= 0.0 then
        return value
    end
    return nil
end

local function get_titan_supply_cost(context, titan_type)
    local ok, value = pcall(function()
        return context.simulation:get_unit_supply_cost(titan_type)
    end)
    if ok and type(value) == "number" and value > 0.0 then
        return value
    end
    return CONFIG.fallback_titan_supply_cost
end

local function ensure_supply_support(context, player, target_count)
    local race_family = get_race_family(safe_player_race(player))
    local support = SUPPLY_SUPPORT_BY_FAMILY[race_family]
    if support == nil then
        return nil
    end

    local wanted_index = support.stage_last_research_index[target_count]
    if wanted_index == nil then
        return nil
    end

    local completed_key = player_state_key(
        player.player_index,
        "supply_support_research_count"
    )
    local completed_count = context.shared[completed_key] or 0
    if type(completed_count) ~= "number" or completed_count < 0 then
        completed_count = 0
    end
    completed_count = math.min(
        math.floor(completed_count),
        #support.research_ids
    )

    for research_index = completed_count + 1, wanted_index do
        local research_id = support.research_ids[research_index]
        local give_ok, give_error = pcall(function()
            context.simulation:give_research(player, research_id)
        end)
        if not give_ok then
            log_once(
                context,
                player_state_key(
                    player.player_index,
                    "supply_research_error_" .. tostring(research_index)
                ),
                "ERROR: supply support research failed player="
                    .. tostring(player.player_index)
                    .. " research=" .. tostring(research_id)
                    .. " error=" .. tostring(give_error)
            )
            return nil
        end

        completed_count = research_index
        context.shared[completed_key] = completed_count
        context.shared[
            player_state_key(player.player_index, "guaranteed_supply_cap")
        ] = support.cap_after_research[research_index]
    end

    local guaranteed_cap = support.cap_after_research[completed_count]
    if completed_count >= wanted_index and guaranteed_cap ~= nil then
        local logged_key = player_state_key(
            player.player_index,
            "supply_stage_logged_" .. tostring(target_count)
        )
        log_once(
            context,
            logged_key,
            "supply support player=" .. tostring(player.player_index)
                .. " family=" .. tostring(race_family)
                .. " completed_through="
                .. support.research_ids[completed_count]
                .. " guaranteed_cap=" .. tostring(guaranteed_cap)
        )
        return guaranteed_cap
    end

    return nil
end

local function normalize_full_faction(value)
    local normalized = normalize_identifier(value)
    if TITAN_PLAN_BY_FACTION[normalized] ~= nil then
        return normalized
    end

    local family = get_race_family(normalized)
    if family == nil then
        return nil
    end

    if string.find(normalized, "loyalist", 1, true) then
        return family .. "_loyalist"
    end
    if string.find(normalized, "rebel", 1, true) then
        return family .. "_rebel"
    end

    return nil
end

local function is_unit_alive_and_owned(context, player, unit_id)
    if type(unit_id) ~= "number" or unit_id <= 0 then
        return false
    end

    local exists_ok, exists = pcall(function()
        return context.simulation:does_unit_exist_by_id(unit_id)
    end)
    if not exists_ok or not exists then
        return false
    end

    local unit_ok, unit = pcall(function()
        return context.simulation:get_unit_by_id(unit_id)
    end)
    if not unit_ok or unit == nil then
        return false
    end

    -- The numeric owner accessor is documented inconsistently as both a
    -- player ID and a player index. Match the official pirate event's
    -- unambiguous pattern: resolve the owner object and compare player_index.
    local owner_ok, owner = pcall(function()
        return context.simulation:get_unit_owner(unit)
    end)
    if not owner_ok or owner == nil then
        return false
    end

    local index_ok, owner_player_index = pcall(function()
        return owner.player_index
    end)
    return index_ok and owner_player_index == player.player_index
end

local function definition_matches_titan(definition_name, titan_type)
    return definition_name == titan_type
        or definition_name == "native_" .. titan_type
end

local function build_owned_titan_index(context, player)
    local result = {}
    for _, unit in ipairs(safe_player_units(player, "all_units")) do
        local definition_name = safe_unit_definition_name(unit)
        local titan_type = CANONICAL_TITAN_BY_DEFINITION[definition_name]
        if titan_type ~= nil then
            local unit_id = safe_unit_id(unit)
            if unit_id ~= nil
                and is_unit_alive_and_owned(context, player, unit_id)
                and (
                    result[titan_type] == nil
                    or unit_id < result[titan_type]
                )
            then
                result[titan_type] = unit_id
            end
        end
    end
    return result
end

local function has_owned_definition(player, definition_name)
    for _, unit in ipairs(safe_player_units(player, "all_units")) do
        if safe_unit_definition_name(unit) == definition_name then
            return true
        end
    end
    return false
end

local function resolve_faction_from_markers(player, race_family)
    local matched_faction = nil
    for _, faction in ipairs(FACTION_IDS) do
        local marker_units = FACTION_MARKER_UNITS[faction]
        if get_race_family(faction) == race_family then
            local faction_matched = false
            for _, definition_name in ipairs(marker_units) do
                if has_owned_definition(player, definition_name) then
                    faction_matched = true
                    break
                end
            end

            if faction_matched then
                if matched_faction ~= nil and matched_faction ~= faction then
                    -- Captured units or another mod produced conflicting
                    -- markers. Do not guess between two alignments.
                    return nil
                end
                matched_faction = faction
            end
        end
    end
    return matched_faction
end

local function get_or_select_plan(context, player)
    local plan_key = player_state_key(player.player_index, "titan_plan_id")
    local stored_plan_id = context.shared[plan_key]
    if type(stored_plan_id) == "string" then
        if TITAN_PLAN_BY_FACTION[stored_plan_id] ~= nil then
            return stored_plan_id, TITAN_PLAN_BY_FACTION[stored_plan_id]
        end

        local stored_family = string.match(stored_plan_id, "^family_(.+)$")
        if stored_family ~= nil and TITAN_PLAN_BY_FAMILY[stored_family] ~= nil then
            return stored_plan_id, TITAN_PLAN_BY_FAMILY[stored_family]
        end
    end

    local raw_race = safe_player_race(player)
    local faction = normalize_full_faction(raw_race)
    local method = "player.race"
    local race_family = get_race_family(raw_race)

    if faction == nil and race_family ~= nil then
        faction = resolve_faction_from_markers(player, race_family)
        method = "native unit marker"
    end

    if faction ~= nil then
        context.shared[plan_key] = faction
        log_once(
            context,
            player_state_key(player.player_index, "plan_logged"),
            "player=" .. tostring(player.player_index)
                .. " race=" .. tostring(raw_race)
                .. " plan=" .. faction
                .. " resolved_by=" .. method
        )
        return faction, TITAN_PLAN_BY_FACTION[faction]
    end

    if race_family ~= nil then
        local fallback_id = "family_" .. race_family
        context.shared[plan_key] = fallback_id
        log_once(
            context,
            player_state_key(player.player_index, "plan_logged"),
            "WARNING: player=" .. tostring(player.player_index)
                .. " exposes broad race=" .. tostring(raw_race)
                .. "; using deterministic six-Titan compatibility plan="
                .. fallback_id
        )
        return fallback_id, TITAN_PLAN_BY_FAMILY[race_family]
    end

    return nil, nil
end

local function record_initial_player_control(context, player)
    local player_index = player.player_index
    local human_key = player_state_key(player_index, "ever_human")
    local ai_key = player_state_key(player_index, "confirmed_ai")

    if player.is_human then
        context.shared[human_key] = true
        context.shared[ai_key] = false
        return
    end

    if player.is_npc then
        context.shared[ai_key] = false
        return
    end

    if safe_ai_difficulty(player) ~= nil then
        context.shared[ai_key] = true
    else
        context.shared[ai_key] = false
        log_once(
            context,
            player_state_key(player_index, "unconfirmed_ai_warned"),
            "WARNING: non-human playable slot player="
                .. tostring(player_index)
                .. " has no AI difficulty; it will not receive scripted Titans"
        )
    end
end

local function is_confirmed_active_ai(context, player)
    local player_index = player.player_index
    local human_key = player_state_key(player_index, "ever_human")
    local ai_key = player_state_key(player_index, "confirmed_ai")

    if player.is_human then
        -- Persist this identity. player.is_human becomes false when a human
        -- disconnects, so checking only its current value is unsafe.
        context.shared[human_key] = true
        context.shared[ai_key] = false
        return false
    end

    if context.shared[human_key] == true then
        return false
    end
    if player.is_npc or player.has_lost then
        return false
    end

    return context.shared[ai_key] == true
end

local function get_all_playable_player_indices(context)
    local ok, indices = pcall(function()
        return context.simulation:filter_playable_players(function()
            return true
        end)
    end)
    if ok and type(indices) == "table" then
        return indices
    end
    return {}
end

local function register_death_watch(
    context,
    player_index,
    titan_type,
    unit_id
)
    local tracker = context:get_or_create_unit_tracker(
        tracker_name(player_index, titan_type)
    )
    local watch_key = state_key(player_index, titan_type, "death_watch_id")
    if context.shared[watch_key] == unit_id then
        return
    end

    -- Older versions used add_unit(), so remove and re-add the tracker entry
    -- once to upgrade it to an actual death notification subscription.
    local watch_ok, watch_error = pcall(function()
        if tracker:has_unit(unit_id) then
            tracker:remove_unit(unit_id)
        end
        tracker:add_unit_with_death_notification(unit_id)
    end)

    if watch_ok then
        context.shared[watch_key] = unit_id
        return
    end

    -- The regular update scan remains a complete fallback if a future API
    -- version removes death notifications.
    pcall(function()
        tracker:add_unit(unit_id)
    end)
    context.shared[watch_key] = 0
    log_once(
        context,
        state_key(player_index, titan_type, "death_watch_warned"),
        "WARNING: death notification unavailable for player="
            .. tostring(player_index)
            .. " titan=" .. titan_type
            .. " error=" .. tostring(watch_error)
            .. "; periodic ownership scan remains active"
    )
end

local function adopt_unit(context, player, titan_type, unit_id)
    context.shared[state_key(player.player_index, titan_type, "id")] = unit_id
    context.shared[state_key(player.player_index, titan_type, "ever_present")] = true
    -- Preserve the old marker so saves can move freely between compatible
    -- revisions without forgetting that this type was already introduced.
    context.shared[state_key(player.player_index, titan_type, "granted")] = true
    context.shared[state_key(player.player_index, titan_type, "due")] = 0.0
    context.shared[state_key(player.player_index, titan_type, "retry")] = 0.0
    register_death_watch(
        context,
        player.player_index,
        titan_type,
        unit_id
    )
end

local function find_tracked_unit_id(context, player, titan_type)
    local stored_id = context.shared[
        state_key(player.player_index, titan_type, "id")
    ] or 0
    if is_unit_alive_and_owned(context, player, stored_id) then
        local unit = context.simulation:get_unit_by_id(stored_id)
        local definition_name = safe_unit_definition_name(unit)
        if definition_name == nil
            or definition_matches_titan(definition_name, titan_type)
        then
            return stored_id
        end
    end

    local tracker = context:get_or_create_unit_tracker(
        tracker_name(player.player_index, titan_type)
    )
    local units_ok, tracked_ids = pcall(function()
        return tracker:get_units()
    end)
    if units_ok and type(tracked_ids) == "table" then
        for _, candidate_id in ipairs(tracked_ids) do
            if is_unit_alive_and_owned(context, player, candidate_id) then
                local unit = context.simulation:get_unit_by_id(candidate_id)
                local definition_name = safe_unit_definition_name(unit)
                if definition_name == nil
                    or definition_matches_titan(definition_name, titan_type)
                then
                    return candidate_id
                end
            end
        end
    end

    return nil
end

local function resolve_alive_unit_id(
    context,
    player,
    titan_type,
    owned_titan_index
)
    local indexed_id = owned_titan_index[titan_type]
    if indexed_id ~= nil then
        adopt_unit(context, player, titan_type, indexed_id)
        return indexed_id
    end

    local tracked_id = find_tracked_unit_id(context, player, titan_type)
    if tracked_id ~= nil then
        adopt_unit(context, player, titan_type, tracked_id)
        return tracked_id
    end

    return nil
end

local function is_unit_owned_by_player(context, player, unit)
    local unit_id = safe_unit_id(unit)
    return unit_id ~= nil
        and is_unit_alive_and_owned(context, player, unit_id)
end

local function gravity_well_for_unit(context, unit)
    local unit_id = safe_unit_id(unit)
    if unit_id == nil then
        return nil
    end

    local id_ok, gravity_well_id = pcall(function()
        return context.simulation:get_unit_current_gravity_well_id(unit_id)
    end)
    if not id_ok
        or type(gravity_well_id) ~= "number"
        or gravity_well_id <= 0
    then
        return nil
    end

    local well_ok, gravity_well = pcall(function()
        return context.simulation:get_unit_by_id(gravity_well_id)
    end)
    if not well_ok or gravity_well == nil then
        return nil
    end

    local exists_ok, exists = pcall(function()
        return context.simulation:does_unit_exist(gravity_well)
    end)
    if exists_ok and exists then
        return gravity_well
    end
    return nil
end

local function get_spawn_gravity_well(context, player)
    -- Prefer the home planet only while the player still owns it.
    local home_planet = player.home_planet
    if is_unit_owned_by_player(context, player, home_planet) then
        local home_well = gravity_well_for_unit(context, home_planet)
        if home_well ~= nil then
            return home_well
        end
    end

    -- This API directly returns gravity-well units and also validates primary
    -- fixture ownership, avoiding the planet/gravity-well type mismatch that
    -- made the old spawn call invalid.
    local wells_ok, owned_wells = pcall(function()
        return context.simulation:get_gravity_wells_owned_by_player(player)
    end)
    if wells_ok and type(owned_wells) == "table" then
        for _, gravity_well in ipairs(owned_wells) do
            local exists_ok, exists = pcall(function()
                return context.simulation:does_unit_exist(gravity_well)
            end)
            if exists_ok and exists then
                return gravity_well
            end
        end
    end

    -- Vasari Exodus can remain alive without planets. Use an owned ruler
    -- ship's current well, then any owned unit's well as a final fallback.
    for _, rulership in ipairs(safe_player_units(player, "alive_rulerships")) do
        if is_unit_owned_by_player(context, player, rulership) then
            local gravity_well = gravity_well_for_unit(context, rulership)
            if gravity_well ~= nil then
                return gravity_well
            end
        end
    end

    for _, unit in ipairs(safe_player_units(player, "all_units")) do
        if is_unit_owned_by_player(context, player, unit) then
            local gravity_well = gravity_well_for_unit(context, unit)
            if gravity_well ~= nil then
                return gravity_well
            end
        end
    end

    return nil
end

local function spawn_definition_candidates(plan_id, titan_type)
    if TITAN_PLAN_BY_FACTION[plan_id] ~= nil
        and NATIVE_TITAN_BY_FACTION[plan_id] == titan_type
    then
        return {
            "native_" .. titan_type,
            titan_type,
        }
    end

    return {titan_type}
end

local function spawn_titan(context, player, plan_id, titan_type)
    local gravity_well = get_spawn_gravity_well(context, player)
    if gravity_well == nil then
        log_once(
            context,
            state_key(player.player_index, titan_type, "no_anchor_warned"),
            "WARNING: no valid owned/current gravity well for player="
                .. tostring(player.player_index)
                .. "; delayed titan=" .. titan_type
        )
        return nil
    end

    local last_error = nil
    for _, definition_name in ipairs(
        spawn_definition_candidates(plan_id, titan_type)
    ) do
        local spawn_ok, unit_or_error = pcall(function()
            return context.simulation:spawn_unit_in_hyperspace(
                definition_name,
                gravity_well,
                player,
                CONFIG.hyperspace_arrival_seconds
            )
        end)

        if spawn_ok then
            local unit_id = safe_unit_id(unit_or_error)
            if unit_id ~= nil then
                adopt_unit(context, player, titan_type, unit_id)
                pcall(function()
                    context.simulation:set_unit_auto_order_mode_by_id(
                        unit_id,
                        "engage_any_targets"
                    )
                end)

                log_info(
                    "spawned player=" .. tostring(player.player_index)
                        .. " titan=" .. titan_type
                        .. " definition=" .. definition_name
                        .. " id=" .. tostring(unit_id)
                )
                return unit_id
            end
            last_error = "spawn returned no unit"
        else
            last_error = unit_or_error
        end
    end

    log_info(
        "ERROR: spawn failed player=" .. tostring(player.player_index)
            .. " titan=" .. titan_type
            .. " error=" .. tostring(last_error)
    )
    return nil
end

local function spawn_titan_with_supply_budget(
    context,
    player,
    plan_id,
    titan_type,
    remaining_supply,
    guaranteed_cap
)
    local titan_supply_cost = get_titan_supply_cost(context, titan_type)
    if remaining_supply < titan_supply_cost then
        log_once(
            context,
            state_key(player.player_index, titan_type, "supply_wait_warned"),
            "supply wait player=" .. tostring(player.player_index)
                .. " titan=" .. titan_type
                .. " used=" .. tostring(
                    safe_player_used_supply(player) or "unknown"
                )
                .. " guaranteed_cap=" .. tostring(guaranteed_cap)
                .. " remaining=" .. tostring(remaining_supply)
                .. " required=" .. tostring(titan_supply_cost)
        )
        return nil, remaining_supply
    end

    local unit_id = spawn_titan(context, player, plan_id, titan_type)
    if unit_id == nil then
        return nil, remaining_supply
    end

    context.shared[
        state_key(player.player_index, titan_type, "supply_wait_warned")
    ] = false
    return unit_id, remaining_supply - titan_supply_cost
end

local function current_stage_target(now)
    if now >= CONFIG.stage_60_seconds then
        return 6
    end
    if now >= CONFIG.stage_40_seconds then
        return 2
    end
    if now >= CONFIG.stage_20_seconds then
        return 1
    end
    return 0
end

local function has_ever_been_present(context, player_index, titan_type)
    return context.shared[
        state_key(player_index, titan_type, "ever_present")
    ] == true
        or context.shared[
            state_key(player_index, titan_type, "granted")
        ] == true
end

local function schedule_missing_replacement(
    context,
    player_index,
    titan_type,
    now,
    reason
)
    local due_key = state_key(player_index, titan_type, "due")
    local due = context.shared[due_key] or 0.0
    if due > 0.0 then
        return
    end

    local replacement_due = now + CONFIG.replacement_delay_seconds
    context.shared[due_key] = replacement_due
    context.shared[state_key(player_index, titan_type, "retry")] = 0.0
    context.shared[state_key(player_index, titan_type, "id")] = 0
    context.shared[
        state_key(player_index, titan_type, "death_watch_id")
    ] = 0

    log_info(
        "replacement scheduled player=" .. tostring(player_index)
            .. " titan=" .. titan_type
            .. " reason=" .. tostring(reason)
            .. " due=" .. tostring(replacement_due)
    )
end

local function process_player(context, player, now, target_count)
    if target_count <= 0 then
        return
    end

    local guaranteed_cap = ensure_supply_support(
        context,
        player,
        target_count
    )
    if guaranteed_cap == nil then
        log_once(
            context,
            player_state_key(player.player_index, "no_supply_support_warned"),
            "ERROR: no guaranteed supply support for player="
                .. tostring(player.player_index)
                .. " race=" .. tostring(safe_player_race(player))
                .. "; Titan grants are paused"
        )
        return
    end

    local used_supply = safe_player_used_supply(player)
    if used_supply == nil then
        log_once(
            context,
            player_state_key(player.player_index, "used_supply_error_warned"),
            "ERROR: player.used_supply unavailable for player="
                .. tostring(player.player_index)
                .. "; Titan grants are paused to avoid overfilling supply"
        )
        return
    end
    local remaining_supply = math.max(0.0, guaranteed_cap - used_supply)

    local plan_id, titan_plan = get_or_select_plan(context, player)
    if titan_plan == nil then
        log_once(
            context,
            player_state_key(player.player_index, "unsupported_race_warned"),
            "ERROR: unsupported playable race="
                .. tostring(safe_player_race(player))
                .. " player=" .. tostring(player.player_index)
        )
        return
    end

    local owned_titan_index = build_owned_titan_index(context, player)
    local alive_count = 0

    for plan_index = 1, math.min(target_count, #titan_plan) do
        local titan_type = titan_plan[plan_index]
        local entitled_key = state_key(
            player.player_index,
            titan_type,
            "entitled"
        )
        context.shared[entitled_key] = true

        local active_id = resolve_alive_unit_id(
            context,
            player,
            titan_type,
            owned_titan_index
        )

        if active_id ~= nil then
            alive_count = alive_count + 1
        elseif has_ever_been_present(
            context,
            player.player_index,
            titan_type
        ) then
            -- The death callback normally starts this timer immediately.
            -- This ownership/existence scan also handles capture, transfer,
            -- saves made by the old script, and missed notifications.
            schedule_missing_replacement(
                context,
                player.player_index,
                titan_type,
                now,
                "periodic scan"
            )
        else
            local retry_key = state_key(
                player.player_index,
                titan_type,
                "retry"
            )
            local retry = context.shared[retry_key] or 0.0
            if now >= retry then
                local spawned_id = nil
                spawned_id, remaining_supply =
                    spawn_titan_with_supply_budget(
                        context,
                        player,
                        plan_id,
                        titan_type,
                        remaining_supply,
                        guaranteed_cap
                    )
                if spawned_id ~= nil then
                    alive_count = alive_count + 1
                    owned_titan_index[titan_type] = spawned_id
                else
                    context.shared[retry_key] = (
                        now + CONFIG.spawn_retry_seconds
                    )
                end
            end
        end
    end

    -- Replacement and initial grants share the same supply budget. The
    -- research chain above proves the cap, and successful spawns reserve
    -- their cost locally in case used_supply updates at the end of the tick.
    for plan_index = 1, math.min(target_count, #titan_plan) do
        local titan_type = titan_plan[plan_index]
        local due_key = state_key(player.player_index, titan_type, "due")
        local retry_key = state_key(player.player_index, titan_type, "retry")
        local due = context.shared[due_key] or 0.0
        local retry = context.shared[retry_key] or 0.0

        if due > 0.0 and now >= due and now >= retry then
            local active_id = resolve_alive_unit_id(
                context,
                player,
                titan_type,
                owned_titan_index
            )
            if active_id ~= nil then
                context.shared[due_key] = 0.0
                context.shared[retry_key] = 0.0
            else
                local replacement_id = nil
                replacement_id, remaining_supply =
                    spawn_titan_with_supply_budget(
                        context,
                        player,
                        plan_id,
                        titan_type,
                        remaining_supply,
                        guaranteed_cap
                    )
                if replacement_id ~= nil then
                    owned_titan_index[titan_type] = replacement_id
                else
                    context.shared[retry_key] = (
                        now + CONFIG.spawn_retry_seconds
                    )
                end
            end
        end
    end

    local last_stage_key = player_state_key(
        player.player_index,
        "last_logged_stage_target"
    )
    if context.shared[last_stage_key] ~= target_count then
        context.shared[last_stage_key] = target_count
        log_info(
            "stage player=" .. tostring(player.player_index)
                .. " target=" .. tostring(target_count)
                .. " alive=" .. tostring(alive_count)
                .. " plan=" .. tostring(plan_id)
                .. " guaranteed_supply=" .. tostring(guaranteed_cap)
        )
    end
end

function Get_event_metadata()
    local metadata = EventMetadata.create()

    metadata.event_name = "AI Foreign Titan Reinforcement"
    metadata.event_id = EVENT_ID

    metadata.register_event_function = "Ai_foreign_titan_register"
    metadata.on_event_registered_function = (
        "Ai_foreign_titan_on_event_registered"
    )
    metadata.on_initialize_function = "Ai_foreign_titan_initialize"
    metadata.should_trigger_function = "Ai_foreign_titan_should_trigger"
    metadata.on_start_function = "Ai_foreign_titan_on_start"
    metadata.on_update_function = "Ai_foreign_titan_on_update"
    metadata.on_complete_function = "Ai_foreign_titan_on_complete"
    metadata.on_teardown_function = "Ai_foreign_titan_on_teardown"
    metadata.on_unit_death_function = "Ai_foreign_titan_on_unit_death"

    metadata.trigger_check_interval_seconds = 2.0
    metadata.update_interval_seconds = 10.0
    metadata.on_update_function_initial_delay = 5.0

    metadata.event_version = 2.0
    metadata.description = (
        "Timed AI-only grants and replacements for all six Titan types"
    )
    metadata.author = "MORVELIA / Marshall"
    metadata.priority = 40.0
    metadata.incompatible_event_ids = {}
    metadata.max_concurrent_instances = 1

    local valid, validation_error = EventMetadata.validate(metadata)
    if not valid then
        local message = LOG_PREFIX
            .. "metadata validation failed: "
            .. tostring(validation_error)
        print(message)
        error(message)
    end

    return metadata
end

function Ai_foreign_titan_register(context)
    -- The mod's purpose applies equally to random maps and unique scenarios.
    -- Filtering playable, confirmed-AI players is sufficient and avoids
    -- silently disabling the feature in DLC scenarios.
    return true
end

function Ai_foreign_titan_on_event_registered(context)
    for _, player_index in ipairs(get_all_playable_player_indices(context)) do
        local player = context.simulation:get_player_by_player_index(
            player_index
        )
        if player ~= nil then
            record_initial_player_control(context, player)
        end
    end

    local unique_ok, has_unique_scenario = pcall(function()
        return context.simulation:has_unique_scenario()
    end)
    log_info(
        "registered event_id=" .. EVENT_ID
            .. " metadata_version=2.0"
            .. " unique_scenario="
            .. tostring(unique_ok and has_unique_scenario or false)
    )
end

function Ai_foreign_titan_initialize(context)
    context.instance.ready = true
end

function Ai_foreign_titan_should_trigger(context)
    return context.instance.ready == true
end

function Ai_foreign_titan_on_start(context)
    context.instance.ready = false
    log_info(
        "event started at game_time="
            .. tostring(context.simulation.current_time)
    )
end

function Ai_foreign_titan_on_update(context)
    local now = context.simulation.current_time
    local target_count = current_stage_target(now)

    for _, player_index in ipairs(get_all_playable_player_indices(context)) do
        local player = context.simulation:get_player_by_player_index(
            player_index
        )
        if player ~= nil and is_confirmed_active_ai(context, player) then
            process_player(context, player, now, target_count)
        end
    end
end

function Ai_foreign_titan_on_unit_death(context, unit_id)
    local now = context.simulation.current_time
    local matched = false

    for _, player_index in ipairs(get_all_playable_player_indices(context)) do
        for _, titan_type in ipairs(ALL_TITAN_TYPES) do
            local stored_id = context.shared[
                state_key(player_index, titan_type, "id")
            ] or 0
            local watched_id = context.shared[
                state_key(player_index, titan_type, "death_watch_id")
            ] or 0

            if stored_id == unit_id or watched_id == unit_id then
                matched = true
                schedule_missing_replacement(
                    context,
                    player_index,
                    titan_type,
                    now,
                    "death notification"
                )
            end
        end
    end

    if not matched then
        debug_log("unmatched tracked unit death id=" .. tostring(unit_id))
    end
end

function Ai_foreign_titan_on_complete(context)
    -- This is a persistent match-long maintenance event and normally never
    -- completes. The required callback is intentionally a no-op.
    debug_log("event completed")
end

function Ai_foreign_titan_on_teardown(context)
    -- Spawned Titans belong to their AI player and must survive event
    -- teardown/save transitions; only event state is released by the engine.
    debug_log("event teardown")
end
