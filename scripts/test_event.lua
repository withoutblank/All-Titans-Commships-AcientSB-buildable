-- AI Foreign Titan Reinforcement Event
-- The native faction Titan remains under the game's normal AI Titan planner.
-- This event manages only the five non-native Titan types for AI players.

local EventMetadata = require("event_metadata")

local EVENT_ID = "ai_foreign_titan_reinforcement_v1"
local LOG_PREFIX = "[ai_foreign_titan_reinforcement] "

local CONFIG = {
    debug_enabled = true,
    stage_20_seconds = 20.0 * 60.0,
    stage_40_seconds = 40.0 * 60.0,
    stage_60_seconds = 60.0 * 60.0,
    death_scan_interval_seconds = 10.0 * 60.0,
    replacement_delay_seconds = 5.0 * 60.0,
    supply_retry_seconds = 60.0,
    hyperspace_arrival_seconds = 10.0,
    titan_supply_cost = 150.0,
}

local FOREIGN_TITANS_BY_FACTION = {
    trader_loyalist = {
        "trader_rebel_titan",
        "advent_loyalist_titan",
        "advent_rebel_titan",
        "vasari_loyalist_titan",
        "vasari_rebel_titan",
    },
    trader_rebel = {
        "trader_loyalist_titan",
        "advent_rebel_titan",
        "advent_loyalist_titan",
        "vasari_rebel_titan",
        "vasari_loyalist_titan",
    },
    advent_loyalist = {
        "advent_rebel_titan",
        "trader_loyalist_titan",
        "trader_rebel_titan",
        "vasari_loyalist_titan",
        "vasari_rebel_titan",
    },
    advent_rebel = {
        "advent_loyalist_titan",
        "trader_rebel_titan",
        "trader_loyalist_titan",
        "vasari_rebel_titan",
        "vasari_loyalist_titan",
    },
    vasari_loyalist = {
        "vasari_rebel_titan",
        "trader_loyalist_titan",
        "trader_rebel_titan",
        "advent_loyalist_titan",
        "advent_rebel_titan",
    },
    vasari_rebel = {
        "vasari_loyalist_titan",
        "trader_rebel_titan",
        "trader_loyalist_titan",
        "advent_rebel_titan",
        "advent_loyalist_titan",
    },
}

-- Conservative fallback values copied from the active player definitions.
-- The smallest tier able to contain current used supply never exceeds the
-- player's real unlocked tier, so this fallback can delay a replacement but
-- will not knowingly overfill fleet supply.
local SUPPLY_TIERS_BY_RACE = {
    trader = {100, 250, 500, 1000, 1500, 2000},
    advent = {100, 250, 500, 1000, 1500, 2000},
    vasari = {120, 300, 600, 900, 1500, 2100, 2400},
}

local function debug_log(message)
    if CONFIG.debug_enabled then
        print(LOG_PREFIX .. message)
    end
end

local function state_key(player_index, titan_type, suffix)
    return "p" .. tostring(player_index) .. "_" .. titan_type .. "_" .. suffix
end

local function player_state_key(player_index, suffix)
    return "p" .. tostring(player_index) .. "_" .. suffix
end

local function tracker_name(player_index, titan_type)
    return "ai_foreign_titan_p" .. tostring(player_index) .. "_" .. titan_type
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

local function get_active_ai_player_indices(context)
    return context.simulation:filter_playable_players(function(player)
        return not player.is_human and not player.is_npc and not player.has_lost
    end)
end

local function get_spawn_anchor(context, player)
    local home_planet = player.home_planet
    if home_planet ~= nil and context.simulation:does_unit_exist(home_planet) then
        return home_planet
    end

    for _, planet in ipairs(player.owned_planets or {}) do
        if context.simulation:does_unit_exist(planet) then
            return planet
        end
    end

    return nil
end

local function get_race_family(faction)
    if string.find(faction, "trader", 1, true) then
        return "trader"
    end
    if string.find(faction, "advent", 1, true) then
        return "advent"
    end
    if string.find(faction, "vasari", 1, true) then
        return "vasari"
    end
    return nil
end

