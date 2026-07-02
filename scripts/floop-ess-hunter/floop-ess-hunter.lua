-- Floop Ess Hunter: taming hiss in a single pass.
-- @description Floop Ess Hunter: tame hiss and sibilance with envelopes.
-- @version 1.2.0
-- @author Floop-s
-- @license GPL-3.0
-- @changelog
--   - UI/UX: Custom toggles, simplified layout, and async analysis (no UI freeze).
--   - Added Context-Aware Right-Click Reset for sliders.
--   - Optimized Live Edit for real-time volume adjustments.
--   - DSP: Switched to zero-allocation Butterworth HPF engine.
--   - Fix: Corrected start_offs envelope alignment and edge segment dropping.
-- @about
--   Floop Ess Hunter
--   Taming hiss.
--
--   Detects and attenuates sibilance in vocal items by writing Volume envelope points.
--   Features a fast zero-allocation HPF engine, adaptive thresholds, and ZCR.
--
--   Requires:
--     - ReaImGui (ReaTeam Extensions repository), v0.10.2 or newer
--
--   For full documentation and changelog, please refer to the README file.
--   Keywords: vocal, de-esser, envelope, processing, analysis
-- @provides [main] floop-ess-hunter.lua


-- Support reaper.ImGui and legacy ImGui_* APIs

local min, max, floor, abs, sqrt, log = math.min, math.max, math.floor, math.abs, math.sqrt, math.log
local table_insert = table.insert
local table_remove = table.remove

if not reaper then return end
if not reaper.ImGui and not reaper.ImGui_CreateContext then
  reaper.ShowMessageBox("ReaImGui not found. Install via ReaPack 'Dear ImGui for ReaScript'.", "Floop Ess Hunter", 0)
  return
end

local ImGui = reaper.ImGui
if not ImGui then
  ImGui = {}
  function ImGui.CreateContext(name) return reaper.ImGui_CreateContext(name) end
  function ImGui.DestroyContext(ctx)
    if reaper.ImGui_DestroyContext then
      return reaper.ImGui_DestroyContext(ctx)
    end
  end
  function ImGui.SetNextWindowSize(ctx, w, h, cond) return reaper.ImGui_SetNextWindowSize(ctx, w, h, cond) end
  function ImGui.Begin(ctx, title, open, flags) return reaper.ImGui_Begin(ctx, title, open, flags) end
  function ImGui.End(ctx) return reaper.ImGui_End(ctx) end
  function ImGui.Text(ctx, txt) return reaper.ImGui_Text(ctx, txt) end
  function ImGui.TextWrapped(ctx, txt) return reaper.ImGui_TextWrapped(ctx, txt) end
  function ImGui.Separator(ctx) return reaper.ImGui_Separator(ctx) end
  function ImGui.Button(ctx, label, w, h) return reaper.ImGui_Button(ctx, label, w, h) end
  function ImGui.SliderInt(ctx, label, v, min, max) return reaper.ImGui_SliderInt(ctx, label, v, min, max) end
  function ImGui.SliderFloat(ctx, label, v, min, max, format, flags)
    local f = reaper.ImGui_SliderFloat or reaper.ImGui_SliderDouble
    return f(ctx, label, v, min, max, format or '%.3f', flags)
  end
  function ImGui.Checkbox(ctx, label, v) return reaper.ImGui_Checkbox(ctx, label, v) end
  function ImGui.WindowFlags_NoCollapse() return reaper.ImGui_WindowFlags_NoCollapse() end
  function ImGui.Cond_Appearing() return reaper.ImGui_Cond_Appearing() end
  function ImGui.BeginCombo(ctx, label, preview, flags) return reaper.ImGui_BeginCombo(ctx, label, preview, flags or 0) end
  function ImGui.EndCombo(ctx) return reaper.ImGui_EndCombo(ctx) end
  function ImGui.Selectable(ctx, label, selected) return reaper.ImGui_Selectable(ctx, label, selected or false) end
  function ImGui.SameLine(ctx, pos_x, spacing) return reaper.ImGui_SameLine(ctx, pos_x or nil, spacing or nil) end
  function ImGui.InputText(ctx, label, buf, flags)
    local f = reaper.ImGui_InputText
    if not f then return false, buf end
    local changed, out = f(ctx, label, buf or '', flags or 0)
    return changed, out
  end
  function ImGui.ProgressBar(ctx, frac, w, h, overlay)
    local f = reaper.ImGui_ProgressBar
    if f then return f(ctx, frac or 0.0, w or 0, h or 0, overlay or nil) end
    reaper.ImGui_Text(ctx, string.format('Progress: %d%%', floor((frac or 0)*100+0.5)))
    return true
  end
end

if ImGui and not ImGui.ProgressBar then
  function ImGui.ProgressBar(ctx, frac, w, h, overlay)
    local f = reaper.ImGui_ProgressBar
    if f then return f(ctx, frac or 0.0, w or 0, h or 0, overlay or nil) end
    reaper.ImGui_Text(ctx, string.format('Progress: %d%%', floor((frac or 0)*100+0.5)))
    return true
  end
end

local ctx = ImGui.CreateContext('Floop Ess Hunter')
local sans_serif_font = (reaper.ImGui_CreateFont and reaper.ImGui_CreateFont('sans-serif', 12))
if sans_serif_font and reaper.ImGui_Attach then
  reaper.ImGui_Attach(ctx, sans_serif_font)
end

local THEME_COLORS = {
  [reaper.ImGui_Col_WindowBg()]         = 0x1e2328FF,
  [reaper.ImGui_Col_TitleBg()]          = 0x14B8A6FF,
  [reaper.ImGui_Col_TitleBgActive()]    = 0x0F766EFF,
  [reaper.ImGui_Col_Button()]           = 0x14B8A6FF,
  [reaper.ImGui_Col_ButtonHovered()]    = 0x0F766EFF,
  [reaper.ImGui_Col_ButtonActive()]     = 0x0D9488FF,
  [reaper.ImGui_Col_FrameBg()]          = 0x0F766EFF,
  [reaper.ImGui_Col_FrameBgHovered()]   = 0x0F766EFF,
  [reaper.ImGui_Col_FrameBgActive()]    = 0x0D9488FF,
  [reaper.ImGui_Col_SliderGrab()]       = 0xFFFFFFFF,
  [reaper.ImGui_Col_SliderGrabActive()] = 0xFFFFFFFF,
  [reaper.ImGui_Col_CheckMark()]        = 0xFBBF24FF,
  [reaper.ImGui_Col_Header()]           = 0x1F2937FF,
  [reaper.ImGui_Col_HeaderHovered()]    = 0x14B8A6FF,
  [reaper.ImGui_Col_HeaderActive()]     = 0x0F766EFF,
  [reaper.ImGui_Col_Separator()]        = 0x14B8A6FF,
  [reaper.ImGui_Col_Text()]             = 0xF7FAFCFF,
  [reaper.ImGui_Col_TextDisabled()]     = 0x929292FF,
  [reaper.ImGui_Col_ResizeGrip()]       = 0x14B8A6FF,
  [reaper.ImGui_Col_ResizeGripHovered()] = 0x2DD4BFFF,
  [reaper.ImGui_Col_ResizeGripActive()]  = 0x0EA5A5FF,
}

local function apply_theme()
  reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameRounding(), 6.0)
  reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowRounding(), 8.0)
  reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowPadding(), 16.0, 16.0)
  reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FramePadding(), 5.0, 5.0)
  reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ItemSpacing(), 5.0, 5.0)
  if reaper.ImGui_StyleVar_GrabRounding then
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_GrabRounding(), 4.0)
  end

  local color_count = 0
  for k, v in pairs(THEME_COLORS) do
    reaper.ImGui_PushStyleColor(ctx, k, v)
    color_count = color_count + 1
  end
  return color_count
end

local function end_theme(color_count)
  reaper.ImGui_PopStyleColor(ctx, color_count)
  local to_pop = 5 + (reaper.ImGui_StyleVar_GrabRounding and 1 or 0)
  reaper.ImGui_PopStyleVar(ctx, to_pop)
end

local function mod_ctrl()
  if reaper.ImGui_Mod_Ctrl and reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Mod_Ctrl()) then return true end
  if reaper.ImGui_Mod_Super and reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Mod_Super()) then return true end
  if reaper.ImGui_GetKeyMods then
    local mods = reaper.ImGui_GetKeyMods(ctx)
    local ctrl = (reaper.ImGui_KeyModFlags_Ctrl and reaper.ImGui_KeyModFlags_Ctrl()) or (reaper.ImGui_ModFlags_Ctrl and reaper.ImGui_ModFlags_Ctrl()) or 0
    local super = (reaper.ImGui_KeyModFlags_Super and reaper.ImGui_KeyModFlags_Super()) or (reaper.ImGui_ModFlags_Super and reaper.ImGui_ModFlags_Super()) or 0
    return (mods & ctrl) ~= 0 or (mods & super) ~= 0
  end
  return false
end

local function mod_alt()
  if reaper.ImGui_Mod_Alt and reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Mod_Alt()) then return true end
  if reaper.ImGui_GetKeyMods then
    local mods = reaper.ImGui_GetKeyMods(ctx)
    local alt = (reaper.ImGui_KeyModFlags_Alt and reaper.ImGui_KeyModFlags_Alt()) or (reaper.ImGui_ModFlags_Alt and reaper.ImGui_ModFlags_Alt()) or 0
    return (mods & alt) ~= 0
  end
  return false
end

local function is_valid_item(item)
  if not item then return false end
  if reaper.ValidatePtr2 then
    return reaper.ValidatePtr2(0, item, "MediaItem*")
  end
  return true
end

local state = {
  hop_ms = 6,
  target_freq = 6500,
  fricative_sens = 50.0,
  min_level_db = -45.0,
  min_seg_ms = 25,
  max_gap_ms = 18,
  reduction_db = 4.0,
  pre_ramp_ms = 8,
  post_ramp_ms = 12,
  overwrite = true,
  target_mode = 2,
  auto_analyze = false,
  last_change_time = nil,
  last_auto_analyze = nil,
  drag_threshold = false,
  drag_seg_index = -1,
  drag_edge = 0,
  drag_seg_vol_index = -1,
  view_start_frac = 0.0,
  view_len_frac = 1.0,
  snap_to_hop = true,
  live_edit = false,
  new_seg_active = false,
  new_seg_start_t = nil,
  new_seg_end_t = nil,
  custom_preset_name = '',
  selected_custom_index = 0,
  msg = "",
  preset_index = 0,
  show_help = false,
}
local EXT_NS = 'FloopEssHunter'

