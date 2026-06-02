-- Floop Studio Trainer
-- @description Floop Studio Trainer: practice your instrument inside Reaper.
-- @version 1.3
-- @author Floop-s
-- @license GPL v-3.0
-- @changelog
--   v1.3 (2026-06-02)
--   - New: Advanced Training Mode (cycles, BPM range, end behavior)
--   - UI: ReaImGui redesign + metronome icon + in-app Help window
--   - Docs: Added quick guide (count-in + custom metronome click note)
--   - Fix: More robust loop restart + safer undo handling
-- @about
--    Floop Studio Trainer
--   © 2025-2026 Floop-s
--
--   Practice your instrument inside Reaper using either an audio track or the metronome.
--   Set repetitions and BPM increments to practice hands-free.
--
--   Requires:
--     - ReaImGui (ReaTeam Extensions repository), v0.10.2 or newer
--   Keywords: practice, loop, trainer, bpm, metronome
-- @provides
--   [main] floop-studio-trainer.lua
--   IMG/metro-nome.png



--------------------------------------------------------------------------------
--- [ DEPENDENCIES & INIT ]
--------------------------------------------------------------------------------

-- Ensure ReaImGui dependency is available
if not reaper.ImGui_CreateContext then
    reaper.ShowMessageBox("ReaImGui is not installed!\nPlease install ReaImGui Api package from ReaPack and try again.", "Error", 0)
    return
end

--------------------------------------------------------------------------------
--- [ STATE ]
--------------------------------------------------------------------------------

local State = {
    config = {
        num_repeats = 10,
        bpm_increment = 3,
        training_mode = 0, -- 0 = Standard, 1 = Complex
        comp_start_bpm = 80,
        comp_increment = 5,
        comp_max_bpm = 140,
        comp_cycles = 3,
        comp_end_behavior = 0, -- 0 = Stop, 1 = Restart, 2 = Keep playing at Max BPM
        restore_on_close = true
    },
    runtime = {
        running = false,
        script_running = true,
        remaining_repeats = 10,
        metronome_active = false,
        project_bpm = reaper.Master_GetTempo(),
        original_bpm = reaper.Master_GetTempo(),
        repeat_count = 0,
        session_id = 0,
        current_cycle = 1
    },
    ui = {
        ctx = reaper.ImGui_CreateContext("Loop Trainer"),
        scale_factor = 1.0,
        font_size = 14,
        sans_serif = nil,
        img_metro = nil,
        show_help_modal = false
    }
}

State.runtime.metronome_active = (reaper.GetToggleCommandState(40364) == 1)

State.ui.sans_serif = reaper.ImGui_CreateFont("sans-serif", State.ui.font_size)
reaper.ImGui_Attach(State.ui.ctx, State.ui.sans_serif)

local script_path = debug.getinfo(1, "S").source:match("@?(.*[\\/])")
local metro_icon_path = script_path .. "IMG/metro-nome.png"
if reaper.file_exists(metro_icon_path) then
    State.ui.img_metro = reaper.ImGui_CreateImage(metro_icon_path)
end

--------------------------------------------------------------------------------
--- [ THEME CONFIGURATION ]
--------------------------------------------------------------------------------

local function ApplyTheme()
    local s = State.ui.scale_factor or 1.0
    reaper.ImGui_PushStyleVar(State.ui.ctx, reaper.ImGui_StyleVar_WindowRounding(), 9 * s)
    reaper.ImGui_PushStyleVar(State.ui.ctx, reaper.ImGui_StyleVar_FrameRounding(), 12 * s)
    reaper.ImGui_PushStyleVar(State.ui.ctx, reaper.ImGui_StyleVar_FrameBorderSize(), 1 * s)
    reaper.ImGui_PushStyleVar(State.ui.ctx, reaper.ImGui_StyleVar_GrabRounding(), 4 * s)
    reaper.ImGui_PushStyleVar(State.ui.ctx, reaper.ImGui_StyleVar_WindowPadding(), 20 * s, 20 * s)
    reaper.ImGui_PushStyleVar(State.ui.ctx, reaper.ImGui_StyleVar_WindowMinSize(), 360 * s, 420 * s)

    reaper.ImGui_PushStyleColor(State.ui.ctx, reaper.ImGui_Col_WindowBg(), 0x26272aFF)
    reaper.ImGui_PushStyleColor(State.ui.ctx, reaper.ImGui_Col_PopupBg(), 0x26272aFF)
    reaper.ImGui_PushStyleColor(State.ui.ctx, reaper.ImGui_Col_Border(), 0x26272aFF)
    reaper.ImGui_PushStyleColor(State.ui.ctx, reaper.ImGui_Col_TitleBg(), 0x1A686BFF) 
    reaper.ImGui_PushStyleColor(State.ui.ctx, reaper.ImGui_Col_TitleBgActive(), 0x1A686BFF) 
    reaper.ImGui_PushStyleColor(State.ui.ctx, reaper.ImGui_Col_FrameBg(), 0x1A686BFF)
    reaper.ImGui_PushStyleColor(State.ui.ctx, reaper.ImGui_Col_FrameBgHovered(), 0x32878AFF)
    reaper.ImGui_PushStyleColor(State.ui.ctx, reaper.ImGui_Col_FrameBgActive(), 0x135E61FF)
    reaper.ImGui_PushStyleColor(State.ui.ctx, reaper.ImGui_Col_SliderGrab(), 0xFFFFFFFF)
    reaper.ImGui_PushStyleColor(State.ui.ctx, reaper.ImGui_Col_SliderGrabActive(), 0xC6CFDAFF)
    reaper.ImGui_PushStyleColor(State.ui.ctx, reaper.ImGui_Col_Button(), 0x1A686BFF)
    reaper.ImGui_PushStyleColor(State.ui.ctx, reaper.ImGui_Col_ButtonHovered(), 0x32878AFF)
    reaper.ImGui_PushStyleColor(State.ui.ctx, reaper.ImGui_Col_ButtonActive(), 0x135E61FF)
    reaper.ImGui_PushStyleColor(State.ui.ctx, reaper.ImGui_Col_ResizeGrip(), 0x135E61FF)  
    reaper.ImGui_PushStyleColor(State.ui.ctx, reaper.ImGui_Col_ResizeGripHovered(), 0x32878AFF) 
    reaper.ImGui_PushStyleColor(State.ui.ctx, reaper.ImGui_Col_ResizeGripActive(), 0x135E61FF) 
    reaper.ImGui_PushStyleColor(State.ui.ctx, reaper.ImGui_Col_Header(), 0x1A686BFF)
    reaper.ImGui_PushStyleColor(State.ui.ctx, reaper.ImGui_Col_HeaderHovered(), 0x32878AFF)
    reaper.ImGui_PushStyleColor(State.ui.ctx, reaper.ImGui_Col_HeaderActive(), 0x135E61FF)
