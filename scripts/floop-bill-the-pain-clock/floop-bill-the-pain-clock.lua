-- @description Floop Bill The Pain Clock
-- @version 1.0.0
-- @author Floop-s
-- @license GPL-3.0
-- @about
--   Background time-tracking utility for REAPER designed for billing and project management.
--   
--   Tracks time per-project seamlessly with a background daemon, even when the UI is closed.
--   Splits work into distinct phases (Setup, Tracking, Editing, etc.) and chronological sessions.
--   Features idle-detection (auto-pause), transport override, and detailed CSV exports.
--
--   Requires:
--     - ReaImGui (ReaTeam Extensions repository)
--     - js_ReaScriptAPI (for CSV export dialog)
-- @provides
--   [main] floop-bill-the-pain-clock.lua
--   [nomain] floop-bill-the-pain-clock-daemon.lua

if not reaper.ImGui_CreateContext then
  reaper.ShowMessageBox("ReaImGui API not found!\nPlease install 'ReaImGui' via ReaPack and restart REAPER.", "Error", 0)
  return
end

if not reaper.JS_Dialog_BrowseForSaveFile then
  reaper.ShowMessageBox("js_ReaScriptAPI not found!\nPlease install 'js_ReaScriptAPI' via ReaPack and restart REAPER.", "Error", 0)
  return
end

local TITLE = "Floop Bill The Pain Clock"

local EXT_SECTION = "FLOOP_BILL_PAIN_CLOCK"
local EXT_KEY = "v2"

local KEY_HB = "DAEMON_HB"
local KEY_CMD = "CMD"
local KEY_CMD_ACK = "CMD_ACK"
local KEY_CMD_SEQ = "CMD_SEQ"
local KEY_LIVE_PREFIX = "LIVE_"
local KEY_UI_AUTOSTART = "UI_AUTOSTART"
local KEY_DAEMON_STARTUP = "DAEMON_STARTUP"
local KEY_DAEMON_CPU = "DAEMON_CPU"
local PROJ_ID_KEY = "PERSIST_ID"

local UI_CONST = {
  ROUNDING = 6,
  FONT_SIZE = 14,
  FONT_SIZE_LARGE = 18,
  BUTTON_H = 26,
}

local PHASES = {
  { key = "setup",     label = "Setup/Prep" },
  { key = "tracking",  label = "Tracking" },
  { key = "editing",   label = "Editing" },
  { key = "mixing",    label = "Mixing" },
  { key = "mastering", label = "Mastering" },
  { key = "revisions", label = "Revisions" },
}

local PHASE_COLORS = {
  { 239, 142, 39 },  -- Setup (Orange)
  { 156, 65,  66 },  -- Tracking (Red)
  { 41,  140, 206 }, -- Editing (Blue)
  { 155, 89,  182 }, -- Mixing (Purple)
  { 38,  226, 68 },  -- Mastering (Green)
  { 241, 196, 15 },  -- Revisions (Yellow)
}

local function rgba(r, g, b, a)
  return (math.floor(r) << 24) | (math.floor(g) << 16) | (math.floor(b) << 8) | math.floor(a * 255)
end

local function get_phase_colors(i)
  local c = PHASE_COLORS[i] or { 41, 140, 206 }
  local r, g, b = c[1], c[2], c[3]
  local base = rgba(r, g, b, 1.0)
  local hover = rgba(math.min(255, r + 20), math.min(255, g + 20), math.min(255, b + 20), 1.0)
  local active = rgba(math.max(0, r - 20), math.max(0, g - 20), math.max(0, b - 20), 1.0)
  return base, hover, active
end

local PROJ_POLL_SEC = 0.5
local DAEMON_POLL_SEC = 0.25
local DAEMON_ALIVE_SEC = 5.0
local INIT_DAEMON_WAIT_SEC = 1.0
local INIT_DAEMON_RETRY_SEC = 0.05

local function now() return reaper.time_precise() end
local function clamp0(x) return (x and x > 0) and x or 0 end
local function proj_guid(proj)
  if type(proj) ~= "userdata" then return "" end
  if not reaper.GetProjectGUID then return "" end
  return reaper.GetProjectGUID(proj) or ""
end

local function is_project_valid(proj)
  if type(proj) ~= "userdata" then return false end
  if reaper.ValidatePtr then
    return reaper.ValidatePtr(proj, "ReaProject*")
  end
  local idx = 0
  while true do
    local p = reaper.EnumProjects(idx, "")
    if not p then break end
    if p == proj then return true end
    idx = idx + 1
  end
  return false
end

local function proj_persist_id(proj)
  if not is_project_valid(proj) then return "" end
  local guid = reaper.GetProjectGUID and (reaper.GetProjectGUID(proj) or "") or ""
  local _, id = reaper.GetProjExtState(proj, EXT_SECTION, PROJ_ID_KEY)
  if not id or id == "" then
    id = reaper.genGuid and reaper.genGuid("") or string.format("PERSIST_%d", math.floor(now() * 1000000))
    reaper.SetProjExtState(proj, EXT_SECTION, PROJ_ID_KEY, id)
  end
  return id
end

-- ===========================================================
-- Theme Engine
-- ===========================================================
local Theme = { colors = nil, special = nil, _pushed_cols = 0, _pushed_vars = 0, last_bg_native = -1 }

local function GenerateDynamicTheme()
  local bg_native = reaper.GetThemeColor("col_main_bg2", 0)
  local text_native = reaper.GetThemeColor("col_main_text2", 0)

  if bg_native == -1 then bg_native = reaper.ColorToNative(27, 27, 27) end
  if text_native == -1 then text_native = reaper.ColorToNative(232, 232, 232) end

  local bg_r, bg_g, bg_b = reaper.ColorFromNative(bg_native)
  local txt_r, txt_g, txt_b = reaper.ColorFromNative(text_native)

  local luminance = (0.299 * bg_r + 0.587 * bg_g + 0.114 * bg_b)
  local is_dark = luminance < 128

  local txt_luminance = (0.299 * txt_r + 0.587 * txt_g + 0.114 * txt_b)
  if is_dark and txt_luminance < 180 then
    txt_r, txt_g, txt_b = 210, 212, 220
  elseif (not is_dark) and txt_luminance > 80 then
    txt_r, txt_g, txt_b = 40, 40, 40
  end

  local function rgba(r, g, b, a)
    return (math.floor(r) << 24) | (math.floor(g) << 16) | (math.floor(b) << 8) | math.floor(a * 255)
  end

  local function mix(r1, g1, b1, r2, g2, b2, t)
    return r1 + (r2 - r1) * t, g1 + (g2 - g1) * t, b1 + (b2 - b1) * t
  end

  local frame_r, frame_g, frame_b = mix(bg_r, bg_g, bg_b, txt_r, txt_g, txt_b, is_dark and 0.05 or 0.10)
  local hover_r, hover_g, hover_b = mix(bg_r, bg_g, bg_b, txt_r, txt_g, txt_b, is_dark and 0.12 or 0.18)
  local active_r, active_g, active_b = mix(bg_r, bg_g, bg_b, txt_r, txt_g, txt_b, is_dark and 0.18 or 0.25)
  local title_r, title_g, title_b = mix(bg_r, bg_g, bg_b, 0, 0, 0, is_dark and 0.2 or 0.05)

  local acc_native = reaper.GetThemeColor("col_mi_selbg", 0)
  if acc_native == -1 then acc_native = reaper.GetThemeColor("col_seltrack", 0) end
  if acc_native == -1 then acc_native = reaper.ColorToNative(41, 140, 206) end
  local acc_r, acc_g, acc_b = reaper.ColorFromNative(acc_native)

  local colors = {
    [reaper.ImGui_Col_WindowBg()]             = rgba(bg_r, bg_g, bg_b, 1.0),
    [reaper.ImGui_Col_ChildBg()]              = rgba(frame_r, frame_g, frame_b, 0.2),
    [reaper.ImGui_Col_PopupBg()]              = rgba(bg_r, bg_g, bg_b, 0.95),
    [reaper.ImGui_Col_Text()]                 = rgba(txt_r, txt_g, txt_b, 1.0),
    [reaper.ImGui_Col_TextDisabled()]         = rgba(txt_r, txt_g, txt_b, 0.5),
    [reaper.ImGui_Col_TitleBg()]              = rgba(title_r, title_g, title_b, 1.0),
    [reaper.ImGui_Col_TitleBgActive()]        = rgba(title_r, title_g, title_b, 1.0),
    [reaper.ImGui_Col_TitleBgCollapsed()]     = rgba(title_r, title_g, title_b, 0.7),
    [reaper.ImGui_Col_Button()]               = rgba(frame_r, frame_g, frame_b, 1.0),
    [reaper.ImGui_Col_ButtonHovered()]        = rgba(hover_r, hover_g, hover_b, 1.0),
    [reaper.ImGui_Col_ButtonActive()]         = rgba(active_r, active_g, active_b, 1.0),
    [reaper.ImGui_Col_FrameBg()]              = rgba(frame_r, frame_g, frame_b, 1.0),
    [reaper.ImGui_Col_FrameBgHovered()]       = rgba(hover_r, hover_g, hover_b, 1.0),
    [reaper.ImGui_Col_FrameBgActive()]        = rgba(active_r, active_g, active_b, 1.0),
    [reaper.ImGui_Col_SliderGrab()]           = rgba(acc_r, acc_g, acc_b, 0.8),
    [reaper.ImGui_Col_SliderGrabActive()]     = rgba(acc_r, acc_g, acc_b, 1.0),
    [reaper.ImGui_Col_Border()]               = rgba(txt_r, txt_g, txt_b, 0.15),
    [reaper.ImGui_Col_Separator()]            = rgba(txt_r, txt_g, txt_b, 0.15),
    [reaper.ImGui_Col_SeparatorHovered()]     = rgba(txt_r, txt_g, txt_b, 0.3),
    [reaper.ImGui_Col_SeparatorActive()]      = rgba(txt_r, txt_g, txt_b, 0.4),
    [reaper.ImGui_Col_Header()]               = rgba(frame_r, frame_g, frame_b, 1.0),
    [reaper.ImGui_Col_HeaderHovered()]        = rgba(hover_r, hover_g, hover_b, 1.0),
    [reaper.ImGui_Col_HeaderActive()]         = rgba(active_r, active_g, active_b, 1.0),
    [reaper.ImGui_Col_ResizeGrip()]           = rgba(acc_r, acc_g, acc_b, 0.5),
    [reaper.ImGui_Col_ResizeGripHovered()]    = rgba(acc_r, acc_g, acc_b, 0.8),
    [reaper.ImGui_Col_ResizeGripActive()]     = rgba(acc_r, acc_g, acc_b, 1.0),
    [reaper.ImGui_Col_CheckMark()]            = rgba(acc_r, acc_g, acc_b, 1.0),
    [reaper.ImGui_Col_PlotHistogram()]        = rgba(239, 142, 39, 1.0),
    [reaper.ImGui_Col_PlotHistogramHovered()] = rgba(239, 142, 39, 1.0),
  }

  local special = {
    accent = rgba(acc_r, acc_g, acc_b, 1.0),
    accent_hover = rgba(math.min(255, acc_r + 20), math.min(255, acc_g + 20), math.min(255, acc_b + 20), 1.0),
    accent_active = rgba(math.max(0, acc_r - 20), math.max(0, acc_g - 20), math.max(0, acc_b - 20), 1.0),
    warn = rgba(239, 142, 39, 1.0),
    error = rgba(255, 77, 79, 1.0),
    ok = rgba(38, 226, 68, 1.0),
    text_muted = rgba(txt_r, txt_g, txt_b, 0.6),
    white = rgba(255, 255, 255, 1.0),
  }

  return colors, special, bg_native