local function try_get_runtime_max_supply(player)
    local candidate_fields = {
        "max_supply",
        "current_max_supply",
        "fleet_supply_cap",
    }

    for _, field_name in ipairs(candidate_fields) do
        local ok, value = pcall(function()
            return player[field_name]
        end)
        if ok and type(value) == "number" and value >= 0.0 then
            return value
        end
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

    return CONFIG.titan_supply_cost
end

local function is_unit_alive_and_owned(context, player, unit_id)
    if type(unit_id) ~= "number" or unit_id <= 0 then
        return false
    end
    if not context.simulation:does_unit_exist_by_id(unit_id) then
        return false
    end

    local owner_id = context.simulation:get_unit_owner_id(unit_id)
    return owner_id ~= nil and owner_id == player.id
end

local function resolve_tracked_unit_id(context, player, titan_type)
    local id_key = state_key(player.player_index, titan_type, "id")
    local stored_id = context.shared[id_key] or 0
    if is_unit_alive_and_owned(context, player, stored_id) then
        return stored_id
    end

    local tracker = context:get_or_create_unit_tracker(
        tracker_name(player.player_index, titan_type)
    )
    local tracked_ids = tracker:get_units()
    for _, candidate_id in ipairs(tracked_ids) do
        if is_unit_alive_and_owned(context, player, candidate_id) then
            context.shared[id_key] = candidate_id
            return candidate_id
        end
    end

    return nil
end

local function was_granted(context, player_index, titan_type)
    return context.shared[state_key(player_index, titan_type, "granted")] == true
end

local function calculate_alive_managed_supply(context, player, foreign_titans)
    local total = 0.0
    for _, titan_type in ipairs(foreign_titans) do
        if was_granted(context, player.player_index, titan_type) then
            local unit_id = resolve_tracked_unit_id(context, player, titan_type)
            if unit_id ~= nil then
                total = total + get_titan_supply_cost(context, titan_type)
            end
        end
    end
    return total
end