end

--------------------------------------------------------------------------------
--- [ UI HELPERS ]
--------------------------------------------------------------------------------

local UI = {}

function UI.Toggle(label, value, tooltip)
    local x, y = reaper.ImGui_GetCursorScreenPos(State.ui.ctx)
    local dl = reaper.ImGui_GetWindowDrawList(State.ui.ctx)
  
    local height = reaper.ImGui_GetFrameHeight(State.ui.ctx) * 0.75
    local width = height * 2.0
    local radius = height * 0.5
    local frame_height = reaper.ImGui_GetFrameHeight(State.ui.ctx)
    local y_offset = (frame_height - height) * 0.5
  
    local clicked = reaper.ImGui_InvisibleButton(State.ui.ctx, "##" .. label, width, frame_height)
    local hovered_switch = reaper.ImGui_IsItemHovered(State.ui.ctx)
    local toggled = value
    if clicked then
        toggled = not toggled
    end
  
    local col_bg_off = 0x555555FF
    local col_bg_on  = 0x135E61FF
    local col_knob   = 0xFFFFFFFF
  
    local bg_col     = toggled and col_bg_on or col_bg_off
    reaper.ImGui_DrawList_AddRectFilled(dl, x, y + y_offset, x + width, y + height + y_offset, bg_col, radius)
  
    local t = toggled and 1.0 or 0.0
    local knob_x = x + radius + t * (width - radius * 2)
    local knob_radius = radius * 0.8
    reaper.ImGui_DrawList_AddCircleFilled(dl, knob_x, y + y_offset + radius, knob_radius, col_knob)
  
    reaper.ImGui_SameLine(State.ui.ctx)
    
    local text_y_offset = (frame_height - reaper.ImGui_GetTextLineHeight(State.ui.ctx)) * 0.5
    reaper.ImGui_SetCursorPosY(State.ui.ctx, reaper.ImGui_GetCursorPosY(State.ui.ctx) + text_y_offset)
    reaper.ImGui_Text(State.ui.ctx, label)
    
    local hovered_label = reaper.ImGui_IsItemHovered(State.ui.ctx)
    if tooltip and tooltip ~= "" and (hovered_switch or hovered_label) then
        reaper.ImGui_BeginTooltip(State.ui.ctx)
        reaper.ImGui_PushTextWrapPos(State.ui.ctx, 300 * State.ui.scale_factor)
        reaper.ImGui_Text(State.ui.ctx, tooltip)
        reaper.ImGui_PopTextWrapPos(State.ui.ctx)
        reaper.ImGui_EndTooltip(State.ui.ctx)
    end
    return toggled, clicked
end

function UI.BeginFramedGroup(label)
    local ctx = State.ui.ctx
    
    local pad_x = 12 * State.ui.scale_factor
    local pad_y = 8 * State.ui.scale_factor
    
    local start_x, start_y = reaper.ImGui_GetCursorScreenPos(ctx)
    
    reaper.ImGui_SetCursorScreenPos(ctx, start_x + pad_x, start_y + pad_y)
    reaper.ImGui_TextDisabled(ctx, label)
    
    reaper.ImGui_Dummy(ctx, 0, 4 * State.ui.scale_factor)
    
    reaper.ImGui_BeginGroup(ctx)
    
    reaper.ImGui_Indent(ctx, pad_x)
    
    return {
        min_x = start_x,
        min_y = start_y,
        pad_x = pad_x,
        pad_y = pad_y
    }
end

