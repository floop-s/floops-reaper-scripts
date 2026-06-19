-- @noindex
-- @description Floop Hunter Framework - UI
-- @author Floop-s
-- @license GPL-3.0
local UI = {}
local reaper = reaper
local ImGui = require("floop_imgui")
local Engine = require("floop_engine")
local Logger = require("floop_logger")
local Cache = require("floop_cache")

-- Load Hunters
local HunterEss = require("hunters.hunter_ess")
local HunterPlosive = require("hunters.hunter_plosive")
local HunterBreath = require("hunters.hunter_breath")

UI.hunters = {
  [1] = HunterEss,
  [2] = HunterPlosive,
  [3] = HunterBreath
}
UI.active_hunter_idx = 1
UI.config = {}
UI.ctx = ImGui.CreateContext('Floop Hunter Framework')
UI.wants_close = false

-- Async State
UI.analysis_ctx = nil

-- View State
UI.view_start_frac = 0.0
UI.view_len_frac = 1.0
UI.auto_rescan = false
UI.auto_rescan_delay_ms = 200

local LAYOUT_DEBUG = false
local layout_debug = {}
local current_layout_key = nil

local SEGMENT_COLORS = {
  ["Plosive Hunter"] = 0xF97316AA,
  ["Ess Hunter"] = 0x10B981AA,
  ["Breath Hunter"] = 0x22D3EEAA
}

local LABEL_COLORS = {
  ["Plosive Hunter"] = 0xF97316FF,
  ["Ess Hunter"] = 0x10B981FF,
  ["Breath Hunter"] = 0x22D3EEFF
}

local function get_active_cache_for_selected_item()
  local hunter = UI.hunters[UI.active_hunter_idx]
  if not hunter then return nil, nil, nil end
  local item = reaper.GetSelectedMediaItem(0, 0)
  if not item then return nil, hunter, nil end
  local _, guid = reaper.GetSetMediaItemInfo_String(item, "GUID", "", false)

  local cache = Cache.get(guid, hunter.name)
  return cache, hunter, item
end

-- Initialize config
for k, v in pairs(UI.hunters[1].default_config) do UI.config[k] = v end

-- Theme Colors
local COLOR_WINDOW_BG = 0x1F2933FF
local COLOR_FRAME_BG = 0x0B1120FF
local COLOR_POPUP_BG = COLOR_FRAME_BG

local THEME_COLORS = {
  [reaper.ImGui_Col_WindowBg()]          = COLOR_WINDOW_BG,
  [reaper.ImGui_Col_TitleBg()]           = 0x0F766EFF,
  [reaper.ImGui_Col_TitleBgActive()]     = 0x0D9488FF,
  [reaper.ImGui_Col_Button()]            = 0x0D9488FF,
  [reaper.ImGui_Col_ButtonHovered()]     = 0x14B8A6FF,
  [reaper.ImGui_Col_ButtonActive()]      = 0x0F766EFF,
  [reaper.ImGui_Col_FrameBg()]           = COLOR_FRAME_BG,
  [reaper.ImGui_Col_FrameBgHovered()]    = 0x0F172AFF,
  [reaper.ImGui_Col_FrameBgActive()]     = 0x0F172AFF,
  [reaper.ImGui_Col_PopupBg()]           = COLOR_POPUP_BG,
  [reaper.ImGui_Col_SliderGrab()]        = 0xE5E7EBFF,
  [reaper.ImGui_Col_SliderGrabActive()]  = 0xFFFFFFFF,
  [reaper.ImGui_Col_CheckMark()]         = 0xFBBF24FF,
  [reaper.ImGui_Col_Header()]            = 0x1F2937FF,
  [reaper.ImGui_Col_HeaderHovered()]     = 0x0F766EFF,
  [reaper.ImGui_Col_HeaderActive()]      = 0x0D9488FF,
  [reaper.ImGui_Col_Separator()]         = 0x1F2937FF,
  [reaper.ImGui_Col_Text()]              = 0xE5E7EBFF,
  [reaper.ImGui_Col_TextDisabled()]      = 0x6B7280FF,
  [reaper.ImGui_Col_ResizeGrip()]        = 0x0D9488FF,
  [reaper.ImGui_Col_ResizeGripHovered()] = 0x14B8A6FF,
  [reaper.ImGui_Col_ResizeGripActive()]  = 0x0F766EFF,
}

local function apply_theme()
  reaper.ImGui_PushStyleVar(UI.ctx, reaper.ImGui_StyleVar_FrameRounding(), 4.0)
  reaper.ImGui_PushStyleVar(UI.ctx, reaper.ImGui_StyleVar_WindowRounding(), 8.0)
  reaper.ImGui_PushStyleVar(UI.ctx, reaper.ImGui_StyleVar_WindowPadding(), 16.0, 16.0)
  reaper.ImGui_PushStyleVar(UI.ctx, reaper.ImGui_StyleVar_FramePadding(), 3.0, 4.0)
  reaper.ImGui_PushStyleVar(UI.ctx, reaper.ImGui_StyleVar_ItemSpacing(), 6.0, 6.0)
  if reaper.ImGui_StyleVar_GrabRounding then
    reaper.ImGui_PushStyleVar(UI.ctx, reaper.ImGui_StyleVar_GrabRounding(), 4.0)
  end

  local color_count = 0
  for k, v in pairs(THEME_COLORS) do
    reaper.ImGui_PushStyleColor(UI.ctx, k, v)
    color_count = color_count + 1
  end
  return color_count
end

local apply_reduction -- forward declare

local function apply_active_hunter_only()
  local cache, hunter, item_res = get_active_cache_for_selected_item()
  if not item_res then return end

  if not cache or not cache.segments then
    scan_item()
    return
  end

  local segments_time = {}
  local tmap = cache.time or {}
  local hop_sec = (tmap[2] and tmap[1]) and (tmap[2] - tmap[1]) or ((UI.config.hop_ms or 10) / 1000)
  if hop_sec <= 0 then hop_sec = (UI.config.hop_ms or 10) / 1000 end

  for _, seg in ipairs(cache.segments) do
    local t1 = tmap[seg.start_idx]
    local t2 = tmap[seg.end_idx]
    if t1 and t2 then
      local t_end_real = t2 + hop_sec
      if seg.points and #seg.points > 0 then
        segments_time[#segments_time + 1] = {
          start_time = t1,
          end_time = t_end_real,
          points = seg.points,
          hpf_strength = seg.hpf_strength,
          hunter_name = hunter and hunter.name or nil
        }
      else
        local db = seg.gain_db or (UI.config.reduction_db or 6.0)
        segments_time[#segments_time + 1] = {
          start_time = t1,
          end_time = t_end_real,
          reduction_db = db,
          gain_db = db,
          hunter_name = hunter and hunter.name or nil
        }
      end
    end
  end

  if #segments_time == 0 then return end

  reaper.Undo_BeginBlock()

  local env_gain, env_hpf
  if UI.config.use_take_fx then
    local take = reaper.GetActiveTake(item_res)
    if take then
      env_gain = Engine.ensure_take_envelope(take, 0)
      env_hpf = Engine.ensure_take_envelope(take, 1)
    end
  else
    local track = reaper.GetMediaItem_Track(item_res)
    if track then
      env_gain = Engine.ensure_track_envelope(track, 0)
      env_hpf = Engine.ensure_track_envelope(track, 1)
    end
  end

  local item_pos = reaper.GetMediaItemInfo_Value(item_res, "D_POSITION")
  local item_len = reaper.GetMediaItemInfo_Value(item_res, "D_LENGTH")
  local pre = (UI.config.pre_ramp_ms or 10) / 1000
  local post = (UI.config.post_ramp_ms or 20) / 1000
  local t_start = math.max(0, item_pos - pre)
  local t_end = item_pos + item_len + post

  if hunter and hunter.name == "Plosive Hunter" then
    if env_hpf then
      if UI.config.use_take_fx then
        local take = reaper.GetActiveTake(item_res)
        local play_rate = take and reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE") or 1.0
        reaper.DeleteEnvelopePointRange(env_hpf, 0, item_len * play_rate + 1.0)
      else
        reaper.DeleteEnvelopePointRange(env_hpf, t_start, t_end)
      end
      reaper.Envelope_SortPoints(env_hpf)
    end
  else
    if env_gain then
      if UI.config.use_take_fx then
        local take = reaper.GetActiveTake(item_res)
        local play_rate = take and reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE") or 1.0
        reaper.DeleteEnvelopePointRange(env_gain, 0, item_len * play_rate + 1.0)
      else
        reaper.DeleteEnvelopePointRange(env_gain, t_start, t_end)
      end
      reaper.Envelope_SortPoints(env_gain)
    end
  end

  local cfg = {}
  for k, v in pairs(UI.config) do cfg[k] = v end
  cfg.overwrite = false
  Engine.apply_reduction(item_res, segments_time, cfg)
  reaper.Undo_EndBlock("Floop Hunter: Live Edit", -1)
  reaper.UpdateArrange()
end

local function apply_live_edit()
  if not UI.config.live_edit then return end
  apply_active_hunter_only()
end

UI.apply_live_edit = apply_live_edit

local function sanitize_csv_field(s)
  s = tostring(s or "")
  s = s:gsub("[\r\n]", " ")
  s = s:gsub(",", "_")
  return s
end

local function get_take_file_id(take)
  if not take then return "unknown" end
  local src = reaper.GetMediaItemTake_Source(take)
  if src and reaper.GetMediaSourceFileName then
    local _, fn = reaper.GetMediaSourceFileName(src, "")
    if fn and fn ~= "" then
      local base = fn:match("([^/\\]+)$") or fn
      if base and base ~= "" then return sanitize_csv_field(base) end
    end
  end
  if reaper.GetTakeName then
    local tn = reaper.GetTakeName(take)
    if tn and tn ~= "" then return sanitize_csv_field(tn) end
  end
  return "unknown"
end

local function export_eval(cache_entry, hunter, segments, stats)
  if not cache_entry or not hunter then return end
  local time_map = cache_entry.time
  if not time_map then return end

  Logger:set_target_hunter(hunter.name)

  local profile_id = tonumber(UI.config.source_profile or 0) or 0
  local file_id = sanitize_csv_field(cache_entry.file_id or cache_entry.item_guid or "unknown")
  local item_pos = cache_entry.item_pos or 0.0
  local hop_sec = (UI.config.hop_ms or 10) / 1000.0

  Logger:csv(string.format("%s,%d,%d,%d,%s", file_id, profile_id, 0, 0, "eval_start"))

  local csv_label = "det_generic"
  if hunter.name == "Breath Hunter" then csv_label = "det_breath_inhale"
  elseif hunter.name == "Ess Hunter" then csv_label = "det_ess"
  elseif hunter.name == "Plosive Hunter" then csv_label = "det_plosive" end

  if segments then
    for _, seg in ipairs(segments) do
      local t1 = time_map[seg.start_idx]
      local t2 = time_map[seg.end_idx]
      if t1 and t2 then
        local t_end_real = t2 + hop_sec
        local s_ms = math.floor(((t1 - item_pos) * 1000) + 0.5)
        local e_ms = math.floor(((t_end_real - item_pos) * 1000) + 0.5)
        Logger:csv(string.format("%s,%d,%d,%d,%s", file_id, profile_id, s_ms, e_ms, csv_label))
      end
    end
  end

  if stats and stats.rejected then
    for _, r in ipairs(stats.rejected) do
      local t1 = time_map[r.start_idx]
      local t2 = time_map[r.end_idx]
      if t1 and t2 then
        local t_end_real = t2 + hop_sec
        local s_ms = math.floor(((t1 - item_pos) * 1000) + 0.5)
        local e_ms = math.floor(((t_end_real - item_pos) * 1000) + 0.5)
        Logger:csv(string.format("%s,%d,%d,%d,%s", file_id, profile_id, s_ms, e_ms, "rej_" .. tostring(r.reason or "unk")))
      end
    end
  end

  Logger:csv(string.format("%s,%d,%d,%d,%s", file_id, profile_id, 0, 0, "eval_end"))