end

function Theme.Init()
  Theme.colors, Theme.special, Theme.last_bg_native = GenerateDynamicTheme()
end

function Theme.Tick()
  local current_bg = reaper.GetThemeColor("col_main_bg2", 0)
  if current_bg ~= Theme.last_bg_native then
    Theme.Init()
  end
end

function Theme.Push(ctx)
  local count = 0
  for col, val in pairs(Theme.colors) do
    reaper.ImGui_PushStyleColor(ctx, col, val)
    count = count + 1
  end
  Theme._pushed_cols = count
  reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowRounding(), UI_CONST.ROUNDING)
  reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameRounding(), UI_CONST.ROUNDING)
  Theme._pushed_vars = 2
end

function Theme.Pop(ctx)
  if Theme._pushed_cols > 0 then reaper.ImGui_PopStyleColor(ctx, Theme._pushed_cols) end
  if Theme._pushed_vars > 0 then reaper.ImGui_PopStyleVar(ctx, Theme._pushed_vars) end
  Theme._pushed_cols = 0
  Theme._pushed_vars = 0
end

function Theme.GetColor(role)
  return Theme.special and Theme.special[role] or nil
end

Theme.Init()

-- ===========================================================
-- State
-- ===========================================================
local State = {
  ui = {
    ctx = nil,
    open = true,
    font = nil,
    font_large = nil,
  },
  mappings = {
    data = {},
    learning = nil,
    open = false,
    candidate_keys = nil,
    actions = {
      { id = "toggle_pause", label = "Toggle Global Pause" },
      { id = "phase_1", label = "Phase 1: Setup/Prep" },
      { id = "phase_2", label = "Phase 2: Tracking" },
      { id = "phase_3", label = "Phase 3: Editing" },
      { id = "phase_4", label = "Phase 4: Mixing" },
      { id = "phase_5", label = "Phase 5: Mastering" },
      { id = "phase_6", label = "Phase 6: Revisions" },
    }
  },
  help = {
    open = false
  },
  reset = {
    open = false
  },
  notes = {
    open = false,
    text = ""
  },
  sessions_view = {
    open = false,
    selected_idx = 0,
    edit_text = ""
  },
  proj = {
    ptr = nil,
    fn = "",
    guid = "",
    live_id = "",
  },
  data = {
    phase = 1,
    auto_tracking = true,
    autosave_min = 10,
    t = { 0, 0, 0, 0, 0, 0 },
  },
  rt = {
    next_proj_poll = 0,
    next_daemon_poll = 0,
    status = "Daemon offline",
    daemon_alive = false,
    daemon_hb = 0,
    daemon_cpu = "0.00",
    cmd_ack = 0,
    pending_phase = nil,
    pending_phase_cmd_id = 0,
    pending_until = 0,
  },
}

local function CreateUIFont(size)
  local os_name = string.lower(reaper.GetOS() or "")
  local candidates

  if os_name:find("win") then
    candidates = { "Segoe UI", "Arial", "sans-serif" }
  elseif os_name:find("osx") or os_name:find("mac") then
    candidates = { "SF Pro Text", "Helvetica Neue", "Helvetica", "Arial", "sans-serif" }
  else
    candidates = { "Noto Sans", "DejaVu Sans", "Liberation Sans", "Arial", "sans-serif" }
  end

  for _, font_name in ipairs(candidates) do
    local font = reaper.ImGui_CreateFont(font_name, size)
    if font then
      return font
    end
  end

  return reaper.ImGui_CreateFont("sans-serif", size)
end

local function is_imgui_ctx_valid(ctx)
  if not ctx then return false end
  local ok_push = pcall(reaper.ImGui_PushStyleVar, ctx, reaper.ImGui_StyleVar_WindowRounding(), 0)
  if not ok_push then return false end
  pcall(reaper.ImGui_PopStyleVar, ctx, 1)
  return true
end

local function ensure_imgui_ctx()
  if is_imgui_ctx_valid(State.ui.ctx) then return true end
  State.ui.ctx = reaper.ImGui_CreateContext(TITLE)
  if not State.ui.ctx then return false end
  State.ui.font = CreateUIFont(UI_CONST.FONT_SIZE)
  State.ui.font_large = CreateUIFont(UI_CONST.FONT_SIZE_LARGE)
  local ok1 = State.ui.font and pcall(reaper.ImGui_Attach, State.ui.ctx, State.ui.font)
  local ok2 = State.ui.font_large and pcall(reaper.ImGui_Attach, State.ui.ctx, State.ui.font_large)
  if not ok1 or not ok2 then
    State.ui.font = reaper.ImGui_CreateFont("sans-serif", UI_CONST.FONT_SIZE)
    State.ui.font_large = reaper.ImGui_CreateFont("sans-serif", UI_CONST.FONT_SIZE_LARGE)
    pcall(reaper.ImGui_Attach, State.ui.ctx, State.ui.font)
    pcall(reaper.ImGui_Attach, State.ui.ctx, State.ui.font_large)
  end
  return true
end

-- ===========================================================
-- Key Mappings Helpers
-- ===========================================================
local function GetCandidateKeys()
  if State.mappings.candidate_keys then return State.mappings.candidate_keys end
  State.mappings.candidate_keys = {
    reaper.ImGui_Key_A(), reaper.ImGui_Key_B(), reaper.ImGui_Key_C(), reaper.ImGui_Key_D(), reaper.ImGui_Key_E(), reaper.ImGui_Key_F(), reaper.ImGui_Key_G(), reaper.ImGui_Key_H(), reaper.ImGui_Key_I(), reaper.ImGui_Key_J(), reaper.ImGui_Key_K(), reaper.ImGui_Key_L(), reaper.ImGui_Key_M(), reaper.ImGui_Key_N(), reaper.ImGui_Key_O(), reaper.ImGui_Key_P(), reaper.ImGui_Key_Q(), reaper.ImGui_Key_R(), reaper.ImGui_Key_S(), reaper.ImGui_Key_T(), reaper.ImGui_Key_U(), reaper.ImGui_Key_V(), reaper.ImGui_Key_W(), reaper.ImGui_Key_X(), reaper.ImGui_Key_Y(), reaper.ImGui_Key_Z(),
    reaper.ImGui_Key_0(), reaper.ImGui_Key_1(), reaper.ImGui_Key_2(), reaper.ImGui_Key_3(), reaper.ImGui_Key_4(), reaper.ImGui_Key_5(), reaper.ImGui_Key_6(), reaper.ImGui_Key_7(), reaper.ImGui_Key_8(), reaper.ImGui_Key_9(),
    reaper.ImGui_Key_Keypad0(), reaper.ImGui_Key_Keypad1(), reaper.ImGui_Key_Keypad2(), reaper.ImGui_Key_Keypad3(), reaper.ImGui_Key_Keypad4(), reaper.ImGui_Key_Keypad5(), reaper.ImGui_Key_Keypad6(), reaper.ImGui_Key_Keypad7(), reaper.ImGui_Key_Keypad8(), reaper.ImGui_Key_Keypad9(),
    reaper.ImGui_Key_Space(), reaper.ImGui_Key_Enter(), reaper.ImGui_Key_Tab(), reaper.ImGui_Key_Escape(), reaper.ImGui_Key_Backspace(), reaper.ImGui_Key_Delete(),
    reaper.ImGui_Key_F1(), reaper.ImGui_Key_F2(), reaper.ImGui_Key_F3(), reaper.ImGui_Key_F4(), reaper.ImGui_Key_F5(), reaper.ImGui_Key_F6(), reaper.ImGui_Key_F7(), reaper.ImGui_Key_F8(), reaper.ImGui_Key_F9(), reaper.ImGui_Key_F10(), reaper.ImGui_Key_F11(), reaper.ImGui_Key_F12(),
  }
  return State.mappings.candidate_keys
end

local function GetKeyName(ctx, key_code)
  if not key_code then return "None" end
  if reaper.ImGui_GetKeyName then
    local name = reaper.ImGui_GetKeyName(ctx, key_code)
    if name and name ~= "" then return name end
  end
  
  -- Fallback mapping like floopa-station
  local m = {}
  -- Letters A-Z
  for i = 65, 90 do
      local ch = string.char(i)
      local fn = reaper["ImGui_Key_"..ch]
      if fn then m[fn()] = ch end
  end
  -- Digits 0-9
  for i = 0, 9 do
      local fn = reaper["ImGui_Key_"..i]
      if fn then m[fn()] = tostring(i) end
  end
  -- Common controls
  m[reaper.ImGui_Key_Space()] = "Space"
  m[reaper.ImGui_Key_Enter()] = "Enter"
  m[reaper.ImGui_Key_Tab()] = "Tab"
  m[reaper.ImGui_Key_Escape()] = "Esc"
  m[reaper.ImGui_Key_Backspace()] = "Bksp"
  m[reaper.ImGui_Key_Delete()] = "Del"
  -- Numpad
  for i = 0, 9 do
      local fn = reaper["ImGui_Key_Keypad"..i]
      if fn then m[fn()] = "Num"..i end
  end
  -- F1-F12
  for i = 1, 12 do
      local fn = reaper["ImGui_Key_F"..i]
      if fn then m[fn()] = "F"..i end
  end

  return m[key_code] or ("Key " .. tostring(key_code))