function UI.EndFramedGroup(frame_data)
    local ctx = State.ui.ctx
    local dl = reaper.ImGui_GetWindowDrawList(ctx)
    
    reaper.ImGui_Dummy(ctx, 0, frame_data.pad_y)
    
    reaper.ImGui_Unindent(ctx, frame_data.pad_x)
    reaper.ImGui_EndGroup(ctx)
    
    local _, max_y = reaper.ImGui_GetItemRectMax(ctx)
    
    local window_x = reaper.ImGui_GetWindowPos(ctx)
    local window_w = reaper.ImGui_GetWindowWidth(ctx)
    local style_pad_x, _ = reaper.ImGui_GetStyleVar(ctx, reaper.ImGui_StyleVar_WindowPadding())
    
    local current_indent = reaper.ImGui_GetCursorPosX(ctx) - style_pad_x
    local right_x = window_x + window_w - style_pad_x - current_indent
    
    local col = 0x555555FF
    local rounding = 5 * State.ui.scale_factor
    
    reaper.ImGui_DrawList_AddRect(dl, frame_data.min_x, frame_data.min_y, right_x, max_y, col, rounding)
    
    reaper.ImGui_Dummy(ctx, 0, 6 * State.ui.scale_factor)
end

function UI.DrawRow(label, tooltip, draw_widget_func)
    local ctx = State.ui.ctx
    
    local window_w = reaper.ImGui_GetWindowWidth(ctx)
    local style_pad_x, _ = reaper.ImGui_GetStyleVar(ctx, reaper.ImGui_StyleVar_WindowPadding())
    local current_indent = reaper.ImGui_GetCursorPosX(ctx) - style_pad_x
    
    local frame_inner_pad = 12 * State.ui.scale_factor
    local table_w = window_w - (style_pad_x * 2) - (current_indent * 2) - frame_inner_pad
    if table_w < 10 then table_w = 10 end
    
    local table_flags = reaper.ImGui_TableFlags_None()
    if reaper.ImGui_BeginTable(ctx, "row_table_" .. label, 2, table_flags, table_w) then
        reaper.ImGui_TableSetupColumn(ctx, "LabelCol", reaper.ImGui_TableColumnFlags_WidthFixed(), 150 * State.ui.scale_factor)
        reaper.ImGui_TableSetupColumn(ctx, "WidgetCol", reaper.ImGui_TableColumnFlags_WidthStretch())
        
        reaper.ImGui_TableNextRow(ctx)
        reaper.ImGui_TableNextColumn(ctx)
        
        reaper.ImGui_AlignTextToFramePadding(ctx)
        reaper.ImGui_Text(ctx, label)
        if tooltip then UI.Tooltip(tooltip) end
        
        reaper.ImGui_TableNextColumn(ctx)
        
        reaper.ImGui_SetNextItemWidth(ctx, -1)
        draw_widget_func()
        
        reaper.ImGui_EndTable(ctx)
    end
end

function UI.SegmentedControl(label1, label2, value, tooltip)
    local ctx = State.ui.ctx
    local dl = reaper.ImGui_GetWindowDrawList(ctx)
    
    local w1, h1 = reaper.ImGui_CalcTextSize(ctx, label1)
    local w2, h2 = reaper.ImGui_CalcTextSize(ctx, label2)
    
    local padding_x = 16 * State.ui.scale_factor
    local padding_y = 6 * State.ui.scale_factor
    
    local h = math.max(h1, h2) + padding_y * 2
    local total_w = w1 + w2 + padding_x * 4
    local radius = h * 0.5
    
    local x, y = reaper.ImGui_GetCursorScreenPos(ctx)
    
    local clicked = reaper.ImGui_InvisibleButton(ctx, "##" .. label1 .. label2, total_w, h)
    local hovered = reaper.ImGui_IsItemHovered(ctx)
    
    local toggled = value
    if clicked then
        local mouse_x, _ = reaper.ImGui_GetMousePos(ctx)
        local split_x = x + w1 + padding_x * 2
        toggled = (mouse_x >= split_x)
    end
    
    local col_outline = 0x555555FF
    local col_bg_active = 0x135E61FF
    local col_text_active = 0xFFFFFFFF
    local col_text_inactive = 0xAAAAAAFF
    
    reaper.ImGui_DrawList_AddRect(dl, x, y, x + total_w, y + h, col_outline, radius, 0, 1.0)
    
    local active_w = toggled and (w2 + padding_x * 2) or (w1 + padding_x * 2)
    local active_x = toggled and (x + w1 + padding_x * 2) or x
    
    reaper.ImGui_DrawList_AddRectFilled(dl, active_x, y, active_x + active_w, y + h, col_bg_active, radius)
    
    local text1_x = x + padding_x
    local text1_y = y + padding_y + (math.max(h1, h2) - h1) * 0.5
    reaper.ImGui_DrawList_AddText(dl, text1_x, text1_y, toggled and col_text_inactive or col_text_active, label1)
    
    local text2_x = x + w1 + padding_x * 3
    local text2_y = y + padding_y + (math.max(h1, h2) - h2) * 0.5
    reaper.ImGui_DrawList_AddText(dl, text2_x, text2_y, toggled and col_text_active or col_text_inactive, label2)
    
    if tooltip and tooltip ~= "" and hovered then
        reaper.ImGui_BeginTooltip(ctx)
        reaper.ImGui_PushTextWrapPos(ctx, 300 * State.ui.scale_factor)
        reaper.ImGui_Text(ctx, tooltip)
        reaper.ImGui_PopTextWrapPos(ctx)
        reaper.ImGui_EndTooltip(ctx)
    end
    
    return toggled, clicked
end