local HELP_CONTENT = {
  overview = {
    title = "Floop Ess Hunter — Overview",
    content = [[
Floop Ess Hunter automatically detects and reduces sibilant sounds ('s', 'sh', 'ch') in vocal recordings.

Taming the hiss, one S at a time.

It writes volume envelope points only on detected sibilant segments to preserve natural dynamics.
]]
  },
  
  quick_start = {
    title = "Quick Start",
    content = [[
1) Select one or more vocal items in your project.
2) Launch "Floop Ess Hunter" from the Actions List.
3) Click "Analyze (Preview)" to preview detection.
4) Click "Apply from preview" or "Analyze and apply" to write envelope points.
5) Adjust parameters under "Fine Tuning" as needed.
    ]]
  },
  
  parameters = {
    analysis = {
      title = "ANALYSIS",
      params = {
        {
          name = "Target Freq",
          type = "Integer",
          range = "3000-12000 Hz",
          default = "6000 Hz", 
          description = "Frequency cutoff for sibilance detection (High-Pass Filter). Sibilants typically occur above 5 kHz. Lower values catch softer sibilants, higher values focus on harsh consonants."
        },
        {
          name = "Threshold", 
          type = "Float",
          range = "-60.0 to -20.0 dB",
          default = "-40.0 dB",
          description = "Minimum signal level for sibilance detection. Prevents processing of quiet background noise."
        },
        {
          name = "Sibilance Sens.",
          type = "Float", 
          range = "0.0-100.0 %",
          default = "50.0 %",
          description = "Master sensitivity control. Adjusts internal ZCR and ratio thresholds. Higher values catch more sibilants, lower values are more selective."
        }
      }
    },
    
    detection = {
      title = "TIMING & DETECTION", 
      params = {
        {
          name = "Min Length",
          type = "Integer",
          range = "15-60 ms", 
          default = "20 ms",
          description = "Minimum duration for a valid sibilant segment. Shorter segments are discarded to avoid processing transients or noise."
        },
        {
          name = "Max Gap",
          type = "Integer", 
          range = "10-40 ms",
          default = "20 ms", 
          description = "Maximum gap within a sibilant segment before splitting. Helps merge closely spaced sibilant parts into single segments."
        }
      }
    },
    
    segments = {
      title = "ENVELOPES",
      params = {
        {
          name = "Pre Ramp",
          type = "Integer", 
          range = "0-25 ms",
          default = "2 ms",
          description = "Fade-in duration before volume reduction. Prevents abrupt level changes that could cause artifacts."
        },
        {
          name = "Post Ramp",
          type = "Integer",
          range = "0-40 ms", 
          default = "10 ms",
          description = "Fade-out duration after volume reduction. Ensures smooth transition back to original level."
        }
      }
    }
  },
  
  workflow = {
    title = "Recommended Workflow",
    content = [[
1) Set frequency bounds and reduction dB based on material.
2) Click "Analyze (Preview)" and audition A/B; toggle envelope visibility in REAPER.
3) Tweak Min/Max gap and ramps for natural transitions on fast/mellow phrases.
4) Adjust Sensitivity to reduce false positives/negatives.
5) Enable "Live Edit" to quickly tune the overall volume reduction.
]]
  },
  
  presets = {
    title = "Presets",
    content = [[
SPEECH PRESET:
Optimized for spoken word content with moderate sibilance.
• Frequency range: 3500-9500 Hz (standard sibilant range)
• Moderate sensitivity (Delta IN: 0.08)
• Balanced segment timing (25ms min, 18ms max gap)
• Conservative reduction (4.0 dB)

SOFT SINGING PRESET: 
Designed for gentle vocal performances with subtle sibilants.
• Slightly lower frequency range: 3200-9000 Hz
• Higher sensitivity (Delta IN: 0.06, ZCR: 0.10)
• Longer segments (28ms min, 20ms max gap)
• Gentle reduction (3.0 dB)

AGGRESSIVE SINGING PRESET:
For powerful vocals with prominent, harsh sibilants.
• Extended frequency range: 3600-10000 Hz
• Lower sensitivity (Delta IN: 0.10, ZCR: 0.13) 
• Shorter, tighter segments (22ms min, 16ms max gap)
• Stronger reduction (6.0 dB)

CUSTOM PRESETS:
Save your own configurations using the preset dropdown.
Custom presets are stored per-project and persist across sessions.
]]
  },
  
  envelope_model = {
    title = "Envelope Model",
    content = [[
• Track Volume envelope operates on linear amplitude (not dB).
• Reduction multiplies the local level by a factor < 1.
• Conversion: factor = 10^(dB/20). Examples: −6 dB ≈ 0.50×, −3 dB ≈ 0.71×.
• REAPER clamps envelope values; typical Track Volume range is 0..2.
• "Pre‑FX" writes before the FX chain; otherwise it is post‑fader.
]]
  },
  
  technical = {
    title = "Technical Notes",
    content = [[
• Effective sample rate accounts for the take’s playback rate for correct timing.
• Envelope writes are wrapped in Undo blocks for a safe workflow.
]]
  },
  
  troubleshooting = {
    title = "Troubleshooting",
    content = [[
COMMON ISSUES:

OVER-PROCESSING (too much reduction):
• Decrease Sensitivity (less sensitive)
• Increase Threshold (ignore quiet parts)
• Increase Target Freq (focus on harsh sibilants only)

UNDER-PROCESSING (sibilants missed):
• Increase Sensitivity (more sensitive)
• Decrease Target Freq (catch more sibilant types)
• Reduce Min Length duration (catch shorter sibilants)

CHOPPY/UNNATURAL RESULTS:
• Increase Pre/Post Ramp durations (smoother transitions)
• Increase Max Gap (merge fragmented segments)
• Reduce reduction amount (gentler processing)

NO DETECTION:
• Verify audio item is selected and has content
• Check Threshold isn't too high for your material
• Try "Soft singing" preset for subtle sibilants

ERROR MESSAGES:
• "No active take": Select item with valid audio
• "Cannot create accessor": Audio file may be corrupted
• "Analysis canceled": User interruption or system issue
      ]]
  }
}

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

local function draw_help_modal()
  local modalW, modalH = 700, 680
  local winX, winY = reaper.ImGui_GetWindowPos(ctx)
  local winW, winH = reaper.ImGui_GetWindowSize(ctx)
  if winX and winY and winW and winH then
    reaper.ImGui_SetNextWindowSize(ctx, modalW, modalH, reaper.ImGui_Cond_Always())
    reaper.ImGui_SetNextWindowPos(ctx, winX + (winW - modalW) * 0.5, winY + (winH - modalH) * 0.5, reaper.ImGui_Cond_Appearing())
  end
  local flags = reaper.ImGui_WindowFlags_NoResize() | reaper.ImGui_WindowFlags_NoMove() | reaper.ImGui_WindowFlags_NoDocking()
  if reaper.ImGui_BeginPopupModal(ctx, "Help", true, flags) then
    local childFlags = (reaper.ImGui_ChildFlags_Borders and reaper.ImGui_ChildFlags_Borders()) or 0
    local avail_w = select(1, reaper.ImGui_GetContentRegionAvail(ctx))
    local avail_h = select(2, reaper.ImGui_GetContentRegionAvail(ctx))
    local btn_w = 100
    local btn_h = 25
    local child_h = math.max(120, (avail_h or 0) - (btn_h + 12))
    if reaper.ImGui_BeginChild(ctx, "HelpScroll", -1, child_h, childFlags) then
      reaper.ImGui_SeparatorText(ctx, HELP_CONTENT.overview.title)
      reaper.ImGui_TextWrapped(ctx, HELP_CONTENT.overview.content)
      reaper.ImGui_Spacing(ctx)
      reaper.ImGui_SeparatorText(ctx, HELP_CONTENT.quick_start.title)
      reaper.ImGui_TextWrapped(ctx, HELP_CONTENT.quick_start.content)
      reaper.ImGui_Spacing(ctx)
      reaper.ImGui_SeparatorText(ctx, 'Parameters (Fine Tuning)')
      reaper.ImGui_SeparatorText(ctx, HELP_CONTENT.parameters.analysis.title)
      for _, param in ipairs(HELP_CONTENT.parameters.analysis.params) do
        reaper.ImGui_Text(ctx, param.name)
        reaper.ImGui_SameLine(ctx)
        reaper.ImGui_TextDisabled(ctx, string.format("(%s | Range: %s | Default: %s)", param.type, param.range, param.default))
        reaper.ImGui_TextWrapped(ctx, param.description)
        reaper.ImGui_Spacing(ctx)
      end
      reaper.ImGui_SeparatorText(ctx, HELP_CONTENT.parameters.detection.title)
      for _, param in ipairs(HELP_CONTENT.parameters.detection.params) do
        reaper.ImGui_Text(ctx, param.name)
        reaper.ImGui_SameLine(ctx)
        reaper.ImGui_TextDisabled(ctx, string.format("(%s | Range: %s | Default: %s)", param.type, param.range, param.default))
        reaper.ImGui_TextWrapped(ctx, param.description)
        reaper.ImGui_Spacing(ctx)
      end
      reaper.ImGui_SeparatorText(ctx, HELP_CONTENT.parameters.segments.title)
      for _, param in ipairs(HELP_CONTENT.parameters.segments.params) do
        reaper.ImGui_Text(ctx, param.name)
        reaper.ImGui_SameLine(ctx)
        reaper.ImGui_TextDisabled(ctx, string.format("(%s | Range: %s | Default: %s)", param.type, param.range, param.default))
        reaper.ImGui_TextWrapped(ctx, param.description)
        reaper.ImGui_Spacing(ctx)
      end
      reaper.ImGui_SeparatorText(ctx, 'Preview & Interactions')
      reaper.ImGui_TextWrapped(ctx, [[
• Zoom: mouse wheel over the waveform; pan with right-button drag.
• Drag segments: adjust edges to refine boundaries; optional hop snapping for temporal consistency.
• Segment gain: drag the square handle at the bottom of each segment to change reduction; right-click to delete.
• Apply from preview: available only after "Analyze (Preview)".
      ]])
      reaper.ImGui_Spacing(ctx)
      reaper.ImGui_SeparatorText(ctx, HELP_CONTENT.workflow.title)
      reaper.ImGui_TextWrapped(ctx, HELP_CONTENT.workflow.content)
      reaper.ImGui_Spacing(ctx)
      reaper.ImGui_SeparatorText(ctx, HELP_CONTENT.presets.title)
      reaper.ImGui_TextWrapped(ctx, HELP_CONTENT.presets.content)
      reaper.ImGui_Spacing(ctx)
      reaper.ImGui_SeparatorText(ctx, HELP_CONTENT.envelope_model.title)
      reaper.ImGui_TextWrapped(ctx, HELP_CONTENT.envelope_model.content)
      reaper.ImGui_Spacing(ctx)
      reaper.ImGui_SeparatorText(ctx, HELP_CONTENT.technical.title)
      reaper.ImGui_TextWrapped(ctx, HELP_CONTENT.technical.content)
      reaper.ImGui_Spacing(ctx)
      reaper.ImGui_SeparatorText(ctx, HELP_CONTENT.troubleshooting.title)
      reaper.ImGui_TextWrapped(ctx, HELP_CONTENT.troubleshooting.content)
      reaper.ImGui_Spacing(ctx)
      reaper.ImGui_SeparatorText(ctx, 'SUPPORT')
      reaper.ImGui_TextWrapped(ctx, 'If this script saves you time, a coffee is always appreciated.')
      reaper.ImGui_Spacing(ctx)
      if reaper.ImGui_Button(ctx, "Support Floop's Reaper Scripts on Ko-fi") then
        open_url("https://ko-fi.com/floopsreaperscripts")
      end

      reaper.ImGui_EndChild(ctx)
    end

    local avail_w = select(1, reaper.ImGui_GetContentRegionAvail(ctx))
    reaper.ImGui_SetCursorPosX(ctx, (avail_w - btn_w) * 0.5)

    if reaper.ImGui_Button(ctx, "Close", btn_w, 25) then
      reaper.ImGui_CloseCurrentPopup(ctx)
    end

    reaper.ImGui_EndPopup(ctx)
  end
