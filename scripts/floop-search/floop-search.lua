-- Floop Search - Track Navigation System
-- @description Floop Search: fast track navigation and search tool
-- @version 1.1.0
-- @author Floop-s
-- @license GPL-3.0
-- @changelog
--   v1.1.0 (2026-05-22)
--   + Added support for comma operator to search multiple groups (e.g. 'kick, snare').
--   + Added SHIFT+ENTER shortcut to select all search results at once.
--   + Added full Undo support for track selection.
--   + Added 'Lazy Snapshot' for massive performance improvements on large projects.
--   + Script now ignores hidden tracks.
-- @about
--   Fast track navigation and search tool for REAPER.
--
--   Provides a floating search bar for quickly locating,
--   selecting, and previewing tracks.
--
--   Requires:
--     - ReaImGui (ReaTeam Extensions repository), v0.10.2 or newer
--   Keywords: search, navigation, track, workflow.
-- @provides
--   [main] floop-search.lua

local r = reaper

-- Check ReaImGui
if not reaper.ImGui_CreateContext then 
    reaper.ShowMessageBox("ReaImGui API not found!", "Error", 0) 
    return 
end

local function IG_Const(name)
    local val = r['ImGui_' .. name]
    if type(val) == 'function' then return val() end
    return val or 0
end

-- ---------------------------------------------------------
-- CONFIG & STATE
-- ---------------------------------------------------------
local CTX_NAME = 'FloopSearch'
local FONT_SIZE = 20
local WINDOW_W = 680
local BAR_HEIGHT = 60
local ITEM_HEIGHT = 24
local MAX_HEIGHT = 600
local ANIM_SPEED = 0.25

local ctx = r.ImGui_CreateContext(CTX_NAME)
local font = r.ImGui_CreateFont('sans-serif', FONT_SIZE)
r.ImGui_Attach(ctx, font)

local state = {
    query = "",
    results = {},
    selected_index = 1,
    initial_track_states = {},
    highlighted_guids = {}, 
    preview_solo_guid = nil,
    done = false,
    confirmed = false,
    select_all = false,
    restored = false,
    window_h = BAR_HEIGHT,
    -- Debounce
    search_timer = 0,
    needs_update = false,
    debounce_delay = 0.2,
    -- Cache
    track_cache = nil,
    last_proj_change_count = 0
}

-- ---------------------------------------------------------
-- UTILS
-- ---------------------------------------------------------

local COLOR_SEL_BG = 0x007FDFFF -- Safe Azure Blue



local function SetTracksToDefaultColor(tracks)
    if #tracks == 0 then return end
    for _, tr in ipairs(tracks) do
        r.SetMediaTrackInfo_Value(tr, "I_CUSTOMCOLOR", 0)
    end
end

local function RestoreSoloState(guid)
    local s = state.initial_track_states[guid]
    if s and r.ValidatePtr(s.track, 'MediaTrack*') then
        r.SetMediaTrackInfo_Value(s.track, "I_SOLO", s.solo)
    end
end

local function EnsureTrackStateSaved(guid, tr)
    if not state.initial_track_states[guid] and r.ValidatePtr(tr, 'MediaTrack*') then
        state.initial_track_states[guid] = {
            track = tr,
            solo = r.GetMediaTrackInfo_Value(tr, "I_SOLO"),
            selected = r.IsTrackSelected(tr),
            compact = r.GetMediaTrackInfo_Value(tr, "I_FOLDERCOMPACT"),
            color = r.GetTrackColor(tr)
        }
    end
end

local function RestoreInitialState()
    if state.restored then return end
    r.PreventUIRefresh(1)
    local def_colors = {}
    for guid, s in pairs(state.initial_track_states) do
        local tr = s.track
        if r.ValidatePtr(tr, 'MediaTrack*') then
            if r.GetMediaTrackInfo_Value(tr, "I_SOLO") ~= s.solo then r.SetMediaTrackInfo_Value(tr, "I_SOLO", s.solo) end
            if r.IsTrackSelected(tr) ~= s.selected then r.SetTrackSelected(tr, s.selected) end
            if r.GetMediaTrackInfo_Value(tr, "I_FOLDERCOMPACT") ~= s.compact then r.SetMediaTrackInfo_Value(tr, "I_FOLDERCOMPACT", s.compact) end
            if r.GetTrackColor(tr) ~= s.color then
                if s.color == 0 then table.insert(def_colors, tr) else r.SetTrackColor(tr, s.color) end
            end
        end
    end
    SetTracksToDefaultColor(def_colors)
    r.UpdateArrange()
    state.restored = true
    r.PreventUIRefresh(-1)
end