local function estimate_max_supply(context, player, foreign_titans)
    local runtime_value = try_get_runtime_max_supply(player)
    if runtime_value ~= nil then
        return runtime_value, true
    end

    local tiers = SUPPLY_TIERS_BY_RACE[get_race_family(player.race)]
    local used_supply = player.used_supply or 0.0
    if tiers == nil then
        return used_supply, false
    end

    -- Scripted foreign Titans can push used_supply over the unlocked cap.
    -- Subtract only the alive Titans managed by this event before inferring
    -- the lowest possible unlocked tier. This makes the fallback conservative:
    -- it may postpone a replacement, but it will not knowingly overfill supply.
    local managed_supply = calculate_alive_managed_supply(
        context,
        player,
        foreign_titans
    )
    local organic_used_supply = math.max(0.0, used_supply - managed_supply)

    for _, tier in ipairs(tiers) do
        if tier >= organic_used_supply then
            return tier, false
        end
    end

    return tiers[#tiers], false
end

local function get_remaining_supply(context, player, foreign_titans)
    local maximum_supply, exact = estimate_max_supply(
        context,
        player,
        foreign_titans
    )
    local used_supply = player.used_supply or 0.0
    return math.max(0.0, maximum_supply - used_supply), maximum_supply, exact
end

local function mark_spawned(context, player, titan_type, unit_id)
    context.shared[state_key(player.player_index, titan_type, "id")] = unit_id
    context.shared[state_key(player.player_index, titan_type, "granted")] = true
    context.shared[state_key(player.player_index, titan_type, "due")] = 0.0
    context.shared[state_key(player.player_index, titan_type, "retry")] = 0.0

    local tracker = context:get_or_create_unit_tracker(
        tracker_name(player.player_index, titan_type)
    )
    tracker:add_unit(unit_id)
end

local function spawn_foreign_titan(context, player, titan_type)
    local anchor = get_spawn_anchor(context, player)
    if anchor == nil then
        debug_log(
            "no owned planet for player=" .. tostring(player.player_index) ..
            "; delayed titan=" .. titan_type
        )
        return nil
    end

    local unit = context.simulation:spawn_unit_in_hyperspace(
        titan_type,
        anchor,
        player,
        CONFIG.hyperspace_arrival_seconds
    )
    local unit_id = safe_unit_id(unit)
    if unit_id == nil then
        debug_log(
            "spawn failed player=" .. tostring(player.player_index) ..
            " titan=" .. titan_type
        )
        return nil
    end

    mark_spawned(context, player, titan_type, unit_id)
    context.simulation:set_unit_auto_order_mode_by_id(
        unit_id,
        "engage_any_targets"
    )

    debug_log(
        "spawned player=" .. tostring(player.player_index) ..
        " titan=" .. titan_type ..
        " id=" .. tostring(unit_id)
    )
    return unit_id
end

local function current_stage_target(now)
    if now >= CONFIG.stage_60_seconds then
        return 5
    end
    if now >= CONFIG.stage_40_seconds then
        return 2
    end
    if now >= CONFIG.stage_20_seconds then
        return 1
    end
    return 0
end

local function process_initial_grants(context, player, foreign_titans, target_count)
    if target_count <= 0 then
        return
    end

    local granted_count = 0
    for _, titan_type in ipairs(foreign_titans) do
        if was_granted(context, player.player_index, titan_type) then
            granted_count = granted_count + 1
        end
    end

    if granted_count >= target_count then
        return
    end

    -- Timed grants are deterministic and do not wait for fleet supply.
    -- Replacement grants after deaths are supply-aware.
    for _, titan_type in ipairs(foreign_titans) do
        if granted_count >= target_count then
            break
        end

        if not was_granted(context, player.player_index, titan_type) then
            local unit_id = spawn_foreign_titan(context, player, titan_type)
            if unit_id == nil then
                break
            end

            granted_count = granted_count + 1
        end
    end
end

local function queue_missing_replacements(context, player, foreign_titans, now)
    local next_scan_key = player_state_key(
        player.player_index,
        "next_foreign_titan_scan"
    )
    local next_scan = context.shared[next_scan_key]
    if type(next_scan) ~= "number" or next_scan <= 0 then
        context.shared[next_scan_key] = now + CONFIG.death_scan_interval_seconds
        return
    end
    if now < next_scan then
        return
    end

    for _, titan_type in ipairs(foreign_titans) do
        if was_granted(context, player.player_index, titan_type) then
            local unit_id = resolve_tracked_unit_id(context, player, titan_type)
            local due_key = state_key(player.player_index, titan_type, "due")
            local due = context.shared[due_key] or 0.0

            if unit_id ~= nil then
                context.shared[due_key] = 0.0
                context.shared[state_key(player.player_index, titan_type, "retry")] = 0.0
            elseif due <= 0.0 then
                local last_id = context.shared[
                    state_key(player.player_index, titan_type, "id")
                ] or 0
                context.shared[
                    state_key(player.player_index, titan_type, "dead_id")
                ] = last_id
                context.shared[due_key] = now + CONFIG.replacement_delay_seconds
                context.shared[
                    state_key(player.player_index, titan_type, "retry")
                ] = 0.0

                debug_log(
                    "death detected player=" .. tostring(player.player_index) ..
                    " titan=" .. titan_type ..
                    " dead_id=" .. tostring(last_id) ..
                    " replacement_due=" ..
                    tostring(now + CONFIG.replacement_delay_seconds)
                )
            end
        end
    end

    context.shared[next_scan_key] = now + CONFIG.death_scan_interval_seconds
end

local function process_due_replacements(context, player, foreign_titans, now)
    local remaining_supply, maximum_supply, exact = get_remaining_supply(
        context,
        player,
        foreign_titans
    )

    for _, titan_type in ipairs(foreign_titans) do
        if was_granted(context, player.player_index, titan_type) then
            local due_key = state_key(player.player_index, titan_type, "due")
            local retry_key = state_key(player.player_index, titan_type, "retry")
            local due = context.shared[due_key] or 0.0
            local retry = context.shared[retry_key] or 0.0

            if due > 0.0 and now >= due and now >= retry then
                local active_id = resolve_tracked_unit_id(
                    context,
                    player,
                    titan_type
                )
                if active_id ~= nil then
                    context.shared[due_key] = 0.0
                    context.shared[retry_key] = 0.0
                else
                    local titan_supply_cost = get_titan_supply_cost(
                        context,
                        titan_type
                    )
                    if remaining_supply >= titan_supply_cost then
                        local replacement_id = spawn_foreign_titan(
                            context,
                            player,
                            titan_type
                        )
                        if replacement_id ~= nil then
                            remaining_supply = remaining_supply - titan_supply_cost
                        else
                            context.shared[retry_key] = (
                                now + CONFIG.supply_retry_seconds
                            )
                        end
                    else
                        context.shared[retry_key] = (
                            now + CONFIG.supply_retry_seconds
                        )
                        debug_log(
                            "replacement waiting for supply player=" ..
                            tostring(player.player_index) ..
                            " titan=" .. titan_type ..
                            " used=" .. tostring(player.used_supply or 0) ..
                            " max=" .. tostring(maximum_supply) ..
                            " remaining=" .. tostring(remaining_supply) ..
                            " required=" .. tostring(titan_supply_cost) ..
                            " exact=" .. tostring(exact)
                        )
                    end
                end
            end
        end
    end
end

function Get_event_metadata()
    local metadata = EventMetadata.create()

    metadata.event_name = "ai_foreign_titan_reinforcement"
    metadata.event_id = EVENT_ID

    metadata.register_event_function = "Ai_foreign_titan_register"
    metadata.on_initialize_function = "Ai_foreign_titan_initialize"
    metadata.should_trigger_function = "Ai_foreign_titan_should_trigger"
    metadata.on_start_function = "Ai_foreign_titan_on_start"
    metadata.on_update_function = "Ai_foreign_titan_on_update"
    metadata.on_teardown_function = "Ai_foreign_titan_on_teardown"

    metadata.trigger_check_interval_seconds = 2.0
    metadata.update_interval_seconds = 5.0
    metadata.on_update_function_initial_delay = 5.0

    metadata.event_version = 1.0
    metadata.description = "Timed AI-only foreign Titan grants and replacements"
    metadata.author = "MORVELIA / Marshall"
    metadata.priority = 40.0
    metadata.incompatible_event_ids = {}
    metadata.max_concurrent_instances = 1

    return metadata
end

function Ai_foreign_titan_register(context)
    if context.simulation:has_unique_scenario() then
        debug_log("unique scenario detected; event disabled")
        return false
    end

    return true
end

function Ai_foreign_titan_initialize(context)
    context.instance.ready = true
end

function Ai_foreign_titan_should_trigger(context)
    return context.instance.ready == true
end

function Ai_foreign_titan_on_start(context)
    context.instance.ready = false
    debug_log(
        "event started at game_time=" ..
        tostring(context.simulation.current_time)
    )
end

function Ai_foreign_titan_on_update(context)
    local now = context.simulation.current_time
    local target_count = current_stage_target(now)
    local ai_player_indices = get_active_ai_player_indices(context)

    for _, player_index in ipairs(ai_player_indices) do
        local player = context.simulation:get_player_by_player_index(player_index)
        if player ~= nil and not player.has_lost then
            local foreign_titans = FOREIGN_TITANS_BY_FACTION[player.race]
            if foreign_titans ~= nil then
                process_initial_grants(
                    context,
                    player,
                    foreign_titans,
                    target_count
                )

                if now >= CONFIG.stage_60_seconds then
                    queue_missing_replacements(
                        context,
                        player,
                        foreign_titans,
                        now
                    )
                    process_due_replacements(
                        context,
                        player,
                        foreign_titans,
                        now
                    )
                end
            else
                local warned_key = player_state_key(
                    player.player_index,
                    "unsupported_faction_warned"
                )
                if context.shared[warned_key] ~= true then
                    context.shared[warned_key] = true
                    debug_log(
                        "unsupported playable faction=" ..
                        tostring(player.race) ..
                        " player=" .. tostring(player.player_index)
                    )
                end
            end
        end
    end
end

function Ai_foreign_titan_on_teardown(context)
    debug_log("event teardown")
end