function UI.Tooltip(text, wrap_width)
    if not text or text == "" then return end
    if not reaper.ImGui_IsItemHovered(State.ui.ctx) then return end
    reaper.ImGui_BeginTooltip(State.ui.ctx)
    reaper.ImGui_PushTextWrapPos(State.ui.ctx, (wrap_width or (300 * State.ui.scale_factor)))
    reaper.ImGui_Text(State.ui.ctx, text)
    reaper.ImGui_PopTextWrapPos(State.ui.ctx)
    reaper.ImGui_EndTooltip(State.ui.ctx)
end

local function open_url(url)
    if type(url) ~= "string" or url == "" then return false end
    if reaper.CF_ShellExecute then
        reaper.CF_ShellExecute(url)
        return true
    end
    local os_name = reaper.GetOS() or ""
    local cmd
    if os_name:match("Win") then
        cmd = 'cmd.exe /C start "" "' .. url .. '"'
    elseif os_name:match("OSX") or os_name:match("macOS") then
        cmd = 'open "' .. url .. '"'
    else
        cmd = 'xdg-open "' .. url .. '"'
    end
    reaper.ExecProcess(cmd, 0)
    return true
end

--------------------------------------------------------------------------------
--- [ CORE ENGINE ]
--------------------------------------------------------------------------------

local Core = {}

function Core.UpdateMetronomeState()
    State.runtime.metronome_active = (reaper.GetToggleCommandState(40364) == 1)
end

function Core.ToggleMetronome()
    reaper.Main_OnCommand(40364, 0)  
    Core.UpdateMetronomeState()  
end

function Core.SetProjectBPM()
    if State.runtime.project_bpm < 10 then State.runtime.project_bpm = 10 end
    if State.runtime.project_bpm > 960 then State.runtime.project_bpm = 960 end
    reaper.SetCurrentBPM(0, State.runtime.project_bpm, true)
end

function Core.CleanUp()
    if State.runtime.running then
        reaper.Undo_EndBlock("Loop Trainer Session", -1)
    end
    if State.config.restore_on_close and State.runtime.original_bpm then
        reaper.SetCurrentBPM(0, State.runtime.original_bpm, false)
    end
end

reaper.atexit(Core.CleanUp)

function Core.StopScript()
    State.runtime.session_id = State.runtime.session_id + 1
    State.runtime.running = false
    reaper.CSurf_OnStop()
    reaper.Undo_EndBlock("Loop Trainer Session", -1)
end

function Core.CloseScript()
    Core.StopScript()
    State.runtime.script_running = false  
end

function Core.CheckConditions()
    local loop_start, loop_end = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
    if loop_start == loop_end then
        reaper.ShowMessageBox("No selection in Time Selection!\nPlease select an area of the timeline before running the script.", "Error", 0)
        return false
    end

    local repeat_state = reaper.GetToggleCommandState(1068)  
    if repeat_state ~= 1 then
        reaper.ShowMessageBox("The Repeat button is not enabled!\nEnable the loop in the Transport before running the script.", "Error", 0)
        return false
    end

    return true 
end

function Core.StartLoop()
    if State.runtime.running then return end
    if not Core.CheckConditions() then return end  
    
    reaper.Undo_BeginBlock()
    
    State.runtime.session_id = State.runtime.session_id + 1
    local current_session = State.runtime.session_id
    
    State.runtime.running = true
    State.runtime.repeat_count = 0
    State.runtime.current_cycle = 1
    
    if State.config.training_mode == 1 then
        Core.SetProjectBPM() -- ensure clamp just in case
        reaper.SetCurrentBPM(0, State.config.comp_start_bpm, true)
        State.runtime.project_bpm = State.config.comp_start_bpm
    end

    local loop_start, loop_end = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
    
    reaper.SetEditCurPos(loop_start, true, false)
    reaper.CSurf_OnPlay()

    local last_position = reaper.GetPlayPosition()

    local function checkLoop()
        if not State.runtime.running or State.runtime.session_id ~= current_session then return end
        if reaper.GetPlayState() == 0 then Core.StopScript() return end

        local current_position = reaper.GetPlayPosition()
        local l_start, l_end = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
        local loop_len = l_end - l_start

        if current_position < last_position then
             local jump_dist = last_position - current_position
             local is_near_start = math.abs(current_position - l_start) < 0.5
             if jump_dist > (loop_len * 0.2) and is_near_start then
                 State.runtime.repeat_count = State.runtime.repeat_count + 1
                 State.runtime.remaining_repeats = State.config.num_repeats - State.runtime.repeat_count  
                 
                 if State.runtime.repeat_count >= State.config.num_repeats then
                     State.runtime.repeat_count = 0
                     State.runtime.remaining_repeats = State.config.num_repeats  
                     local bpm = reaper.Master_GetTempo()
                     local new_bpm = bpm
                     
                     if State.config.training_mode == 0 then
                         new_bpm = bpm + State.config.bpm_increment
                         if new_bpm > 960 then new_bpm = 960 end 
                     else
                         new_bpm = bpm + State.config.comp_increment
                         if new_bpm > State.config.comp_max_bpm then
                             State.runtime.current_cycle = State.runtime.current_cycle + 1
                             if State.runtime.current_cycle > State.config.comp_cycles then
                                 if State.config.comp_end_behavior == 0 then
                                     Core.StopScript()
                                     return
                                 elseif State.config.comp_end_behavior == 1 then
                                     new_bpm = State.config.comp_start_bpm
                                     State.runtime.current_cycle = 1
                                 elseif State.config.comp_end_behavior == 2 then
                                     new_bpm = State.config.comp_max_bpm
                                 end
                             else
                                 new_bpm = State.config.comp_start_bpm
                             end
                         end
                     end
                     
                     reaper.SetCurrentBPM(0, new_bpm, true)
                     State.runtime.project_bpm = new_bpm
                     
                     last_position = reaper.GetPlayPosition()
                     
                     local wait_frames = 0
                     local function safeWait()
                         if not State.runtime.running or State.runtime.session_id ~= current_session then return end
                         wait_frames = wait_frames + 1
                         if wait_frames > 5 then
                              last_position = reaper.GetPlayPosition()
                              reaper.defer(checkLoop)
                         else
                              reaper.defer(safeWait)
                         end
                     end
                     reaper.defer(safeWait)
                     return
                 end
             end
        end

        last_position = current_position
        reaper.defer(checkLoop)
    end

    reaper.defer(checkLoop)