end

local function LoadMappings()
  for _, a in ipairs(State.mappings.actions) do
    local v = reaper.GetExtState(EXT_SECTION .. "_KEYS", a.id)
    if v and v ~= "" then
      State.mappings.data[a.id] = tonumber(v)
    end
  end
end

local function SaveMappings()
  for _, a in ipairs(State.mappings.actions) do
    local v = State.mappings.data[a.id]
    reaper.SetExtState(EXT_SECTION .. "_KEYS", a.id, v and tostring(v) or "", true)
  end
end

-- ===========================================================
-- Persistence
-- ===========================================================
local function fmt_time_s(s)
  s = clamp0(s)
  local h = math.floor(s / 3600)
  local m = math.floor((s - h * 3600) / 60)
  local ss = math.floor(s - h * 3600 - m * 60)
  return string.format("%02d:%02d:%02d", h, m, ss)
end

local function b64_encode(s)
  if not s or s == "" then return "" end
  s = tostring(s)
  local b='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
  return ((s:gsub('.', function(x)
      local r,b='',x:byte()
      for i=8,1,-1 do r=r..(b%2^i-b%2^(i-1)>0 and '1' or '0') end
      return r;
  end)..'0000'):gsub('%d%d%d?%d?%d?%d?', function(x)
      if (#x < 6) then return '' end
      local c=0
      for i=1,6 do c=c+(x:sub(i,i)=='1' and 2^(6-i) or 0) end
      return b:sub(c+1,c+1)
  end)..({ '', '==', '=' })[#s%3+1])
end

local function deserialize(s, current_guid)
  if not s or s == "" then return nil end
  
  local parts = {}
  for token in string.gmatch(s, "([^\t]+)") do
    table.insert(parts, token)
  end
  
  local v = parts[1]
  if not v then return nil end

  local d = {
    phase = 1,
    auto_tracking = true,
    autosave_min = 10,
    sessions = {}
  }

  if v == "6" or v == "5" then
    d.phase = tonumber(parts[3]) or 1
    d.auto_tracking = (parts[4] == "1")
    d.autosave_min = tonumber(parts[5]) or 10
    
    local num_sessions = tonumber(parts[6]) or 0
    local offset = 7
    for i = 1, num_sessions do
      local sess_str = parts[offset + i - 1]
      if sess_str then
        local s_parts = {}
        for token in string.gmatch(sess_str, "([^|]+)") do
          table.insert(s_parts, token)
        end
        if #s_parts >= 7 then
          local note = ""
          if v == "6" and s_parts[8] and s_parts[8] ~= "" then
            local b='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
            local data = s_parts[8]:gsub('[^'..b..'=]', '')
            note = (data:gsub('.', function(x)
                if (x == '=') then return '' end
                local r,f='',(b:find(x)-1)
                for i=6,1,-1 do r=r..(f%2^i-f%2^(i-1)>0 and '1' or '0') end
                return r;
            end):gsub('%d%d%d?%d?%d?%d?%d?%d?', function(x)
                if (#x ~= 8) then return '' end
                local c=0
                for i=1,8 do c=c+(x:sub(i,i)=='1' and 2^(8-i) or 0) end
                return string.char(c)
            end))
          end
          table.insert(d.sessions, {
            start_time = tonumber(s_parts[1]) or 0,
            t = {
              tonumber(s_parts[2]) or 0,
              tonumber(s_parts[3]) or 0,
              tonumber(s_parts[4]) or 0,
              tonumber(s_parts[5]) or 0,
              tonumber(s_parts[6]) or 0,
              tonumber(s_parts[7]) or 0,
            },
            note = note
          })
        end
      end
    end
  else
    local guid, phase, autotrack, autosave, t1, t2, t3, t4, t5, t6 = string.match(s,
      "^(%d+)\t([^\t]*)\t(%d+)\t(%d)\t?(%d*)\t([%d%.]+)\t([%d%.]+)\t([%d%.]+)\t([%d%.]+)\t([%d%.]+)\t?([%d%.]*)")
    
    if phase then
      d.phase = tonumber(phase) or 1
      d.auto_tracking = (autotrack == "1")
      d.autosave_min = ((v == "3" or v == "4") and tonumber(autosave)) or 10
      table.insert(d.sessions, {
        start_time = os.time(),
        t = {
          tonumber(t1) or 0,
          tonumber(t2) or 0,
          tonumber(t3) or 0,
          tonumber(t4) or 0,
          tonumber(t5) or 0,
          tonumber(t6) or 0,
        }
      })
    end
  end

  if d.phase < 1 then d.phase = 1 end
  if d.phase > #PHASES then d.phase = #PHASES end
  
  if #d.sessions == 0 then
    table.insert(d.sessions, { start_time = os.time(), t = {0,0,0,0,0,0} })
  end

  for _, sess in ipairs(d.sessions) do
    for i = 1, #PHASES do sess.t[i] = clamp0(sess.t[i]) end
  end

  return d
end

local function deserialize_live(s, current_guid)
  if not s or s == "" then return nil end
  local parts = {}
  for token in string.gmatch(s, "([^\t]+)") do
    table.insert(parts, token)
  end
  
  local v = parts[1]
  if not v or (v ~= "2" and v ~= "3") then return nil end
  
  local status = parts[3]
  local phase = tonumber(parts[4]) or 1
  local autotrack = parts[5]
  local autosave = tonumber(parts[6]) or 10
  local num_sessions = tonumber(parts[7]) or 0
  
  local sessions = {}
  local offset = 8
  for i = 1, num_sessions do
    local sess_str = parts[offset + i - 1]
    if sess_str then
      local s_parts = {}
      for token in string.gmatch(sess_str, "([^|]+)") do
        table.insert(s_parts, token)
      end
      if #s_parts >= 7 then
        local note = ""
        if (v == "3" or v == "2") and s_parts[8] and s_parts[8] ~= "" then
          local b='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
          local data = s_parts[8]:gsub('[^'..b..'=]', '')
          note = (data:gsub('.', function(x)
              if (x == '=') then return '' end
              local r,f='',(b:find(x)-1)
              for i=6,1,-1 do r=r..(f%2^i-f%2^(i-1)>0 and '1' or '0') end
              return r;
          end):gsub('%d%d%d?%d?%d?%d?%d?%d?', function(x)
              if (#x ~= 8) then return '' end
              local c=0
              for i=1,8 do c=c+(x:sub(i,i)=='1' and 2^(8-i) or 0) end
              return string.char(c)
          end))
        end
        table.insert(sessions, {
          start_time = tonumber(s_parts[1]) or 0,
          t = {
            tonumber(s_parts[2]) or 0,
            tonumber(s_parts[3]) or 0,
            tonumber(s_parts[4]) or 0,
            tonumber(s_parts[5]) or 0,
            tonumber(s_parts[6]) or 0,
            tonumber(s_parts[7]) or 0,
          },
          note = note
        })
      end
    end
  end

  if #sessions == 0 then
    table.insert(sessions, { start_time = os.time(), t = {0,0,0,0,0,0} })
  end

  local d = {
    phase = phase,
    auto_tracking = (autotrack == "1"),
    autosave_min = autosave,
    sessions = sessions
  }

  if d.phase < 1 then d.phase = 1 end
  if d.phase > #PHASES then d.phase = #PHASES end
  return d, status or ""
end

local function serialize(d, guid)
  local parts = {
    "6",
    guid or "",
    tostring(d.phase or 1),
    (d.auto_tracking and "1" or "0"),
    tostring(d.autosave_min or 10),
    tostring(#(d.sessions or {}))
  }
  
  for _, sess in ipairs(d.sessions or {}) do
    local encoded_note = ""
    if sess.note and sess.note ~= "" then
      encoded_note = b64_encode(sess.note)
    end
    local s_parts = {
      string.format("%.0f", sess.start_time or 0),
      string.format("%.6f", sess.t[1] or 0),
      string.format("%.6f", sess.t[2] or 0),
      string.format("%.6f", sess.t[3] or 0),
      string.format("%.6f", sess.t[4] or 0),
      string.format("%.6f", sess.t[5] or 0),
      string.format("%.6f", sess.t[6] or 0),
      encoded_note
    }
    table.insert(parts, table.concat(s_parts, "|"))
  end
  
  return table.concat(parts, "\t")
end

local function persist_proj_state()
  if not is_project_valid(State.proj.ptr) then return end
  local s = serialize(State.data, State.proj.guid)
  reaper.SetProjExtState(State.proj.ptr, EXT_SECTION, EXT_KEY, s)
end

local function load_proj_persisted(proj)
  if type(proj) ~= "userdata" then proj = select(1, reaper.EnumProjects(-1, "")) end
  if not is_project_valid(proj) then return end
  local guid = proj_guid(proj)
  local has_ext, s = reaper.GetProjExtState(proj, EXT_SECTION, EXT_KEY)
  
  if has_ext and s ~= "" then
    State.data = deserialize(s, guid) or { phase = 1, auto_tracking = true, autosave_min = 10, sessions = { { start_time = os.time(), t = { 0, 0, 0, 0, 0, 0 } } } }
    State.is_active = true
  else
    State.data = { phase = 1, auto_tracking = true, autosave_min = 10, sessions = { { start_time = os.time(), t = { 0, 0, 0, 0, 0, 0 } } } }
    State.is_active = false
  end
end

-- ===========================================================
-- Core Logic
-- ===========================================================
local Logic = {}

function Logic.UpdateProject(force)
  local t = now()
  if not force then
    if t < (State.rt.next_proj_poll or 0) then return end
    State.rt.next_proj_poll = t + PROJ_POLL_SEC
  end
  local proj, fn = reaper.EnumProjects(-1, "")
  fn = fn or ""
  local live_id = proj_persist_id(proj)
  if proj ~= State.proj.ptr or fn ~= State.proj.fn or live_id ~= State.proj.live_id then
    State.proj.ptr = proj
    State.proj.fn = fn
    State.proj.guid = proj_guid(proj)
    State.proj.live_id = live_id
    load_proj_persisted(proj)
  end
end

local function daemon_hb()
  return tonumber(reaper.GetExtState(EXT_SECTION, KEY_HB) or "") or 0
end

local function daemon_cmd_ack()
  return tonumber(reaper.GetExtState(EXT_SECTION, KEY_CMD_ACK) or "") or 0
end

local function daemon_alive()
  local hb = daemon_hb()
  if hb <= 0 then return false, hb end
  return (now() - hb) < DAEMON_ALIVE_SEC, hb
end

local function load_live_for_current_project()
  local live_id = State.proj.live_id or ""
  if live_id == "" then return end
  local s = reaper.GetExtState(EXT_SECTION, KEY_LIVE_PREFIX .. live_id)
  local d, status = deserialize_live(s, State.proj.guid)
  if d then
    local pending_phase = State.rt.pending_phase
    if pending_phase then
      local pending_id = State.rt.pending_phase_cmd_id or 0
      local ack = State.rt.cmd_ack or 0
      local phase_match = (d.phase == pending_phase)
      if phase_match then
        State.rt.pending_phase = nil
        State.rt.pending_phase_cmd_id = 0
        State.rt.pending_until = 0
      else
        local t = now()
        local acked = (pending_id > 0 and ack >= pending_id)
        local until_t = State.rt.pending_until or 0
        if acked and t > until_t then
          State.rt.pending_until = t + 0.75
          until_t = State.rt.pending_until
        end
        if t <= until_t then
          d.phase = pending_phase
        else
          State.rt.pending_phase = nil
          State.rt.pending_phase_cmd_id = 0
          State.rt.pending_until = 0
        end
      end
    end

    State.data = d
    if status and status ~= "" then
      State.rt.status = status
    end
  end
end

function Logic.PollDaemon(force)
  local t = now()
  if not force then
    if t < (State.rt.next_daemon_poll or 0) then return end
    State.rt.next_daemon_poll = t + DAEMON_POLL_SEC
  end
  State.rt.cmd_ack = daemon_cmd_ack()
  local alive, hb = daemon_alive()
  State.rt.daemon_alive = alive
  State.rt.daemon_hb = hb
  if alive then
    local cpu_str = reaper.GetExtState(EXT_SECTION, KEY_DAEMON_CPU)
    if cpu_str and cpu_str ~= "" then
      State.rt.daemon_cpu = cpu_str
    end
    load_live_for_current_project()
  else
    State.rt.status = "Daemon offline"
    State.rt.daemon_cpu = "0.00"
    if State.rt.pending_phase and t > (State.rt.pending_until or 0) then
      State.rt.pending_phase = nil
      State.rt.pending_phase_cmd_id = 0
      State.rt.pending_until = 0
    end
  end
end

-- ===========================================================
-- UI
-- ===========================================================
local UI = {}

local function total_time()
  local s = 0
  for _, sess in ipairs(State.data.sessions or {}) do
    for i = 1, #PHASES do s = s + (sess.t[i] or 0) end
  end
  return s
end

local function phase_total_time(phase_idx)
  local s = 0
  for _, sess in ipairs(State.data.sessions or {}) do
    s = s + (sess.t[phase_idx] or 0)
  end
  return s
end

local function phase_current_session_time(phase_idx)
  local sess = State.data.sessions and State.data.sessions[#State.data.sessions]
  if not sess then return 0 end
  return sess.t[phase_idx] or 0
end

local function status_color(role_ok, role_warn, role_muted)
  if State.rt.status == "Running" then return Theme.GetColor(role_ok) end
  if State.rt.status == "Paused" then return Theme.GetColor(role_warn) end
  return Theme.GetColor(role_muted)
end


local function Toggle(ctx, label, value)
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

  local col_bg_off = 0x555555FF
  local col_bg_on  = 0xff7602FF -- Floop Orange
  local col_knob   = 0xFFFFFFFF

  local bg_col     = toggled and col_bg_on or col_bg_off
  reaper.ImGui_DrawList_AddRectFilled(dl, x, y + y_offset, x + width, y + height + y_offset, bg_col, radius)

  local t = toggled and 1.0 or 0.0
  local knob_x = x + radius + t * (width - radius * 2)
  reaper.ImGui_DrawList_AddCircleFilled(dl, knob_x, y + y_offset + radius, radius * 0.8, col_knob)

  reaper.ImGui_SameLine(ctx)
  reaper.ImGui_Text(ctx, label)
  return toggled, clicked
end

local function get_this_script_path()
  local src = debug.getinfo(1, "S").source or ""
  if src:sub(1, 1) == "@" then src = src:sub(2) end
  return src
end

local function dirname(p)
  return p:match("^(.*)[/\\][^/\\]-$") or ""
end

local function path_join(a, b)
  if not a or a == "" then return b end
  local sep = package.config:sub(1, 1)
  local last = a:sub(-1)
  if last ~= "/" and last ~= "\\" then
    return a .. sep .. b
  end
  return a .. b
end

local function file_read_all(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

local function file_write_all(path, s)
  local f = io.open(path, "wb")
  if not f then return false end
  f:write(s or "")
  f:close()
  return true
end

local function ensure_script_registered(script_path)
  if not reaper.AddRemoveReaScript then return nil, nil end
  local cmd_id = reaper.AddRemoveReaScript(true, 0, script_path, true)
  if not cmd_id or cmd_id == 0 then return nil, nil end
  local cmd_name = reaper.ReverseNamedCommandLookup and reaper.ReverseNamedCommandLookup(cmd_id) or nil
  return cmd_id, cmd_name
end

local function build_startup_block(daemon_path, ui_path)
  return table.concat({
    "",
    "-- Start script: Floop Bill The Pain Clock (Daemon)",
    "local function start_floop_daemon()",
    "  local path = [==[" .. (daemon_path or "") .. "]==]",
    "  if not reaper.AddRemoveReaScript then return end",
    "  local cmd_id = reaper.AddRemoveReaScript(true, 0, path, true)",
    "  if cmd_id and cmd_id ~= 0 then",
    "    reaper.Main_OnCommand(cmd_id, 0)",
    "  end",
    "end",
    "start_floop_daemon()",
    "if reaper.GetExtState('" .. EXT_SECTION .. "','" .. KEY_UI_AUTOSTART .. "') == '1' then",
    "  local function start_floop_ui()",
    "    local path = [==[" .. (ui_path or "") .. "]==]",
    "    if not reaper.AddRemoveReaScript then return end",
    "    local cmd_id = reaper.AddRemoveReaScript(true, 0, path, true)",
    "    if cmd_id and cmd_id ~= 0 then",
    "      reaper.Main_OnCommand(cmd_id, 0)",
    "    end",
    "  end",
    "  start_floop_ui()",
    "end",
    "-- End script: Floop Bill The Pain Clock (Daemon)",
    "",
  }, "\n")
end

local function startup_install_needed(startup_path)
  local s = file_read_all(startup_path) or ""
  if s:find("start_floop_daemon", 1, true) then return false end
  if s:find("_floop_pain_clock_daemon", 1, true) then return false end
  return true
end

local function install_startup(daemon_path, ui_path)
  local startup_path = path_join(path_join(reaper.GetResourcePath(), "Scripts"), "__startup.lua")
  local existing = file_read_all(startup_path) or ""
  if existing ~= "" and existing:sub(-1) ~= "\n" then existing = existing .. "\n" end
  if existing:find("start_floop_daemon", 1, true) or existing:find("_floop_pain_clock_daemon", 1, true) then
    return true, startup_path
  end

  local out = existing .. build_startup_block(daemon_path, ui_path)
  local ok = file_write_all(startup_path, out)
  return ok, startup_path
end

local function uninstall_startup()
  local startup_path = path_join(path_join(reaper.GetResourcePath(), "Scripts"), "__startup.lua")
  local existing = file_read_all(startup_path)
  if not existing or existing == "" then return true end

  local out_lines = {}
  local in_block = false
  
  local pos = 1
  while pos <= #existing do
    local s, e = string.find(existing, "\n", pos, true)
    local line
    if s then
      line = string.sub(existing, pos, s - 1)
      pos = e + 1
    else
      line = string.sub(existing, pos)
      pos = #existing + 1
    end
    if line:sub(-1) == "\r" then line = line:sub(1, -2) end

    if line:find("-- Start script: Floop Bill The Pain Clock (Daemon)", 1, true) then
      in_block = true
    end

    if not in_block then
      table.insert(out_lines, line)
    end

    if in_block and line:find("-- End script: Floop Bill The Pain Clock (Daemon)", 1, true) then
      in_block = false
    end
  end

  local out = table.concat(out_lines, "\n")
  
  if out:find("start_floop_daemon", 1, true) then
    local legacy_pat = "\n?%-%- Start script: Floop Bill The Pain Clock %(Daemon%).-start_floop_ui%(%)%s*end\n?"
    local ok, res = pcall(string.gsub, out, legacy_pat, "\n")
    if ok then out = res end
  end
  
  local ok, res = pcall(string.gsub, out, "\n\n\n+", "\n\n")
  if ok then out = res end

  if out == "\n" or out == "\n\n" then out = "" end

  return file_write_all(startup_path, out)
end

local function daemon_path_from_ui()
  local ui_path = get_this_script_path()
  local dir = dirname(ui_path)
  return path_join(dir, "floop-bill-the-pain-clock-daemon.lua"), ui_path
end

local function start_daemon_now()
  local hb = tonumber(reaper.GetExtState(EXT_SECTION, KEY_HB) or "") or 0
  if hb > 0 and (now() - hb) < DAEMON_ALIVE_SEC then
    return true
  end
  local daemon_path, _ = daemon_path_from_ui()
  local _, daemon_cmd_name = ensure_script_registered(daemon_path)
  if daemon_cmd_name and daemon_cmd_name ~= "" then
    local cmd_id = reaper.NamedCommandLookup(daemon_cmd_name)
    if cmd_id and cmd_id ~= 0 then
      reaper.Main_OnCommand(cmd_id, 0)
      return true
    end
  end
  return false
end

local function next_cmd_id()
  local cur = tonumber(reaper.GetExtState(EXT_SECTION, KEY_CMD_SEQ) or "") or 0
  local ack = tonumber(reaper.GetExtState(EXT_SECTION, KEY_CMD_ACK) or "") or 0
  local t_id = math.floor(now() * 1000000)
  local next_id = math.max(cur, ack, t_id) + 1
  reaper.SetExtState(EXT_SECTION, KEY_CMD_SEQ, tostring(next_id), false)
  return next_id
end

local function send_cmd(action, value)
  if (State.proj.live_id or "") == "" then return end
  local id = next_cmd_id()
  local payload = table.concat({ tostring(id), State.proj.live_id, action, tostring(value or "") }, "\t")
  reaper.SetExtState(EXT_SECTION, KEY_CMD, payload, false)
  return id
end

local function ensure_startup_prompt()
  local alive = select(1, daemon_alive())
  if alive then return end

  local daemon_path, ui_path = daemon_path_from_ui()
  local startup_path = path_join(path_join(reaper.GetResourcePath(), "Scripts"), "__startup.lua")
  local needs = startup_install_needed(startup_path)

  if not needs then
    reaper.SetExtState(EXT_SECTION, KEY_DAEMON_STARTUP, "1", true)
    start_daemon_now()
    return
  end

  if reaper.GetExtState(EXT_SECTION, KEY_DAEMON_STARTUP) == "1" then
    local ret = reaper.ShowMessageBox("Daemon auto-start was previously enabled, but the startup entry is missing.\n\nRestore it now?",
      TITLE, 4)
    if ret == 6 then
      local ok = install_startup(daemon_path, ui_path)
      if ok then
        start_daemon_now()
      else
        reaper.SetExtState(EXT_SECTION, KEY_DAEMON_STARTUP, "0", true)
        reaper.ShowMessageBox("Could not restore startup entry.\n\nDaemon must be started manually or re-enabled from this window.",
          TITLE, 0)
      end
    else
      reaper.SetExtState(EXT_SECTION, KEY_DAEMON_STARTUP, "0", true)
    end
    return
  end

  local msg = table.concat({
    "This tool requires a background daemon for per-project persistence.",
    "",
    "Enable daemon auto-start on REAPER startup now?",
    "Note: REAPER must be restarted for this change to fully take effect.",
    "",
    "If the daemon is stopped, time tracking will stop.",
  }, "\n")

  local ret = reaper.ShowMessageBox(msg, TITLE, 4)
  if ret == 6 then
    local ok, path_written = install_startup(daemon_path, ui_path)
    if ok then
      reaper.SetExtState(EXT_SECTION, KEY_DAEMON_STARTUP, "1", true)
      start_daemon_now()
      reaper.ShowMessageBox("Daemon startup enabled.\n\nDock restore is optional: enable 'UI Auto-Start' in the window if you want the dock to re-open on REAPER launch.",
        TITLE, 0)
    else
      reaper.SetExtState(EXT_SECTION, KEY_DAEMON_STARTUP, "0", true)
      reaper.ShowMessageBox("Could not write startup file:\n" .. tostring(path_written), TITLE, 0)
    end
  else
    reaper.SetExtState(EXT_SECTION, KEY_DAEMON_STARTUP, "0", true)
  end
end

local function escape_csv(s)
  if not s then return "" end
  s = tostring(s)
  if s:find('[,"]') then
    s = s:gsub('"', '""')
  end
  return s
end

local function ExportCSV()
  if not reaper.JS_Dialog_BrowseForSaveFile then
    reaper.ShowMessageBox("Please install 'js_ReaScriptAPI' via ReaPack to use the CSV export dialog.",
      "Missing Dependency", 0)
    return
  end
  local init_dir = ""
  local proj_fn = State.proj.fn
  local proj_name = "Unsaved_Project"
  if proj_fn ~= "" then
    init_dir = proj_fn:match("^(.*)[/\\]") or ""
    proj_name = proj_fn:match("([^/\\]+)%.rpp$") or "Project"
  end
  local default_filename = proj_name .. "_Billing.csv"

  local retval, file_path = reaper.JS_Dialog_BrowseForSaveFile("Export Project State", init_dir, default_filename,
    "CSV Files\0*.csv\0All Files\0*.*\0")
  if retval and file_path ~= "" then
    if not file_path:match("%.csv$") then file_path = file_path .. ".csv" end
    local f = io.open(file_path, "w")
    if f then
      local proj_title = ""
      local proj_author = ""
      if is_project_valid(State.proj.ptr) then
        local _, title = reaper.GetSetProjectInfo_String(State.proj.ptr, "PROJECT_TITLE", "", false)
        local _, author = reaper.GetSetProjectInfo_String(State.proj.ptr, "PROJECT_AUTHOR", "", false)
        proj_title = title or ""
        proj_author = author or ""
      end

      local esc_proj = escape_csv(proj_name)
      local esc_title = escape_csv(proj_title)
      local esc_author = escape_csv(proj_author)

      f:write("Project,Title,Author,Export Date,Type,Start Time,Total Time,Setup/Prep,Tracking,Editing,Mixing,Mastering,Revisions,Notes\n")
      
      -- Write Grand Total Line
      local total = fmt_time_s(total_time())
      local date_str = os.date("%Y-%m-%d %H:%M:%S")
      local line = string.format('"%s","%s","%s","%s",%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n',
        esc_proj, esc_title, esc_author, date_str, '"GRAND TOTAL"', '"-"', '"' .. total .. '"',
        '"' .. fmt_time_s(phase_total_time(1)) .. '"',
        '"' .. fmt_time_s(phase_total_time(2)) .. '"',
        '"' .. fmt_time_s(phase_total_time(3)) .. '"',
        '"' .. fmt_time_s(phase_total_time(4)) .. '"',
        '"' .. fmt_time_s(phase_total_time(5)) .. '"',
        '"' .. fmt_time_s(phase_total_time(6)) .. '"',
        '""'
      )
      f:write(line)

      -- Write Session Breakdown
      for i, sess in ipairs(State.data.sessions or {}) do
        local sess_total_sec = 0
        for j = 1, #PHASES do sess_total_sec = sess_total_sec + (sess.t[j] or 0) end
        if sess_total_sec > 0 then
          local sess_start_str = (sess.start_time and sess.start_time > 0) and os.date("%Y-%m-%d %H:%M:%S", sess.start_time) or "Unknown"
          local sess_total = fmt_time_s(sess_total_sec)
          local esc_note = escape_csv(sess.note or "")
          local s_line = string.format('"%s","%s","%s","%s",%s,"%s",%s,%s,%s,%s,%s,%s,%s,"%s"\n',
            esc_proj, esc_title, esc_author, date_str, '"Session ' .. tostring(i) .. '"', sess_start_str, '"' .. sess_total .. '"',
            '"' .. fmt_time_s(sess.t[1]) .. '"',
            '"' .. fmt_time_s(sess.t[2]) .. '"',
            '"' .. fmt_time_s(sess.t[3]) .. '"',
            '"' .. fmt_time_s(sess.t[4]) .. '"',
            '"' .. fmt_time_s(sess.t[5]) .. '"',
            '"' .. fmt_time_s(sess.t[6]) .. '"',
            esc_note
          )
          f:write(s_line)
        end
      end

      f:close()
      State.rt.export_msg = "Exported successfully to CSV!"
      State.rt.export_msg_time = now()
    else
      State.rt.export_msg = "Error: Could not save file."
      State.rt.export_msg_time = now()
    end
  end
end

local function ProcessShortcuts(ctx)
  if reaper.ImGui_IsPopupOpen(ctx, "Shortcut Mapping") then return end

  for _, a in ipairs(State.mappings.actions) do
    local key_code = State.mappings.data[a.id]
    if key_code and reaper.ImGui_IsKeyPressed(ctx, key_code, false) then
      if a.id == "toggle_pause" then
        local is_global_pause = (State.rt.status == "Global Pause")
        send_cmd("PAUSE_GLOBAL", is_global_pause and "0" or "1")
      else
        local phase_num = tonumber(a.id:match("^phase_(%d+)$"))
        if phase_num and phase_num >= 1 and phase_num <= 6 then
          State.data.phase = phase_num
          local id = send_cmd("SET_PHASE", phase_num)
          if id and id > 0 then
            State.rt.pending_phase = phase_num
            State.rt.pending_phase_cmd_id = id
            State.rt.pending_until = now() + 1.5
          end
        end
      end
    end
  end
end

local function DrawKeyMappingModal(ctx)
  if State.mappings.open then
    reaper.ImGui_OpenPopup(ctx, "Shortcut Mapping")
    State.mappings.open = false
  end

  local center_x, center_y = reaper.ImGui_Viewport_GetCenter(reaper.ImGui_GetMainViewport(ctx))
  reaper.ImGui_SetNextWindowPos(ctx, center_x, center_y, reaper.ImGui_Cond_Appearing(), 0.5, 0.5)

  if reaper.ImGui_BeginPopupModal(ctx, "Shortcut Mapping", nil, reaper.ImGui_WindowFlags_AlwaysAutoResize()) then
    
    reaper.ImGui_Text(ctx, "Assign keys to actions (active when this window is focused)")
    reaper.ImGui_Separator(ctx)
    reaper.ImGui_Spacing(ctx)

    if reaper.ImGui_BeginTable(ctx, "mappings_table", 3, reaper.ImGui_TableFlags_Borders() | reaper.ImGui_TableFlags_RowBg()) then
      reaper.ImGui_TableSetupColumn(ctx, "Action", reaper.ImGui_TableColumnFlags_WidthFixed(), 160)
      reaper.ImGui_TableSetupColumn(ctx, "Key", reaper.ImGui_TableColumnFlags_WidthFixed(), 120)
      reaper.ImGui_TableSetupColumn(ctx, "Assign", reaper.ImGui_TableColumnFlags_WidthFixed(), 100)
      reaper.ImGui_TableHeadersRow(ctx)

      for _, a in ipairs(State.mappings.actions) do
        reaper.ImGui_TableNextRow(ctx)
        reaper.ImGui_TableSetColumnIndex(ctx, 0)
        reaper.ImGui_Text(ctx, a.label)

        reaper.ImGui_TableSetColumnIndex(ctx, 1)
        local key_code = State.mappings.data[a.id]
        if State.mappings.learning == a.id then
          reaper.ImGui_TextColored(ctx, Theme.GetColor("ok") or 0x00FF00FF, "Press key...")
          
          local c_keys = GetCandidateKeys()
          for _, k in ipairs(c_keys) do
            if reaper.ImGui_IsKeyPressed(ctx, k, false) then
              if k ~= reaper.ImGui_Key_Escape() then
                State.mappings.data[a.id] = k
                SaveMappings()
              end
              State.mappings.learning = nil
              break
            end
          end
        else
          local key_name = GetKeyName(ctx, key_code)
          if not key_code then
            reaper.ImGui_TextDisabled(ctx, key_name)
          else
            reaper.ImGui_Text(ctx, key_name)
          end
        end

        reaper.ImGui_TableSetColumnIndex(ctx, 2)
        if State.mappings.learning == a.id then
          if reaper.ImGui_Button(ctx, "Cancel##"..a.id) then
            State.mappings.learning = nil
          end
        else
          if reaper.ImGui_Button(ctx, "Learn##"..a.id) then
            State.mappings.learning = a.id
          end
          reaper.ImGui_SameLine(ctx)
          if reaper.ImGui_Button(ctx, "Clear##"..a.id) then
            State.mappings.data[a.id] = nil
            SaveMappings()
          end
        end
      end
      reaper.ImGui_EndTable(ctx)
    end

    reaper.ImGui_Spacing(ctx)
    if reaper.ImGui_Button(ctx, "Close", -1) then
      State.mappings.learning = nil
      reaper.ImGui_CloseCurrentPopup(ctx)
    end

    reaper.ImGui_EndPopup(ctx)
  end
end

local function BulletTextWrapped(ctx, text)
  reaper.ImGui_Bullet(ctx)
  local avail = select(1, reaper.ImGui_GetContentRegionAvail(ctx))

  reaper.ImGui_PushTextWrapPos(ctx, reaper.ImGui_GetCursorPosX(ctx) + avail - 8)
  reaper.ImGui_Text(ctx, text)
  reaper.ImGui_PopTextWrapPos(ctx)
end

local function DrawResetModal(ctx)
  if State.reset.open then
    reaper.ImGui_OpenPopup(ctx, "Reset Project Data")
    State.reset.open = false
  end

  local center_x, center_y = reaper.ImGui_Viewport_GetCenter(reaper.ImGui_GetMainViewport(ctx))
  reaper.ImGui_SetNextWindowPos(ctx, center_x, center_y, reaper.ImGui_Cond_Appearing(), 0.5, 0.5)

  if reaper.ImGui_BeginPopupModal(ctx, "Reset Project Data", nil, reaper.ImGui_WindowFlags_AlwaysAutoResize()) then
    reaper.ImGui_Text(ctx, "Are you sure you want to completely reset all time tracked for this project?")
    reaper.ImGui_TextColored(ctx, Theme.GetColor("error") or 0xc94b4cFF, "This action cannot be undone.")
    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_Separator(ctx)
    reaper.ImGui_Spacing(ctx)

    if reaper.ImGui_Button(ctx, "Yes, Reset Data", 120) then
      State.data.phase = 1
      State.data.sessions = { { start_time = os.time(), t = {0,0,0,0,0,0} } }
      send_cmd("RESET", "1")
      reaper.ImGui_CloseCurrentPopup(ctx)
    end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "Cancel", 120) then
      reaper.ImGui_CloseCurrentPopup(ctx)
    end
    reaper.ImGui_EndPopup(ctx)
  end
end

local function DrawNotesModal(ctx)
  if State.notes.open then
    reaper.ImGui_OpenPopup(ctx, "Session Notes")
    State.notes.open = false
    -- Load current session note
    local cur_sess = State.data.sessions and State.data.sessions[#State.data.sessions]
    State.notes.text = cur_sess and cur_sess.note or ""
  end

  local center_x, center_y = reaper.ImGui_Viewport_GetCenter(reaper.ImGui_GetMainViewport(ctx))
  reaper.ImGui_SetNextWindowPos(ctx, center_x, center_y, reaper.ImGui_Cond_Appearing(), 0.5, 0.5)
  reaper.ImGui_SetNextWindowSize(ctx, 400, 300, reaper.ImGui_Cond_Appearing())

  if reaper.ImGui_BeginPopupModal(ctx, "Session Notes", nil, reaper.ImGui_WindowFlags_NoSavedSettings()) then
    reaper.ImGui_Text(ctx, "Notes for the CURRENT session:")
    reaper.ImGui_Spacing(ctx)
    
    local avail_w, avail_h = reaper.ImGui_GetContentRegionAvail(ctx)
    local rv, text = reaper.ImGui_InputTextMultiline(ctx, "##notes_text", State.notes.text, avail_w, avail_h - 40)
    if rv then State.notes.text = text end
    
    reaper.ImGui_Spacing(ctx)
    
    if reaper.ImGui_Button(ctx, "Save Notes", 120) then
      local cur_sess = State.data.sessions and State.data.sessions[#State.data.sessions]
      if cur_sess then
        cur_sess.note = State.notes.text
        persist_proj_state()
        send_cmd("SET_NOTE", b64_encode(State.notes.text))
      end
      reaper.ImGui_CloseCurrentPopup(ctx)
    end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "Cancel", 120) then
      reaper.ImGui_CloseCurrentPopup(ctx)
    end
    
    reaper.ImGui_EndPopup(ctx)
  end
end

local function DrawSessionsModal(ctx)
  if State.sessions_view.open then
    reaper.ImGui_OpenPopup(ctx, "Sessions")
    State.sessions_view.open = false
    local n = #(State.data.sessions or {})
    if n < 1 then n = 1 end
    if State.sessions_view.selected_idx <= 0 or State.sessions_view.selected_idx > n then
      State.sessions_view.selected_idx = n
    end
    local sess = State.data.sessions and State.data.sessions[State.sessions_view.selected_idx]
    State.sessions_view.edit_text = sess and (sess.note or "") or ""
  end

  local center_x, center_y = reaper.ImGui_Viewport_GetCenter(reaper.ImGui_GetMainViewport(ctx))
  reaper.ImGui_SetNextWindowPos(ctx, center_x, center_y, reaper.ImGui_Cond_Appearing(), 0.5, 0.5)
  reaper.ImGui_SetNextWindowSize(ctx, 720, 440, reaper.ImGui_Cond_Appearing())

  if reaper.ImGui_BeginPopupModal(ctx, "Sessions", nil, reaper.ImGui_WindowFlags_NoSavedSettings()) then
    local avail_w, avail_h = reaper.ImGui_GetContentRegionAvail(ctx)
    local left_w = math.min(360, math.max(260, avail_w * 0.5))
    local child_flags = (reaper.ImGui_ChildFlags_Borders and reaper.ImGui_ChildFlags_Borders()) or 0

    if reaper.ImGui_BeginChild(ctx, "sessions_left", left_w, avail_h - 40, child_flags) then
      local flags = reaper.ImGui_TableFlags_Borders() | reaper.ImGui_TableFlags_RowBg() | reaper.ImGui_TableFlags_SizingFixedFit()
      if reaper.ImGui_BeginTable(ctx, "sessions_tbl", 4, flags) then
        reaper.ImGui_TableSetupColumn(ctx, "#", reaper.ImGui_TableColumnFlags_WidthFixed(), 30)
        reaper.ImGui_TableSetupColumn(ctx, "Start", reaper.ImGui_TableColumnFlags_WidthFixed(), 140)
        reaper.ImGui_TableSetupColumn(ctx, "Total", reaper.ImGui_TableColumnFlags_WidthFixed(), 70)
        reaper.ImGui_TableSetupColumn(ctx, "Note", reaper.ImGui_TableColumnFlags_WidthStretch())
        reaper.ImGui_TableHeadersRow(ctx)

        local selectable_flags = (reaper.ImGui_SelectableFlags_SpanAllColumns and reaper.ImGui_SelectableFlags_SpanAllColumns()) or 0

        for i, sess in ipairs(State.data.sessions or {}) do
          local total_sec = 0
          for j = 1, #PHASES do total_sec = total_sec + (sess.t[j] or 0) end
          local start_str = (sess.start_time and sess.start_time > 0) and os.date("%Y-%m-%d %H:%M:%S", sess.start_time) or "Unknown"
          local note_preview = tostring(sess.note or ""):gsub("\r\n", " "):gsub("\n", " ")
          if #note_preview > 60 then note_preview = note_preview:sub(1, 60) .. "..." end

          reaper.ImGui_TableNextRow(ctx)
          reaper.ImGui_TableSetColumnIndex(ctx, 0)
          local selected = (State.sessions_view.selected_idx == i)
          if reaper.ImGui_Selectable(ctx, tostring(i) .. "##sess_sel_" .. i, selected, selectable_flags) then
            State.sessions_view.selected_idx = i
            State.sessions_view.edit_text = tostring(sess.note or "")
          end
          reaper.ImGui_TableSetColumnIndex(ctx, 1)
          reaper.ImGui_Text(ctx, start_str)
          reaper.ImGui_TableSetColumnIndex(ctx, 2)
          reaper.ImGui_Text(ctx, fmt_time_s(total_sec))
          reaper.ImGui_TableSetColumnIndex(ctx, 3)
          reaper.ImGui_Text(ctx, note_preview)
        end

        reaper.ImGui_EndTable(ctx)
      end
      reaper.ImGui_EndChild(ctx)
    end

    reaper.ImGui_SameLine(ctx)

    if reaper.ImGui_BeginChild(ctx, "sessions_right", 0, avail_h - 40, child_flags) then
      local idx = State.sessions_view.selected_idx or 0
      local sess = State.data.sessions and State.data.sessions[idx]
      local header = "Select a session"
      if sess then
        local start_str = (sess.start_time and sess.start_time > 0) and os.date("%Y-%m-%d %H:%M:%S", sess.start_time) or "Unknown"
        header = string.format("Session %d (%s)", idx, start_str)
      end
      reaper.ImGui_Text(ctx, header)
      reaper.ImGui_Separator(ctx)
      reaper.ImGui_Spacing(ctx)

      if sess then
        local active_phases = {}
        for i = 1, #PHASES do
          if (sess.t[i] or 0) > 0 then
            table.insert(active_phases, i)
          end
        end

        if #active_phases > 0 then
          local table_flags = reaper.ImGui_TableFlags_BordersInnerV() | reaper.ImGui_TableFlags_SizingStretchProp()
          if reaper.ImGui_BeginTable(ctx, "sess_breakdown", 2, table_flags) then
            for idx, i in ipairs(active_phases) do
              if idx % 2 == 1 then reaper.ImGui_TableNextRow(ctx) end
              reaper.ImGui_TableSetColumnIndex(ctx, (idx - 1) % 2)
              local t_sec = sess.t[i] or 0
              reaper.ImGui_Text(ctx, PHASES[i].label .. ":")
              reaper.ImGui_SameLine(ctx)
              local base_col = get_phase_colors(i)
              reaper.ImGui_TextColored(ctx, base_col, fmt_time_s(t_sec))
            end
            reaper.ImGui_EndTable(ctx)
          end
          reaper.ImGui_Spacing(ctx)
          reaper.ImGui_Separator(ctx)
          reaper.ImGui_Spacing(ctx)
        end
      end

      reaper.ImGui_TextDisabled(ctx, "Notes:")
      local w, h = reaper.ImGui_GetContentRegionAvail(ctx)
      local rv, text = reaper.ImGui_InputTextMultiline(ctx, "##sess_note", State.sessions_view.edit_text, w, h)
      if rv then State.sessions_view.edit_text = text end

      reaper.ImGui_EndChild(ctx)
    end

    reaper.ImGui_Spacing(ctx)

    if reaper.ImGui_Button(ctx, "Save Note", 120) then
      local idx = State.sessions_view.selected_idx or 0
      local sess = State.data.sessions and State.data.sessions[idx]
      if sess then
        sess.note = State.sessions_view.edit_text
        persist_proj_state()
        local payload = string.format("%d|%d|%s", idx, tonumber(sess.start_time or 0) or 0, b64_encode(State.sessions_view.edit_text))
        send_cmd("SET_NOTE_SESSION", payload)
      end
      reaper.ImGui_CloseCurrentPopup(ctx)
    end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "Close", 120) then
      reaper.ImGui_CloseCurrentPopup(ctx)
    end

    reaper.ImGui_EndPopup(ctx)
  end
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

local function DrawHelpModal(ctx)
  if State.help.open then
    reaper.ImGui_OpenPopup(ctx, "Help & Info")
    State.help.open = false
  end

  local center_x, center_y = reaper.ImGui_Viewport_GetCenter(reaper.ImGui_GetMainViewport(ctx))
  reaper.ImGui_SetNextWindowPos(ctx, center_x, center_y, reaper.ImGui_Cond_Appearing(), 0.5, 0.5)
  reaper.ImGui_SetNextWindowSize(ctx, 550, 500, reaper.ImGui_Cond_Appearing())

  reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowPadding(), 20, 20)
  local visible = reaper.ImGui_BeginPopupModal(ctx, "Help & Info", nil, reaper.ImGui_WindowFlags_NoSavedSettings())
  reaper.ImGui_PopStyleVar(ctx, 1)

  if visible then
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ItemSpacing(), 8, 12)

    local avail_header = select(1, reaper.ImGui_GetContentRegionAvail(ctx))
    reaper.ImGui_PushTextWrapPos(ctx, reaper.ImGui_GetCursorPosX(ctx) + avail_header - 8)
    reaper.ImGui_Text(ctx, "Floop Bill The Pain Clock is a background time-tracking utility for REAPER designed for billing and project management.")
    reaper.ImGui_PopTextWrapPos(ctx)
    
    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_Separator(ctx)
    reaper.ImGui_Spacing(ctx)

    if reaper.ImGui_BeginChild(ctx, "help_scroll_region", 0, -45) then
      
      local function DrawHeader(text)
        if State.ui.font_large then reaper.ImGui_PushFont(ctx, State.ui.font_large, UI_CONST.FONT_SIZE_LARGE) end
        reaper.ImGui_TextColored(ctx, 0xFFFFFFFF, text)
        if State.ui.font_large then reaper.ImGui_PopFont(ctx) end
      end

      DrawHeader("1. Installation & Daemon")
      BulletTextWrapped(ctx, "The core engine is a background Daemon installed in REAPER's __startup.lua file. It tracks time seamlessly even if this UI is closed.")
      BulletTextWrapped(ctx, "Uninstall Daemon: Safely removes the background script from the startup routine without affecting your logged data.")
      BulletTextWrapped(ctx, "UI Auto-Start: If enabled, this interface will automatically launch when REAPER starts.")
      
      reaper.ImGui_Spacing(ctx)
      DrawHeader("2. Opt-in & Tracking Mechanics")
      BulletTextWrapped(ctx, "Start Tracking for this Project: Tracking is strictly opt-in per project. Click this button to initialize tracking for the current REAPER tab.")
      BulletTextWrapped(ctx, "Idle Detection: Time pauses automatically after 5 minutes of inactivity (no mouse movement or REAPER interaction).")
      BulletTextWrapped(ctx, "Transport Override: Playing or Recording keeps the clock running continuously, bypassing the idle detection.")
      
      reaper.ImGui_Spacing(ctx)
      DrawHeader("3. Features & Controls")
      BulletTextWrapped(ctx, "Auto Tracking: When enabled, pressing Record in REAPER automatically forces the active phase to 'Tracking'.")
      BulletTextWrapped(ctx, "Global Pause: Instantly suspends all tracking across all open projects. Useful for breaks or phone calls.")
      BulletTextWrapped(ctx, "Autosave Interval: Available in the Tools menu, sets the background persistence frequency to prevent data loss on crashes.")
      
      reaper.ImGui_Spacing(ctx)
      DrawHeader("4. Sessions & Data")
      BulletTextWrapped(ctx, "Sessions: Time is automatically split into chronological sessions. A new session starts when you reopen a project or resume work after a long break.")
      BulletTextWrapped(ctx, "Export CSV: Generates a detailed spreadsheet with the Grand Total and a breakdown of every individual session's duration and phase split.")
      
      reaper.ImGui_Spacing(ctx)
      DrawHeader("5. Customization")
      BulletTextWrapped(ctx, "Key Mapping: Assign custom keyboard shortcuts to phases and Global Pause. To prevent conflicts with REAPER's native hotkeys (like markers), shortcuts are ONLY active when this UI window is focused.")
      
      reaper.ImGui_Spacing(ctx)
      DrawHeader("6. Support")
      reaper.ImGui_TextWrapped(ctx, "If this script saves you time, a coffee is always appreciated.")
      reaper.ImGui_Spacing(ctx)
      
      reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0xff7602FF)
      reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0xff8c1aFF)
      reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), 0xe66a02FF)
      reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0xFFFFFFFF)
      if reaper.ImGui_Button(ctx, "Support Floop's Reaper Scripts on Ko-fi") then
        open_url("https://ko-fi.com/floopsreaperscripts")
      end
      reaper.ImGui_PopStyleColor(ctx, 4)
      
      reaper.ImGui_EndChild(ctx)
    end

    reaper.ImGui_PopStyleVar(ctx, 1)

    reaper.ImGui_Spacing(ctx)
    if reaper.ImGui_Button(ctx, "Close", -1) then
      reaper.ImGui_CloseCurrentPopup(ctx)
    end

    reaper.ImGui_EndPopup(ctx)
  end