end

local function re_detect(cache_entry, hunter)
  if not hunter then hunter = UI.hunters[UI.active_hunter_idx] end
  local segments, stats = hunter.detect_segments(cache_entry.features, UI.config)
  cache_entry.segments = segments
  cache_entry.stats = stats
  export_eval(cache_entry, hunter, segments, stats)

  -- Apply default gain if missing
  local base_reduction = UI.config.reduction_db or 6.0
  for i = 1, #cache_entry.segments do
    local seg = cache_entry.segments[i]
    if seg.points and #seg.points > 0 then
      if seg.hpf_strength == nil then seg.hpf_strength = base_reduction end
    elseif seg.gain_db == nil then
      seg.gain_db = base_reduction
    end
  end

  apply_live_edit()
end

local function scan_item()
  local hunter = UI.hunters[UI.active_hunter_idx]
  local item = reaper.GetSelectedMediaItem(0, 0)
  if not item then
    reaper.ShowMessageBox("Please select an audio item first.", "No Item Selected", 0)
    return
  end

  if (UI.config.source_profile or 0) == 0 then
    reaper.ShowMessageBox("Please select a Source Profile before analyzing.", "Profile Required", 0)
    return
  end

  local _, guid = reaper.GetSetMediaItemInfo_String(item, "GUID", "", false)

  Cache.prune()

  -- Check Cache for existing features
  local cache_entry = Cache.get(guid, hunter.name)
  local current_hash = Cache.get_params_hash(UI.config, hunter.name)

  if cache_entry and cache_entry.params_hash == current_hash then
    re_detect(cache_entry, hunter)
    return
  end

  -- Start Async Analysis
  UI.analysis_ctx = Engine.create_analysis_context(item, hunter, UI.config)
  if UI.analysis_ctx then
    UI.analysis_ctx.guid = guid
    UI.analysis_ctx.params_hash = current_hash
    UI.analysis_ctx.hunter_name = hunter.name
    UI.view_start_frac = 0.0
    UI.view_len_frac = 1.0
  end
end

local function trigger_scan_or_detect()
  if UI.auto_rescan then
    scan_item()
  end
end

