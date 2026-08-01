-- The game currently exposes no generic Lua entry point for the standard
-- enemy_titan_built notification. This observer uses the equivalent Mad Titan
-- notification transport, whose presentation is mapped to the standard enemy
-- Titan notification in notification.uniforms.
--
-- This script is intentionally notification-only. It never creates, removes,
-- replaces, damages, upgrades, or issues orders to any unit.
local EventMetadata = require("event_metadata")

local EVENT_ID = "ai_foreign_titan_build_announcements"
local LOG_PREFIX = "[ai_foreign_titan_announcement] "

-- These are the six cruiser-class compatibility copies used only for foreign
-- Titans. A faction's own canonical Titan remains engine-classified as a Titan
-- and therefore continues to receive the game's native announcement.
local MONITORED_DEFINITIONS = {
    native_trader_loyalist_titan = true,
    native_trader_rebel_titan = true,
    native_advent_loyalist_titan = true,
    native_advent_rebel_titan = true,
    native_vasari_loyalist_titan = true,
    native_vasari_rebel_titan = true,
}

local function log_info(message)
    print(LOG_PREFIX .. message)
end

local function read_property(object, property_name)
    if object == nil then
        return nil
    end

    local ok, value = pcall(function()
        return object[property_name]
    end)
    if ok then
        return value
    end
    return nil
end

local function get_playable_player_indices(context)
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

local function get_player_units(player)
    -- Every monitored Titan has item slots. This engine-provided subset stays
    -- small even in late games; fall back to all_units only if unavailable.
    local units = read_property(player, "all_units_with_items")
    if type(units) == "table" then
        return units, true
    end

    units = read_property(player, "all_units")
    if type(units) == "table" then
        return units, true
    end
    return {}, false
end

local function get_player_index(player)
    local player_index = read_property(player, "player_index")
    if type(player_index) == "number" then
        return player_index
    end
    return nil
end

local function get_unit_id(unit)
    local unit_id = read_property(unit, "id")
    if type(unit_id) == "number" and unit_id > 0 then
        return unit_id
    end
    return nil
end

local function get_unit_definition_name(unit)
    local definition_name = read_property(unit, "def_name")
    if type(definition_name) == "string" then
        return definition_name
    end
    return nil
end

local function player_state_key(player_index, suffix)
    return "p" .. tostring(player_index) .. "_" .. suffix
end

local function unit_state_key(unit_id, suffix)
    return "u" .. tostring(unit_id) .. "_" .. suffix
end

local function log_once(context, key, message)
    if context.shared[key] == true then
        return
    end
    context.shared[key] = true
    log_info(message)
end

local function classify_player(context, player)
    local player_index = get_player_index(player)
    if player_index == nil then
        return "unknown"
    end

    local ever_human_key = player_state_key(player_index, "ever_human")
    if read_property(player, "is_human") == true then
        -- A disconnected human slot may later report is_human=false. Remember
        -- its original identity so it is never mistaken for an AI builder.
        context.shared[ever_human_key] = true
    end

    if context.shared[ever_human_key] == true
        or read_property(player, "is_npc") == true
        or read_property(player, "has_lost") == true then
        return "non_ai"
    end

    -- Evaluate this on every scan. During early event registration the engine
    -- may not yet expose AI difficulty, which made the removed reinforcement
    -- script permanently misclassify AI slots.
    if read_property(player, "ai_difficulty") ~= nil then
        return "ai"
    end
    return "unknown"
end

local function layer_is_full(current_points, maximum_points)
    if type(current_points) ~= "number"
        or type(maximum_points) ~= "number"
        or maximum_points <= 0 then
        return nil
    end

    local tolerance = math.max(1.0, maximum_points * 0.0001)
    return current_points + tolerance >= maximum_points
end

local function get_completion_state(unit)
    -- Ships can appear in player unit collections while under construction.
    -- Full hull (and full armor when exposed) is the read-only completion
    -- signal available to the Lua event API.
    local hull_is_full = layer_is_full(
        read_property(unit, "current_hull_points"),
        read_property(unit, "max_hull_points")
    )
    if hull_is_full == nil then
        return "unknown"
    end
    if not hull_is_full then
        return "building"
    end

    local current_armor = read_property(unit, "current_armor_points")
    local maximum_armor = read_property(unit, "max_armor_points")
    if type(maximum_armor) == "number" and maximum_armor > 0 then
        local armor_is_full = layer_is_full(current_armor, maximum_armor)
        if armor_is_full == nil then
            return "unknown"
        end
        if not armor_is_full then
            return "building"
        end
    end

    return "complete"
end

local function remember_non_ai_units(context, player)
    -- Prevent a later ownership transfer from being mistaken for construction
    -- by an AI. Human and NPC builds themselves intentionally get no script
    -- notification because this feature is scoped to AI players.
    local units, units_available = get_player_units(player)
    if not units_available then
        return
    end

    for _, unit in ipairs(units) do
        local definition_name = get_unit_definition_name(unit)
        if MONITORED_DEFINITIONS[definition_name] == true then
            local unit_id = get_unit_id(unit)
            if unit_id ~= nil then
                context.shared[unit_state_key(unit_id, "known")] = true
            end
        end
    end
end