end

local function DrawToolsPopup(ctx)
  if not reaper.ImGui_BeginPopup(ctx, "ToolsMenu") then
    return
  end
  reaper.ImGui_TextDisabled(ctx, "Autosave")

  local autosave_items = {
    { label = "Off", minutes = 0 },
    { label = "1 min", minutes = 1 },
    { label = "5 min", minutes = 5 },
    { label = "10 min", minutes = 10 },
    { label = "15 min", minutes = 15 },
    { label = "30 min", minutes = 30 },
  }
  for _, item in ipairs(autosave_items) do
    if reaper.ImGui_MenuItem(ctx, item.label, nil, State.data.autosave_min == item.minutes) then
      State.data.autosave_min = item.minutes
      send_cmd("SET_AUTOSAVE", State.data.autosave_min)
    end
  end

  reaper.ImGui_Separator(ctx)

  if reaper.ImGui_MenuItem(ctx, "Auto Tracking", nil, State.data.auto_tracking) then
    State.data.auto_tracking = not State.data.auto_tracking
    send_cmd("SET_AUTOTRACK", State.data.auto_tracking and 1 or 0)
  end

  local ui_autostart = reaper.GetExtState(EXT_SECTION, KEY_UI_AUTOSTART) == "1"
  if reaper.ImGui_MenuItem(ctx, "UI Auto-Start", nil, ui_autostart) then
    reaper.SetExtState(EXT_SECTION, KEY_UI_AUTOSTART, ui_autostart and "0" or "1", true)
  end

  if reaper.ImGui_MenuItem(ctx, "Key Mapping") then
    State.mappings.open = true
  end

  reaper.ImGui_Separator(ctx)

  if reaper.ImGui_MenuItem(ctx, "Export CSV") then
    ExportCSV()
  end

  reaper.ImGui_Separator(ctx)

  if not State.rt.daemon_alive then
    if reaper.ImGui_MenuItem(ctx, "Enable Daemon Startup") then
      ensure_startup_prompt()
    end
  else
    if reaper.ImGui_MenuItem(ctx, "Uninstall Daemon") then
      local ret = reaper.ShowMessageBox("Are you sure you want to remove the Daemon from REAPER startup?\n\nTime tracking will stop until you manually run the script again.", "Uninstall Daemon", 4)
      if ret == 6 then
        local ok = uninstall_startup()
        if ok then
          reaper.SetExtState(EXT_SECTION, KEY_DAEMON_STARTUP, "0", true)
          reaper.ShowMessageBox("Daemon successfully removed from REAPER startup.\n\nThe current Daemon is still running in the background. It will be fully stopped the next time you close REAPER.", TITLE, 0)
        else
          reaper.ShowMessageBox("Error removing Daemon from __startup.lua. Check file permissions.", TITLE, 0)
        end
      end
    end
  end

  reaper.ImGui_Separator(ctx)

  if reaper.ImGui_MenuItem(ctx, "Reset Project Data") then
    State.reset.open = true
  end

  reaper.ImGui_EndPopup(ctx)