local function draw_waveform_panel()
  local W_avail, H_avail = reaper.ImGui_GetContentRegionAvail(UI.ctx)
  local W = math.max(420, W_avail)
  local H = 200 -- Fixed height for waveform
  local x0, y0 = reaper.ImGui_GetCursorScreenPos(UI.ctx)
  local cx, cy = reaper.ImGui_GetCursorPos(UI.ctx)

  reaper.ImGui_InvisibleButton(UI.ctx, '##waveform_panel', W, H)
  local dl = reaper.ImGui_GetWindowDrawList(UI.ctx)

  reaper.ImGui_DrawList_AddRectFilled(dl, x0, y0, x0 + W, y0 + H, 0x111827FF)
  reaper.ImGui_DrawList_AddRect(dl, x0, y0, x0 + W, y0 + H, 0x3A3A3AFF)

  local hovered = reaper.ImGui_IsItemHovered(UI.ctx)
  local mx, my = reaper.ImGui_GetMousePos(UI.ctx)
  local wheel = reaper.ImGui_GetMouseWheel(UI.ctx)
  local ctrl_down = reaper.ImGui_IsKeyDown(UI.ctx, reaper.ImGui_Mod_Ctrl())
  local wave_top = y0
  local wave_h = H
  local wave_scale = 0.90

  local cache, hunter = get_active_cache_for_selected_item()

  -- Progress Bar Overlay
  if UI.analysis_ctx then
    local progress = UI.analysis_ctx:get_progress()
    local bar_w = W * 0.6
    local bar_h = 20
    local bar_x = x0 + (W - bar_w) * 0.5
    local bar_y = y0 + (H - bar_h) * 0.5 -- Centered vertically

    -- Background
    reaper.ImGui_DrawList_AddRectFilled(dl, bar_x, bar_y, bar_x + bar_w, bar_y + bar_h, 0x00000088, 4.0)
    -- Fill
    reaper.ImGui_DrawList_AddRectFilled(dl, bar_x, bar_y, bar_x + (bar_w * progress), bar_y + bar_h, 0x0D9488FF, 4.0)
    -- Text
    local txt = string.format("Scanning... %d%%", math.floor(progress * 100))
    local tw, th = reaper.ImGui_CalcTextSize(UI.ctx, txt)
    reaper.ImGui_DrawList_AddText(dl, bar_x + (bar_w - tw) * 0.5, bar_y + (bar_h - th) * 0.5, 0xFFFFFFFF, txt)
  end

  -- Interaction: Zoom/Scroll
  if cache and cache.amp and #cache.amp > 0 then
    local view_start = UI.view_start_frac or 0.0
    local view_len = UI.view_len_frac or 1.0

    if view_start < 0 then view_start = 0 end
    if view_len < 0.05 then view_len = 0.05 end
    if view_start + view_len > 1.0 then view_start = 1.0 - view_len end

    if hovered then
      if wheel ~= 0 then
        if ctrl_down then
          local step = 0.25 * view_len
          local delta = -wheel * step
          view_start = view_start + delta
          if view_start < 0 then view_start = 0 end
          if view_start + view_len > 1.0 then view_start = 1.0 - view_len end
          UI.view_start_frac = view_start
        else
          local cursor_frac = (mx - x0) / W
          if cursor_frac < 0 then cursor_frac = 0 elseif cursor_frac > 1 then cursor_frac = 1 end

          local factor = math.exp(-wheel * 0.1)
          local new_len = math.max(0.05, math.min(1.0, view_len * factor))
          local delta_len = new_len - view_len
          local new_start = view_start + cursor_frac * (-delta_len)

          if new_start < 0 then new_start = 0 end
          if new_start + new_len > 1.0 then new_start = 1.0 - new_len end

          view_len = new_len
          view_start = new_start
          UI.view_len_frac = new_len
          UI.view_start_frac = new_start
        end
      end

      if reaper.ImGui_IsMouseDown(UI.ctx, 2) then -- Middle click drag
        local dx, dy = reaper.ImGui_GetMouseDelta(UI.ctx)
        if dx ~= 0 then
          local delta = (dx / W) * view_len
          view_start = view_start - delta
          if view_start < 0 then view_start = 0 end
          if view_start + view_len > 1.0 then view_start = 1.0 - view_len end
          UI.view_start_frac = view_start
        end
      end
    end

    local vis_t0 = cache.item_pos + view_start * cache.item_len
    local vis_len = view_len * cache.item_len
    local vis_t1 = vis_t0 + vis_len

    local mid = wave_top + wave_h / 2
    local n = #cache.amp

    local stride = math.max(1, math.floor(n / W))

    for i = 1, n, stride do
      local t = cache.time[i]
      if t >= vis_t0 and t <= vis_t1 then
        local x = x0 + ((t - vis_t0) / vis_len) * W
        if x >= x0 and x <= x0 + W then
          local a = cache.amp[i]
          if a > 1.0 then a = 1.0 end
          local y = a * (wave_h * wave_scale * 0.5) 
          reaper.ImGui_DrawList_AddLine(dl, x, mid - y, x, mid + y, 0xBFC7CDAA, 1.0)
        end
      end
    end

    local seg_col = SEGMENT_COLORS[hunter and hunter.name or ""] or 0xEF444455
    local label_bg = LABEL_COLORS[hunter and hunter.name or ""] or 0xF7FAFCFF

    local label = hunter and hunter.name or ""
    if label ~= "" then
      local tw, th = reaper.ImGui_CalcTextSize(UI.ctx, label)
      local pad_x = 6
      local pad_y = 3
      local bx1 = x0 + 8
      local by1 = y0 + 6
      local bx2 = bx1 + tw + pad_x * 2
      local by2 = by1 + th + pad_y * 2
      reaper.ImGui_DrawList_AddRectFilled(dl, bx1, by1, bx2, by2, label_bg, 4.0)
      reaper.ImGui_DrawList_AddText(dl, bx1 + pad_x, by1 + pad_y, 0x000000FF, label)
    end

    local handle_size = 12
    local handle_margin = 2
    cache.drag_seg_vol_index = cache.drag_seg_vol_index or nil
    cache.drag_seg_edge_index = cache.drag_seg_edge_index or nil
    cache.drag_seg_edge_side = cache.drag_seg_edge_side or 0
    cache.create_drag_active = cache.create_drag_active or false
    cache.create_drag_start_t = cache.create_drag_start_t or nil
    cache.right_click_consumed = false
    local hop_sec_cache = (cache.time and cache.time[2] and cache.time[1]) and (cache.time[2] - cache.time[1]) or ((UI.config.hop_ms or 10) / 1000)
    if hop_sec_cache <= 0 then hop_sec_cache = (UI.config.hop_ms or 10) / 1000 end

    for i = 1, #cache.segments do
      local s = cache.segments[i]
      local t_s = cache.time[s.start_idx]
      local t_e = cache.time[s.end_idx] + hop_sec_cache
      local is_plosive_seg = (hunter and hunter.name == "Plosive Hunter") and (s.points and #s.points > 0)

      local x1 = x0 + ((math.max(t_s, vis_t0) - vis_t0) / vis_len) * W
      local x2 = x0 + ((math.min(t_e, vis_t1) - vis_t0) / vis_len) * W

      if x2 > x1 and x2 >= x0 and x1 <= x0 + W then
        x1 = math.max(x0, x1)
        x2 = math.min(x0 + W, x2)
        if x2 < x1 + 1.0 then x2 = x1 + 1.0 end
        reaper.ImGui_DrawList_AddRectFilled(dl, x1, wave_top, x2, wave_top + wave_h, seg_col)
        local seg_line_col = (seg_col & 0xFFFFFF00) | 0xFF
        reaper.ImGui_DrawList_AddLine(dl, x1, wave_top, x1, wave_top + wave_h, seg_line_col, 1.0)
        reaper.ImGui_DrawList_AddLine(dl, x2, wave_top, x2, wave_top + wave_h, seg_line_col, 1.0)

        local h_x1 = x1 + handle_margin
        local h_y1 = wave_top + wave_h - handle_size - handle_margin
        local h_x2 = h_x1 + handle_size
        local h_y2 = h_y1 + handle_size

        local is_handle_hovered = hovered and mx >= h_x1 and mx <= h_x2 and my >= h_y1 and my <= h_y2

        if is_handle_hovered then
          if reaper.ImGui_IsMouseClicked(UI.ctx, 0) then
            cache.drag_seg_vol_index = i
            cache.drag_vol_start_y = my
            cache.drag_vol_start_val = (is_plosive_seg and (s.hpf_strength or (UI.config.reduction_db or 6.0))) or (s.gain_db or (UI.config.reduction_db or 6.0))
          end
          if reaper.ImGui_IsMouseClicked(UI.ctx, 1) then
            table.remove(cache.segments, i)
            cache.right_click_consumed = true
            if cache.drag_seg_vol_index and cache.drag_seg_vol_index >= i then
              cache.drag_seg_vol_index = nil
              cache.drag_vol_start_y = nil
              cache.drag_vol_start_val = nil
            end
            if cache.drag_seg_edge_index and cache.drag_seg_edge_index >= i then
              cache.drag_seg_edge_index = nil
              cache.drag_seg_edge_side = 0
            end
            apply_live_edit()
            break
          end
        end

        local is_dragging = cache.drag_seg_vol_index == i

        if is_dragging then
          if reaper.ImGui_IsMouseDown(UI.ctx, 0) then
            local dy = cache.drag_vol_start_y - my
            local delta_db = dy / 5.0
            local new_db = cache.drag_vol_start_val + delta_db
            if new_db < 0 then new_db = 0 end
            if new_db > 24 then new_db = 24 end
            if is_plosive_seg then
              s.hpf_strength = new_db
            else
              s.gain_db = new_db
            end
          else
            cache.drag_seg_vol_index = nil
            cache.drag_vol_start_y = nil
            cache.drag_vol_start_val = nil
            apply_live_edit() 
          end
        end

        local handle_col = (is_handle_hovered or is_dragging) and 0xFFFFFFFF or 0xBFC7CDAA
        reaper.ImGui_DrawList_AddRectFilled(dl, h_x1, h_y1, h_x2, h_y2, handle_col, 2.0)

        local shown = is_plosive_seg and s.hpf_strength or s.gain_db
        if shown then
          local txt = string.format('%.1f', shown)
          reaper.ImGui_DrawList_AddText(dl, h_x1, h_y1 - 14, 0xFFFFFFCC, txt)
        end

        if hovered and my >= wave_top and my <= wave_top + wave_h then
          if not cache.drag_seg_vol_index then
            if cache.drag_seg_edge_index == nil or cache.drag_seg_edge_index < 0 then
              cache.drag_seg_edge_index = -1
              cache.drag_seg_edge_side = 0
            end
            if cache.drag_seg_edge_index < 0 and cache.drag_seg_edge_side == 0 then
              if ctrl_down then
                if math.abs(mx - x1) <= 6 then
                  reaper.ImGui_SetMouseCursor(UI.ctx, reaper.ImGui_MouseCursor_ResizeEW())
                  if reaper.ImGui_IsMouseDown(UI.ctx, 0) then
                    cache.drag_seg_edge_index = i
                    cache.drag_seg_edge_side = 1
                    cache.drag_edge_orig_start_idx = s.start_idx
                    cache.drag_edge_orig_end_idx = s.end_idx
                  end
                elseif math.abs(mx - x2) <= 6 then
                  reaper.ImGui_SetMouseCursor(UI.ctx, reaper.ImGui_MouseCursor_ResizeEW())
                  if reaper.ImGui_IsMouseDown(UI.ctx, 0) then
                    cache.drag_seg_edge_index = i
                    cache.drag_seg_edge_side = 2
                    cache.drag_edge_orig_start_idx = s.start_idx
                    cache.drag_edge_orig_end_idx = s.end_idx
                  end
                end
              end
            end
          end
        end

        if cache.drag_seg_edge_index == i and cache.drag_seg_edge_side ~= 0 then
          reaper.ImGui_SetMouseCursor(UI.ctx, reaper.ImGui_MouseCursor_ResizeEW())
            local rel = (mx - x0) / W
              if rel < 0 then rel = 0 elseif rel > 1 then rel = 1 end
              local new_t = vis_t0 + rel * vis_len
              if hop_sec_cache > 0 then
                local rel_pos = (new_t - cache.item_pos) / hop_sec_cache
                local snapped = math.floor(rel_pos + 0.5) * hop_sec_cache + cache.item_pos
                new_t = snapped
              end
              local idx = 1
              if hop_sec_cache > 0 then
                local approx = math.floor((new_t - cache.item_pos) / hop_sec_cache + 0.5) + 1
                if approx < 1 then approx = 1 end
                if approx > #cache.time then approx = #cache.time end
                idx = approx
              end
              if cache.drag_seg_edge_side == 1 then
                s.start_idx = math.min(idx, s.end_idx - 1)
              else
                s.end_idx = math.max(idx, s.start_idx + 1)
              end
              if not reaper.ImGui_IsMouseDown(UI.ctx, 0) then
                if (hunter and hunter.name == "Plosive Hunter") and (s.points and #s.points > 0) and cache.drag_edge_orig_start_idx and cache.time then
                  local t_old = cache.time[cache.drag_edge_orig_start_idx]
                  local t_new = cache.time[s.start_idx]
                  local t_end = cache.time[s.end_idx] + hop_sec_cache
                  if t_old and t_new and t_end and t_end > t_new then
                    local new_points = {}
                    for p = 1, #s.points do
                      local pt = s.points[p]
                      local abs_t = t_old + (pt.offset_sec or 0.0)
                      local off = abs_t - t_new
                      if off >= 0 and off <= (t_end - t_new) then
                        new_points[#new_points + 1] = { offset_sec = off, val = pt.val }
                      end
                    end
                    s.points = new_points
                  end
                end
                cache.drag_seg_edge_index = nil
                cache.drag_seg_edge_side = 0
                cache.drag_edge_orig_start_idx = nil
                cache.drag_edge_orig_end_idx = nil
                apply_live_edit() 
              end
            end
      end
    end

    local play_state = reaper.GetPlayState()
    if play_state & 1 == 1 then
      local play_pos = reaper.GetPlayPosition()
      if play_pos >= vis_t0 and play_pos <= vis_t1 then
        local x_p = x0 + ((play_pos - vis_t0) / vis_len) * W
        reaper.ImGui_DrawList_AddLine(dl, x_p, wave_top, x_p, wave_top + wave_h, 0xFFFF00FF, 1.5)
      end
    end
    local edit_pos = reaper.GetCursorPosition()
    if edit_pos >= vis_t0 and edit_pos <= vis_t1 then
      local x_e = x0 + ((edit_pos - vis_t0) / vis_len) * W
      reaper.ImGui_DrawList_AddLine(dl, x_e, wave_top, x_e, wave_top + wave_h, 0xFFD700FF, 1.5)
    end

    if hovered and my >= wave_top and my <= wave_top + wave_h then
      if not cache.right_click_consumed then
        if not cache.create_drag_active and reaper.ImGui_IsMouseClicked(UI.ctx, 1) then
          if ctrl_down then
            local cursor_frac = (mx - x0) / W
            if cursor_frac < 0 then cursor_frac = 0 elseif cursor_frac > 1 then cursor_frac = 1 end
            local t_start = vis_t0 + cursor_frac * vis_len
            cache.create_drag_active = true
            cache.create_drag_start_t = t_start
          end
        end
        if cache.create_drag_active and reaper.ImGui_IsMouseReleased(UI.ctx, 1) then
          local cursor_frac = (mx - x0) / W
          if cursor_frac < 0 then cursor_frac = 0 elseif cursor_frac > 1 then cursor_frac = 1 end
          local t_end = vis_t0 + cursor_frac * vis_len
          local t1 = math.min(cache.create_drag_start_t or t_end, t_end)
          local t2 = math.max(cache.create_drag_start_t or t_end, t_end)
          local min_len_sec = ((UI.config.min_seg_ms or 15) / 1000)
          if (t2 - t1) >= min_len_sec and hop_sec_cache > 0 then
            local function time_to_index(t)
              local rel_pos = (t - cache.item_pos) / hop_sec_cache
              local approx = math.floor(rel_pos + 0.5) + 1
              if approx < 1 then approx = 1 end
              if approx > #cache.time then approx = #cache.time end
              return approx
            end
            local start_idx = time_to_index(t1)
            local end_idx = time_to_index(t2)
            if end_idx > start_idx then
              local seg
              if hunter and hunter.name == "Plosive Hunter" then
                local dur = (end_idx - start_idx) * hop_sec_cache
                if dur < 0 then dur = 0 end
                seg = {
                  start_idx = start_idx,
                  end_idx = end_idx,
                  hpf_strength = UI.config.reduction_db or 6.0,
                  points = {
                    { offset_sec = 0.0, val = 80.0 },
                    { offset_sec = dur, val = 80.0 }
                  }
                }
              else
                seg = {
                  start_idx = start_idx,
                  end_idx = end_idx,
                  gain_db = UI.config.reduction_db or 6.0
                }
              end
              table.insert(cache.segments, seg)
              apply_live_edit() 
            end
          end
          cache.create_drag_active = false
          cache.create_drag_start_t = nil
        end
      end
    end

    if hovered and reaper.ImGui_IsMouseDown(UI.ctx, 0) then
      local is_drag_action = (cache.drag_seg_vol_index ~= nil) or
          (cache.drag_seg_edge_index ~= nil and cache.drag_seg_edge_side ~= 0)
      if not is_drag_action then
        local cursor_frac = (mx - x0) / W
        if cursor_frac < 0 then cursor_frac = 0 elseif cursor_frac > 1 then cursor_frac = 1 end
        local seek_pos = vis_t0 + cursor_frac * vis_len
        reaper.SetEditCurPos(seek_pos, true, false)
      end
    end
  else
    if not UI.analysis_ctx then
      local txt = "No Analysis Data. Select an item and click 'Analyze'."
      local tw, th = reaper.ImGui_CalcTextSize(UI.ctx, txt)
      local tx = x0 + (W - tw) * 0.5
      local ty = y0 + (H - th) * 0.5
      reaper.ImGui_DrawList_AddText(dl, tx, ty, 0xF7FAFCFF, txt)
    end
  end

  reaper.ImGui_SetCursorPos(UI.ctx, cx, cy + H + 4)
  reaper.ImGui_TextDisabled(UI.ctx, "Controls: Wheel = Zoom, Ctrl+Wheel = Scroll, Ctrl+Right Drag = Add Segment Left Click = Remove Segment Edges = Resize")
end

apply_reduction = function()
  local cache, _, item_res = get_active_cache_for_selected_item()
  if not item_res then
      item_res = reaper.GetSelectedMediaItem(0, 0)
  end
  
  if not item_res then 
      reaper.ShowMessageBox("No item selected.", "Error", 0)
      return 
  end

  if not cache or not cache.segments then
    scan_item()
    return
  end

  local guid = cache.item_guid
  local gain_segments_to_apply = {}
  local hpf_segments_to_apply = {}
  
  for i, h in ipairs(UI.hunters) do
      local c = Cache.get(guid, h.name)
      if c and c.segments and #c.segments > 0 then
          local hop_sec = (c.time and c.time[2] and c.time[1]) and (c.time[2] - c.time[1]) or ((UI.config.hop_ms or 10) / 1000)
          if hop_sec <= 0 then hop_sec = (UI.config.hop_ms or 10) / 1000 end
          for _, seg in ipairs(c.segments) do
             local t1 = c.time[seg.start_idx]
             local t2 = c.time[seg.end_idx]
             if t1 and t2 then
                 local t_end_real = t2 + hop_sec
                 
                 local db = seg.gain_db or 6.0
                 if seg.points and #seg.points > 0 then
                     table.insert(hpf_segments_to_apply, {
                         start_time = t1,
                         end_time = t_end_real,
                         points = seg.points,
                         hpf_strength = seg.hpf_strength,
                         hunter_name = h.name
                     })
                 else
                     table.insert(gain_segments_to_apply, {
                         start_time = t1,
                         end_time = t_end_real,
                         reduction_db = db,
                         gain_db = db,
                         hunter_name = h.name
                     })
                 end
             end
          end
      end
  end
  
  local resolved_gain = Engine.resolve_overlaps(gain_segments_to_apply)
  local resolved_segments = {}
  for _, seg in ipairs(resolved_gain) do
      resolved_segments[#resolved_segments + 1] = seg
  end
  for _, seg in ipairs(hpf_segments_to_apply) do
      resolved_segments[#resolved_segments + 1] = seg
  end

  UI.config.hunter_type = "Unified"
  
  reaper.Undo_BeginBlock()
  
  local env_gain, env_hpf
  if UI.config.use_take_fx then
    local take = reaper.GetActiveTake(item_res)
    if take then 
      env_gain = Engine.ensure_take_envelope(take, 0) 
      env_hpf = Engine.ensure_take_envelope(take, 1) 
    end
  else
    local track = reaper.GetMediaItem_Track(item_res)
    if track then 
      env_gain = Engine.ensure_track_envelope(track, 0) 
      env_hpf = Engine.ensure_track_envelope(track, 1) 
    end
  end

  if env_gain then
    local item_pos = reaper.GetMediaItemInfo_Value(item_res, "D_POSITION")
    local item_len = reaper.GetMediaItemInfo_Value(item_res, "D_LENGTH")
    local pre = (UI.config.pre_ramp_ms or 10) / 1000
    local post = (UI.config.post_ramp_ms or 20) / 1000
    
    if UI.config.use_take_fx then
      local play_rate = reaper.GetMediaItemTakeInfo_Value(reaper.GetActiveTake(item_res), "D_PLAYRATE")
      reaper.DeleteEnvelopePointRange(env_gain, 0, item_len * play_rate + 1.0)
      if env_hpf then reaper.DeleteEnvelopePointRange(env_hpf, 0, item_len * play_rate + 1.0) end
    else
      reaper.DeleteEnvelopePointRange(env_gain, math.max(0, item_pos - pre), item_pos + item_len + post)
      if env_hpf then reaper.DeleteEnvelopePointRange(env_hpf, math.max(0, item_pos - pre), item_pos + item_len + post) end
    end
    reaper.Envelope_SortPoints(env_gain)
    if env_hpf then reaper.Envelope_SortPoints(env_hpf) end
  end

  Engine.apply_reduction(item_res, resolved_segments, UI.config)
  reaper.Undo_EndBlock("Floop Hunter: Applied Unified Reduction", -1)

  reaper.UpdateArrange()
end

UI.open_help_requested = false
UI.show_help_modal = false

-- Modal Help Guide
local function DrawHelpModal()
    if UI.open_help_requested then
        reaper.ImGui_OpenPopup(UI.ctx, "Help Guide")
        UI.open_help_requested = false
        UI.show_help_modal = true
    end

    if UI.show_help_modal then
        local ctx = UI.ctx
        local modalW, modalH = 700, 860
        reaper.ImGui_SetNextWindowSize(ctx, modalW, modalH, reaper.ImGui_Cond_Always())

        local winX, winY = reaper.ImGui_GetWindowPos(ctx)
        local winW, winH = reaper.ImGui_GetWindowSize(ctx)
        if winX and winY and winW and winH then
            local posX = winX + (winW - modalW) * 0.5
            local posY = winY + (winH - modalH) * 0.5
            reaper.ImGui_SetNextWindowPos(ctx, posX, posY, reaper.ImGui_Cond_Appearing())
        else
            local center = { reaper.ImGui_Viewport_GetCenter(reaper.ImGui_GetMainViewport(ctx)) }
            reaper.ImGui_SetNextWindowPos(ctx, center[1], center[2], reaper.ImGui_Cond_Appearing(), 0.5, 0.5)
        end

        local flags = reaper.ImGui_WindowFlags_NoResize() | reaper.ImGui_WindowFlags_NoMove() |
            reaper.ImGui_WindowFlags_NoScrollbar()
        if reaper.ImGui_BeginPopupModal(ctx, 'Help Guide', true, flags) then
            reaper.ImGui_Text(ctx, 'Floop Hunter Framework - User Guide')
            reaper.ImGui_Separator(ctx)
            reaper.ImGui_Spacing(ctx)

            if reaper.ImGui_BeginChild(ctx, "HelpContent", 0, -40) then
                reaper.ImGui_Text(ctx, 'WHAT THIS SCRIPT DOES')
                reaper.ImGui_TextWrapped(ctx,
                    'This script listens to the selected vocal track, detects sibilants, plosives, and breath events, and writes volume automation to reduce them. It works in conjunction with a companion JSFX plugin. You can run one, two, or all three detection modules at the same time to clean up a performance.')
                reaper.ImGui_Spacing(ctx)
                reaper.ImGui_Separator(ctx)
                reaper.ImGui_Spacing(ctx)

                reaper.ImGui_Text(ctx, 'VOCAL PROFILES')
                reaper.ImGui_TextWrapped(ctx,
                    'Before running an analysis, you must select the correct vocal profile (Female, Male, Spoken, or Rap). This choice directly affects the detection sensitivity and internal thresholds to match the frequency content of the voice. Choose the closest match even if the source is not a perfect fit.')
                reaper.ImGui_Spacing(ctx)
                reaper.ImGui_Separator(ctx)
                reaper.ImGui_Spacing(ctx)

                reaper.ImGui_Text(ctx, 'THE THREE MODULES')
                reaper.ImGui_BulletText(ctx, 'Ess Hunter: Targets sibilance (harsh "S" sounds). Best used on bright or close-mic\'d vocals. Note that sensitivity may need adjustment for voices with natural lisps or heavy presence boost.')
                reaper.ImGui_BulletText(ctx, 'Plosive Hunter: Targets low-frequency transient bursts ("P" or "B" pops). Particularly useful on dynamic mics or when no pop filter was used during recording.')
                reaper.ImGui_BulletText(ctx, 'Breath Hunter: Targets inhale and exhale events. Note that very quiet breaths may be missed, while very loud breaths in otherwise quiet passages may be caught more aggressively.')
                reaper.ImGui_TextWrapped(ctx, 'You can enable and run any combination of these three hunters.')
                reaper.ImGui_Spacing(ctx)
                reaper.ImGui_Separator(ctx)
                reaper.ImGui_Spacing(ctx)

                reaper.ImGui_Text(ctx, 'ROUTING & SHAPES')
                reaper.ImGui_TextWrapped(ctx,
                    'The framework applies its volume reduction non-destructively via a dedicated JSFX plugin ("Floop Hunter.jsfx"). You can choose to install this plugin and its automation envelope either on the Track FX chain or directly on the Take FX. You can also select the interpolation shape of the envelope points (Linear, Bezier, Slow Start/End, etc.).')
                reaper.ImGui_Spacing(ctx)
                reaper.ImGui_Separator(ctx)
                reaper.ImGui_Spacing(ctx)

                reaper.ImGui_Text(ctx, 'HOW RESULTS ARE COMBINED')
                reaper.ImGui_TextWrapped(ctx,
                    'If multiple modules want to write automation at the exact same point in time (for example, if a breath overlaps with a plosive), the script compares the required volume reductions and keeps only the stronger one. This prevents double-automation and keeps your envelope clean and unified.')
                reaper.ImGui_Spacing(ctx)
                reaper.ImGui_Separator(ctx)
                reaper.ImGui_Spacing(ctx)

                reaper.ImGui_Text(ctx, 'LIVE EDIT & AUTO SCAN')
                reaper.ImGui_TextWrapped(ctx,
                    'To speed up your workflow, enable "Auto Scan": whenever you select a new item, the script will instantly analyze it using your current settings. By enabling "Live Edit", any adjustment you make to the sliders will instantly rewrite the automation envelope in the timeline, allowing you to fine-tune the reduction depth or detection thresholds by ear.')
                reaper.ImGui_Spacing(ctx)
                reaper.ImGui_Separator(ctx)
                reaper.ImGui_Spacing(ctx)
                
                reaper.ImGui_Text(ctx, 'VISUALIZER OPERATIONS')
                reaper.ImGui_TextWrapped(ctx, 'The waveform visualizer is fully interactive and allows you to manually correct the detections:')
                reaper.ImGui_BulletText(ctx, 'Zoom / Pan: Use Mousewheel to zoom and Right-Click Drag to pan the waveform.')
                reaper.ImGui_BulletText(ctx, 'Adjust Gain: Click and drag vertically on a segment to change its specific reduction (dB).')
                reaper.ImGui_BulletText(ctx, 'Resize Segments: Hold CTRL and click the edges of a segment to drag and resize it.')
                reaper.ImGui_BulletText(ctx, 'Delete False Positives: Right-click directly on a segment to delete it.')
                reaper.ImGui_BulletText(ctx, 'Add New Segments: Hold CTRL and Right-Click Drag over an area to create a custom reduction segment manually.')
                reaper.ImGui_BulletText(ctx, 'Seek: Left-click anywhere on the empty waveform to move REAPER\'s edit cursor.')
                reaper.ImGui_Spacing(ctx)
                reaper.ImGui_Separator(ctx)
                reaper.ImGui_Spacing(ctx)

                reaper.ImGui_Text(ctx, 'WORKFLOW RECOMMENDATION')
                reaper.ImGui_TextWrapped(ctx, '1. Select the vocal item or track in REAPER\n2. Choose the correct vocal profile\n3. Enable the hunters you need\n4. Select your routing (Take FX vs Track FX)\n5. Run the analysis and "Apply Unified"\n6. Use the Visualizer and Live Edit to fine-tune')
                reaper.ImGui_Spacing(ctx)
                reaper.ImGui_Text(ctx, 'IMPORTANT: Always listen back carefully. Do not rely blindly on the visual detection.')
                reaper.ImGui_Spacing(ctx)
                reaper.ImGui_Separator(ctx)
                reaper.ImGui_Spacing(ctx)
                
                reaper.ImGui_Text(ctx, 'THE PHILOSOPHY')
                reaper.ImGui_TextWrapped(ctx,
                    'This script is designed as a workflow accelerator and an interactive editor, not a magical 100% accurate one-click solution. Automated detection is never perfect. Its purpose is to rapidly find artifact candidates and provide you with a visual editor to quickly confirm, delete, or adjust the automation, saving you hours of tedious manual clicking and zooming. False positives and false negatives are inevitable, especially on unusual or heavily processed vocals. Treat the script\'s output as a highly advanced starting point. It does the heavy lifting, but your ears remain the final judge. Always review the automation before committing to a mix.')
                reaper.ImGui_Spacing(ctx)
                reaper.ImGui_Separator(ctx)
                reaper.ImGui_Spacing(ctx)
                
                reaper.ImGui_Text(ctx, 'SUPPORT')
                reaper.ImGui_TextWrapped(ctx, 'If this script saves you time, a coffee is always appreciated.')
                reaper.ImGui_Spacing(ctx)
                if reaper.ImGui_Button(ctx, "Support Floop's Reaper Scripts on Ko-fi") then
                    local os_name = reaper.GetOS()
                    if os_name:match("Win") then
                        os.execute('start "" "https://ko-fi.com/floopsreaperscripts"')
                    elseif os_name:match("OSX") or os_name:match("macOS") then
                        os.execute('open "https://ko-fi.com/floopsreaperscripts"')
                    else
                        os.execute('xdg-open "https://ko-fi.com/floopsreaperscripts"')
                    end
                end

                reaper.ImGui_EndChild(ctx)
            end

            reaper.ImGui_Separator(ctx)
            reaper.ImGui_Spacing(ctx)

            local btn_w = 120
            reaper.ImGui_SetCursorPosX(ctx, (modalW - btn_w) * 0.5)
            if reaper.ImGui_Button(ctx, 'Close', btn_w) then
                UI.show_help_modal = false
                reaper.ImGui_CloseCurrentPopup(ctx)
            end

            reaper.ImGui_EndPopup(ctx)
        else
            UI.show_help_modal = false
        end
    end
end

-- Preset System 
local EXT_NS = 'FloopHunter'

local function serialize_preset_values(hunter, config)
  local parts = {}
  local keys = {}
  if hunter and hunter.default_config then
    for k, _ in pairs(hunter.default_config) do
      if k ~= "source_profile" then
        keys[#keys + 1] = k
      end
    end
  end
  keys[#keys + 1] = "use_take_fx"
  keys[#keys + 1] = "live_edit"
  table.sort(keys)

  for i = 1, #keys do
    local k = keys[i]
    local v = config[k]
    if v ~= nil then
      parts[#parts + 1] = k .. '=' .. tostring(v)
    end
  end
  return table.concat(parts, ';')
end

local function deserialize_preset_values(str)
  local v = {}
  for token in string.gmatch(str or '', '[^;]+') do
    local k, val = token:match('([^=]+)=(.*)')
    if k then
      local num = tonumber(val)
      if num then
        v[k] = num
      elseif val == "true" then
        v[k] = true
      elseif val == "false" then
        v[k] = false
      else
        v[k] = val
      end
    end
  end
  return v
end

local function list_custom_presets(hunter_name)
  local ok, s = reaper.GetProjExtState(0, EXT_NS, 'custom_presets_' .. tostring(hunter_name))
  local names = {}
  if ok > 0 and s and s ~= '' then
    for name in s:gmatch('[^;]+') do names[#names + 1] = name end
  end
  return names
end

local function save_custom_preset(hunter, name, config)
  local ser = serialize_preset_values(hunter, config)
  reaper.SetProjExtState(0, EXT_NS, 'preset_' .. tostring(hunter.name) .. ':' .. name, ser)
  local names = list_custom_presets(hunter.name)
  local exists = false
  for i = 1, #names do
    if names[i] == name then
      exists = true; break
    end
  end
  if not exists then
    names[#names + 1] = name
    reaper.SetProjExtState(0, EXT_NS, 'custom_presets_' .. tostring(hunter.name), table.concat(names, ';'))
  end
end

local function load_custom_preset(hunter, name)
  local ok, ser = reaper.GetProjExtState(0, EXT_NS, 'preset_' .. tostring(hunter.name) .. ':' .. name)
  if ok == 0 or not ser or ser == '' then return false end
  local loaded_config = deserialize_preset_values(ser)

  UI.config = {}
  for k, v in pairs(hunter.default_config) do UI.config[k] = v end
  for k, v in pairs(loaded_config) do UI.config[k] = v end
  return true
end

local function delete_custom_preset(hunter, name)
  reaper.SetProjExtState(0, EXT_NS, 'preset_' .. tostring(hunter.name) .. ':' .. name, '')
  local names = list_custom_presets(hunter.name)
  local kept = {}
  for i = 1, #names do if names[i] ~= name then kept[#kept + 1] = names[i] end end
  reaper.SetProjExtState(0, EXT_NS, 'custom_presets_' .. tostring(hunter.name), table.concat(kept, ';'))
end

local function reset_envelopes()
  local hunter = UI.hunters[UI.active_hunter_idx]
  local item = reaper.GetSelectedMediaItem(0, 0)
  if not item then return end

  local pre = (UI.config.pre_ramp_ms or 10) / 1000
  local post = (UI.config.post_ramp_ms or 20) / 1000
  local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  local item_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
  local t_start = math.max(0, item_pos - pre)
  local t_end = item_pos + item_len + post

  local env_hunter, env_unified_gain, env_unified_hpf
  if UI.config.use_take_fx then
    local take = reaper.GetActiveTake(item)
    if take then 
      env_unified_gain = Engine.ensure_take_envelope(take, 0)
      env_unified_hpf = Engine.ensure_take_envelope(take, 1)
    end
  else
    local track = reaper.GetMediaItem_Track(item)
    if track then 
      env_unified_gain = Engine.ensure_track_envelope(track, 0)
      env_unified_hpf = Engine.ensure_track_envelope(track, 1)
    end
  end

  reaper.Undo_BeginBlock()
  if env_unified_gain then
    reaper.DeleteEnvelopePointRange(env_unified_gain, t_start, t_end)
    reaper.Envelope_SortPoints(env_unified_gain)
  end
  if env_unified_hpf then
    reaper.DeleteEnvelopePointRange(env_unified_hpf, t_start, t_end)
    reaper.Envelope_SortPoints(env_unified_hpf)
  end
  reaper.Undo_EndBlock("Floop Hunter Reset Envelopes: " .. hunter.name, -1)
  reaper.UpdateArrange()
end

function UI.draw()
  local open = true

  -- Run Async Analysis if active
  if UI.analysis_ctx then
    local done = UI.analysis_ctx:run_chunk(15)
    if done then
      local hunter = UI.analysis_ctx.hunter
      local features = UI.analysis_ctx.features_arrays
      local time_map = UI.analysis_ctx.time_map
      local guid = UI.analysis_ctx.guid
      local params_hash = UI.analysis_ctx.params_hash
      local item_pos = UI.analysis_ctx.item_pos
      local item_len = UI.analysis_ctx.item_len
      local file_id = get_take_file_id(UI.analysis_ctx.take)

  if hunter.name == "Plosive Hunter" then
      -- Visual-only mapping for the waveform: Plosive uses diff_db instead of ratio.
      if features.diff_db then
          local norm_ratios = {}
          for i=1, #features.diff_db do
              norm_ratios[i] = math.max(0, features.diff_db[i]) / 24.0
          end
          features.ratio = norm_ratios
      end
  end

  local cache_entry = {
    features = features,
    time = time_map,
    params_hash = params_hash,
    item_pos = item_pos,
    item_len = item_len,
    item_guid = guid,
    file_id = file_id,
    amp = {}
  }
      -- Pre-calculate amp for visualizer
      local levels = features.level
      if levels then
        for i = 1, #levels do
          local lvl = levels[i]
          local amp = 0.0
          if lvl then amp = 10 ^ (lvl / 20) end
          cache_entry.amp[i] = amp
        end
      end

      -- Store in Cache
      Cache.set(guid, hunter.name, cache_entry)

      -- Run Detection
      re_detect(cache_entry, hunter)

      UI.analysis_ctx = nil
    end
  end

  local colors_pushed = apply_theme()
  if LAYOUT_DEBUG then
    layout_debug = {}
  end

  reaper.ImGui_SetNextWindowSizeConstraints(UI.ctx, 620, 850, 4000, 4000)
  reaper.ImGui_SetNextWindowSize(UI.ctx, 750, 850, reaper.ImGui_Cond_FirstUseEver())

  -- Main window
  local visible, open_ref = reaper.ImGui_Begin(UI.ctx, 'Floop Hunter Framework', true, reaper.ImGui_WindowFlags_NoCollapse())
  
  if visible then
    local ctx = UI.ctx
    local function set_active_hunter(i, hunter)
      if UI.active_hunter_idx ~= i then
        UI.active_hunter_idx = i
        UI.config = {}
        for k, v in pairs(hunter.default_config) do UI.config[k] = v end
      end
    end

    -- Load profile from Cache or default to 0 for current item
    local current_guid = "unknown"
    local item = reaper.GetSelectedMediaItem(0, 0)
    if item then
      _, current_guid = reaper.GetSetMediaItemInfo_String(item, "GUID", "", false)
    end
    UI.config.source_profile = Cache.get_profile(current_guid) or 0

    if reaper.ImGui_IsWindowFocused(ctx) and reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Space()) then
      reaper.Main_OnCommand(40044, 0)
    end

    for i, h in ipairs(UI.hunters) do
      if UI.active_hunter_idx == i then
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x0F766EFF)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x115E59FF)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), 0x134E4AFF)
      end
      
      local clicked = reaper.ImGui_Button(ctx, h.name)
      
      if UI.active_hunter_idx == i then
        reaper.ImGui_PopStyleColor(ctx, 3)
      end

      if clicked then
        set_active_hunter(i, h)
        UI.selected_presets = UI.selected_presets or {}
        UI.selected_preset_name = UI.selected_presets[h.name] or "Default"
      end
      if i < #UI.hunters then
        reaper.ImGui_SameLine(ctx)
      end
    end

    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_Dummy(ctx, 18, 1)
    reaper.ImGui_SameLine(ctx)

    local source_profiles = { "Select Profile...", "Female Vocal", "Male Vocal", "Spoken Male", "Spoken Female", "Rap" }
    local sp_idx = (UI.config.source_profile or 0) + 1
    if sp_idx < 1 then sp_idx = 1 end
    if sp_idx > #source_profiles then sp_idx = 1 end
    local sp_preview = source_profiles[sp_idx]
    local tw_sp, _ = reaper.ImGui_CalcTextSize(ctx, sp_preview)
    local w_sp = math.max(120, math.min(tw_sp + 24, 220))
    reaper.ImGui_SetNextItemWidth(ctx, w_sp)
    if reaper.ImGui_BeginCombo(ctx, "##SourceProfileTop", sp_preview) then
      for i = 1, #source_profiles do
        local name = source_profiles[i]
        local profile_id = i - 1
        if reaper.ImGui_Selectable(ctx, name, (UI.config.source_profile or 0) == profile_id) then
          UI.config.source_profile = profile_id
          Cache.set_profile(current_guid, profile_id)
          
          if UI.auto_rescan and profile_id > 0 then trigger_scan_or_detect() end
        end
      end
      reaper.ImGui_EndCombo(ctx)
    end

    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "Clear Cache") then
      Cache.clear()
    end

    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_Dummy(ctx, 14, 1)
    reaper.ImGui_SameLine(ctx)

    local active_hunter = UI.hunters[UI.active_hunter_idx]
    UI.selected_presets = UI.selected_presets or {}
    UI.selected_preset_name = UI.selected_preset_name or UI.selected_presets[active_hunter.name] or "Default"

    if active_hunter and active_hunter.name == "Plosive Hunter" then
      local profile_id = UI.config.source_profile or 0
      if profile_id > 0 and active_hunter.Profiles and active_hunter.Profiles[profile_id] then
        if UI._plosive_profile_applied_id ~= profile_id then
          local p = active_hunter.Profiles[profile_id]
          UI.config.low_pass = p.low_pass
          UI.config.min_low_db = p.min_low_db
          UI.config.transient_thresh = p.transient_thresh
          UI.config.delay_ms = p.delay_ms
          UI._plosive_profile_applied_id = profile_id
        end
      else
        UI._plosive_profile_applied_id = 0
      end
    end

    local preset_label = "Preset"
    local tw_p, _ = reaper.ImGui_CalcTextSize(ctx, preset_label)
    local w_p = math.max(140, math.min(tw_p + 44, 220))
    reaper.ImGui_SetNextItemWidth(ctx, w_p)
    if reaper.ImGui_BeginCombo(ctx, "##PresetCombo", preset_label) then
      reaper.ImGui_Text(ctx, "Preset")
      reaper.ImGui_Separator(ctx)

      if reaper.ImGui_Selectable(ctx, "Default", UI.selected_preset_name == "Default") then
        UI.selected_preset_name = "Default"
        UI.selected_presets[active_hunter.name] = "Default"
        UI.config = {}
        for k, v in pairs(active_hunter.default_config) do UI.config[k] = v end
      end

      local custom_names = list_custom_presets(active_hunter.name)
      reaper.ImGui_Separator(ctx)
      reaper.ImGui_Text(ctx, "User Presets")
      reaper.ImGui_Separator(ctx)

      local function truncate_to_width(text, max_w)
        local tw, _ = reaper.ImGui_CalcTextSize(ctx, text)
        if tw <= max_w then return text end
        local ell = "..."
        local ell_w, _ = reaper.ImGui_CalcTextSize(ctx, ell)
        for i = 1, #text do
          local sub = text:sub(1, i)
          local sw, _ = reaper.ImGui_CalcTextSize(ctx, sub)
          if sw + ell_w > max_w then
            local cut = math.max(1, i - 1)
            return text:sub(1, cut) .. ell
          end
        end
        return text
      end

      for i = 1, #custom_names do
        local cname = custom_names[i]
        local disp = truncate_to_width(cname, w_p - 32)
        if reaper.ImGui_Selectable(ctx, disp .. "##" .. cname, UI.selected_preset_name == cname) then
          UI.selected_preset_name = cname
          UI.selected_presets[active_hunter.name] = cname
          load_custom_preset(active_hunter, cname)
        end
      end
      reaper.ImGui_EndCombo(ctx)
    end

    reaper.ImGui_SameLine(ctx)
    local preset_btn_clicked = reaper.ImGui_Button(ctx, "💾")
    do
      local bmin_x, bmin_y = reaper.ImGui_GetItemRectMin(ctx)
      local bmax_x, bmax_y = reaper.ImGui_GetItemRectMax(ctx)
      UI._preset_button_rect = { min_x = bmin_x, min_y = bmin_y, max_x = bmax_x, max_y = bmax_y }
    end
    if preset_btn_clicked then
      reaper.ImGui_OpenPopup(ctx, "PresetMenu")
    end
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_PopupBg(), 0x1F2933FF)
    do
      local a = UI._preset_button_rect
      if a then
        local win_x, win_y = reaper.ImGui_GetWindowPos(ctx)
        local win_w, win_h = reaper.ImGui_GetWindowSize(ctx)
        local bound_x0 = win_x
        local bound_y0 = win_y
        local bound_x1 = win_x + win_w
        local bound_y1 = win_y + win_h
        if reaper.ImGui_GetWindowContentRegionMin and reaper.ImGui_GetWindowContentRegionMax then
          local crmin_x, crmin_y = reaper.ImGui_GetWindowContentRegionMin(ctx)
          local crmax_x, crmax_y = reaper.ImGui_GetWindowContentRegionMax(ctx)
          bound_x0 = win_x + crmin_x
          bound_y0 = win_y + crmin_y
          bound_x1 = win_x + crmax_x
          bound_y1 = win_y + crmax_y
        end
        local popup_w = 250
        local popup_h = 60
        local margin = 8
        local x = a.min_x
        local y = a.max_y + 2
        x = math.min(x, bound_x1 - popup_w - margin)
        x = math.max(x, bound_x0 + margin)
        if y + popup_h > bound_y1 - margin then
          y = a.min_y - popup_h - 2
        end
        y = math.max(y, bound_y0 + margin)
        reaper.ImGui_SetNextWindowPos(ctx, x, y, reaper.ImGui_Cond_Always())
        reaper.ImGui_SetNextWindowSize(ctx, popup_w, popup_h, reaper.ImGui_Cond_Always())
      end
    end
    if reaper.ImGui_BeginPopup(ctx, "PresetMenu") then
      UI.preset_name_buf = UI.preset_name_buf or ""
      reaper.ImGui_SetNextItemWidth(ctx, 140)
      local changed, new_buf = reaper.ImGui_InputText(ctx, "##name", UI.preset_name_buf)
      if changed then UI.preset_name_buf = new_buf end
      reaper.ImGui_SameLine(ctx)
      if reaper.ImGui_Button(ctx, "Save") and UI.preset_name_buf ~= "" then
        save_custom_preset(active_hunter, UI.preset_name_buf, UI.config)
        UI.selected_preset_name = UI.preset_name_buf
        UI.selected_presets[active_hunter.name] = UI.preset_name_buf
        reaper.ImGui_CloseCurrentPopup(ctx)
      end
      if UI.selected_preset_name ~= "Default" then
        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_Button(ctx, "Delete") then
          delete_custom_preset(active_hunter, UI.selected_preset_name)
          UI.selected_preset_name = "Default"
          UI.selected_presets[active_hunter.name] = "Default"
          UI.config = {}
          for k, v in pairs(active_hunter.default_config) do UI.config[k] = v end
          reaper.ImGui_CloseCurrentPopup(ctx)
        end
      end
      reaper.ImGui_EndPopup(ctx)
    end
    reaper.ImGui_PopStyleColor(ctx)
    
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "?") then
        UI.open_help_requested = true
    end

    reaper.ImGui_Separator(UI.ctx)

    -- Waveform Panel
    draw_waveform_panel()

    reaper.ImGui_Separator(UI.ctx)

    -- Main Controls
    local hunter = UI.hunters[UI.active_hunter_idx]

    local function Toggle(label, value)
      local ctx = UI.ctx
      local x, y = reaper.ImGui_GetCursorScreenPos(ctx)
      local dl = reaper.ImGui_GetWindowDrawList(ctx)

      local height = reaper.ImGui_GetFrameHeight(ctx) * 0.8
      local width = height * 1.8
      local radius = height * 0.5

      local clicked = reaper.ImGui_InvisibleButton(ctx, "##" .. label, width, height)
      local toggled = value
      if clicked then
        toggled = not toggled
      end

      local col_bg_off = 0x555555FF
      local col_bg_on  = 0x14B8A6FF
      local col_knob   = 0xFFFFFFFF

      local bg_col     = toggled and col_bg_on or col_bg_off
      reaper.ImGui_DrawList_AddRectFilled(dl, x, y, x + width, y + height, bg_col, radius)

      local t = toggled and 1.0 or 0.0
      local knob_x = x + radius + t * (width - radius * 2)
      reaper.ImGui_DrawList_AddCircleFilled(dl, knob_x, y + radius, radius * 0.8, col_knob)

      reaper.ImGui_SameLine(ctx)
      reaper.ImGui_Text(ctx, label)
      return toggled
    end

    local function Slider(label, key, min, max, fmt, width, flags)
      local ctx = UI.ctx
      if current_layout_key and reaper.ImGui_TableGetColumnIndex(ctx) == 1 then
        local cx, cy = reaper.ImGui_GetCursorPos(ctx)
        reaper.ImGui_SetCursorPos(ctx, cx, cy - 4)
      end
      reaper.ImGui_BeginGroup(ctx)
      reaper.ImGui_Text(ctx, label)
      reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ItemSpacing(), 0, 4)
      if width == -1 then
        reaper.ImGui_SetNextItemWidth(ctx, -1)
      elseif width then
        reaper.ImGui_SetNextItemWidth(ctx, width)
      end
      local changed, v = ImGui.SliderDouble(ctx, "##" .. label, UI.config[key], min, max, fmt or "%.1f", flags)
      if reaper.ImGui_IsItemHovered(ctx) and reaper.ImGui_IsMouseClicked(ctx, reaper.ImGui_MouseButton_Right()) then
        -- Default Handling:
        -- If key is 'sensitivity', default is 0.0
        local active_hunter = UI.hunters[UI.active_hunter_idx]
        local def_val = nil
        local profile_id = UI.config.source_profile or 2
        if active_hunter.Profiles and active_hunter.Profiles[profile_id] and active_hunter.Profiles[profile_id][key] ~= nil then
          def_val = active_hunter.Profiles[profile_id][key]
        else
          def_val = active_hunter.default_config[key]
        end
        if key == "sensitivity" and def_val == nil then def_val = 0.0 end
        
        if def_val ~= nil then
          v = def_val
          changed = true
          if UI.auto_rescan then
            UI._rescan_armed = true
            UI._rescan_last_change = reaper.time_precise()
          end
        end
      end
      if changed then
        if v ~= nil then UI.config[key] = v end
        -- SPECIAL CASE: If slider is Reduction, propagate change to cache immediately
        if key == "reduction_db" or key == "pre_ramp_ms" or key == "post_ramp_ms" then
             local cache, _, _ = get_active_cache_for_selected_item()
             if cache and cache.segments then
                 local ah = UI.hunters[UI.active_hunter_idx]
                 local is_plosive = ah and ah.name == "Plosive Hunter"
                 for _, seg in ipairs(cache.segments) do
                     if key == "reduction_db" then
                       if is_plosive and seg.points and #seg.points > 0 then
                         seg.hpf_strength = v
                       else
                         seg.gain_db = v
                       end
                     end
                 end
                 -- If modifying in Live Edit, apply the unified logic, not just the current Hunter!
                 if UI.config.live_edit then
                    apply_live_edit() -- Calls apply_live_edit which internally calls apply_reduction (unified)
                 end
             end
        end
        if UI.auto_rescan and key ~= "reduction_db" and key ~= "pre_ramp_ms" and key ~= "post_ramp_ms" then
          UI._rescan_armed = true
          UI._rescan_last_change = reaper.time_precise()
        end
      end
      if UI.auto_rescan and UI._rescan_armed then
        local now = reaper.time_precise()
        local delay_s = 0.2
        local idle = not reaper.ImGui_IsMouseDown(ctx, reaper.ImGui_MouseButton_Left())
        if (now - (UI._rescan_last_change or now)) >= delay_s and idle then
          UI._rescan_armed = false
          trigger_scan_or_detect()
        end
      end
      reaper.ImGui_PopStyleVar(ctx)
      reaper.ImGui_EndGroup(ctx)
      return changed
    end

    local function IntSlider(label, key, min, max, width)
      local ctx = UI.ctx
      if current_layout_key and reaper.ImGui_TableGetColumnIndex(ctx) == 1 then
        local cx, cy = reaper.ImGui_GetCursorPos(ctx)
        reaper.ImGui_SetCursorPos(ctx, cx, cy - 4)
      end
      reaper.ImGui_BeginGroup(ctx)
      reaper.ImGui_Text(ctx, label)
      reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ItemSpacing(), 0, 4)
      if width == -1 then
        reaper.ImGui_SetNextItemWidth(ctx, -1)
      elseif width then
        reaper.ImGui_SetNextItemWidth(ctx, width)
      end
      local changed, v = ImGui.SliderInt(ctx, "##" .. label, UI.config[key], min, max, nil, nil)
      if reaper.ImGui_IsItemHovered(ctx) and reaper.ImGui_IsMouseClicked(ctx, reaper.ImGui_MouseButton_Right()) then
        local active_hunter = UI.hunters[UI.active_hunter_idx]
        local def_val = nil
        local profile_id = UI.config.source_profile or 2
        if active_hunter.Profiles and active_hunter.Profiles[profile_id] and active_hunter.Profiles[profile_id][key] ~= nil then
          def_val = active_hunter.Profiles[profile_id][key]
        else
          def_val = active_hunter.default_config[key]
        end
        if def_val ~= nil then
          v = def_val
          changed = true
          if UI.auto_rescan then
            UI._rescan_armed = true
            UI._rescan_last_change = reaper.time_precise()
          end
        end
      end
      if LAYOUT_DEBUG then
        local min_x, min_y = reaper.ImGui_GetItemRectMin(ctx)
        local row = reaper.ImGui_TableGetRowIndex(ctx) or -1
        local col = reaper.ImGui_TableGetColumnIndex(ctx) or -1
        layout_debug[#layout_debug + 1] = {
          label = label,
          row = row,
          col = col,
          y = min_y,
          x = min_x,
          table_key = current_layout_key
        }
      end
      if changed then
        if v ~= nil then UI.config[key] = v end
        if UI.auto_rescan then
          UI._rescan_armed = true
          UI._rescan_last_change = reaper.time_precise()
        end
      end
      if UI.auto_rescan and UI._rescan_armed then
        local now = reaper.time_precise()
        local delay_s = 0.2
        local idle = not reaper.ImGui_IsMouseDown(ctx, reaper.ImGui_MouseButton_Left())
        if (now - (UI._rescan_last_change or now)) >= delay_s and idle then
          UI._rescan_armed = false
          trigger_scan_or_detect()
        end
      end
      reaper.ImGui_PopStyleVar(ctx)
      reaper.ImGui_EndGroup(ctx)
      return changed
    end

    -- Global Options
    reaper.ImGui_SeparatorText(UI.ctx, "GLOBAL OPTIONS")
    
    if reaper.ImGui_BeginTable(UI.ctx, "GlobalOptionsTable", 2, reaper.ImGui_TableFlags_SizingStretchSame()) then
      reaper.ImGui_PushStyleVar(UI.ctx, reaper.ImGui_StyleVar_CellPadding(), 0, 8)
      reaper.ImGui_TableSetupColumn(UI.ctx, "Col1", reaper.ImGui_TableColumnFlags_WidthStretch())
      reaper.ImGui_TableSetupColumn(UI.ctx, "Col2", reaper.ImGui_TableColumnFlags_WidthStretch())
      
      reaper.ImGui_TableNextRow(UI.ctx)
      reaper.ImGui_TableNextColumn(UI.ctx)
      UI.auto_rescan = Toggle("Auto Re-Scan on Change", UI.auto_rescan)
      
      reaper.ImGui_TableNextColumn(UI.ctx)
      local move_env_state = reaper.GetToggleCommandState(40070) == 1
      local new_move_env_state = Toggle("Move Envelopes with Items", move_env_state)
      if new_move_env_state ~= move_env_state then
        reaper.Main_OnCommand(40070, 0)
      end
      
      reaper.ImGui_PopStyleVar(UI.ctx)
      reaper.ImGui_EndTable(UI.ctx)
    end
    
    reaper.ImGui_Spacing(UI.ctx)

    if hunter.name == "Plosive Hunter" then
      reaper.ImGui_SeparatorText(UI.ctx, "DETECTION")

      current_layout_key = "PlosiveDetect"
      if reaper.ImGui_BeginTable(UI.ctx, "PlosiveDetectionTable", 2, reaper.ImGui_TableFlags_SizingStretchSame()) then
        reaper.ImGui_PushStyleVar(UI.ctx, reaper.ImGui_StyleVar_CellPadding(), 0, 8)
        reaper.ImGui_TableSetupColumn(UI.ctx, "Col1", reaper.ImGui_TableColumnFlags_WidthStretch())
        reaper.ImGui_TableSetupColumn(UI.ctx, "Col2", reaper.ImGui_TableColumnFlags_WidthStretch())

        reaper.ImGui_TableNextRow(UI.ctx)
        reaper.ImGui_TableNextColumn(UI.ctx)
        IntSlider("Low Pass Freq (Hz)", "low_pass", 40, 150, -1)
        reaper.ImGui_TableNextColumn(UI.ctx)
        IntSlider("Lookback (ms)", "delay_ms", 10, 80, -1)

        reaper.ImGui_TableNextRow(UI.ctx)
        reaper.ImGui_TableNextColumn(UI.ctx)
        Slider("Min Low Energy (dB)", "min_low_db", -80.0, -20.0, "%.1f", -1)
        reaper.ImGui_TableNextColumn(UI.ctx)
        Slider("Burst vs Lookback (dB)", "transient_thresh", 0.0, 14.0, "%.1f", -1)

        reaper.ImGui_TableNextRow(UI.ctx)
        reaper.ImGui_TableNextColumn(UI.ctx)
        Slider("Max Gap (ms)", "max_gap_ms", 0, 80, "%.0f", -1)
        reaper.ImGui_TableNextColumn(UI.ctx)
        Slider("Min Segment (ms)", "min_seg_ms", 1, 40, "%.0f", -1)

        reaper.ImGui_TableNextRow(UI.ctx)
        reaper.ImGui_TableNextColumn(UI.ctx)
        reaper.ImGui_TextDisabled(UI.ctx, "Max Gap merges short dips inside one plosive segment.")
        reaper.ImGui_TableNextColumn(UI.ctx)
        reaper.ImGui_TextDisabled(UI.ctx, "Min Segment rejects very short detections (clicks/edge noise).")

        reaper.ImGui_PopStyleVar(UI.ctx)
        reaper.ImGui_EndTable(UI.ctx)
      end
      current_layout_key = nil
      
      reaper.ImGui_Spacing(UI.ctx)
      reaper.ImGui_SeparatorText(UI.ctx, "REDUCTION SETTINGS")
      UI.config.live_edit = UI.config.live_edit or false
      UI.config.use_take_fx = UI.config.use_take_fx or false
      if reaper.ImGui_BeginTable(UI.ctx, "PlosiveReductionHeader", 3, reaper.ImGui_TableFlags_SizingStretchSame()) then
        reaper.ImGui_PushStyleVar(UI.ctx, reaper.ImGui_StyleVar_CellPadding(), 0, 4)
        reaper.ImGui_TableSetupColumn(UI.ctx, "Col1", reaper.ImGui_TableColumnFlags_WidthStretch())
        reaper.ImGui_TableSetupColumn(UI.ctx, "Col2", reaper.ImGui_TableColumnFlags_WidthStretch())
        reaper.ImGui_TableSetupColumn(UI.ctx, "Col3", reaper.ImGui_TableColumnFlags_WidthStretch())
        reaper.ImGui_TableNextRow(UI.ctx)

        reaper.ImGui_TableNextColumn(UI.ctx)
        UI.config.live_edit = Toggle("Live Edit", UI.config.live_edit)

        reaper.ImGui_TableNextColumn(UI.ctx)
        UI.config.use_take_fx = Toggle("Target: Take FX", UI.config.use_take_fx)

        reaper.ImGui_TableNextColumn(UI.ctx)
        local shape_names = { "Linear", "Square", "Slow Start/End", "Fast Start", "Fast End", "Bezier" }
        local shape_vals = { 0, 1, 2, 3, 4, 5 }
        UI.config.env_shape = UI.config.env_shape or 2
        local current_shape_idx = 0
        for i, v in ipairs(shape_vals) do
          if UI.config.env_shape == v then
            current_shape_idx = i - 1
            break
          end
        end
        reaper.ImGui_Text(UI.ctx, "Shape (HPF)")
        reaper.ImGui_SameLine(UI.ctx)
        reaper.ImGui_SetNextItemWidth(UI.ctx, -1)
        if reaper.ImGui_BeginCombo(UI.ctx, "##Shape", shape_names[current_shape_idx + 1]) then
          for i, name in ipairs(shape_names) do
            if reaper.ImGui_Selectable(UI.ctx, name, current_shape_idx == i - 1) then
              UI.config.env_shape = shape_vals[i]
            end
          end
          reaper.ImGui_EndCombo(UI.ctx)
        end

        reaper.ImGui_PopStyleVar(UI.ctx)
        reaper.ImGui_EndTable(UI.ctx)
      end

      reaper.ImGui_Spacing(UI.ctx)

      current_layout_key = "PlosiveReduction"
      if reaper.ImGui_BeginTable(UI.ctx, "PlosiveReductionTable", 2, reaper.ImGui_TableFlags_SizingStretchSame()) then
        reaper.ImGui_PushStyleVar(UI.ctx, reaper.ImGui_StyleVar_CellPadding(), 0, 8)
        reaper.ImGui_TableSetupColumn(UI.ctx, "Col1", reaper.ImGui_TableColumnFlags_WidthStretch())
        reaper.ImGui_TableSetupColumn(UI.ctx, "Col2", reaper.ImGui_TableColumnFlags_WidthStretch())

        reaper.ImGui_TableNextRow(UI.ctx)
        reaper.ImGui_TableNextColumn(UI.ctx)
        Slider("HPF Intensity", "reduction_db", 0.0, 24.0, "%.1f", -1)
        reaper.ImGui_TableNextColumn(UI.ctx)
        Slider("Pre-Ramp (ms)", "pre_ramp_ms", 0, 100, "%.0f", -1)

        reaper.ImGui_TableNextRow(UI.ctx)
        reaper.ImGui_TableNextColumn(UI.ctx)
        Slider("Post-Ramp (ms)", "post_ramp_ms", 0, 100, "%.0f", -1)
        reaper.ImGui_TableNextColumn(UI.ctx)

        reaper.ImGui_PopStyleVar(UI.ctx)
        reaper.ImGui_EndTable(UI.ctx)
      end
      current_layout_key = nil
    elseif hunter.name == "Ess Hunter" then
      reaper.ImGui_SeparatorText(UI.ctx, "DETECTION")

      current_layout_key = "EssDetect"
      if reaper.ImGui_BeginTable(UI.ctx, "EssDetectTable", 2, reaper.ImGui_TableFlags_SizingStretchSame()) then
        reaper.ImGui_PushStyleVar(UI.ctx, reaper.ImGui_StyleVar_CellPadding(), 0, 8)
        reaper.ImGui_TableSetupColumn(UI.ctx, "Col1", reaper.ImGui_TableColumnFlags_WidthStretch())
        reaper.ImGui_TableSetupColumn(UI.ctx, "Col2", reaper.ImGui_TableColumnFlags_WidthStretch())

        reaper.ImGui_TableNextRow(UI.ctx)
        reaper.ImGui_TableNextColumn(UI.ctx)
        Slider("ZCR Threshold", "zcr_thresh", 0.0, 0.5, "%.2f", -1)
        reaper.ImGui_TableNextColumn(UI.ctx)
        Slider("Sensitivity", "sensitivity", -1.0, 1.0, "%.2f", -1)

        reaper.ImGui_TableNextRow(UI.ctx)
        reaper.ImGui_TableNextColumn(UI.ctx)
        Slider("Min Segment (ms)", "min_seg_ms", 10, 100, "%.0f", -1)
        reaper.ImGui_TableNextColumn(UI.ctx)
        Slider("Max Gap (ms)", "max_gap_ms", 5, 100, "%.0f", -1)

        reaper.ImGui_PopStyleVar(UI.ctx)
        reaper.ImGui_EndTable(UI.ctx)
      end
      current_layout_key = nil

      reaper.ImGui_Spacing(UI.ctx)
      reaper.ImGui_SeparatorText(UI.ctx, "REDUCTION")
      UI.config.live_edit = UI.config.live_edit or false
      UI.config.use_take_fx = UI.config.use_take_fx or false
      if reaper.ImGui_BeginTable(UI.ctx, "EssReductionHeader", 3, reaper.ImGui_TableFlags_SizingStretchSame()) then
        reaper.ImGui_PushStyleVar(UI.ctx, reaper.ImGui_StyleVar_CellPadding(), 0, 4)
        reaper.ImGui_TableSetupColumn(UI.ctx, "Col1", reaper.ImGui_TableColumnFlags_WidthStretch())
        reaper.ImGui_TableSetupColumn(UI.ctx, "Col2", reaper.ImGui_TableColumnFlags_WidthStretch())
        reaper.ImGui_TableSetupColumn(UI.ctx, "Col3", reaper.ImGui_TableColumnFlags_WidthStretch())
        reaper.ImGui_TableNextRow(UI.ctx)

        reaper.ImGui_TableNextColumn(UI.ctx)
        UI.config.live_edit = Toggle("Live Edit", UI.config.live_edit)

        reaper.ImGui_TableNextColumn(UI.ctx)
        UI.config.use_take_fx = Toggle("Target: Take FX", UI.config.use_take_fx)

        reaper.ImGui_TableNextColumn(UI.ctx)
        local shape_names = { "Linear", "Square", "Slow Start/End", "Fast Start", "Fast End", "Bezier" }
        local shape_vals = { 0, 1, 2, 3, 4, 5 }
        UI.config.env_shape = UI.config.env_shape or 2
        local current_shape_idx = 0
        for i, v in ipairs(shape_vals) do
          if UI.config.env_shape == v then
            current_shape_idx = i - 1
            break
          end
        end
        reaper.ImGui_Text(UI.ctx, "Shape")
        reaper.ImGui_SameLine(UI.ctx)
        reaper.ImGui_SetNextItemWidth(UI.ctx, -1)
        if reaper.ImGui_BeginCombo(UI.ctx, "##Shape", shape_names[current_shape_idx + 1]) then
          for i, name in ipairs(shape_names) do
            if reaper.ImGui_Selectable(UI.ctx, name, current_shape_idx == i - 1) then
              UI.config.env_shape = shape_vals[i]
            end
          end
          reaper.ImGui_EndCombo(UI.ctx)
        end

        reaper.ImGui_PopStyleVar(UI.ctx)
        reaper.ImGui_EndTable(UI.ctx)
      end

      reaper.ImGui_Spacing(UI.ctx)

      current_layout_key = "EssReduction"
      if reaper.ImGui_BeginTable(UI.ctx, "EssReductionTable", 2, reaper.ImGui_TableFlags_SizingStretchSame()) then
        reaper.ImGui_PushStyleVar(UI.ctx, reaper.ImGui_StyleVar_CellPadding(), 0, 8)
        reaper.ImGui_TableSetupColumn(UI.ctx, "Col1", reaper.ImGui_TableColumnFlags_WidthStretch())
        reaper.ImGui_TableSetupColumn(UI.ctx, "Col2", reaper.ImGui_TableColumnFlags_WidthStretch())

        reaper.ImGui_TableNextRow(UI.ctx)
        reaper.ImGui_TableNextColumn(UI.ctx)
        Slider("Reduction (dB)", "reduction_db", 0.0, 18.0, "%.1f", -1)
        reaper.ImGui_TableNextColumn(UI.ctx)
        Slider("Pre-Ramp (ms)", "pre_ramp_ms", 0, 50, "%.0f", -1)

        reaper.ImGui_TableNextRow(UI.ctx)
        reaper.ImGui_TableNextColumn(UI.ctx)
        Slider("Post-Ramp (ms)", "post_ramp_ms", 0, 50, "%.0f", -1)
        reaper.ImGui_TableNextColumn(UI.ctx)

        reaper.ImGui_PopStyleVar(UI.ctx)
        reaper.ImGui_EndTable(UI.ctx)
      end
      current_layout_key = nil
    elseif hunter.name == "Breath Hunter" then
      reaper.ImGui_SeparatorText(UI.ctx, "LEVELS & DETECTION")

      current_layout_key = "BreathLevel"
      if reaper.ImGui_BeginTable(UI.ctx, "BreathLevelTable", 2, reaper.ImGui_TableFlags_SizingStretchSame()) then
        reaper.ImGui_PushStyleVar(UI.ctx, reaper.ImGui_StyleVar_CellPadding(), 0, 8)
        reaper.ImGui_TableSetupColumn(UI.ctx, "Col1", reaper.ImGui_TableColumnFlags_WidthStretch())
        reaper.ImGui_TableSetupColumn(UI.ctx, "Col2", reaper.ImGui_TableColumnFlags_WidthStretch())

        reaper.ImGui_TableNextRow(UI.ctx)
        reaper.ImGui_TableNextColumn(UI.ctx)
        local old_auto = UI.config.level_auto
        UI.config.level_auto = Toggle("Auto Levels", UI.config.level_auto)
        if old_auto ~= UI.config.level_auto and UI.auto_rescan then
            UI._rescan_armed = true
            UI._rescan_last_change = reaper.time_precise()
        end
        reaper.ImGui_TableNextColumn(UI.ctx)
        UI.config.focus = UI.config.focus or 0.5
        Slider("Focus (Isolamento)", "focus", 0.0, 1.0, "%.2f", -1)

        reaper.ImGui_TableNextRow(UI.ctx)
        reaper.ImGui_TableNextColumn(UI.ctx)
        UI.config.style = UI.config.style or 0.5
        Slider("Breath Style", "style", 0.0, 1.0, "%.2f", -1)
        
        reaper.ImGui_TableNextColumn(UI.ctx)
        UI.config.character = UI.config.character or 0.5
        Slider("Character", "character", 0.0, 1.0, "%.2f", -1)

        if not UI.config.level_auto then
          reaper.ImGui_TableNextRow(UI.ctx)
          reaper.ImGui_TableNextColumn(UI.ctx)
          Slider("Min Level (dB)", "min_level_db", -80.0, -30.0, "%.1f", -1)
          reaper.ImGui_TableNextColumn(UI.ctx)
          Slider("Max Level (dB)", "max_level_db", -60.0, 0.0, "%.1f", -1)
        end

        reaper.ImGui_TableNextRow(UI.ctx)
        reaper.ImGui_TableNextColumn(UI.ctx)

        reaper.ImGui_TableNextColumn(UI.ctx)

        reaper.ImGui_PopStyleVar(UI.ctx)
        reaper.ImGui_EndTable(UI.ctx)
      end
      current_layout_key = nil

      reaper.ImGui_Spacing(UI.ctx)
      reaper.ImGui_SeparatorText(UI.ctx, "REDUCTION")
      UI.config.live_edit = UI.config.live_edit or false
      UI.config.use_take_fx = UI.config.use_take_fx or false
      if reaper.ImGui_BeginTable(UI.ctx, "BreathReductionHeader", 3, reaper.ImGui_TableFlags_SizingStretchSame()) then
        reaper.ImGui_PushStyleVar(UI.ctx, reaper.ImGui_StyleVar_CellPadding(), 0, 4)
        reaper.ImGui_TableSetupColumn(UI.ctx, "Col1", reaper.ImGui_TableColumnFlags_WidthStretch())
        reaper.ImGui_TableSetupColumn(UI.ctx, "Col2", reaper.ImGui_TableColumnFlags_WidthStretch())
        reaper.ImGui_TableSetupColumn(UI.ctx, "Col3", reaper.ImGui_TableColumnFlags_WidthStretch())
        reaper.ImGui_TableNextRow(UI.ctx)

        reaper.ImGui_TableNextColumn(UI.ctx)
        UI.config.live_edit = Toggle("Live Edit", UI.config.live_edit)

        reaper.ImGui_TableNextColumn(UI.ctx)
        UI.config.use_take_fx = Toggle("Target: Take FX", UI.config.use_take_fx)

        reaper.ImGui_TableNextColumn(UI.ctx)
        local shape_names = { "Linear", "Square", "Slow Start/End", "Fast Start", "Fast End", "Bezier" }
        local shape_vals = { 0, 1, 2, 3, 4, 5 }
        UI.config.env_shape = UI.config.env_shape or 2
        local current_shape_idx = 0
        for i, v in ipairs(shape_vals) do
          if UI.config.env_shape == v then
            current_shape_idx = i - 1
            break
          end
        end
        reaper.ImGui_Text(UI.ctx, "Shape")
        reaper.ImGui_SameLine(UI.ctx)
        reaper.ImGui_SetNextItemWidth(UI.ctx, -1)
        if reaper.ImGui_BeginCombo(UI.ctx, "##Shape", shape_names[current_shape_idx + 1]) then
          for i, name in ipairs(shape_names) do
            if reaper.ImGui_Selectable(UI.ctx, name, current_shape_idx == i - 1) then
              UI.config.env_shape = shape_vals[i]
            end
          end
          reaper.ImGui_EndCombo(UI.ctx)
        end

        reaper.ImGui_PopStyleVar(UI.ctx)
        reaper.ImGui_EndTable(UI.ctx)
      end

      reaper.ImGui_Spacing(UI.ctx)

      current_layout_key = "BreathReduction"
      if reaper.ImGui_BeginTable(UI.ctx, "BreathReductionTable", 2, reaper.ImGui_TableFlags_SizingStretchSame()) then
        reaper.ImGui_PushStyleVar(UI.ctx, reaper.ImGui_StyleVar_CellPadding(), 0, 8)
        reaper.ImGui_TableSetupColumn(UI.ctx, "Col1", reaper.ImGui_TableColumnFlags_WidthStretch())
        reaper.ImGui_TableSetupColumn(UI.ctx, "Col2", reaper.ImGui_TableColumnFlags_WidthStretch())

        reaper.ImGui_TableNextRow(UI.ctx)
        reaper.ImGui_TableNextColumn(UI.ctx)
        Slider("Reduction (dB)", "reduction_db", 0.0, 60.0, "%.1f", -1)
        reaper.ImGui_TableNextColumn(UI.ctx)
        Slider("Pre-Ramp (ms)", "pre_ramp_ms", 0, 200, "%.0f", -1)

        reaper.ImGui_TableNextRow(UI.ctx)
        reaper.ImGui_TableNextColumn(UI.ctx)
        Slider("Post-Ramp (ms)", "post_ramp_ms", 0, 200, "%.0f", -1)
        reaper.ImGui_TableNextColumn(UI.ctx)

        reaper.ImGui_PopStyleVar(UI.ctx)
        reaper.ImGui_EndTable(UI.ctx)
      end
      current_layout_key = nil
    end

    -- Bottom Action Bar
    reaper.ImGui_Separator(UI.ctx)
    reaper.ImGui_Spacing(UI.ctx)
    
    local profile_selected = (UI.config.source_profile ~= nil and UI.config.source_profile > 0)

    if not profile_selected then
      reaper.ImGui_BeginDisabled(UI.ctx, true)
    end

    local avail_w = reaper.ImGui_GetContentRegionAvail(UI.ctx)
    local btn_w = math.floor((avail_w - 40) / 3)
    if btn_w < 160 then btn_w = 160 end

    if reaper.ImGui_Button(UI.ctx, "Analyze Active Hunter", btn_w, 30) then
      scan_item()
    end
    
    reaper.ImGui_SameLine(UI.ctx)
    reaper.ImGui_Dummy(UI.ctx, 10, 1)
    reaper.ImGui_SameLine(UI.ctx)
    
    if reaper.ImGui_Button(UI.ctx, "APPLY", btn_w, 30) then
      apply_reduction()
    end

    if not profile_selected then
      reaper.ImGui_EndDisabled(UI.ctx)
    end
    
    reaper.ImGui_SameLine(UI.ctx)
    reaper.ImGui_Dummy(UI.ctx, 10, 1)
    reaper.ImGui_SameLine(UI.ctx)

    if reaper.ImGui_Button(UI.ctx, "Reset Envelopes", btn_w, 30) then
      reset_envelopes()
    end

    DrawHelpModal()
    
    reaper.ImGui_End(UI.ctx)
  else
    UI.wants_close = true
  end

  if not open_ref then UI.wants_close = true end

  if LAYOUT_DEBUG and #layout_debug > 0 then
    local tables = {}
    for i = 1, #layout_debug do
      local e = layout_debug[i]
      local tkey = e.table_key or "unknown"
      local t = tables[tkey]
      if not t then
        t = {}
        tables[tkey] = t
      end
      local r = e.row
      local row_entry = t[r]
      if not row_entry then
        row_entry = {}
        t[r] = row_entry
      end
      if e.col == 0 then
        row_entry.left = e
      elseif e.col == 1 then
        row_entry.right = e
      end
    end
    for tkey, rows in pairs(tables) do
      Logger:debug("UI_LAYOUT | table:" .. tostring(tkey))
      for row, entry in pairs(rows) do
        if entry.left and entry.right then
          local dy = math.abs(entry.left.y - entry.right.y)
          Logger:debug(string.format("UI_LAYOUT | row:%d | dy:%.3f | left:%s | right:%s", row, dy, entry.left.label, entry.right.label))
        end
      end
    end
  end

  reaper.ImGui_PopStyleColor(UI.ctx, colors_pushed)
  reaper.ImGui_PopStyleVar(UI.ctx, 6)
end

return UI