local function bootstrap_ai_player(context, player)
    local player_index = get_player_index(player)
    local initialized_key = player_state_key(player_index, "initialized")
    if context.shared[initialized_key] == true then
        return false
    end

    local units, units_available = get_player_units(player)
    if not units_available then
        log_once(
            context,
            player_state_key(player_index, "units_unavailable"),
            "waiting for unit collection for AI player="
                .. tostring(player_index)
        )
        return true
    end

    local completed_count = 0
    local building_count = 0
    for _, unit in ipairs(units) do
        local definition_name = get_unit_definition_name(unit)
        if MONITORED_DEFINITIONS[definition_name] == true then
            local unit_id = get_unit_id(unit)
            if unit_id ~= nil then
                local completion_state = get_completion_state(unit)
                if completion_state == "complete" then
                    -- Do not replay announcements for Titans already present
                    -- when a save is loaded or this observer is first added.
                    context.shared[unit_state_key(unit_id, "known")] = true
                    completed_count = completed_count + 1
                elseif completion_state == "building" then
                    -- Leave it unknown so its actual completion is announced.
                    building_count = building_count + 1
                else
                    log_once(
                        context,
                        unit_state_key(unit_id, "completion_unavailable"),
                        "ERROR: completion properties unavailable for unit="
                            .. tostring(unit_id)
                            .. " definition=" .. tostring(definition_name)
                    )
                end
            end
        end
    end

    context.shared[initialized_key] = true
    log_info(
        "initialized AI player=" .. tostring(player_index)
            .. " existing_complete=" .. tostring(completed_count)
            .. " existing_building=" .. tostring(building_count)
    )
    return true
end

local function scan_ai_player(context, player)
    local player_index = get_player_index(player)
    if bootstrap_ai_player(context, player) then
        return
    end

    local units, units_available = get_player_units(player)
    if not units_available then
        return
    end

    for _, unit in ipairs(units) do
        local definition_name = get_unit_definition_name(unit)
        if MONITORED_DEFINITIONS[definition_name] == true then
            local unit_id = get_unit_id(unit)
            local known_key = unit_id ~= nil
                and unit_state_key(unit_id, "known")
                or nil

            if known_key ~= nil and context.shared[known_key] ~= true then
                local completion_state = get_completion_state(unit)
                if completion_state == "complete" then
                    local ok, notification_error = pcall(function()
                        local simulation = context.simulation
                        simulation:simulation_display_mad_titan_built_by_enemy_notification(
                            player,
                            unit
                        )
                    end)

                    if ok then
                        context.shared[known_key] = true
                        log_info(
                            "announced AI player=" .. tostring(player_index)
                                .. " unit=" .. tostring(unit_id)
                                .. " definition=" .. tostring(definition_name)
                        )
                    else
                        log_once(
                            context,
                            unit_state_key(unit_id, "notification_error"),
                            "ERROR: notification failed for unit="
                                .. tostring(unit_id)
                                .. " definition=" .. tostring(definition_name)
                                .. " error=" .. tostring(notification_error)
                        )
                    end
                elseif completion_state == "unknown" then
                    log_once(
                        context,
                        unit_state_key(unit_id, "completion_unavailable"),
                        "ERROR: completion properties unavailable for unit="
                            .. tostring(unit_id)
                            .. " definition=" .. tostring(definition_name)
                    )
                end
            end
        end
    end
end

function Get_event_metadata()
    local metadata = EventMetadata.create()

    metadata.event_name = "AI Foreign Titan Build Announcements"
    metadata.event_id = EVENT_ID
    metadata.register_event_function = "Ai_foreign_titan_announcement_register"
    metadata.on_event_registered_function = (
        "Ai_foreign_titan_announcement_on_registered"
    )
    metadata.on_initialize_function = "Ai_foreign_titan_announcement_initialize"
    metadata.should_trigger_function = (
        "Ai_foreign_titan_announcement_should_trigger"
    )
    metadata.on_start_function = "Ai_foreign_titan_announcement_on_start"
    metadata.on_update_function = "Ai_foreign_titan_announcement_on_update"
    metadata.on_complete_function = "Ai_foreign_titan_announcement_on_complete"
    metadata.on_teardown_function = "Ai_foreign_titan_announcement_on_teardown"

    metadata.trigger_check_interval_seconds = 2.0
    metadata.update_interval_seconds = 1.0
    metadata.on_update_function_initial_delay = 1.0
    metadata.event_version = 1.0
    metadata.description = (
        "Notification-only observer for AI-built foreign Titan variants"
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

function Ai_foreign_titan_announcement_register(context)
    return true
end

function Ai_foreign_titan_announcement_on_registered(context)
    log_info("registered notification-only observer")
end

function Ai_foreign_titan_announcement_initialize(context)
    context.instance.ready = true
end

function Ai_foreign_titan_announcement_should_trigger(context)
    return context.instance.ready == true
end

function Ai_foreign_titan_announcement_on_start(context)
    context.instance.ready = false
    log_info(
        "started at game_time="
            .. tostring(context.simulation.current_time)
    )
end

function Ai_foreign_titan_announcement_on_update(context)
    for _, player_index in ipairs(get_playable_player_indices(context)) do
        local player = context.simulation:get_player_by_player_index(player_index)
        if player ~= nil then
            local player_kind = classify_player(context, player)
            if player_kind == "ai" then
                scan_ai_player(context, player)
            elseif player_kind == "non_ai" then
                remember_non_ai_units(context, player)
            end
        end
    end
end

function Ai_foreign_titan_announcement_on_complete(context)
    -- Persistent match-long observer; normally never completed.
end

function Ai_foreign_titan_announcement_on_teardown(context)
    -- No units or simulation resources are owned by this observer.
end