end

function UI.Draw()
  if not ensure_imgui_ctx() then return end
  Theme.Tick()
  local ctx = State.ui.ctx
  Theme.Push(ctx)

  reaper.ImGui_SetNextWindowSizeConstraints(ctx, 520, 180, 9999, 9999)
  reaper.ImGui_SetNextWindowSize(ctx, 530, 200, reaper.ImGui_Cond_FirstUseEver())
  local visible, open = reaper.ImGui_Begin(ctx, TITLE, State.ui.open, reaper.ImGui_WindowFlags_NoCollapse())
  State.ui.open = open

  if visible then
    local window_w = select(1, reaper.ImGui_GetWindowSize(ctx)) or 0
    local style_item_spacing_x = 8
    if reaper.ImGui_GetStyleVar then
      style_item_spacing_x = select(1, reaper.ImGui_GetStyleVar(ctx, reaper.ImGui_StyleVar_ItemSpacing())) or style_item_spacing_x
    end
    local proj_label = State.proj.fn ~= "" and State.proj.fn or "Unsaved project"
    local num_sessions = #(State.data.sessions or {})
    local total_lbl = "Total " .. fmt_time_s(total_time())
    local sessions_lbl = string.format("(%d session%s)", num_sessions, num_sessions == 1 and "" or "s")

    reaper.ImGui_TextDisabled(ctx, proj_label)

    local help_btn_w = select(1, reaper.ImGui_CalcTextSize(ctx, "?")) + 16
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_SetCursorPosX(ctx, math.max(reaper.ImGui_GetCursorPosX(ctx) or 0, window_w - help_btn_w - style_item_spacing_x))
    if reaper.ImGui_Button(ctx, "?") then
      State.help.open = true
    end

    reaper.ImGui_Spacing(ctx)

    local is_global_pause = (State.rt.status == "Global Pause")
    local slot_is_operational = State.is_active and (State.rt.status ~= "Inactive")
    local start_idle_lbl = "Start Tracking"
    local start_active_lbl = is_global_pause and "Resume" or "Pause"
    local start_slot_lbl = slot_is_operational and start_active_lbl or start_idle_lbl
    local start_idle_w_raw = select(1, reaper.ImGui_CalcTextSize(ctx, start_idle_lbl))
    local start_active_w_raw = select(1, reaper.ImGui_CalcTextSize(ctx, start_active_lbl))
    local start_slot_w = math.max(
      start_idle_w_raw,
      start_active_w_raw
    ) + 22
    local notes_w = select(1, reaper.ImGui_CalcTextSize(ctx, "Notes")) + 16
    local sessions_btn_w = select(1, reaper.ImGui_CalcTextSize(ctx, "Sessions")) + 16
    local tools_w = select(1, reaper.ImGui_CalcTextSize(ctx, "Tools")) + 16
    local action_group_w = start_slot_w + 8 + notes_w + 8 + sessions_btn_w + 8 + tools_w

    reaper.ImGui_PushFont(ctx, State.ui.font_large, UI_CONST.FONT_SIZE_LARGE)
    reaper.ImGui_Text(ctx, total_lbl)
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_Text(ctx, sessions_lbl)
    reaper.ImGui_PopFont(ctx)

    local metrics_end_x = reaper.ImGui_GetCursorPosX(ctx) or 0
    local avail_after_metrics = select(1, reaper.ImGui_GetContentRegionAvail(ctx)) or 0
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_SetCursorPosX(ctx, metrics_end_x + math.max(0, avail_after_metrics - action_group_w))

    if slot_is_operational then
      if is_global_pause then
        local slot_col = Theme.GetColor("warn") or 0xF08E27FF
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), slot_col)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), slot_col)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), slot_col)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0x000000FF)
        if reaper.ImGui_Button(ctx, start_slot_lbl, start_slot_w) then
          send_cmd("PAUSE_GLOBAL", "0")
        end
        reaper.ImGui_PopStyleColor(ctx, 4)
      else
        if reaper.ImGui_Button(ctx, start_slot_lbl, start_slot_w) then
          send_cmd("PAUSE_GLOBAL", "1")
        end
      end
    else
      if reaper.ImGui_Button(ctx, start_slot_lbl, start_slot_w) then
        State.is_active = true
        local s = serialize(State.data, State.proj.guid)
        reaper.SetProjExtState(State.proj.ptr, EXT_SECTION, EXT_KEY, s)
        send_cmd("ACTIVATE", "1")
      end
    end

    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "Notes") then
      State.notes.open = true
    end

    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "Sessions") then
      State.sessions_view.open = true
    end

    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "Tools") then
      reaper.ImGui_OpenPopup(ctx, "ToolsMenu")
    end
    DrawToolsPopup(ctx)

    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_Spacing(ctx)

    local btn_h = UI_CONST.BUTTON_H + 10

    if reaper.ImGui_BeginTable(ctx, "ph_btns", #PHASES, reaper.ImGui_TableFlags_SizingStretchSame()) then
      reaper.ImGui_TableNextRow(ctx)
      for i = 1, #PHASES do
        reaper.ImGui_TableSetColumnIndex(ctx, i - 1)
        local active = (State.data.phase == i)

        if active then
          local base, hover, active_col = get_phase_colors(i)
          reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), base)
          reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), hover)
          reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), active_col)
          reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0x000000FF)
        end

        if reaper.ImGui_Button(ctx, PHASES[i].label .. "##ph_" .. i, -1, btn_h) then
          State.data.phase = i
          local id = send_cmd("SET_PHASE", i)
          if id and id > 0 then
            State.rt.pending_phase = i
            State.rt.pending_phase_cmd_id = id
            State.rt.pending_until = now() + 1.5
          end
        end

        if active then
          reaper.ImGui_PopStyleColor(ctx, 4)
        end
      end
      reaper.ImGui_EndTable(ctx)
    end

    reaper.ImGui_Spacing(ctx)

    if reaper.ImGui_BeginTable(ctx, "ph_times", #PHASES, reaper.ImGui_TableFlags_SizingStretchSame()) then
      reaper.ImGui_PushFont(ctx, State.ui.font_large, UI_CONST.FONT_SIZE_LARGE)
      reaper.ImGui_TableNextRow(ctx)
      for i = 1, #PHASES do
        reaper.ImGui_TableSetColumnIndex(ctx, i - 1)
        local txt = fmt_time_s(phase_current_session_time(i))
        local tw = select(1, reaper.ImGui_CalcTextSize(ctx, txt))
        local cell_w = select(1, reaper.ImGui_GetContentRegionAvail(ctx)) or 0
        local x0 = reaper.ImGui_GetCursorPosX(ctx)
        if cell_w > tw then reaper.ImGui_SetCursorPosX(ctx, x0 + (cell_w - tw) * 0.5) end

        if i == (State.data.phase or 1) then
          local base = get_phase_colors(i)
          local a = 0.95
          local faded_col = (base & 0xFFFFFF00) | math.floor(a * 255 + 0.5)
          reaper.ImGui_TextColored(ctx, faded_col, txt)
        else
          reaper.ImGui_Text(ctx, txt)
        end
      end
      reaper.ImGui_PopFont(ctx)
      reaper.ImGui_EndTable(ctx)
    end

    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_Separator(ctx)
    reaper.ImGui_Spacing(ctx)

    local daemon_col = State.rt.daemon_alive and Theme.GetColor("ok") or Theme.GetColor("error")
    if daemon_col then
      local label = State.rt.daemon_alive and string.format("Daemon: OK (CPU: %s%%)", State.rt.daemon_cpu) or "Daemon: NOT RUNNING"
      reaper.ImGui_TextColored(ctx, daemon_col, label)
    else
      reaper.ImGui_Text(ctx, State.rt.daemon_alive and string.format("Daemon: OK (CPU: %s%%)", State.rt.daemon_cpu) or "Daemon: NOT RUNNING")
    end

    if State.rt.export_msg and (now() - (State.rt.export_msg_time or 0) < 3.0) then
      local msg_color = Theme.GetColor("ok")
      if State.rt.export_msg:match("Error") then msg_color = Theme.GetColor("error") end

      local msg_w = select(1, reaper.ImGui_CalcTextSize(ctx, State.rt.export_msg))
      local cw = select(1, reaper.ImGui_GetContentRegionAvail(ctx))
      reaper.ImGui_SetCursorPosX(ctx, reaper.ImGui_GetCursorPosX(ctx) + (cw - msg_w) * 0.5)

      if msg_color then
        reaper.ImGui_TextColored(ctx, msg_color, State.rt.export_msg)
      else
        reaper.ImGui_Text(ctx, State.rt.export_msg)
      end
    end

    ProcessShortcuts(ctx)
    DrawKeyMappingModal(ctx)
    DrawHelpModal(ctx)
    DrawNotesModal(ctx)
    DrawSessionsModal(ctx)
    DrawResetModal(ctx)

    reaper.ImGui_End(ctx)
  end

  Theme.Pop(ctx)
end

-- ===========================================================
-- Main Loop
-- ===========================================================
local function Main()
  if not State.ui.open then return end
  Logic.UpdateProject()
  Logic.PollDaemon()
  UI.Draw()
  reaper.defer(Main)
end

local function Init()
  ensure_startup_prompt()
  State.rt.init_deadline = now() + INIT_DAEMON_WAIT_SEC
  State.rt.init_next_try = 0
  State.rt.init_started = false

  local function InitStep()
    if not State.ui.open then return end
    if not State.rt.init_mappings_loaded then
      LoadMappings()
      State.rt.init_mappings_loaded = true
    end
    Logic.UpdateProject(true)
    Logic.PollDaemon(true)
    if State.rt.daemon_alive then
      reaper.defer(Main)
      return
    end
    local t = now()
    if (not State.rt.init_started) and (t >= (State.rt.init_next_try or 0)) then
      start_daemon_now()
      State.rt.init_started = true
      State.rt.init_next_try = t + INIT_DAEMON_RETRY_SEC
    end
    if t < (State.rt.init_deadline or 0) then
      reaper.defer(InitStep)
      return
    end
    reaper.defer(Main)
  end

  reaper.defer(InitStep)
end

Init()
