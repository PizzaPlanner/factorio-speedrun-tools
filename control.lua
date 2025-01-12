-- Achievement data is stored here: C:\Program Files (x86)\Steam\userdata\34790003\427520\remote\achievements-modded.dat

local compaction = require("compaction")

local debug_mode = false
local this_mod = "all-achievements-tracker"
local default_style = "side_menu_button"
local tracked_style = "tool_button_blue"
local gained_style = "tool_button_green"
local failed_style = "tool_button_red"

local show_only_splits_on_comp = true
local need_rebuild = false
local need_score_update = false
local need_split_update = false
local last_update = 0
local best_scores = nil
local race_splits = nil
local all_achieves = prototypes.get_achievement_filtered{{filter="allowed-without-fight"}, {filter="allowed-without-fight", invert=true}}
local all_techs    = prototypes.get_technology_filtered{{filter="has-prerequisites"}, {filter="has-prerequisites", invert=true}}

local function to_time(tick)
    if not tick or tick >= 0xFFFFFFFF then return "-" end
    local is_over = false
    if tick < 0 then
        tick = -tick
        is_over = true
    end
    local seconds = tick / 60
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local secs = seconds % 60

    local fmt
    if hours > 0 then
        -- Format as h:mm
        fmt = "%d:%02d:%02d"
        if is_over then fmt = "+"..fmt end
        return string.format(fmt, hours, minutes, secs)
    else
        -- Format as m.ss
        fmt = "%d:%02d"
        if is_over then fmt = "+"..fmt end
        return string.format(fmt, minutes, secs)
    end
end

local function to_icon_string(key)
    if all_achieves[key] then 
        return "[achievement="..key.."]"
    elseif all_techs[key] then
        return "[technology="..key.."]"
    else
        return "["..key.."]"
    end
end

local function is_pending(key)
    if not storage.gained[key] and not storage.failed[key] then
        return true
    else return false end
end

local function cache_scores()
    if not best_scores then
        best_scores = compaction.deserialize64(settings.get_player_settings(storage.player)["scores"].value)
    end
    if not race_splits then
        race_splits = compaction.deserialize64(settings.get_player_settings(storage.player)["splits"].value)
    end
end

local function set_split(key, value)
    cache_scores()
    if value > 0 then
        race_splits[key] = value
    else
        value = nil
    end
    need_split_update = true
    need_rebuild = true
end

local function best_score(key)
    cache_scores()
    local best = best_scores[key] or 0xFFFFFFFF
    return best
end

local function reset_highscore(key)
    cache_scores()
    best_scores[key] = nil
    need_score_update = true
    need_rebuild = true
    game.print("Reset best time for "..to_icon_string(key))
end

local function propose_highscore(key, tick)
    if tick < best_score(key) then
        best_scores[key] = tick
        need_score_update = true
    end
end

local function on_achievement_failed(key)
    if is_pending(key) == false then return end
    storage.failed[key] = true
    need_rebuild = true
    storage.player.play_sound{path = "utility/game_lost"}
    game.print("Failed: "..to_icon_string(key))
end

local function on_achievement_gained(key, tick)
    if is_pending(key) == false then return end
    storage.gained[key] = tick
    need_rebuild = true
    if debug_mode == true then
        game.print("Gained: "..to_icon_string(key))
    end
    propose_highscore(key, tick)
end

local function on_research_gained(key, tick)
    if is_pending(key) == false then return end
    storage.gained[key] = tick
    need_rebuild = true
    if debug_mode == true then
        game.print("Researched: "..to_icon_string(key))
    end
    propose_highscore(key, tick)
end

local progresses = { }
local handcraft_progresses = { }
local handcraft_achieves = { }

local untils = { }
local QUICKLIST_WIDTH = 5
local MAX_UNTIL = 9999999999

local function update_handcrafts()
    for key, value in pairs(handcraft_progresses) do
        if is_pending(key) then
            local progress = storage.handcrafts / handcraft_achieves[key].amount
            value.caption = tostring(storage.handcrafts) .. "/" .. tostring(handcraft_achieves[key].amount)
            value.value = progress
        end
    end
end

local function update_splits_tracker(tick)
    local splits = storage.player.gui.left.categories.tracker_frame.splits
    if #splits.children >= 2 and is_pending(splits.children[1].name) then
        local key = splits.children[1].name
        local ticks_left = best_score(key) - tick
        local progress = ticks_left / best_score(key)
        if progress < 0 then 
            splits.children[2].value = 1
            splits.children[2].style.color = {1, 0.3, 0}
        elseif progress < 60 then
            splits.children[2].value = progress
            splits.children[2].style.color = {1, 0.8, 0}
        else
            splits.children[2].value = progress
        end
        splits.children[2].caption = to_time(ticks_left)
    end
    local comp = storage.player.gui.left.categories.completed.table
    for i = 4, #comp.children, 3 do
        if is_pending(comp.children[i].name) then
            comp.children[i + 1].caption = to_time(tick)
            return
        end
    end