end

local function serialize_last_state()
  local kv = {}
  local function add(k, v)
    kv[#kv+1] = tostring(k) .. '=' .. tostring(v)
  end
  add('target_freq', state.target_freq)
  add('fricative_sens', state.fricative_sens)
  add('min_level_db', state.min_level_db)
  add('min_seg_ms', state.min_seg_ms)
  add('max_gap_ms', state.max_gap_ms)
  add('pre_ramp_ms', state.pre_ramp_ms)
  add('post_ramp_ms', state.post_ramp_ms)
  add('reduction_db', state.reduction_db)
  add('overwrite', state.overwrite and 1 or 0)
  add('snap_to_hop', state.snap_to_hop and 1 or 0)
  add('target_mode', state.target_mode)
  add('auto_analyze', state.auto_analyze and 1 or 0)
  return table.concat(kv, ',')
end

local function deserialize_last_state(s)
  if not s or s == '' then return end
  for token in string.gmatch(s, '[^,]+') do
    local k, v = token:match('([^=]+)=([^=]+)')
    if k and v then
      if k == 'overwrite' or k == 'snap_to_hop' or k == 'auto_analyze' then
        state[k] = (tonumber(v) or 0) ~= 0
      elseif state[k] ~= nil then
        local num = tonumber(v)
        state[k] = num or v
      end
    end
  end
  if state.target_freq == nil then state.target_freq = 6500 end
  if state.fricative_sens == nil then state.fricative_sens = 50.0 end
end

local function load_last_state()
  local ok, value = reaper.GetProjExtState(0, EXT_NS, 'last_state')
  if ok ~= 0 and value and value ~= '' then
    deserialize_last_state(value)
  end
end

local function save_last_state()
  local s = serialize_last_state()
  reaper.SetProjExtState(0, EXT_NS, 'last_state', s)
end

if reaper and reaper.GetProjExtState then load_last_state() end

local PRESETS
local apply_preset
local list_custom_presets
local save_custom_preset
local load_custom_preset
local delete_custom_preset

local function db_to_amp(db) return 10 ^ (db/20) end
local function amp_to_db(amp) return 20 * (log(max(amp, 1e-12)) / log(10)) end

local function current_values_from_state()
  return {
    target_freq=state.target_freq, fricative_sens=state.fricative_sens,
    min_level_db=state.min_level_db, min_seg_ms=state.min_seg_ms, max_gap_ms=state.max_gap_ms,
    reduction_db=state.reduction_db, pre_ramp_ms=state.pre_ramp_ms, post_ramp_ms=state.post_ramp_ms,
  }
end

local function serialize_preset_values(v)
  local parts = {}
  local keys = {
    'target_freq','fricative_sens','min_level_db','min_seg_ms','max_gap_ms','reduction_db','pre_ramp_ms','post_ramp_ms'
  }
  for i=1,#keys do
    local k = keys[i]
    parts[#parts+1] = k..'='..tostring(v[k])
  end
  return table.concat(parts, ';')
end

local function deserialize_preset_values(str)
  local v = {}
  for token in string.gmatch(str or '', '[^;]+') do
    local k, val = token:match('([^=]+)=(.*)')
    if k then
      local num = tonumber(val)
      v[k] = num or val
    end
  end
  return v
end

list_custom_presets = function()
  local ok, s = reaper.GetProjExtState(0, EXT_NS, 'custom_presets')
  local names = {}
  if ok > 0 and s and s ~= '' then
    for name in s:gmatch('[^;]+') do names[#names+1] = name end
  end
  return names
end

save_custom_preset = function(name)
  local v = current_values_from_state()
  local ser = serialize_preset_values(v)
  reaper.SetProjExtState(0, EXT_NS, 'preset:'..name, ser)
  local names = list_custom_presets()
  local exists = false
  for i=1,#names do if names[i] == name then exists = true; break end end
  if not exists then
    names[#names+1] = name
    reaper.SetProjExtState(0, EXT_NS, 'custom_presets', table.concat(names, ';'))
  end
  state.msg = 'Saved preset: '..name
end

load_custom_preset = function(name)
  local ok, ser = reaper.GetProjExtState(0, EXT_NS, 'preset:'..name)
  if ok == 0 or not ser or ser == '' then state.msg = 'Preset not found: '..name; return end
  local v = deserialize_preset_values(ser)
  apply_preset({ name = name, values = v })
end

delete_custom_preset = function(name)
  reaper.SetProjExtState(0, EXT_NS, 'preset:'..name, '')
  local names = list_custom_presets()
  local kept = {}
  for i=1,#names do if names[i] ~= name then kept[#kept+1] = names[i] end end
  reaper.SetProjExtState(0, EXT_NS, 'custom_presets', table.concat(kept, ';'))
  state.msg = 'Deleted preset: '..name
end

local function rbj_bandpass(fc, Q, fs)
  local w0 = 2 * math.pi * fc / fs
  local cosw0 = math.cos(w0)
  local sinw0 = math.sin(w0)
  local alpha = sinw0 / (2 * Q)
  local b0 = alpha
  local b1 = 0
  local b2 = -alpha
  local a0 = 1 + alpha
  local a1 = -2 * cosw0
  local a2 = 1 - alpha
  return { b0=b0/a0, b1=b1/a0, b2=b2/a0, a1=a1/a0, a2=a2/a0 }
end

local function rbj_highpass(fc, Q, fs)
  local w0 = 2 * math.pi * fc / fs
  local cosw0 = math.cos(w0)
  local sinw0 = math.sin(w0)
  local alpha = sinw0 / (2 * Q)
  local b0 = (1 + cosw0) / 2
  local b1 = -(1 + cosw0)
  local b2 = (1 + cosw0) / 2
  local a0 = 1 + alpha
  local a1 = -2 * cosw0
  local a2 = 1 - alpha
  return { b0=b0/a0, b1=b1/a0, b2=b2/a0, a1=a1/a0, a2=a2/a0 }
end

local function biquad_new(coeff)
  return { b0=coeff.b0, b1=coeff.b1, b2=coeff.b2, a1=coeff.a1, a2=coeff.a2, x1=0.0, x2=0.0, y1=0.0, y2=0.0 }
end

local function biquad_process(st, x)
  local y = st.b0*x + st.b1*st.x1 + st.b2*st.x2 - st.a1*st.y1 - st.a2*st.y2
  st.x2 = st.x1; st.x1 = x
  st.y2 = st.y1; st.y1 = y
  return y
end

local TARGET_TRACK_VOL = 0
local TARGET_TRACK_PREFX = 1
local TARGET_TAKE_VOL = 2

local function ensure_envelope_visible(env)
  local vis = reaper.GetEnvelopeInfo_Value(env, "VIS")
  if vis >= 0.5 then return end
  if reaper.SetEnvelopeInfo_Value then
    reaper.SetEnvelopeInfo_Value(env, "VIS", 1.0)
    return
  end
  if reaper.GetEnvelopeStateChunk and reaper.SetEnvelopeStateChunk then
    local ok, chunk = reaper.GetEnvelopeStateChunk(env, "", false)
    if ok == true and type(chunk) == "string" and #chunk > 0 then
      local new = chunk:gsub("VIS%s+%d", "VIS 1")
      if new ~= chunk then
        reaper.SetEnvelopeStateChunk(env, new, false)
      end
    end
  end
end

local function get_target_envelope(track, item, mode)
  if mode == TARGET_TAKE_VOL then
    local take = reaper.GetActiveTake(item)
    if not take then return nil end
    local env = reaper.GetTakeEnvelopeByName(take, "Volume")
    if env then
      ensure_envelope_visible(env)
      return env, true
    end

    local selected_items = {}
    for i=0, reaper.CountSelectedMediaItems(0)-1 do
      selected_items[#selected_items+1] = reaper.GetSelectedMediaItem(0, i)
    end

    reaper.SelectAllMediaItems(0, false)
    reaper.SetMediaItemSelected(item, true)
    reaper.Main_OnCommand(40693, 0)

    env = reaper.GetTakeEnvelopeByName(take, "Volume")
    if env then
      ensure_envelope_visible(env)
    end

    reaper.SelectAllMediaItems(0, false)
    for _, it in ipairs(selected_items) do reaper.SetMediaItemSelected(it, true) end

    return env, true
  end

  local name = (mode == TARGET_TRACK_PREFX) and "Volume (Pre-FX)" or "Volume"
  local selected_tracks = {}
  for i = 0, reaper.CountTracks(0)-1 do
    local t = reaper.GetTrack(0, i)
    if reaper.IsTrackSelected(t) then
      selected_tracks[#selected_tracks+1] = t
    end
  end

  for i = 0, reaper.CountTracks(0)-1 do
    local t = reaper.GetTrack(0, i)
    reaper.SetTrackSelected(t, false)
  end
  reaper.SetTrackSelected(track, true)

  local env = reaper.GetTrackEnvelopeByName(track, name)
  if env == nil then
    if mode == TARGET_TRACK_PREFX then
      reaper.Main_OnCommand(40050, 0)
    else
      reaper.Main_OnCommand(40406, 0)
    end
    env = reaper.GetTrackEnvelopeByName(track, name)
    if env == nil then
      reaper.ShowMessageBox("Unable to create envelope '"..name.."'. Open Track Envelopes and enable it.", "Floop Ess Hunter", 0)
      for i = 0, reaper.CountTracks(0)-1 do
        reaper.SetTrackSelected(reaper.GetTrack(0, i), false)
      end
      for _, t in ipairs(selected_tracks) do
        reaper.SetTrackSelected(t, true)
      end
      return nil
    end
  end

  ensure_envelope_visible(env)
  for i = 0, reaper.CountTracks(0)-1 do
    reaper.SetTrackSelected(reaper.GetTrack(0, i), false)
  end
  for _, t in ipairs(selected_tracks) do
    reaper.SetTrackSelected(t, true)
  end

  return env, false
end

-- ExtState: per-item overwrite tracking

local function get_item_guid(item)
  local _, guid = reaper.GetSetMediaItemInfo_String(item, 'GUID', '', false)
  return guid
end

local function get_track_guid(track)
  return reaper.GetTrackGUID(track)
end

local function make_key(track, item)
  return string.format('%s|%s', get_track_guid(track), get_item_guid(item))
end

local function save_segments(track, item, segments, pre_ms, post_ms)
  local key = make_key(track, item)
  local parts = { tostring(pre_ms), tostring(post_ms) }
  for i=1,#segments do
    parts[#parts+1] = string.format('%.6f,%.6f', segments[i][1], segments[i][2])
  end
  local value = table.concat(parts, ';')
  reaper.SetProjExtState(0, EXT_NS, key, value)
end

local function load_segments(track, item)
  local key = make_key(track, item)
  local ok, value = reaper.GetProjExtState(0, EXT_NS, key)
  if ok == 0 or not value or value == '' then return nil end
  local segs = {}
  local pre_ms, post_ms = 0, 0
  local first = true
  for token in string.gmatch(value, '[^;]+') do
    if first then pre_ms = tonumber(token); first = false
    elseif post_ms == 0 then post_ms = tonumber(token)
    else
      local a,b = token:match('([^,]+),([^,]+)')
      if a and b then segs[#segs+1] = { tonumber(a), tonumber(b) } end
    end
  end
  return { pre_ms = pre_ms or 0, post_ms = post_ms or 0, segments = segs }
end

local function clear_previous_segments(env, track, item, item_pos, start_offs, playrate, is_take_env)
  local item_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
  local t1 = item_pos
  local t2 = item_pos + item_len
  
  if is_take_env then
    t1 = (t1 - item_pos) * playrate + start_offs
    t2 = (t2 - item_pos) * playrate + start_offs
  end
  

  reaper.DeleteEnvelopePointRange(env, t1 - 0.05, t2 + 0.05)
  
  local key = make_key(track, item)
  reaper.SetProjExtState(0, EXT_NS, key, '')
end

local function insert_reduction_points(env, t_start, t_end, factor, pre_ms, post_ms, overwrite, item_pos, start_offs, playrate, is_take_env)
  local pre = max(0, pre_ms/1000)
  local post = max(0, post_ms/1000)
  local shape = 0 -- linear
  
  local function to_env_time(t_proj)
    if is_take_env then
      return (t_proj - item_pos) * playrate + start_offs
    else
      return t_proj
    end
  end

  local t1 = to_env_time(max(0, t_start - pre))
  local t2 = to_env_time(t_start)
  local t3 = to_env_time(t_end)
  local t4 = to_env_time(t_end + post)
  
  local v_pre = select(2, reaper.Envelope_Evaluate(env, max(0, t1 - 1e-3), 0, 0))
  local v_post = select(2, reaper.Envelope_Evaluate(env, t4 + 1e-3, 0, 0))

  --  envelope scaling 
  local mode = reaper.GetEnvelopeScalingMode(env)
  local v_pre_lin = reaper.ScaleFromEnvelopeMode(mode, v_pre)
  local v_post_lin = reaper.ScaleFromEnvelopeMode(mode, v_post)
  local v_t2 = reaper.ScaleToEnvelopeMode(mode, v_pre_lin * factor)
  local v_t3 = reaper.ScaleToEnvelopeMode(mode, v_post_lin * factor)

  -- remove points in range 
  if overwrite then
    reaper.DeleteEnvelopePointRange(env, t1, t4)
  end
  -- insert points based on baseline
  reaper.InsertEnvelopePointEx(env, -1, t1, v_pre, shape, 0, false, true)
  reaper.InsertEnvelopePointEx(env, -1, t2, v_t2, shape, 0, false, true)
  reaper.InsertEnvelopePointEx(env, -1, t3, v_t3, shape, 0, false, true)
  reaper.InsertEnvelopePointEx(env, -1, t4, v_post, shape, 0, false, true)
end

local function coalesce_segments(segments, times, pre_ms, post_ms, default_db)
  if #segments == 0 then return {} end
  local merged = {}
  -- Sort by start time 
  table.sort(segments, function(a,b) return a.start_idx < b.start_idx end)
  
  local cur_start_t = times[segments[1].start_idx]
  local cur_end_t = times[segments[1].end_idx]
  local cur_db = segments[1].reduction_db or default_db
  local pre = max(0, pre_ms/1000)
  local post = max(0, post_ms/1000)
  
  for i = 2, #segments do
    local next_s = segments[i]
    local next_db = next_s.reduction_db or default_db
    local next_start_t = times[next_s.start_idx]
    local next_end_t = times[next_s.end_idx]
    
    -- Check overlap including ramps
    if (cur_end_t + post) >= (next_start_t - pre) then
      cur_end_t = max(cur_end_t, next_end_t)
      cur_db = max(cur_db, next_db)
    else
      merged[#merged+1] = {cur_start_t, cur_end_t, cur_db}
      cur_start_t = next_start_t
      cur_end_t = next_end_t
      cur_db = next_db
    end
  end
  merged[#merged+1] = {cur_start_t, cur_end_t, cur_db}
  return merged
end

-- =========================================================================
-- 1. ZERO-ALLOCATION DSP ENGINE
-- =========================================================================

local function init_hunter_state(sr, cfg)
  local num_hops = max(1, floor(12 / 6)) -- Hardcoded window_ms=12, hop_ms=6
  local filter = biquad_new(rbj_highpass(cfg.target_freq or 6500, 0.707, sr))
  
  local hist = { wb = {}, band_max = {}, zcr = {} }
  for i = 1, num_hops do
    hist.wb[i], hist.band_max[i], hist.zcr[i] = 0.0, 0.0, 0
  end

  return {
    sr = sr, filter = filter, num_hops = num_hops,
    hist = hist, hist_idx = 1, prev_sign = 0,
    result = { ratio = 0.0, zcr = 0.0, level_db = -144.0 }
  }
end

local function process_window_zero_alloc(buf_table, Ns, ch, state)
  local hop_wb, hop_zcr = 0.0, 0
  local prev_sign = state.prev_sign
  local filter = state.filter
  local filter_energy = 0.0
  
  for i = 0, Ns-1 do
    local mono = 0.0
    for c = 0, ch-1 do mono = mono + buf_table[(i*ch)+c+1] end
    mono = mono / ch
    hop_wb = hop_wb + mono*mono
    
    local sign = (mono >= 0) and 1 or -1
    if i > 0 and sign ~= prev_sign then hop_zcr = hop_zcr + 1 end
    prev_sign = sign
    
    local y = biquad_process(filter, mono)
    filter_energy = filter_energy + y*y
  end
  state.prev_sign = prev_sign

  local idx = state.hist_idx
  state.hist.wb[idx], state.hist.band_max[idx], state.hist.zcr[idx] = hop_wb, filter_energy, hop_zcr
  
  state.hist_idx = idx + 1
  if state.hist_idx > state.num_hops then state.hist_idx = 1 end

  local sum_wb, sum_bmax, tot_zcr = 0.0, 0.0, 0
  for i = 1, state.num_hops do
    sum_wb = sum_wb + state.hist.wb[i]
    sum_bmax = sum_bmax + state.hist.band_max[i]
    tot_zcr = tot_zcr + state.hist.zcr[i]
  end

  local N_tot = Ns * state.num_hops
  local rms_wb = sqrt(sum_wb / max(1, N_tot))
  local rms_band = sqrt(sum_bmax / max(1, N_tot))

  state.result.ratio = (rms_band + 1e-12) / (rms_wb + 1e-12)
  state.result.zcr = tot_zcr / max(1, (N_tot - 1))
  state.result.level_db = amp_to_db(rms_wb)
  return state.result
end

local function init_analysis_job(item, cfg)
  local take = reaper.GetActiveTake(item); if not take then return nil end
  local src = reaper.GetMediaItemTake_Source(take); if not src then return nil end
  local sr = floor((reaper.GetMediaSourceSampleRate(src) or 48000) * (reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE") or 1.0) + 0.5)
  local ch = max(1, reaper.GetMediaSourceNumChannels(src) or 1)
  local accessor = reaper.CreateTakeAudioAccessor(take); if not accessor then return nil end

  local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  local item_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
  local pr = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE") or 1.0
  
  local hop_ms = 6
  local H = max(32, floor(sr * (hop_ms/1000)))
  local buf = reaper.new_array(H * ch)
  local state_obj = init_hunter_state(sr, cfg)
  
  local features = { levels = {}, ratios = {}, zcrs = {}, times = {}, amps = {} }
  return {
    item = item, accessor = accessor, sr = sr, ch = ch, pr = pr, H = H, buf = buf,
    state_obj = state_obj, features = features, item_pos = item_pos, item_len = item_len,
    t_rel = 0.0, max_amp = 0.0, progress = 0.0, cfg = cfg
  }
end

local function step_analysis_job(job, budget)
  local t0 = reaper.time_precise()
  while job.t_rel + (job.H/job.sr) <= job.item_len do
    job.buf.clear()
    reaper.GetAudioAccessorSamples(job.accessor, job.sr, job.ch, job.t_rel * job.pr, job.H, job.buf)
    local res = process_window_zero_alloc(job.buf.table(), job.H, job.ch, job.state_obj)
    
    local idx = #job.features.levels + 1
    local peak = db_to_amp(res.level_db)
    if peak > job.max_amp then job.max_amp = peak end
    
    job.features.levels[idx] = res.level_db
    job.features.ratios[idx] = res.ratio
    job.features.zcrs[idx] = res.zcr
    job.features.times[idx] = job.item_pos + job.t_rel
    job.features.amps[idx] = peak
    
    job.t_rel = job.t_rel + (job.H / job.sr)
    
    if reaper.time_precise() - t0 >= budget then
      job.progress = job.t_rel / job.item_len
      return false
    end
  end
  job.progress = 1.0
  return true
end

local function finish_analysis_job(job)
  if job.max_amp > 0 then
    local factor = 1.0 / job.max_amp
    for i = 1, #job.features.amps do
      job.features.amps[i] = job.features.amps[i] * factor
    end
  end
  reaper.DestroyAudioAccessor(job.accessor)
  return job.features, job.item_pos, job.item_len
end

local function cancel_analysis_job(job)
  if job and job.accessor then
    reaper.DestroyAudioAccessor(job.accessor)
  end
end

local function extract_features_single_pass(item, cfg)
  local job = init_analysis_job(item, cfg)
  if not job then return nil end
  while not step_analysis_job(job, 1.0) do end
  return finish_analysis_job(job)
end

local function median(t)
  if not t or #t == 0 then return 0 end
  local temp = {}
  for i=1,#t do temp[i] = t[i] end
  table.sort(temp)
  local half = math.floor(#temp / 2)
  if #temp % 2 == 0 then
    return (temp[half] + temp[half+1]) / 2.0
  else
    return temp[half+1]
  end
end

local function detect_segments_from_features(features, cfg)
  local med_lvl = median(features.levels)
  local min_level_use = max(cfg.min_level_db, (med_lvl or cfg.min_level_db) - 12.0)
  
  local valid_ratios = {}
  for i=1,#features.levels do if features.levels[i] > min_level_use then valid_ratios[#valid_ratios+1] = features.ratios[i] end end
  if #valid_ratios == 0 then valid_ratios = features.ratios end
  
  local med_ratio = min(median(valid_ratios), 0.55)
  local delta_on = 0.08
  local delta_off = 0.05
  local thr_on = med_ratio + delta_on
  local thr_off = med_ratio + delta_off
  local hop_ms = 6
  
  local sens = cfg.fricative_sens or 50.0
  local zcr_thresh = 0.05 + ((100.0 - sens) / 100.0) * 0.20

  local inS = false
  local seg_start_idx = 0
  local gap_run_ms = 0
  local segments = {}
  local r_prev1, r_prev2 = 0.0, 0.0

  for i=1,#features.levels do
    local r_s = features.ratios[i]
    if i > 2 then r_s = 0.6*features.ratios[i] + 0.3*r_prev1 + 0.1*r_prev2
    elseif i > 1 then r_s = 0.75*features.ratios[i] + 0.25*r_prev1 end
    r_prev2, r_prev1 = r_prev1, features.ratios[i]

    local pass_on = (features.levels[i] > min_level_use) and (r_s >= thr_on) and (features.zcrs[i] >= zcr_thresh)
    local pass_off = (features.ratios[i] <= thr_off) or (features.zcrs[i] < zcr_thresh)

    if pass_on then
      if not inS then inS = true; seg_start_idx = i end
      gap_run_ms = 0
    else
      if inS then
        gap_run_ms = gap_run_ms + hop_ms
        if pass_off and gap_run_ms >= cfg.max_gap_ms then
          local end_idx = i
          if (end_idx - seg_start_idx) * hop_ms >= cfg.min_seg_ms then
            segments[#segments+1] = {start_idx = seg_start_idx, end_idx = end_idx, reduction_db = cfg.reduction_db}
          end
          inS = false; gap_run_ms = 0
        end
      end
    end
  end
  if inS then
    local end_idx = #features.levels
    if (end_idx - seg_start_idx) * hop_ms >= cfg.min_seg_ms then
      segments[#segments+1] = {start_idx = seg_start_idx, end_idx = end_idx, reduction_db = cfg.reduction_db}
    end
  end
  return segments, med_ratio, min_level_use
end

local analysis_cache = nil
local preview_job    = nil

local function preview_start(cfg)
  if preview_job then cancel_analysis_job(preview_job) end
  local item = reaper.GetSelectedMediaItem(0, 0)
  if not item then state.msg = 'Select one item'; return end
  preview_job = init_analysis_job(item, cfg)
  if preview_job then
    state.msg = 'Analysis started...'
  else
    state.msg = 'Analysis failed: no take, no audio source, or accessor error.'
  end
end

local function preview_cancel()
  if preview_job then
    cancel_analysis_job(preview_job)
    preview_job = nil
    state.msg = 'Analysis canceled.'
  end
end

local function preview_cleanup(msg) end

local function preview_step(budget_seconds)
  if not preview_job then return end
  if step_analysis_job(preview_job, budget_seconds) then
    local features, ipos, ilen = finish_analysis_job(preview_job)
    local cfg = preview_job.cfg
    local item = preview_job.item
    preview_job = nil
    if features then
      local segs = detect_segments_from_features(features, cfg)
      analysis_cache = {
        item = item, item_pos = ipos, item_len = ilen,
        segments = segs, amps = features.amps, times = features.times
      }
      state.msg = string.format('Preview: %d segments detected', #segs)
      if state.live_edit then apply_cached_segments(state) end
    else
      state.msg = 'Analysis failed during processing.'
    end
  end
end

local function analyze_item_and_reduce(item, cfg)
  local features, ep_pos, ep_len = extract_features_single_pass(item, cfg)
  if not features then return 0 end
  local segments = detect_segments_from_features(features, cfg)
  
  local track = reaper.GetMediaItem_Track(item)
  local env, is_take_env = get_target_envelope(track, item, cfg.target_mode or (cfg.use_prefx and 1 or 0))
  if not env then return 0 end

  local take = reaper.GetActiveTake(item)
  local pr = take and reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE") or 1.0
  local soffs = take and reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS") or 0.0

  clear_previous_segments(env, track, item, ep_pos, soffs, pr, is_take_env)

  reaper.PreventUIRefresh(1)
  local factor = db_to_amp(-cfg.reduction_db)
  local merged = coalesce_segments(segments, features.times, cfg.pre_ramp_ms, cfg.post_ramp_ms, cfg.reduction_db)
  for _, seg in ipairs(merged) do
    insert_reduction_points(env, seg[1], seg[2], db_to_amp(-(seg[3] or cfg.reduction_db)), cfg.pre_ramp_ms, cfg.post_ramp_ms, true, ep_pos, soffs, pr, is_take_env)
  end
  save_segments(track, item, merged, cfg.pre_ramp_ms, cfg.post_ramp_ms)
  reaper.Envelope_SortPoints(env)
  reaper.PreventUIRefresh(-1)
  
  return #segments
end

local function apply_cached_segments(cfg)
  if not analysis_cache or not analysis_cache.item then state.msg = 'No preview cached'; return end
  local item = analysis_cache.item
  if not is_valid_item(item) then
    state.msg = 'Item changed, run Analyze (Preview) again'
    analysis_cache = nil
    return
  end
  local track = reaper.GetMediaItem_Track(item)
  local env, is_take_env = get_target_envelope(track, item, cfg.target_mode or (cfg.use_prefx and 1 or 0))
  if not env then state.msg = 'Cannot access envelope'; return end
  
  local take = reaper.GetActiveTake(item)
  local pr = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE") or 1.0
  local start_offs = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS") or 0.0
  
  local ep_pos = is_take_env and reaper.GetMediaItemInfo_Value(item, "D_POSITION") or 0.0
  local ep_offs = is_take_env and start_offs or 0.0
  local ep_rate = is_take_env and pr or 1.0

  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)
  clear_previous_segments(env, track, item, ep_pos, ep_offs, ep_rate, is_take_env)
  local merged_segments = coalesce_segments(analysis_cache.segments, analysis_cache.times, cfg.pre_ramp_ms, cfg.post_ramp_ms, cfg.reduction_db)
  for i=1,#merged_segments do
    local s = merged_segments[i]
    local seg_factor = factor
    if s[3] then
      seg_factor = db_to_amp(-s[3])
    end
    insert_reduction_points(env, s[1], s[2], seg_factor, cfg.pre_ramp_ms, cfg.post_ramp_ms, true, ep_pos, ep_offs, ep_rate, is_take_env)
  end
  save_segments(track, item, merged_segments, cfg.pre_ramp_ms, cfg.post_ramp_ms)
  reaper.Envelope_SortPoints(env)
  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock('Floop Ess Hunter: apply segments from preview', -1)
  reaper.UpdateArrange()
  state.msg = string.format('Applied %d segments from preview', #analysis_cache.segments)
end

local function clear_segments_for_selection()
  local cnt = reaper.CountSelectedMediaItems(0)
  if cnt == 0 then state.msg = "Select at least one item to clear segments"; return end
  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)
  local cleared_count = 0
  for i = 0, cnt - 1 do
    local item = reaper.GetSelectedMediaItem(0, i)
    local track = reaper.GetMediaItem_Track(item)
    local env, is_take_env = get_target_envelope(track, item, state.target_mode or (state.use_prefx and 1 or 0))
    if env then
      local take = reaper.GetActiveTake(item)
      local pr = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE") or 1.0
      local start_offs = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS") or 0.0
      
      local ep_pos = is_take_env and reaper.GetMediaItemInfo_Value(item, "D_POSITION") or 0.0
      local ep_offs = is_take_env and start_offs or 0.0
      local ep_rate = is_take_env and pr or 1.0
      
      clear_previous_segments(env, track, item, ep_pos, ep_offs, ep_rate, is_take_env)
      
      local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
      local item_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
      
      
      local range_t1 = item_pos
      local range_t2 = item_pos + item_len
      
      if is_take_env then
        range_t1 = (range_t1 - ep_pos) * ep_rate + start_offs
        range_t2 = (range_t2 - ep_pos) * ep_rate + start_offs
      end
      
      reaper.DeleteEnvelopePointRange(env, range_t1, range_t2)
      reaper.Envelope_SortPoints(env)
      -- Clear ExtState data
      local key = make_key(track, item)
      reaper.SetProjExtState(0, EXT_NS, key, '')
      cleared_count = cleared_count + 1
    end
  end
  if cleared_count > 0 then
    reaper.UpdateArrange()
    state.msg = string.format('Cleared segments for %d item(s)', cleared_count)
  else
    state.msg = 'No segments to clear'
  end
  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock('Floop Ess Hunter: clear segments', -1)
end

local function apply_on_selection()
  local cnt = reaper.CountSelectedMediaItems(0)
  if cnt == 0 then state.msg = 'Select at least one item'; return end
  reaper.Undo_BeginBlock()
  local total_segs = 0
  for i = 0, cnt - 1 do
    local item = reaper.GetSelectedMediaItem(0, i)
    total_segs = total_segs + analyze_item_and_reduce(item, state)
  end
  reaper.UpdateArrange()
  reaper.Undo_EndBlock('Floop Ess Hunter: apply on selection', -1)
  state.msg = string.format('Applied to %d items (total %d segments)', cnt, total_segs)
end

-- =========================================================================
-- 2.New User Interface
-- =========================================================================

local function draw_waveform_panel()
  local W_avail, H_avail = reaper.ImGui_GetContentRegionAvail(ctx)
  local W = math.max(420, W_avail)
  local H = 200
  local x0, y0 = reaper.ImGui_GetCursorScreenPos(ctx)
  local cx, cy = reaper.ImGui_GetCursorPos(ctx)
  
  local flags = reaper.ImGui_ButtonFlags_MouseButtonLeft() | reaper.ImGui_ButtonFlags_MouseButtonRight() | reaper.ImGui_ButtonFlags_MouseButtonMiddle()
  reaper.ImGui_InvisibleButton(ctx, '##waveform_panel', W, H, flags)
  local hovered = reaper.ImGui_IsItemHovered(ctx)
  local dl = reaper.ImGui_GetWindowDrawList(ctx)
  
  reaper.ImGui_DrawList_AddRectFilled(dl, x0, y0, x0 + W, y0 + H, 0x15191DFF)
  reaper.ImGui_DrawList_AddRect(dl, x0, y0, x0 + W, y0 + H, 0x3A3A3AFF)

  if preview_job then
    local progress = preview_job.progress or 0.0
    local bar_w = W * 0.6
    local bar_h = 20
    local bar_x = x0 + (W - bar_w) * 0.5
    local bar_y = y0 + (H - bar_h) * 0.5

    reaper.ImGui_DrawList_AddRectFilled(dl, bar_x, bar_y, bar_x + bar_w, bar_y + bar_h, 0x00000088, 4.0)
    reaper.ImGui_DrawList_AddRectFilled(dl, bar_x, bar_y, bar_x + (bar_w * progress), bar_y + bar_h, 0x14B8A6FF, 4.0)
    local txt = string.format("Scanning... %d%%", math.floor(progress * 100))
    local tw, th = reaper.ImGui_CalcTextSize(ctx, txt)
    reaper.ImGui_DrawList_AddText(dl, bar_x + (bar_w - tw) * 0.5, bar_y + (bar_h - th) * 0.5, 0xFFFFFFFF, txt)
  end

  local mx, my = reaper.ImGui_GetMousePos(ctx)
  local wheel = reaper.ImGui_GetMouseWheel(ctx)
  local ctrl_down = mod_ctrl()
  local wave_top = y0
  local wave_h = H
  local wave_scale = 0.90

  -- GLOBAL FALLBACK 
  if not reaper.ImGui_IsMouseDown(ctx, 0) and not reaper.ImGui_IsMouseReleased(ctx, 0) then
    state.drag_seg_index = nil
    state.drag_edge = 0
    state.drag_seg_vol_index = nil
    state.drag_threshold = false
    state.new_seg_active = false
  end

  if analysis_cache and analysis_cache.amps and #analysis_cache.amps > 0 then
    local view_start = state.view_start_frac or 0.0
    local view_len = state.view_len_frac or 1.0

    if hovered and wheel ~= 0 then
      if ctrl_down then
        local step = 0.25 * view_len
        view_start = view_start - (wheel * step)
      else
        local cursor_frac = (mx - x0) / W
        local factor = math.exp(-wheel * 0.1)
        local new_len = math.max(0.05, math.min(1.0, view_len * factor))
        view_start = view_start + cursor_frac * (view_len - new_len)
        view_len = new_len
      end
      if view_start < 0 then view_start = 0 end
      if view_start + view_len > 1.0 then view_start = 1.0 - view_len end
      state.view_start_frac = view_start
      state.view_len_frac = view_len
    end

    if reaper.ImGui_IsMouseDown(ctx, 2) then -- Middle click drag
      local dx, dy = reaper.ImGui_GetMouseDelta(ctx)
      if dx ~= 0 then
        local delta = (dx / W) * view_len
        view_start = view_start - delta
        if view_start < 0 then view_start = 0 end
        if view_start + view_len > 1.0 then view_start = 1.0 - view_len end
        state.view_start_frac = view_start
      end
    end

    local vis_t0 = analysis_cache.item_pos + view_start * analysis_cache.item_len
    local vis_len = view_len * analysis_cache.item_len
    local vis_t1 = vis_t0 + vis_len
    local mid = wave_top + wave_h / 2

    local n = #analysis_cache.amps
    local stride = math.max(1, math.floor(n / W))
    for i = 1, n, stride do
      local t = analysis_cache.times[i]
      if t >= vis_t0 and t <= vis_t1 then
        local x = x0 + ((t - vis_t0) / vis_len) * W
        if x >= x0 and x <= x0 + W then
          local a = math.min(1.0, analysis_cache.amps[i])
          local y = a * (wave_h * wave_scale * 0.5)
          reaper.ImGui_DrawList_AddLine(dl, x, mid - y, x, mid + y, 0xBFC7CDAA, 1.0)
        end
      end
    end

    local hop_sec_cache = (state.hop_ms or 6) / 1000.0
    local function time_to_index(t)
      local rel_pos = (t - analysis_cache.item_pos) / hop_sec_cache
      local approx = math.floor(rel_pos + 0.5) + 1
      if approx < 1 then approx = 1 end
      if approx > n then approx = n end
      return approx
    end

    local seg_col = 0x10B981AA
    local handle_size = 12
    local handle_margin = 2
    local is_mouse_over_any_segment = false

    for i = 1, #analysis_cache.segments do
      local s = analysis_cache.segments[i]
      local s_t1 = analysis_cache.times[s.start_idx]
      local s_t2 = analysis_cache.times[s.end_idx]
      local x1 = x0 + ((math.max(s_t1, vis_t0) - vis_t0) / vis_len) * W
      local x2 = x0 + ((math.min(s_t2, vis_t1) - vis_t0) / vis_len) * W

      if x2 > x1 and x2 >= x0 and x1 <= x0 + W then
        x1 = math.max(x0, x1); x2 = math.min(x0 + W, math.max(x1 + 1.0, x2))
        
        if hovered and mx >= x1 and mx <= x2 and my >= wave_top and my <= wave_top + wave_h then
          is_mouse_over_any_segment = true
        end
        
        reaper.ImGui_DrawList_AddRectFilled(dl, x1, wave_top, x2, wave_top + wave_h, seg_col)
        reaper.ImGui_DrawList_AddLine(dl, x1, wave_top, x1, wave_top + wave_h, (seg_col & 0xFFFFFF00) | 0xFF, 1.0)
        reaper.ImGui_DrawList_AddLine(dl, x2, wave_top, x2, wave_top + wave_h, (seg_col & 0xFFFFFF00) | 0xFF, 1.0)

        local h_x1 = x1 + handle_margin
        local h_y1 = wave_top + wave_h - handle_size - handle_margin
        local is_handle_hovered = hovered and (mx >= h_x1 and mx <= h_x1 + handle_size and my >= h_y1 and my <= h_y1 + handle_size)

        if is_handle_hovered and reaper.ImGui_IsMouseClicked(ctx, 0) then
          state.drag_seg_vol_index = i
          state.drag_vol_start_y = my
          state.drag_vol_start_val = s.reduction_db or state.reduction_db
        elseif is_handle_hovered and reaper.ImGui_IsMouseClicked(ctx, 1) then
          table.remove(analysis_cache.segments, i)
          if state.live_edit then apply_cached_segments(state) end
          break
        end

        local is_dragging = (state.drag_seg_vol_index == i)
        if is_dragging then
          s.reduction_db = math.max(0, math.min(24, state.drag_vol_start_val + (state.drag_vol_start_y - my) / 5.0))
        end

        local handle_col = (is_handle_hovered or is_dragging) and 0xFFFFFFFF or 0xBFC7CDAA
        reaper.ImGui_DrawList_AddRectFilled(dl, h_x1, h_y1, h_x1 + handle_size, h_y1 + handle_size, handle_col, 2.0)
        reaper.ImGui_DrawList_AddText(dl, h_x1, h_y1 - 14, 0xFFFFFFCC, string.format('%.1f', s.reduction_db or state.reduction_db))

        if hovered and my >= wave_top and my <= wave_top + wave_h and not is_handle_hovered and not state.drag_seg_vol_index then
          if (not state.drag_edge or state.drag_edge == 0) and ctrl_down then
            if math.abs(mx - x1) <= 6 then
              reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_ResizeEW())
              if reaper.ImGui_IsMouseClicked(ctx, 0) then state.drag_seg_index = i; state.drag_edge = 1 end
            elseif math.abs(mx - x2) <= 6 then
              reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_ResizeEW())
              if reaper.ImGui_IsMouseClicked(ctx, 0) then state.drag_seg_index = i; state.drag_edge = 2 end
            end
          end
        end

        if state.drag_seg_index == i and state.drag_edge ~= 0 then
          reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_ResizeEW())
          local new_t = vis_t0 + math.max(0, math.min(1, (mx - x0) / W)) * vis_len
          local new_idx = time_to_index(new_t)
          if state.drag_edge == 1 then s.start_idx = math.min(new_idx, s.end_idx - 1) else s.end_idx = math.max(new_idx, s.start_idx + 1) end
        end
      end
    end
    
    local thr_amp = db_to_amp(state.min_level_db)
    if thr_amp and thr_amp > 0 then
      local y_thr = thr_amp * (wave_h * wave_scale * 0.5)
      local col = 0xBFC7CDFF
      reaper.ImGui_DrawList_AddLine(dl, x0, mid - y_thr, x0+W, mid - y_thr, col, 1.5)
      reaper.ImGui_DrawList_AddLine(dl, x0, mid + y_thr, x0+W, mid + y_thr, col, 1.5)
      if hovered then
        local near_thr = (math.abs(my - (mid + y_thr)) <= 8) or (math.abs(my - (mid - y_thr)) <= 8)
        if not state.drag_threshold and near_thr and reaper.ImGui_IsMouseClicked(ctx, 0) then
          state.drag_threshold = true
        end
      end
      if state.drag_threshold then
        local dy = math.abs(my - mid)
        local new_amp = dy / (wave_h * wave_scale * 0.5)
        local new_db = amp_to_db(math.max(0, math.min(1, new_amp)))
        state.min_level_db = math.max(-60, math.min(-20, new_db))
      end
    end

    if hovered and my >= wave_top and my <= wave_top+wave_h then
       local guide_x = mx
       if guide_x >= x0 and guide_x <= x0+W then
         reaper.ImGui_DrawList_AddLine(dl, guide_x, wave_top, guide_x, wave_top+wave_h, 0xFFFFFF44, 1.0)
       end
    end

    -- New segment logic with Left Click + Ctrl
    if hovered and ctrl_down and not is_mouse_over_any_segment and not state.new_seg_active and not state.drag_seg_index and not state.drag_seg_vol_index then
      if reaper.ImGui_WantCaptureMouse then reaper.ImGui_WantCaptureMouse(ctx, true) end
      if reaper.ImGui_IsMouseClicked(ctx, 0) then
        state.new_seg_start_t = vis_t0 + math.max(0, math.min(1, (mx - x0) / W)) * vis_len
        state.new_seg_end_t = state.new_seg_start_t
        state.new_seg_active = true
      end
    end

    if state.new_seg_active then
      if reaper.ImGui_WantCaptureMouse then reaper.ImGui_WantCaptureMouse(ctx, true) end
      reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_ResizeEW())
      state.new_seg_end_t = vis_t0 + math.max(0, math.min(1, (mx - x0) / W)) * vis_len
      local x1 = x0 + ((math.max(state.new_seg_start_t, vis_t0) - vis_t0) / vis_len) * W
      local x2 = x0 + ((math.min(state.new_seg_end_t, vis_t1) - vis_t0) / vis_len) * W
      if x2 < x1 then x1, x2 = x2, x1 end
      reaper.ImGui_DrawList_AddRectFilled(dl, x1, wave_top, x2, wave_top+wave_h, 0x10B98155)
    end
    
    -- Handle mouse up (apply all edit ends)
    if reaper.ImGui_IsMouseReleased(ctx, 0) then
       local apply_needed = false
       if state.drag_seg_vol_index then apply_needed = true end
       if state.drag_seg_index then apply_needed = true end
       if state.new_seg_active then
         local t1 = math.min(state.new_seg_start_t or vis_t0, state.new_seg_end_t or vis_t0)
         local t2 = math.max(state.new_seg_start_t or vis_t0, state.new_seg_end_t or vis_t0)
         local start_idx = time_to_index(t1)
         local end_idx = time_to_index(t2)
         if end_idx > start_idx and (end_idx - start_idx) * hop_sec_cache * 1000 >= (state.min_seg_ms or 25) then
           analysis_cache.segments[#analysis_cache.segments+1] = { start_idx = start_idx, end_idx = end_idx, reduction_db = state.reduction_db }
           apply_needed = true
         end
       end
       state.drag_seg_vol_index = nil
       state.drag_seg_index = nil
       state.drag_edge = 0
       state.drag_threshold = false
       state.new_seg_active = false
       if apply_needed and state.live_edit then apply_cached_segments(state) end
    end

    if hovered and reaper.ImGui_IsMouseDown(ctx, 0) and not ctrl_down then
      local is_drag_action = (state.drag_seg_index and state.drag_seg_index >= 0) or state.drag_threshold or (state.drag_seg_vol_index and state.drag_seg_vol_index >= 0)
      if not is_drag_action then
         reaper.SetEditCurPos(vis_t0 + math.max(0, math.min(1, (mx - x0) / W)) * vis_len, true, false)
      end
    end
    
    local play_state = reaper.GetPlayState()
    if (play_state & 1) == 1 then
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
  else
    if not preview_job then
      local msg = "No Analysis Data. Select an item and click 'Analyze'."
      local tw, th = reaper.ImGui_CalcTextSize(ctx, msg)
      reaper.ImGui_DrawList_AddText(dl, x0 + (W - tw) * 0.5, y0 + (H - th) * 0.5, 0xF7FAFCFF, msg)
    end
  end
  
  reaper.ImGui_SetCursorPos(ctx, cx, cy + H + 4)
  reaper.ImGui_TextDisabled(ctx, "Controls: Wheel=Zoom, MClick/Ctrl+Wheel=Pan, LClick/Drag=Scrub, Ctrl+LDrag=New, Ctrl+Edges=Resize")
end

-- Renders a dynamic switch button. Returns (toggled_boolean, clicked_boolean)
local function DrawToggle(ctx, label, value, active_color, inactive_color, knob_color)
  local x, y = reaper.ImGui_GetCursorScreenPos(ctx)
  local dl = reaper.ImGui_GetWindowDrawList(ctx)

  local height = reaper.ImGui_GetFrameHeight(ctx) * 0.6
  local width = height * 1.8
  local radius = height * 0.5
  local y_offset = (reaper.ImGui_GetFrameHeight(ctx) - height) * 0.5

  local clicked = reaper.ImGui_InvisibleButton(ctx, "##" .. label, width, height + y_offset)
  local toggled = value
  if clicked then
    toggled = not toggled
  end

  local col_bg_off = inactive_color or 0x555555FF
  local col_bg_on  = active_color or (Theme and Theme.GetColor and Theme.GetColor("accent")) or 0x14B8A6FF
  local col_knob   = knob_color or 0xFFFFFFFF

  local bg_col     = toggled and col_bg_on or col_bg_off
  reaper.ImGui_DrawList_AddRectFilled(dl, x, y + y_offset, x + width, y + height + y_offset, bg_col, radius)

  local t = toggled and 1.0 or 0.0
  local knob_x = x + radius + t * (width - radius * 2)
  reaper.ImGui_DrawList_AddCircleFilled(dl, knob_x, y + y_offset + radius, radius * 0.8, col_knob)

  reaper.ImGui_SameLine(ctx)
  reaper.ImGui_Text(ctx, label)
  return toggled, clicked
end

local function get_preset_default(id, fallback)
  if state.preset_index and state.preset_index > 0 and PRESETS and PRESETS[state.preset_index] then
    local p = PRESETS[state.preset_index].values
    if p and p[id] ~= nil then return p[id] end
  elseif state.selected_custom_index and state.selected_custom_index > 0 then
    local names = list_custom_presets()
    local name = names[state.selected_custom_index]
    if name then
      local ok, ser = reaper.GetProjExtState(0, EXT_NS, 'preset:'..name)
      if ok > 0 and ser and ser ~= '' then
        local v = deserialize_preset_values(ser)
        if v and v[id] ~= nil then return v[id] end
      end
    end
  end
  return fallback
end

local function slider_labeled_int(id, label, v, vmin, vmax, width, suffix, default_val)
  if width then reaper.ImGui_SetNextItemWidth(ctx, width) end
  local changed, nv = ImGui.SliderInt(ctx, '##'..id, v, vmin, vmax)
  if reaper.ImGui_IsItemClicked(ctx, 1) and default_val then
    nv = get_preset_default(id, default_val)
    changed = true
  end
  local x1, y1 = reaper.ImGui_GetItemRectMin(ctx)
  local x2, y2 = reaper.ImGui_GetItemRectMax(ctx)
  local h = y2 - y1
  local dl = reaper.ImGui_GetWindowDrawList(ctx)
  local fs = reaper.ImGui_GetFontSize(ctx)
  local ty = y1 + (h - fs) * 0.5
  -- Left label
  reaper.ImGui_DrawList_AddText(dl, x1 + 8, ty, 0xBFC7CDFF, label)
  -- Right value
  local val_str = tostring(nv) .. (suffix or '')
  local tw = select(1, reaper.ImGui_CalcTextSize(ctx, val_str))
  reaper.ImGui_DrawList_AddText(dl, x2 - tw - 8, ty, 0xF7FAFCFF, val_str)
  if changed and state then state.last_change_time = reaper.time_precise() end
  return changed, nv
end

local function slider_labeled_float(id, label, v, vmin, vmax, width, fmt, suffix, default_val)
  if width then reaper.ImGui_SetNextItemWidth(ctx, width) end
  local changed, nv = ImGui.SliderFloat(ctx, '##'..id, v, vmin, vmax)
  if reaper.ImGui_IsItemClicked(ctx, 1) and default_val then
    nv = get_preset_default(id, default_val)
    changed = true
  end
  local x1, y1 = reaper.ImGui_GetItemRectMin(ctx)
  local x2, y2 = reaper.ImGui_GetItemRectMax(ctx)
  local h = y2 - y1
  local dl = reaper.ImGui_GetWindowDrawList(ctx)
  local fs = reaper.ImGui_GetFontSize(ctx)
  local ty = y1 + (h - fs) * 0.5
  -- Left label
  reaper.ImGui_DrawList_AddText(dl, x1 + 8, ty, 0xBFC7CDFF, label)
  -- Right value
  local val_str
  if fmt then
    val_str = string.format(fmt, nv)
  else
    val_str = string.format('%.2f', nv)
  end
  val_str = val_str .. (suffix or '')
  local tw = select(1, reaper.ImGui_CalcTextSize(ctx, val_str))
  reaper.ImGui_DrawList_AddText(dl, x2 - tw - 8, ty, 0xF7FAFCFF, val_str)
  if changed and state then state.last_change_time = reaper.time_precise() end
  return changed, nv
end
-- UI: main loop
local function loop()
  -- Perf: step preview with a small time budget per frame
  if preview_job then preview_step(0.008) end
  
  if not preview_job and state.live_edit and state.last_change_time_vol then
    local now = reaper.time_precise()
    if not state.last_auto_analyze_vol or state.last_auto_analyze_vol < state.last_change_time_vol then
      if now - state.last_change_time_vol > 0.05 then
        apply_cached_segments(state)
        state.last_auto_analyze_vol = now
      end
    end
  end

  if not preview_job and (state.auto_analyze or state.live_edit) and state.last_change_time then
    local now = reaper.time_precise()
    if not state.last_auto_analyze or state.last_auto_analyze < state.last_change_time then
      if now - state.last_change_time > 0.35 then
        preview_start(state)
        if state.live_edit then apply_cached_segments(state) end
        state.last_auto_analyze = now
      end
    end
  end
  ImGui.SetNextWindowSize(ctx,700, 680, ImGui.Cond_Appearing())
  local color_count = apply_theme()
local visible, open = ImGui.Begin(ctx, 'Floop Ess Hunter', true, ImGui.WindowFlags_NoCollapse())
  if visible then
    -- Keyboard shortcuts: Space to Play/Stop
    if reaper.ImGui_IsWindowFocused(ctx) and reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Space()) then
      reaper.Main_OnCommand(40044, 0) -- Transport: Play/Stop
    end

    -- UI: presets row above waveform
    reaper.ImGui_SeparatorText(ctx, 'PRESETS')
    ImGui.Text(ctx, 'Preset')
    ImGui.SameLine(ctx, nil, 8)
    local names = list_custom_presets()
    local preview
    if state.preset_index>0 then
      preview = PRESETS[state.preset_index].name
    elseif state.selected_custom_index>0 then
      preview = names[state.selected_custom_index] or 'None'
    else
      preview = 'None'
    end
    reaper.ImGui_SetNextItemWidth(ctx, 180)
    if ImGui.BeginCombo(ctx, '##combined_preset', preview) then
      reaper.ImGui_SeparatorText(ctx, 'Default presets')
      for i=1,#PRESETS do
        local sel = (state.preset_index == i)
        if ImGui.Selectable(ctx, PRESETS[i].name, sel) then
          state.preset_index = i
          state.selected_custom_index = 0
          apply_preset(PRESETS[i])
        end
      end
      reaper.ImGui_Separator(ctx)
      reaper.ImGui_SeparatorText(ctx, 'User presets')
      if #names == 0 then
        ImGui.Text(ctx, 'No user presets')
      else
        for i=1,#names do
          local sel = (state.selected_custom_index == i)
          if ImGui.Selectable(ctx, names[i], sel) then
            state.selected_custom_index = i
            state.preset_index = 0
            load_custom_preset(names[i])
          end
        end
      end
      ImGui.EndCombo(ctx)
    end
    ImGui.SameLine(ctx, nil, 6)
    -- Use dynamic frame height to keep button text vertically centered
    local preset_btn_h = reaper.ImGui_GetFrameHeight(ctx)
    if ImGui.Button(ctx, 'Del', 46, preset_btn_h) then
      if state.selected_custom_index>0 then
        delete_custom_preset(names[state.selected_custom_index])
        state.selected_custom_index = 0
      end
    end
    ImGui.SameLine(ctx, nil, 10)
    ImGui.Text(ctx, 'Save as')
    ImGui.SameLine(ctx, nil, 6)
    reaper.ImGui_SetNextItemWidth(ctx, 140)
    local changed
    changed, state.custom_preset_name = ImGui.InputText(ctx, '##preset_name', state.custom_preset_name)
    ImGui.SameLine(ctx, nil, 6)
    if ImGui.Button(ctx, 'Save', 60, preset_btn_h) then
      local name = (state.custom_preset_name or ''):gsub('^%s+', ''):gsub('%s+$', '')
      if name ~= '' then
        save_custom_preset(name)
        state.custom_preset_name = ''
        local nn = list_custom_presets()
        for i=1,#nn do if nn[i] == name then state.selected_custom_index = i break end end
      end
    end
  reaper.ImGui_Dummy(ctx, 0, 8)
    -- UI: waveform preview & actions
     reaper.ImGui_SeparatorText(ctx, 'WAVEFORM PREVIEW')
      
    local changed
    if not preview_job then
      if ImGui.Button(ctx, 'Analyze (Preview)', 180, 28) then preview_start(state) end
    else
      if ImGui.Button(ctx, 'Cancel Analysis', 180, 28) then preview_cancel() end
    end
    ImGui.SameLine(ctx, nil, 12)
    do
      local apply_disabled = (not analysis_cache or not analysis_cache.segments or #analysis_cache.segments==0)
      if apply_disabled then
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x3A3A3A88)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x3A3A3AAA)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), 0x3A3A3ACC)
      end
      local clicked = ImGui.Button(ctx, 'Apply', 120, 28)
      if apply_disabled then
        reaper.ImGui_PopStyleColor(ctx, 3)
        if reaper.ImGui_IsItemHovered(ctx) then
          reaper.ImGui_SetTooltip(ctx, 'Run Analyze (Preview) first')
        end
      else
        if clicked then apply_cached_segments(state) end
      end
    end
    ImGui.SameLine(ctx, nil, 16)
    
    state.live_edit, changed = DrawToggle(ctx, 'Live Edit', state.live_edit)
    if reaper.ImGui_IsItemHovered(ctx) then
      reaper.ImGui_SetTooltip(ctx, 'Apply envelope changes immediately when releasing mouse drag')
    end
    ImGui.SameLine(ctx, nil, 16)
    state.auto_analyze, changed = DrawToggle(ctx, 'Auto-analyze', state.auto_analyze)
    if reaper.ImGui_IsItemHovered(ctx) then
      reaper.ImGui_SetTooltip(ctx, 'Automatically re-run analysis when parameters change')
    end
    reaper.ImGui_Dummy(ctx, 0, 4)
    draw_waveform_panel()
    
   
reaper.ImGui_Dummy(ctx, 0, 4)
    -- UI: volume reduction controls & actions
    reaper.ImGui_SetNextItemWidth(ctx, 160)
    
    local changed_vol = false
    changed_vol, state.reduction_db = ImGui.SliderFloat(ctx, '##reduction_db', state.reduction_db, 0.0, 12.0, '%.1f')
    if reaper.ImGui_IsItemClicked(ctx, 1) then
      state.reduction_db = get_preset_default('reduction_db', 6.0)
      changed_vol = true
    end
    if changed_vol then 
      state.last_change_time_vol = reaper.time_precise()
      if analysis_cache and analysis_cache.segments then
         for i=1,#analysis_cache.segments do
            analysis_cache.segments[i].reduction_db = state.reduction_db
         end
      end
    end
    
    if reaper.ImGui_IsItemHovered(ctx) then
      reaper.ImGui_SetTooltip(ctx, 'Reduction in dB')
    end
    ImGui.SameLine(ctx, nil, 8)
    ImGui.Text(ctx, 'Reduction (dB)')
    ImGui.SameLine(ctx, nil, 12)
    reaper.ImGui_SetNextItemWidth(ctx, 150)
    local tm_preview = "Track Vol"
    if state.target_mode == 1 then tm_preview = "Track Pre-FX"
    elseif state.target_mode == 2 then tm_preview = "Take Vol" end
    
    if ImGui.BeginCombo(ctx, '##target_mode', tm_preview) then
      if ImGui.Selectable(ctx, 'Track Volume', state.target_mode == 0) then state.target_mode = 0 end
      if ImGui.Selectable(ctx, 'Track Pre-FX', state.target_mode == 1) then state.target_mode = 1 end
      if ImGui.Selectable(ctx, 'Take Volume', state.target_mode == 2) then state.target_mode = 2 end
      ImGui.EndCombo(ctx)
    end
    if reaper.ImGui_IsItemHovered(ctx) then
      reaper.ImGui_SetTooltip(ctx, 'Select which envelope to automate')
    end
    reaper.ImGui_Dummy(ctx, 0, 4)
    if ImGui.Button(ctx, 'Analyze and apply', 200, 30) then apply_on_selection() end
    ImGui.SameLine(ctx, nil, 12)
    if ImGui.Button(ctx, 'Clear segments on selection', 220, 30) then clear_segments_for_selection() end
    ImGui.SameLine(ctx, nil, 12)
    -- Help button inline next to Clear, with green accent style
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x14B8A6FF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x0F766EFF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), 0x0D9488FF)
    if reaper.ImGui_Button(ctx, "Help", 80, 30) then
      reaper.ImGui_OpenPopup(ctx, "Help")
    end
    reaper.ImGui_PopStyleColor(ctx, 3)
    reaper.ImGui_Dummy(ctx, 0, 18)
    -- Make collapsing header background fully transparent (no bg color)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Header(), 0x00000000)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderHovered(), 0x00000000)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderActive(), 0x00000000)
    -- Explicitly use the variant without a close button (p_open = nil)
local adv_open = reaper.ImGui_CollapsingHeader(ctx, 'ADVANCED SETTINGS', nil, 0)
    reaper.ImGui_PopStyleColor(ctx, 3)
    if adv_open then
   
    -- UI: three parameter columns, labeled sliders
    local availW = select(1, reaper.ImGui_GetContentRegionAvail(ctx))
    local spacing = 16
    local colW = math.max(200, math.floor((availW - spacing*2) / 3))

    -- UI: Analysis column
    reaper.ImGui_BeginGroup(ctx)
    reaper.ImGui_Text(ctx, 'ANALYSIS')
    local changed
    changed, state.target_freq = slider_labeled_int('target_freq', 'Target Freq', state.target_freq, 3000, 12000, colW, ' Hz', 6000)
    changed, state.min_level_db = slider_labeled_float('min_level_db', 'Threshold', state.min_level_db, -60.0, -20.0, colW, '%.1f', ' dB', -40.0)
    changed, state.fricative_sens = slider_labeled_float('fricative_sens', 'Sibilance Sens.', state.fricative_sens, 0.0, 100.0, colW, '%.1f', ' %%', 50.0)
    reaper.ImGui_EndGroup(ctx)

    ImGui.SameLine(ctx, nil, spacing)

    -- UI: Segments Timing column
    reaper.ImGui_BeginGroup(ctx)
    reaper.ImGui_Text(ctx, 'TIMING')
    changed, state.min_seg_ms  = slider_labeled_int('min_seg_ms', 'Min Length', state.min_seg_ms, 15, 60, colW, ' ms', 20)
    changed, state.max_gap_ms  = slider_labeled_int('max_gap_ms', 'Max Gap', state.max_gap_ms, 10, 40, colW, ' ms', 20)
    reaper.ImGui_EndGroup(ctx)

    ImGui.SameLine(ctx, nil, spacing)

    -- UI: Envelopes column
    reaper.ImGui_BeginGroup(ctx)
    reaper.ImGui_Text(ctx, 'ENVELOPES')
    changed, state.pre_ramp_ms = slider_labeled_int('pre_ramp_ms', 'Pre Ramp', state.pre_ramp_ms, 0, 25, colW, ' ms', 2)
    changed, state.post_ramp_ms = slider_labeled_int('post_ramp_ms', 'Post Ramp', state.post_ramp_ms, 0, 40, colW, ' ms', 10)
    reaper.ImGui_EndGroup(ctx)

    end 

    if state.msg ~= '' then ImGui.TextWrapped(ctx, state.msg) end
    


    -- Help modal in main frame (dock focus fix)
    draw_help_modal()
    
    ImGui.End(ctx)
  end
  
  end_theme(color_count)
  if reaper and reaper.SetProjExtState then save_last_state() end
  if open then reaper.defer(loop) else ImGui.DestroyContext(ctx) end
end

-- Presets: built-in
PRESETS = {
  { name = 'Speech', values = { -- Preset
      target_freq=6500, fricative_sens=50.0, min_level_db=-45.0,
      min_seg_ms=25, max_gap_ms=18, reduction_db=4.0, pre_ramp_ms=8, post_ramp_ms=12,
    }
  },
  { name = 'Soft singing', values = { -- Preset
      target_freq=6000, fricative_sens=60.0, min_level_db=-48.0,
      min_seg_ms=28, max_gap_ms=20, reduction_db=3.0, pre_ramp_ms=10, post_ramp_ms=14,
    }
  },
  { name = 'Aggressive singing', values = { -- Preset
      target_freq=7500, fricative_sens=35.0, min_level_db=-42.0,
      min_seg_ms=22, max_gap_ms=16, reduction_db=6.0, pre_ramp_ms=6, post_ramp_ms=10,
    }
  },
}

apply_preset = function(p)
  local v = p.values
  -- Apply main parameters, without touching overwrite or msg
  state.target_freq = v.target_freq; state.fricative_sens = v.fricative_sens
  state.min_level_db = v.min_level_db
  state.min_seg_ms = v.min_seg_ms; state.max_gap_ms = v.max_gap_ms
  state.reduction_db = v.reduction_db; state.pre_ramp_ms = v.pre_ramp_ms; state.post_ramp_ms = v.post_ramp_ms
  state.msg = 'Preset applied: '..p.name
  state.last_change_time = reaper.time_precise()
end

loop()