end

-- Main GUI render loop
function UI.LoopTrainerGUI()
    if not State.runtime.script_running then return end
    
    Core.UpdateMetronomeState()  

    ApplyTheme()
    reaper.ImGui_PushFont(State.ui.ctx, State.ui.sans_serif, State.ui.font_size)
    
    local window_flags = reaper.ImGui_WindowFlags_NoCollapse()
    
    reaper.ImGui_SetNextWindowSize(State.ui.ctx, 600 * State.ui.scale_factor, 550 * State.ui.scale_factor, reaper.ImGui_Cond_FirstUseEver())
        
    local visible, open = reaper.ImGui_Begin(State.ui.ctx, "Floop Studio - Trainer", true, window_flags)

    if visible then
        if reaper.ImGui_IsKeyPressed(State.ui.ctx, reaper.ImGui_Key_Space()) then
            if State.runtime.running then
                Core.StopScript()
            else
                Core.StartLoop()
            end
        end

        local window_width = reaper.ImGui_GetWindowWidth(State.ui.ctx)
        
        local is_complex = State.config.training_mode == 1
        local mode_toggled, mode_clicked = UI.SegmentedControl("Simple Training", "Complex Training", is_complex, "Enable additional advanced training options and parameters.")
        if mode_clicked then
            State.config.training_mode = mode_toggled and 1 or 0
        end
        
        reaper.ImGui_SameLine(State.ui.ctx, 0, 15 * State.ui.scale_factor)
        
        local pad_y = 6 * State.ui.scale_factor
        local dummy_w, h1 = reaper.ImGui_CalcTextSize(State.ui.ctx, "Simple Training")
        local dummy_w2, h2 = reaper.ImGui_CalcTextSize(State.ui.ctx, "Complex Training")
        local segmented_h = math.max(h1, h2) + pad_y * 2
        local metro_btn_size = segmented_h
        
        local mx, my = reaper.ImGui_GetCursorScreenPos(State.ui.ctx)
        local dl = reaper.ImGui_GetWindowDrawList(State.ui.ctx)
        
        local clicked = reaper.ImGui_InvisibleButton(State.ui.ctx, "##metro_btn", metro_btn_size, metro_btn_size)
        local hovered = reaper.ImGui_IsItemHovered(State.ui.ctx)
        local active = reaper.ImGui_IsItemActive(State.ui.ctx)
        
        if clicked then
            Core.ToggleMetronome()
        end
        
        local col_outline = 0x555555FF
        local bg_color = 0x00000000
        if State.runtime.metronome_active then
            bg_color = 0x135E61FF
        end
        
        if active then
            bg_color = 0x1A686BFF
        elseif hovered then
            if State.runtime.metronome_active then
                bg_color = 0x32878AFF
            else
                bg_color = 0x333333FF
            end
        end
        
        local radius = metro_btn_size * 0.25
        
        if bg_color == 0x00000000 then
             reaper.ImGui_DrawList_AddRect(dl, mx, my, mx + metro_btn_size, my + metro_btn_size, col_outline, radius, 0, 1.0)
        else
             reaper.ImGui_DrawList_AddRectFilled(dl, mx, my, mx + metro_btn_size, my + metro_btn_size, bg_color, radius)
        end
        
        if State.ui.img_metro and reaper.ImGui_ValidatePtr(State.ui.img_metro, 'ImGui_Image*') then
            local img_pad = 4 * State.ui.scale_factor
            local img_draw_size = metro_btn_size - (img_pad * 2)
            reaper.ImGui_DrawList_AddImage(dl, State.ui.img_metro, mx + img_pad, my + img_pad, mx + img_pad + img_draw_size, my + img_pad + img_draw_size)
        else
            local btn_text = State.runtime.metronome_active and "M" or "m"
            local tw, th = reaper.ImGui_CalcTextSize(State.ui.ctx, btn_text)
            local tx = mx + (metro_btn_size - tw) * 0.5
            local ty = my + (metro_btn_size - th) * 0.5
            reaper.ImGui_DrawList_AddText(dl, tx, ty, 0xFFFFFFFF, btn_text)
        end
        
        UI.Tooltip("Toggle REAPER Metronome")
        
        local is_compact = reaper.ImGui_IsWindowDocked(State.ui.ctx) or window_width < (380 * State.ui.scale_factor)
        
        if not is_compact then
            reaper.ImGui_SameLine(State.ui.ctx, 0, 15 * State.ui.scale_factor)
            
            local switch_y_offset = (metro_btn_size - reaper.ImGui_GetFrameHeight(State.ui.ctx)) * 0.5
            reaper.ImGui_SetCursorPosY(State.ui.ctx, reaper.ImGui_GetCursorPosY(State.ui.ctx) + switch_y_offset)
            
            local restore_label = "Restore BPM on Exit"
            local restore_toggled, restore_clicked = UI.Toggle(restore_label, State.config.restore_on_close)
            if restore_clicked then State.config.restore_on_close = restore_toggled end
            
            reaper.ImGui_SameLine(State.ui.ctx, 0, 15 * State.ui.scale_factor)
            local help_btn_w = 34 * State.ui.scale_factor
            if reaper.ImGui_Button(State.ui.ctx, " ? ", help_btn_w, 0) then
                State.ui.show_help_modal = true
                reaper.ImGui_OpenPopup(State.ui.ctx, "Help")
            end
            
            reaper.ImGui_SetCursorPosY(State.ui.ctx, reaper.ImGui_GetCursorPosY(State.ui.ctx) - switch_y_offset)
        else
            reaper.ImGui_SameLine(State.ui.ctx, 0, 15 * State.ui.scale_factor)
            local help_btn_w = 34 * State.ui.scale_factor
            if reaper.ImGui_Button(State.ui.ctx, " ? ", help_btn_w, metro_btn_size) then
                State.ui.show_help_modal = true
                reaper.ImGui_OpenPopup(State.ui.ctx, "Help")
            end
        end
        
        reaper.ImGui_Dummy(State.ui.ctx, 0, 10 * State.ui.scale_factor)
        
        local frame_param = UI.BeginFramedGroup("Training Parameters")
        
        if State.config.training_mode == 1 then
            UI.DrawRow("On Finish:", "When you reach Max BPM, choose what happens next: stop the training, repeat the training from Start BPM, or keep playing at the maximum speed until you stop.", function()
                local preview_text = State.config.comp_end_behavior == 0 and "Stop playing" or (State.config.comp_end_behavior == 1 and "Restart from Start BPM" or "Keep playing at Max BPM")
                if reaper.ImGui_BeginCombo(State.ui.ctx, "##end_behavior", preview_text) then
                    if reaper.ImGui_Selectable(State.ui.ctx, "Stop playing", State.config.comp_end_behavior == 0) then State.config.comp_end_behavior = 0 end
                    if reaper.ImGui_Selectable(State.ui.ctx, "Restart from Start BPM", State.config.comp_end_behavior == 1) then State.config.comp_end_behavior = 1 end
                    if reaper.ImGui_Selectable(State.ui.ctx, "Keep playing at Max BPM", State.config.comp_end_behavior == 2) then State.config.comp_end_behavior = 2 end
                    reaper.ImGui_EndCombo(State.ui.ctx)
                end
            end)
            reaper.ImGui_Dummy(State.ui.ctx, 0, 10 * State.ui.scale_factor)
        end
        
        if State.config.training_mode == 0 then
            UI.DrawRow("BPM Increment", "How many BPM to add to the project tempo after each repetition.", function()
                _, State.config.bpm_increment = reaper.ImGui_SliderInt(State.ui.ctx, "##bpm_increment", State.config.bpm_increment, 1, 20)
                if State.config.bpm_increment < 1 then State.config.bpm_increment = 1 end
                if State.config.bpm_increment > 50 then State.config.bpm_increment = 50 end
            end)
        else
            local frame_bpm = UI.BeginFramedGroup("BPM Progression")
            
            UI.DrawRow("Start BPM", "The initial speed where the training begins.", function()
                _, State.config.comp_start_bpm = reaper.ImGui_InputInt(State.ui.ctx, "##comp_start_bpm", State.config.comp_start_bpm, 0, 0)
            end)
            
            UI.DrawRow("Max BPM", "The target maximum speed limit.", function()
                _, State.config.comp_max_bpm = reaper.ImGui_InputInt(State.ui.ctx, "##comp_max_bpm", State.config.comp_max_bpm, 0, 0)
            end)
            
            UI.DrawRow("BPM Increment", "How many BPM to add at each new step.", function()
                _, State.config.comp_increment = reaper.ImGui_SliderInt(State.ui.ctx, "##comp_increment", State.config.comp_increment, 1, 20)
            end)

            UI.DrawRow("Total Cycles", "How many times to repeat the whole sequence (from Start to Max BPM).", function()
                _, State.config.comp_cycles = reaper.ImGui_SliderInt(State.ui.ctx, "##comp_cycles", State.config.comp_cycles, 1, 20)
            end)
            
            UI.EndFramedGroup(frame_bpm)
        end
        
        UI.EndFramedGroup(frame_param)

        local frame_play = UI.BeginFramedGroup("Playback & Feedback")
        
        local rep_text = State.config.training_mode == 0 and "Repetitions" or "Loops / Step"
        local rep_tooltip = State.config.training_mode == 0 and "Total number of times the loop will repeat during the session." or "Number of repetitions (loops) for each speed level."
        
        UI.DrawRow(rep_text, rep_tooltip, function()
            local repeats_changed
            repeats_changed, State.config.num_repeats = reaper.ImGui_SliderInt(State.ui.ctx, "##num_repeats", State.config.num_repeats, 1, 30)
            if State.config.num_repeats < 1 then State.config.num_repeats = 1 end
            if State.config.num_repeats > 100 then State.config.num_repeats = 100 end
            State.runtime.remaining_repeats = State.config.num_repeats - State.runtime.repeat_count
        end)
        
        reaper.ImGui_Dummy(State.ui.ctx, 0, 5 * State.ui.scale_factor)
        
        if not reaper.ImGui_IsItemActive(State.ui.ctx) and not State.runtime.running then
            State.runtime.project_bpm = reaper.Master_GetTempo()
        end

        UI.DrawRow("Project BPM", "Type a value and press Enter to update the project tempo.", function()
            local changed
            changed, State.runtime.project_bpm = reaper.ImGui_InputDouble(State.ui.ctx, "##project_bpm", State.runtime.project_bpm, 0, 0, "%.2f")
            if changed or reaper.ImGui_IsItemDeactivatedAfterEdit(State.ui.ctx) then
                Core.SetProjectBPM()
            end
        end)
        
        UI.EndFramedGroup(frame_play)

        local frame_status = UI.BeginFramedGroup("Session Progress")
        reaper.ImGui_Dummy(State.ui.ctx, 0, 5)

        reaper.ImGui_Text(State.ui.ctx, "Repetitions remaining: " .. State.runtime.remaining_repeats)
        if State.config.training_mode == 1 then
            reaper.ImGui_Text(State.ui.ctx, "Current Cycle: " .. State.runtime.current_cycle .. " / " .. State.config.comp_cycles)
        end
        reaper.ImGui_Dummy(State.ui.ctx, 0, 10 * State.ui.scale_factor)
        
        local style_pad_x, _ = reaper.ImGui_GetStyleVar(State.ui.ctx, reaper.ImGui_StyleVar_WindowPadding())
        local current_indent = reaper.ImGui_GetCursorPosX(State.ui.ctx) - style_pad_x
        local frame_inner_pad = 12 * State.ui.scale_factor
        local safe_width = window_width - (style_pad_x * 2) - (current_indent * 2) - frame_inner_pad
        if safe_width < 10 then safe_width = 10 end
        
        local spacing = 20 * State.ui.scale_factor
        local button_height = 30 * State.ui.scale_factor
        local button_width = (safe_width - spacing) * 0.5

        reaper.ImGui_BeginDisabled(State.ui.ctx, State.runtime.running)
        if reaper.ImGui_Button(State.ui.ctx, "Start", button_width, button_height) then
            Core.StartLoop()
        end
        reaper.ImGui_EndDisabled(State.ui.ctx)
        reaper.ImGui_SameLine(State.ui.ctx, nil, spacing)
        if reaper.ImGui_Button(State.ui.ctx, "Stop", button_width, button_height) then
            Core.StopScript()
        end
        
        reaper.ImGui_Dummy(State.ui.ctx, 0, 8 * State.ui.scale_factor)
        
        local hint_text = "Press Spacebar to Start / Stop"
        local hint_w = reaper.ImGui_CalcTextSize(State.ui.ctx, hint_text)
        local hint_center_x = (safe_width - hint_w) * 0.5
        if hint_center_x > 0 then
            reaper.ImGui_SetCursorPosX(State.ui.ctx, reaper.ImGui_GetCursorPosX(State.ui.ctx) + hint_center_x)
        end
        reaper.ImGui_TextDisabled(State.ui.ctx, hint_text)
        
        UI.EndFramedGroup(frame_status)

        if State.ui.show_help_modal then
            local winX, winY = reaper.ImGui_GetWindowPos(State.ui.ctx)
            local winW, winH = reaper.ImGui_GetWindowSize(State.ui.ctx)

            local modalW = winW * 0.92
            local modalH = winH * 0.90
            if modalW > (680 * State.ui.scale_factor) then modalW = 680 * State.ui.scale_factor end
            if modalH > (560 * State.ui.scale_factor) then modalH = 560 * State.ui.scale_factor end

            reaper.ImGui_SetNextWindowSize(State.ui.ctx, modalW, modalH, reaper.ImGui_Cond_Always())

            if winX and winY and winW and winH then
                local posX = winX + (winW - modalW) * 0.5
                local posY = winY + (winH - modalH) * 0.5
                reaper.ImGui_SetNextWindowPos(State.ui.ctx, posX, posY, reaper.ImGui_Cond_Appearing())
            end

            local flags = reaper.ImGui_WindowFlags_NoResize() | reaper.ImGui_WindowFlags_NoMove()
            if reaper.ImGui_BeginPopupModal(State.ui.ctx, "Help", true, flags) then
                local function BulletWrapped(text)
                    reaper.ImGui_Bullet(State.ui.ctx)
                    reaper.ImGui_SameLine(State.ui.ctx)
                    reaper.ImGui_TextWrapped(State.ui.ctx, text)
                end

                local bottom_reserved = 60 * State.ui.scale_factor
                if reaper.ImGui_BeginChild(State.ui.ctx, "HelpContent", 0, -bottom_reserved) then
                    reaper.ImGui_Text(State.ui.ctx, "FLOOP STUDIO TRAINER - QUICK GUIDE")
                    reaper.ImGui_Separator(State.ui.ctx)
                    reaper.ImGui_Spacing(State.ui.ctx)

                    reaper.ImGui_Text(State.ui.ctx, "WHAT THIS SCRIPT DOES")
                    reaper.ImGui_TextWrapped(State.ui.ctx, "Practice a time selection in REAPER and automatically increase tempo over repetitions. You can use it with an audio track (time-stretched) or with an empty project using only the metronome.")
                    reaper.ImGui_Dummy(State.ui.ctx, 0, 10 * State.ui.scale_factor)

                    reaper.ImGui_Text(State.ui.ctx, "SETUP (REQUIRED)")
                    BulletWrapped("Create a Time Selection for the part you want to practice (loop).")
                    BulletWrapped("Enable REAPER Transport: Repeat (Loop).")
                    BulletWrapped("Pick your training mode and settings, then press Start (Spacebar also toggles Start/Stop).")
                    reaper.ImGui_Dummy(State.ui.ctx, 0, 10 * State.ui.scale_factor)

                    reaper.ImGui_Text(State.ui.ctx, "AUDIO TRACKS: TIMEBASE / PITCH RATE (IMPORTANT)")
                    reaper.ImGui_TextWrapped(State.ui.ctx, "If you loop and change BPM while playing an audio item, REAPER must know how to stretch it. Set either the Project Timebase or the Track Timebase (the track containing the audio) to: Beats (position, length, rate). This keeps the audio aligned with tempo changes and prevents timing/pitch drift.")
                    reaper.ImGui_Dummy(State.ui.ctx, 0, 10 * State.ui.scale_factor)

                    reaper.ImGui_Text(State.ui.ctx, "METRONOME COUNT-IN (OPTIONAL BUT RECOMMENDED)")
                    reaper.ImGui_TextWrapped(State.ui.ctx, "If you want a count-in before each playback start, open REAPER Metronome Settings and enable:")
                    BulletWrapped("Count-in before playback")
                    BulletWrapped("Metronome enabled during playback")
                    reaper.ImGui_TextWrapped(State.ui.ctx, "This script can toggle the metronome on/off, but it does not change these preferences.")
                    reaper.ImGui_Dummy(State.ui.ctx, 0, 10 * State.ui.scale_factor)

                    reaper.ImGui_Text(State.ui.ctx, "COMPLEX TRAINING: EXAMPLE (STEP-BY-STEP)")
                    reaper.ImGui_TextWrapped(State.ui.ctx, "Goal: practice a loop starting slow and gradually speed up in clear steps.")
                    BulletWrapped("Mode: Complex Training")
                    BulletWrapped("Start BPM: 80")
                    BulletWrapped("Max BPM: 120")
                    BulletWrapped("BPM Increment: 5")
                    BulletWrapped("Loops / Step: 3 (repeat the loop 3 times at each BPM before increasing)")
                    BulletWrapped("Total Cycles: 2 (run the whole 80→120 progression twice)")
                    BulletWrapped("On Finish: stop the training, repeat the training from Start BPM, or keep playing at the maximum speed until you stop.")
                    reaper.ImGui_Dummy(State.ui.ctx, 0, 10 * State.ui.scale_factor)

                    reaper.ImGui_Text(State.ui.ctx, "CUSTOM METRONOME SOUNDS (KNOWN QUIRK)")
                    reaper.ImGui_TextWrapped(State.ui.ctx, "With some custom metronome click samples, you may hear a doubled click at the end of the loop. If it happens, switching back to REAPER's default metronome sounds usually fixes it.")
                    reaper.ImGui_Dummy(State.ui.ctx, 0, 14 * State.ui.scale_factor)
                    reaper.ImGui_Separator(State.ui.ctx)
                    reaper.ImGui_Dummy(State.ui.ctx, 0, 10 * State.ui.scale_factor)

                    reaper.ImGui_Text(State.ui.ctx, "SUPPORT")
                    reaper.ImGui_TextWrapped(State.ui.ctx, "If you find my scripts useful and want to support their development, you can buy me a coffee on Ko-fi")
                    if reaper.ImGui_Button(State.ui.ctx, "Support Floop's Reaper Scripts on Ko-fi") then
                        open_url("https://ko-fi.com/floopsreaperscripts")
                    end
                    reaper.ImGui_EndChild(State.ui.ctx)
                end

                reaper.ImGui_Spacing(State.ui.ctx)
                reaper.ImGui_Separator(State.ui.ctx)
                reaper.ImGui_Spacing(State.ui.ctx)

                local availWidth = reaper.ImGui_GetContentRegionAvail(State.ui.ctx)
                local buttonWidth = 100 * State.ui.scale_factor
                reaper.ImGui_SetCursorPosX(State.ui.ctx, (availWidth - buttonWidth) * 0.5)
                if reaper.ImGui_Button(State.ui.ctx, "Close", buttonWidth, 30 * State.ui.scale_factor) then
                    State.ui.show_help_modal = false
                    reaper.ImGui_CloseCurrentPopup(State.ui.ctx)
                end

                reaper.ImGui_EndPopup(State.ui.ctx)
            else
                State.ui.show_help_modal = false
            end
        end
    end

    pcall(reaper.ImGui_End, State.ui.ctx)
    pcall(reaper.ImGui_PopFont, State.ui.ctx)
    pcall(reaper.ImGui_PopStyleVar, State.ui.ctx, 6)
    pcall(reaper.ImGui_PopStyleColor, State.ui.ctx, 19)

    if not open then
        Core.CloseScript()
        return
    end

    if State.runtime.script_running then
        reaper.defer(UI.LoopTrainerGUI)
    end
end

-- Entry point
reaper.defer(UI.LoopTrainerGUI)