end

local function update_timers(tick)
    for key, value in pairs(untils) do
        if is_pending(key) then
            if value.within < tick then
                on_achievement_failed(key)
            elseif progresses[key] ~= nil then
                local ticks_left = value.within - tick
                local progress = ticks_left / value.within
                progresses[key].caption = to_time(ticks_left)
                progresses[key].value = progress
            end
        end
    end
    last_update = tick
    update_handcrafts()
    update_splits_tracker(tick)
end

local function build_thing_button(key, parent)
    local bstyle = default_style
    if storage.gained[key] then bstyle = gained_style
    elseif storage.failed[key] then bstyle = failed_style
    elseif race_splits[key] then bstyle = tracked_style end
    local sprite = ""
    local tooltip = {type="none", name=key}
    if all_achieves[key] then 
        sprite = "achievement/"..key
        tooltip.type = "achievement"
    elseif all_techs[key] then
        sprite = "technology/"..key
        tooltip.type = "technology"
    else
        tooltip = nil
    end
    local btn = parent.add{name=key, type="sprite-button", sprite=sprite, style=bstyle, elem_tooltip=tooltip}
    btn.style.width = 40
    btn.style.height = 40
    btn.style.padding = 0
end

local function update_completed_tracker(parent, splits)
    cache_scores()
    local keys = {}
    local unique_keys = {}
    if show_only_splits_on_comp == false then
        for k in pairs(best_scores) do
            if not unique_keys[k] and (all_techs[k] or storage.split_on_achievements) then
                table.insert(keys, k)
                unique_keys[k] = true
            end
        end
    end
    for k in pairs(race_splits) do
        if not unique_keys[k] and (all_techs[k] or storage.split_on_achievements) then
            table.insert(keys, k)
            unique_keys[k] = true
        end
    end
    if show_only_splits_on_comp then
        table.sort(keys, function(a, b)
            return race_splits[a] < race_splits[b]
        end)
    else
        table.sort(keys, function(a, b)
            if not storage.gained[a] and not storage.gained[b] then
                return best_score(a) < best_score(b)
            elseif not storage.gained[a] then
                return false
            elseif not storage.gained[b] then
                return true
            end
            return storage.gained[a] < storage.gained[b]
        end)
    end
    local tracked_next = false
    
    parent.add{type = "checkbox", name = "only_splits", state = show_only_splits_on_comp, caption = "Only show Splits"}
    local table = parent.add{type = "table", name="table", column_count = 3}
    table.style.vertical_spacing = 0
    table.add{type="flow"}
    table.add{type="label", caption="Current      "}
    table.add{type="label", caption="Best         "}
    for _, key in ipairs(keys) do
        build_thing_button(key, table)
        table.add{type="label", caption=to_time(storage.gained[key])}
        local best = best_score(key)
        table.add{type="label", caption=to_time(best)}
        if tracked_next == false and is_pending(key) and race_splits[key] and (all_techs[key] or storage.split_on_achievements) then
            build_thing_button(key, splits)
            local bar = splits.add{type="progressbar", style="achievement_progressbar", caption="..."}
            bar.style.width = 150
            tracked_next = true
        end
    end
end

local function on_select_tab(tab)
    local parent = tab.parent
    if tab.name == "tracked_tab" then
        parent.style.height = #parent.tabs[1].content.children * 40 + #parent.tabs[1].content.splits.children * 20 + 25
    else
        parent.style.height = 400
    end
    return
end