local function TrackMatchesQuery(entry, query)
    if query == "" then return false end
    -- Support multiple queries separated by comma
    for clause in query:gmatch("[^,]+") do
        local tokens = {}
        for token in clause:lower():gmatch("%S+") do
            table.insert(tokens, token)
        end
        
        if #tokens > 0 then
            local match_clause = true
            for _, token in ipairs(tokens) do
                if not (entry.lower_name:find(token, 1, true) or tostring(entry.number):find(token, 1, true)) then
                    match_clause = false
                    break
                end
            end
            if match_clause then return true end
        end
    end
    return false
end

local function RefreshTrackCache()
    state.track_cache = {}
    local count = r.CountTracks(0)
    for i = 0, count - 1 do
        local tr = r.GetTrack(0, i)
        -- Skip tracks hidden in TCP
        if r.GetMediaTrackInfo_Value(tr, "B_SHOWINTCP") == 1 then
            local _, name = r.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
            if name == "" then name = "Track " .. (i+1) end
            local num = math.floor(r.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER"))
            local guid = r.GetTrackGUID(tr)
            local color = r.GetTrackColor(tr)
            
            -- Pre-calculate RGBA for UI
            local rgba = 0x888888FF
            if color ~= 0 then
                local rv, gv, bv = r.ColorFromNative(color)
                rgba = (rv << 24) | (gv << 16) | (bv << 8) | 0xFF
            end

            table.insert(state.track_cache, {
                name = name,
                lower_name = name:lower(),
                number = num,
                track = tr,
                guid = guid,
                color = rgba,
                native_color = color
            })
        end
    end
    state.last_proj_change_count = r.GetProjectStateChangeCount(0)
end

-- ---------------------------------------------------------
-- LOGIC
-- ---------------------------------------------------------

local function ExpandParentFoldersForTrack(track)
    if not track or not r.ValidatePtr(track, 'MediaTrack*') then return end
    local idx = math.floor(r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER")) - 1
    if idx < 0 then return end

    local function TrackDepthByIndex(i)
        local tr = r.GetTrack(0, i)
        return r.GetTrackDepth(tr)
    end

    local depth = TrackDepthByIndex(idx)
    if not depth or depth <= 0 then return end
    local current_depth = depth
    for i = idx - 1, 0, -1 do
        local tr = r.GetTrack(0, i)
        local d = TrackDepthByIndex(i)
        if d < current_depth then
            r.SetMediaTrackInfo_Value(tr, "I_FOLDERCOMPACT", 0)
            current_depth = d
            if current_depth <= 0 then break end
        end
    end
end

local function UpdateResults()
    if not state.track_cache or r.GetProjectStateChangeCount(0) ~= state.last_proj_change_count then
        RefreshTrackCache()
    end

    state.results = {}
    if state.query == "" then 
        if next(state.highlighted_guids) then
            local defs = {}
            for g, tr in pairs(state.highlighted_guids) do
                local ini = state.initial_track_states[g]
                if r.ValidatePtr(tr, 'MediaTrack*') and ini then
                    if ini.color == 0 then table.insert(defs, tr) else r.SetTrackColor(tr, ini.color) end
                end
            end
            SetTracksToDefaultColor(defs)
            state.highlighted_guids = {}
            r.UpdateArrange()
        end
        return 
    end

    local current_guids = {}

    for _, entry in ipairs(state.track_cache) do
        if TrackMatchesQuery(entry, state.query) then
            if r.ValidatePtr(entry.track, 'MediaTrack*') then
                table.insert(state.results, entry)
                current_guids[entry.guid] = true
            end
        end
    end
    
    -- Sync Highlights
    r.PreventUIRefresh(1)
    local restore_def = {}
    for g, tr in pairs(state.highlighted_guids) do
        if not current_guids[g] then
            local ini = state.initial_track_states[g]
            if r.ValidatePtr(tr, 'MediaTrack*') and ini then
                if ini.color == 0 then table.insert(restore_def, tr) else r.SetTrackColor(tr, ini.color) end
            end
        end
    end
    SetTracksToDefaultColor(restore_def)
    
    state.highlighted_guids = {}
    local red = r.ColorToNative(255, 0, 0)
    for _, res in ipairs(state.results) do
        EnsureTrackStateSaved(res.guid, res.track)
        r.SetTrackColor(res.track, red)
        state.highlighted_guids[res.guid] = res.track
    end
    r.PreventUIRefresh(-1)
    r.UpdateArrange()
end

local function HandlePreviewSolo()
    local alt = r.ImGui_IsKeyDown(ctx, IG_Const('Key_LeftAlt')) or r.ImGui_IsKeyDown(ctx, IG_Const('Key_RightAlt')) or r.ImGui_IsKeyDown(ctx, IG_Const('Mod_Alt'))
    local res = state.results[state.selected_index]
    
    if alt and res then
        if state.preview_solo_guid ~= res.guid then
            if state.preview_solo_guid then RestoreSoloState(state.preview_solo_guid) end
            EnsureTrackStateSaved(res.guid, res.track)
            r.SetMediaTrackInfo_Value(res.track, "I_SOLO", 1)
            state.preview_solo_guid = res.guid
            r.UpdateArrange()
        end
    elseif state.preview_solo_guid then
        RestoreSoloState(state.preview_solo_guid)
        state.preview_solo_guid = nil
        r.UpdateArrange()
    end
end

-- ---------------------------------------------------------
-- LOOP
-- ---------------------------------------------------------

local function Loop()
    if r.GetExtState("FloopSearch", "Signal") == "Close" then state.done = true end

    -- Debounce
    if state.needs_update and r.time_precise() > state.search_timer then
        UpdateResults()
        state.needs_update = false
        state.selected_index = 1
    end

    local vp = r.ImGui_GetMainViewport(ctx)
    local vw, vh = r.ImGui_Viewport_GetSize(vp)
    local vx, vy = r.ImGui_Viewport_GetPos(vp)
    
    r.ImGui_SetNextWindowPos(ctx, vx + (vw/2) - (WINDOW_W/2), vy + (vh * 0.2))
    r.ImGui_SetNextWindowSize(ctx, WINDOW_W, state.window_h)
    
    r.ImGui_PushStyleVar(ctx, IG_Const('StyleVar_WindowRounding'), 12)
    r.ImGui_PushStyleVar(ctx, IG_Const('StyleVar_WindowBorderSize'), 0)
    r.ImGui_PushStyleVar(ctx, IG_Const('StyleVar_FramePadding'), 12, 12)
    r.ImGui_PushStyleColor(ctx, IG_Const('Col_WindowBg'), 0x1E1E1EE6)
    
    local visible, open = r.ImGui_Begin(ctx, 'SearchWindow', true, IG_Const('WindowFlags_NoTitleBar') | IG_Const('WindowFlags_NoResize') | IG_Const('WindowFlags_NoMove') | IG_Const('WindowFlags_NoScrollbar'))
    
    if visible then
        local focused = r.ImGui_IsWindowFocused(ctx, IG_Const('FocusedFlags_RootAndChildWindows'))
        if not state.done and not r.ImGui_IsAnyItemActive(ctx) then r.ImGui_SetKeyboardFocusHere(ctx) end
        
        -- Search Bar
        r.ImGui_PushStyleColor(ctx, IG_Const('Col_FrameBg'), 0x00000000)
        r.ImGui_SetCursorPos(ctx, 20, 16)
        r.ImGui_Text(ctx, "🔍")
        r.ImGui_SetCursorPos(ctx, 50, 10)
        r.ImGui_SetNextItemWidth(ctx, WINDOW_W - 100) 
        
        local changed, nt = r.ImGui_InputText(ctx, '##Search', state.query)
        r.ImGui_PopStyleColor(ctx)
        
        -- TOOLTIP (?)
        r.ImGui_SetCursorPos(ctx, WINDOW_W - 40, 16)
        r.ImGui_TextDisabled(ctx, "(?)")
        if r.ImGui_IsItemHovered(ctx) then
            r.ImGui_SetTooltip(ctx, "Controls:\nARROWS : Navigate List\nHOLD ALT : Solo Selected Track (Preview)\nENTER : Select Highlighted Track\nSHIFT+ENTER : Select All Results\nESC : Close")
        end
        
        if changed then
            state.query = nt
            state.search_timer = r.time_precise() + state.debounce_delay
            state.needs_update = true
        end

        HandlePreviewSolo()

        -- Height Animation
        local target_h = BAR_HEIGHT
        if state.query ~= "" and focused then
            target_h = math.min(MAX_HEIGHT, BAR_HEIGHT + (#state.results * ITEM_HEIGHT) + 25)
        end
        state.window_h = state.window_h + (target_h - state.window_h) * ANIM_SPEED

        -- Navigation
        if focused then
             -- Force update on interaction to prevent using stale results
             if state.needs_update and (
                r.ImGui_IsKeyPressed(ctx, IG_Const('Key_DownArrow')) or 
                r.ImGui_IsKeyPressed(ctx, IG_Const('Key_UpArrow')) or 
                r.ImGui_IsKeyPressed(ctx, IG_Const('Key_Enter')) or 
                r.ImGui_IsKeyPressed(ctx, IG_Const('Key_KeypadEnter'))
             ) then
                 UpdateResults()
                 state.needs_update = false
                 state.selected_index = 1
             end

            if r.ImGui_IsKeyPressed(ctx, IG_Const('Key_DownArrow')) then
                state.selected_index = math.min(#state.results, state.selected_index + 1)
            elseif r.ImGui_IsKeyPressed(ctx, IG_Const('Key_UpArrow')) then
                state.selected_index = math.max(1, state.selected_index - 1)
            elseif r.ImGui_IsKeyPressed(ctx, IG_Const('Key_Enter')) or r.ImGui_IsKeyPressed(ctx, IG_Const('Key_KeypadEnter')) then
                if #state.results > 0 then
                    state.done = true
                    state.confirmed = true
                    state.select_all = r.ImGui_IsKeyDown(ctx, IG_Const('Mod_Shift'))
                end
            elseif r.ImGui_IsKeyPressed(ctx, IG_Const('Key_Escape')) then state.done = true end
        end

        -- List Area
        if state.window_h > BAR_HEIGHT + 10 then
            r.ImGui_SetCursorPosY(ctx, BAR_HEIGHT)
            r.ImGui_Separator(ctx)
            if #state.results == 0 and not state.needs_update then
                r.ImGui_SetCursorPosX(ctx, 20)
                r.ImGui_TextDisabled(ctx, "No results.")
            elseif r.ImGui_BeginChild(ctx, 'ResultsList', 0, 0) then
                for i, res in ipairs(state.results) do
                    local is_sel = (i == state.selected_index)
                    if is_sel then 
                        r.ImGui_PushStyleColor(ctx, IG_Const('Col_Header'), COLOR_SEL_BG)
                        -- Ensure Scroll follows Selection
                         if state.needs_update == false then -- Don't force scroll during rapid typing
                            r.ImGui_SetScrollHereY(ctx, 0.5)
                         end
                    end
                    local label = string.format("  %d: %s", res.number, res.name)
                    
                    -- Speaker Icon Logic
                    if is_sel and state.preview_solo_guid == res.guid then 
                        label = label .. "  🔊" 
                    end
                    
                    if r.ImGui_Selectable(ctx, label, is_sel, 0, 0, ITEM_HEIGHT) then
                        state.selected_index = i state.done = true state.confirmed = true
                    end
                    
                    local mx, my = r.ImGui_GetItemRectMin(ctx)
                    local _, my2 = r.ImGui_GetItemRectMax(ctx)
                    r.ImGui_DrawList_AddRectFilled(r.ImGui_GetWindowDrawList(ctx), mx, my, mx + 4, my2, res.color)
                    if is_sel then r.ImGui_PopStyleColor(ctx) end
                end
                r.ImGui_EndChild(ctx)
            end
        end
        r.ImGui_End(ctx)
    end
    
    r.ImGui_PopStyleColor(ctx)
    r.ImGui_PopStyleVar(ctx, 3)
    
    if state.done then
        if state.confirmed and #state.results > 0 then
            RestoreInitialState()
            r.Undo_BeginBlock()
            r.Main_OnCommand(40297, 0) -- Unselect all tracks
            
            if state.select_all then
                -- Select all matching tracks
                for _, res in ipairs(state.results) do
                    if r.ValidatePtr(res.track, 'MediaTrack*') then
                        r.SetTrackSelected(res.track, true)
                        ExpandParentFoldersForTrack(res.track)
                    end
                end
                
                -- Scroll to the actively highlighted track
                local active_res = state.results[state.selected_index]
                if active_res and r.ValidatePtr(active_res.track, 'MediaTrack*') then
                    -- Temporarily select only this one to scroll to it
                    r.Main_OnCommand(40297, 0)
                    r.SetTrackSelected(active_res.track, true)
                    r.Main_OnCommand(40913, 0) -- View: Scroll view to selected tracks
                    
                    -- Reselect all matching tracks
                    for _, res in ipairs(state.results) do
                        if r.ValidatePtr(res.track, 'MediaTrack*') then
                            r.SetTrackSelected(res.track, true)
                        end
                    end
                end
            else
                -- Select ONLY the highlighted track
                local res = state.results[state.selected_index]
                if res and r.ValidatePtr(res.track, 'MediaTrack*') then
                    r.SetTrackSelected(res.track, true)
                    ExpandParentFoldersForTrack(res.track)
                    r.Main_OnCommand(40913, 0) -- View: Scroll view to selected tracks
                end
            end
            
            r.TrackList_AdjustWindows(false)
            r.UpdateArrange()
            r.Undo_EndBlock(state.select_all and "Floop Search: Select All" or "Floop Search: Select Track", -1)
        else RestoreInitialState() end
        return
    end
    if open then r.defer(Loop) else RestoreInitialState() end
end

local _, _, sid, cid = r.get_action_context()
r.SetToggleCommandState(sid, cid, 1)
r.RefreshToolbar2(sid, cid)
r.atexit(function()
    RestoreInitialState()
    r.SetToggleCommandState(sid, cid, 0)
    r.RefreshToolbar2(sid, cid)
end)

r.defer(Loop)