local function build_sprite_buttons(tick)
    if not storage.player then return end
    cache_scores()  
    need_rebuild = false
    local window = storage.player.gui.left
    local cached_index = 1
    if window.categories then cached_index = window.categories.selected_tab_index end
    window.clear()
    progresses = { }
    handcraft_progresses = { }
    handcraft_achieves = { }
    local tabs = window.add{type="tabbed-pane", name="categories"}
    local tracker_frame = tabs.add{type="flow", name="tracker_frame", direction="vertical"}
    local ongoing_frame = tabs.add{type="scroll-pane"}.add{type="table", name="ongoing_ach", column_count=QUICKLIST_WIDTH, style="filter_slot_table"}
    local ongoing_research = ongoing_frame.parent.add{type="table", name="ongoing_tech", column_count=QUICKLIST_WIDTH, style="filter_slot_table"}
    local completed_frame = tabs.add{type="scroll-pane", name="completed"}
    local restricted_table = tracker_frame.add{type="table", name="restricted_table", column_count=QUICKLIST_WIDTH, direction="horizontal", style="filter_slot_table"}
    local progress_bar = tracker_frame.add{type="progressbar", name="achievements_count", style="achievement_progressbar"}
    local smallest_until = MAX_UNTIL
    for key, value in pairs(all_achieves) do
        if not is_pending(key) then
            -- nothing
        elseif value.within ~= nil and value.within > 0 and value.within < MAX_UNTIL then
            untils[key] = value
            if value.within < smallest_until then
                smallest_until = value.within
            end
        elseif value.type == "dont-craft-manually-achievement" then
            local tracked = tracker_frame.add{type = "table", column_count = 2}
            build_thing_button(key, tracked)
            local bar = tracked.add{type="progressbar", style="achievement_progressbar", caption="0"}
            handcraft_progresses[key] = bar
            handcraft_achieves[key] = value
            bar.style.width = 150
        elseif string.find(value.type, "dont-", 1, true) and (not value.included or #value.included == 0) then
            local rest = build_thing_button(key, restricted_table)
        end

        build_thing_button(key, ongoing_frame)
    end
    for key, value in pairs(all_techs) do
        build_thing_button(key, ongoing_research)
    end
    local tracked = tracker_frame.add{type = "table", caption = "Next deadline", column_count = 2}
    for key, value in pairs(untils) do
        if value.within == smallest_until then
            build_thing_button(key, tracked)
            local bar = tracked.add{type="progressbar", style="achievement_progressbar", caption="0"}
            progresses[key] = bar
            bar.style.width = 150
        end
    end
    local splits_frame = tracker_frame.add{type = "table", name ="splits", caption = "Next up", column_count = 2}
    local tracked_tab  = tabs.add{type="tab", name="tracked_tab", caption="T", badge_text=tostring(#tracker_frame.children - 1 + #restricted_table.children)}
    tracked_tab.style.width = 52
    tabs.add_tab(tracked_tab, tracker_frame)
    local ongoing_tab   = tabs.add{type="tab", name="ongoing_tab",caption="U", badge_text=tostring(#ongoing_frame.children)}
    ongoing_tab.style.width = 52
    tabs.add_tab(ongoing_tab, ongoing_frame.parent)
    local completed_tab   = tabs.add{type="tab", name="completed_tab", caption="C", badge_text=tostring(#completed_frame.children)}
    completed_tab.style.width = 52
    tabs.add_tab(completed_tab, completed_frame)
    
    update_completed_tracker(completed_frame, splits_frame)
    update_timers(tick)

    -- styling
    if #restricted_table.children == 0 then
        restricted_table.destroy()
    end
    tabs.selected_tab_index = cached_index
    on_select_tab(tabs.tabs[cached_index].tab)
    local progress_caption = tostring(#completed_frame.children) .. "/" .. tostring(#all_achieves)
    if #storage.failed > 0 then
        progress_bar.style.color = {1, 0, 0}
        progress_caption = progress_caption .. " - " .. tostring(#storage.failed)
    end
    progress_bar.caption = progress_caption
    progress_bar.value = #completed_frame.children / #all_achieves
    
end

local last_clicked_thing = "character"
local context_window = nil
script.on_event(defines.events.on_gui_click, function(event)
    if event.element.get_mod() ~= this_mod then return end
    if event.element.type == "tab" then
        on_select_tab(event.element)
    elseif event.element.type == "sprite-button" then
        last_clicked_thing = event.element.name
        context_window = context_window or storage.player.gui.screen.add{
            type="frame", 
            name="thing_context", 
            caption = to_icon_string(last_clicked_thing).." ".. last_clicked_thing,
            direction = "vertical"
        }
        context_window.clear()
        local table = context_window.add{type="table", column_count = 2, direction="vertical"}
        table.add{type="label", caption = "Best Time: "..to_time(best_score(last_clicked_thing))}
        table.add{type="button", name="ctx_reset", caption="Reset"}
        if storage.gained[last_clicked_thing] then
            table.add{type="label", caption = "Status: Done"}
            table.add{type="label", caption = to_time(storage.gained[last_clicked_thing])}
        elseif storage.failed[last_clicked_thing] then
            table.add{type="label", caption = "Status: Failed"}
            table.add{type="label", caption = ""}
        else
            table.add{type="label", caption = "Status: Pending"}
            local debugger = table.add{type="flow"}
            if debug_mode == true then
                debugger.add{type="button", name="ctx_finish", style="tool_button_green"}
                debugger.add{type="button", name="ctx_fail", style="tool_button_red"}
            end
        end
        table.add{type="button", name="back", caption="back", style = "back_button"}
        local list = table.add{type="drop-down", name="ctx_splits", caption = "Split"}
        list.add_item("No split", 1)
        for i = 2, 30 do
            local cap = tostring(i - 1).. "  "
            for s, sval in pairs(race_splits) do
                if sval == i then
                    cap = cap .. to_icon_string(s)
                end
            end
            list.add_item(cap, i)
        end
    elseif event.element.type == "button" then
        local key = last_clicked_thing
        if event.element.name == "ctx_finish" then on_achievement_gained(key, event.tick) 
        elseif event.element.name == "ctx_fail" then on_achievement_failed(key)
        elseif event.element.name == "ctx_reset" then reset_highscore(key)
        end
        context_window.destroy()
        context_window = nil
        return
    end
end)

local function on_load()
    if not storage.player then 
        return 
    end
    need_rebuild = true 
    show_only_splits_on_comp = settings.get_player_settings(storage.player)["only-track-splits"].value

    script.on_nth_tick(60, function(event)
        if need_split_update then
            settings.get_player_settings(storage.player)["splits"] = {value = compaction.serialize64(race_splits)}
        end
        if need_score_update then
            settings.get_player_settings(storage.player)["scores"] = {value = compaction.serialize64(best_scores)}
        end
        if need_rebuild then
            build_sprite_buttons(event.tick)
        elseif storage.player then
            update_timers(event.tick)
        end
    end)

    script.on_event(defines.events.on_research_finished, function(event)
        if event.tick < 3600 then
            -- Dont mess up score in sandbox mode 
            return
        end
        if event.research.name == "production-science-pack" or event.research.name == "utility-science-pack" then
            on_achievement_failed("rush-to-space")
        end
        on_research_gained(event.research.name, event.tick)
    end)

    script.on_event(defines.events.on_achievement_gained, function(event)
        on_achievement_gained(event.achievement.name, event.tick)
        if event.achievement.name == "steam-power" then
            storage.split_on_achievements = true
            game.print("Detected achievement reset. Playing with Achievements")
        end
    end)

    --- UI
    script.on_event(defines.events.on_gui_selection_state_changed, function(event)
        if event.element.get_mod() ~= this_mod then return end
        if event.element.name == "ctx_splits" then
            set_split(last_clicked_thing, event.element.selected_index)
        end
    end)
    
    script.on_event(defines.events.on_gui_checked_state_changed, function(event)
        if event.element.get_mod() ~= this_mod then return end
        if event.element.name == "only_splits" then
            show_only_splits_on_comp = event.element.state
            need_rebuild = true
            settings.get_player_settings(storage.player)["only-track-splits"] = {value = show_only_splits_on_comp}
        end
    end)

    --- Specific Achiement conditions
    script.on_event(defines.events.on_player_crafted_item, function(event)
        storage.handcrafts = storage.handcrafts + 1
        for key, value in pairs(handcraft_achieves) do
            if value.amount < storage.handcrafts then
                on_achievement_failed(key)
            end
        end
    end)
    
    script.on_event(defines.events.on_built_entity, function(event)
        if event.entity.name == "solar-panel" then
            on_achievement_failed("steam-all-the-way")
        elseif event.entity.name == "laser-turret" then
            on_achievement_failed("raining-bullets")
        else
            on_achievement_failed("logistic-network-embargo")
        end
    end,
    {
        { filter = "name", name = "solar-panel" },
        { filter = "name", name = "laser-turret"},
        { filter = "name", name = "active-provider-chest"}, 
        { filter = "name", name = "requester-chest"}, 
        { filter = "name", name = "buffer-chest"}
    })
    
    script.on_event(defines.events.on_entity_died, function(event)
        if not event.cause or not string.find(event.cause.name, "artillery", 1, true) then
            on_achievement_failed("keeping-your-hands-clean")
        end
    end,
    {{ filter =  "type", type = "unit-spawner"}})
end

script.on_load(on_load)
script.on_event(defines.events.on_player_created, function(event)
    if storage.player ~= nil then
        game.print("Multiple players detected. AAT only works in singleplayer")
        return
    end
    storage.player = game.get_player(event.player_index)
    storage.gained = { }
    storage.failed = { }
    storage.handcrafts = 0
    storage.split_on_achievements = false
    on_load()
end)