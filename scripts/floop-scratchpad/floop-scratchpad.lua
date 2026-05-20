-- Floop Scratchpad - Per-track notes system for REAPER.
-- @description Floop Scratchpad: per-track notes system
-- @version 2.1.0
-- @author Floop-s
-- @license GPL-3.0
-- @changelog
--   + V2.1.0
--   + Added workflow shortcuts to speed up saving/closing.
--   + JSFX: Text luminance adapts (light/dark) based on background color.
--   + Color Picker: Added saved color palette (5 slots).
-- @about
--   Per-track notes system for REAPER.
--
--   Allows writing, viewing, and managing notes for each track.
--   Notes are automatically saved and recalled when switching tracks.
--
--   V2.0: Massive update! No more background startup script needed. 
--   You can safely remove the old Floop Startup script from your SWS Startup actions if you had it configured.
--
--   Requires:
--     - ReaImGui (ReaTeam Extensions repository), v0.10.2 or newer
--
--   Dynamically generates a companion JSFX (FloopNoteReader)
--   to display notes in the Track Control Panel.
--
--   Keywords: notes, track, text, workflow.
-- @provides
--   [main] floop-scratchpad.lua


local reaper = reaper

-- Dependencies check
if not reaper or not reaper.ImGui_CreateContext then
  reaper.ShowMessageBox("ReaImGui API not found!\nPlease install 'ReaImGui' via ReaPack and restart REAPER.", "Error", 0)
  return
end

-- Context initialization
local ctx = reaper.ImGui_CreateContext('Floop Scratchpad', reaper.ImGui_ConfigFlags_NavEnableKeyboard())

if not ctx then
  reaper.ShowMessageBox("Failed to create ImGui context.\nPlease verify ReaImGui installation and compatibility.", "Error", 0)
  return
end

local sans_serif_font = reaper.ImGui_CreateFont('sans-serif', 12)
reaper.ImGui_Attach(ctx, sans_serif_font)

-- Theme configuration
local THEME_COLORS = {
    [reaper.ImGui_Col_WindowBg()]         = 0x202121FF,
    [reaper.ImGui_Col_PopupBg()]          = 0x202121F0,
    [reaper.ImGui_Col_TitleBg()]          = 0xff7602FF,
    [reaper.ImGui_Col_TitleBgActive()]    = 0xff7602FF,
    [reaper.ImGui_Col_TitleBgCollapsed()] = 0xff7602A0,
    [reaper.ImGui_Col_Button()]           = 0xd77624FF,
    [reaper.ImGui_Col_ButtonHovered()]    = 0xff7602FF,
    [reaper.ImGui_Col_ButtonActive()]     = 0xcb7933FF,
    [reaper.ImGui_Col_FrameBg()]          = 0xd77624FF,
    [reaper.ImGui_Col_FrameBgHovered()]   = 0xff7602FF,
    [reaper.ImGui_Col_FrameBgActive()]    = 0xff7602FF,
    [reaper.ImGui_Col_SliderGrab()]       = 0xFFFFFFFF,
    [reaper.ImGui_Col_SliderGrabActive()] = 0xFFFFFFFF,
    [reaper.ImGui_Col_CheckMark()]        = 0x68d391FF,
    [reaper.ImGui_Col_Header()]           = 0x2d3748FF,
    [reaper.ImGui_Col_HeaderHovered()]    = 0xd77624FF,
    [reaper.ImGui_Col_HeaderActive()]     = 0x718096FF,
    [reaper.ImGui_Col_Separator()]        = 0xd77624FF,
    [reaper.ImGui_Col_Text()]             = 0xf7fafcFF,
    [reaper.ImGui_Col_TextDisabled()]     = 0x585858FF,
    [reaper.ImGui_Col_ResizeGrip()]       = 0xd77624FF,
    [reaper.ImGui_Col_ResizeGripHovered()] = 0xff7602FF,
    [reaper.ImGui_Col_ResizeGripActive()]  = 0xff7602FF,
}

local function GenerateDynamicTheme()
    local bg_color = reaper.GetThemeColor("col_main_bg", 0)
    local text_color = reaper.GetThemeColor("col_main_text", 0)
    
    if bg_color == -1 or text_color == -1 then
        bg_color = reaper.GetThemeColor("3DTDBg", 0)
        text_color = reaper.GetThemeColor("3DTDFG", 0)
    end

    local bg_r, bg_g, bg_b = reaper.ColorFromNative(bg_color)
    local txt_r, txt_g, txt_b = reaper.ColorFromNative(text_color)
    
    local luminance = (0.299 * bg_r + 0.587 * bg_g + 0.114 * bg_b)
    local is_dark = luminance < 128
    
    if bg_r == txt_r and bg_g == txt_g and bg_b == txt_b then
        if is_dark then
            txt_r, txt_g, txt_b = 255, 255, 255
        else
            txt_r, txt_g, txt_b = 0, 0, 0
        end
    end

    local function rgba(r, g, b, a)
        return (math.floor(r) << 24) | (math.floor(g) << 16) | (math.floor(b) << 8) | math.floor(a * 255)
    end

    local function mix(r1, g1, b1, r2, g2, b2, t)
        return r1 + (r2 - r1) * t, g1 + (g2 - g1) * t, b1 + (b2 - b1) * t
    end
    
    local function adjust_luma(r, g, b, amount)
        local nr = r + (amount > 0 and (255 - r) or r) * amount
        local ng = g + (amount > 0 and (255 - g) or g) * amount
        local nb = b + (amount > 0 and (255 - b) or b) * amount
        return math.max(0, math.min(255, nr)), math.max(0, math.min(255, ng)), math.max(0, math.min(255, nb))
    end

    local win_r, win_g, win_b = bg_r, bg_g, bg_b

    local frame_r, frame_g, frame_b
    local hover_r, hover_g, hover_b
    local active_r, active_g, active_b
    local child_r, child_g, child_b
    local title_r, title_g, title_b

    if is_dark then
        frame_r, frame_g, frame_b = adjust_luma(bg_r, bg_g, bg_b, 0.12)
        hover_r, hover_g, hover_b = adjust_luma(bg_r, bg_g, bg_b, 0.20)
        active_r, active_g, active_b = adjust_luma(bg_r, bg_g, bg_b, 0.28)
        child_r, child_g, child_b = adjust_luma(bg_r, bg_g, bg_b, -0.05)
        title_r, title_g, title_b = adjust_luma(bg_r, bg_g, bg_b, 0.08)
    else
        frame_r, frame_g, frame_b = adjust_luma(bg_r, bg_g, bg_b, -0.15)
        hover_r, hover_g, hover_b = adjust_luma(bg_r, bg_g, bg_b, -0.25)
        active_r, active_g, active_b = adjust_luma(bg_r, bg_g, bg_b, -0.35)
        child_r, child_g, child_b = adjust_luma(bg_r, bg_g, bg_b, -0.05)
        title_r, title_g, title_b = adjust_luma(bg_r, bg_g, bg_b, -0.10)
    end

    local acc_r, acc_g, acc_b = 255, 118, 2

    local colors = {
        [reaper.ImGui_Col_WindowBg()]          = rgba(win_r, win_g, win_b, 1.0),
        [reaper.ImGui_Col_ChildBg()]           = rgba(child_r, child_g, child_b, 0.8),
        [reaper.ImGui_Col_PopupBg()]           = rgba(win_r, win_g, win_b, 0.95),
        [reaper.ImGui_Col_Text()]              = rgba(txt_r, txt_g, txt_b, 1.0),
        [reaper.ImGui_Col_TextDisabled()]      = rgba(txt_r, txt_g, txt_b, 0.5),
        [reaper.ImGui_Col_TitleBg()]           = rgba(title_r, title_g, title_b, 1.0),
        [reaper.ImGui_Col_TitleBgActive()]     = rgba(title_r, title_g, title_b, 1.0),
        [reaper.ImGui_Col_TitleBgCollapsed()]  = rgba(title_r, title_g, title_b, 0.7),
        [reaper.ImGui_Col_Button()]            = rgba(frame_r, frame_g, frame_b, 1.0),
        [reaper.ImGui_Col_ButtonHovered()]     = rgba(hover_r, hover_g, hover_b, 1.0),
        [reaper.ImGui_Col_ButtonActive()]      = rgba(active_r, active_g, active_b, 1.0),
        [reaper.ImGui_Col_FrameBg()]           = rgba(frame_r, frame_g, frame_b, 1.0),
        [reaper.ImGui_Col_FrameBgHovered()]    = rgba(hover_r, hover_g, hover_b, 1.0),
        [reaper.ImGui_Col_FrameBgActive()]     = rgba(active_r, active_g, active_b, 1.0),
        [reaper.ImGui_Col_SliderGrab()]        = rgba(acc_r, acc_g, acc_b, 0.8),
        [reaper.ImGui_Col_SliderGrabActive()]  = rgba(acc_r, acc_g, acc_b, 1.0),
        [reaper.ImGui_Col_Border()]            = rgba(txt_r, txt_g, txt_b, 0.15),
        [reaper.ImGui_Col_Separator()]         = rgba(txt_r, txt_g, txt_b, 0.15),
        [reaper.ImGui_Col_SeparatorHovered()]  = rgba(txt_r, txt_g, txt_b, 0.3),
        [reaper.ImGui_Col_SeparatorActive()]   = rgba(txt_r, txt_g, txt_b, 0.4),
        [reaper.ImGui_Col_Header()]            = rgba(frame_r, frame_g, frame_b, 1.0),
        [reaper.ImGui_Col_HeaderHovered()]     = rgba(hover_r, hover_g, hover_b, 1.0),
        [reaper.ImGui_Col_HeaderActive()]      = rgba(active_r, active_g, active_b, 1.0),
        [reaper.ImGui_Col_ResizeGrip()]        = rgba(acc_r, acc_g, acc_b, 0.5),
        [reaper.ImGui_Col_ResizeGripHovered()] = rgba(acc_r, acc_g, acc_b, 0.8),
        [reaper.ImGui_Col_ResizeGripActive()]  = rgba(acc_r, acc_g, acc_b, 1.0),
        [reaper.ImGui_Col_CheckMark()]         = rgba(acc_r, acc_g, acc_b, 1.0)
    }

    return colors
end

local use_reaper_theme = false
if reaper.HasExtState("FloopScratchpad", "use_reaper_theme") then
    use_reaper_theme = reaper.GetExtState("FloopScratchpad", "use_reaper_theme") == "1"
end

local function apply_theme()
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameRounding(), 6.0)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowRounding(), 8.0)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowPadding(), 16.0, 16.0)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FramePadding(), 8.0, 6.0)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ItemSpacing(), 8.0, 8.0)

    if reaper.ImGui_StyleVar_GrabRounding then
      reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_GrabRounding(), 6.0)
    end

    local color_count = 0
    local target_colors = use_reaper_theme and GenerateDynamicTheme() or THEME_COLORS
    for k, v in pairs(target_colors) do
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

-- Helper functions for safe Color Packing (ARGB format required by ReaImGui ColorEdit)
local function pack_argb(r, g, b, a)
  local a_int = math.floor(a * 255.0 + 0.5)
  local r_int = math.floor(r * 255.0 + 0.5)
  local g_int = math.floor(g * 255.0 + 0.5)
  local b_int = math.floor(b * 255.0 + 0.5)
  return (a_int << 24) | (r_int << 16) | (g_int << 8) | b_int
end

local function unpack_argb(argb)
  local a = ((argb >> 24) & 0xFF) / 255.0
  local r = ((argb >> 16) & 0xFF) / 255.0
  local g = ((argb >> 8)  & 0xFF) / 255.0
  local b = (argb & 0xFF) / 255.0
  return r, g, b, a
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

-- Global state
local noteText = ''
local currentTrack = nil
local statusMsg = '✅ System ready'
local lastTrackGUID = nil
local showHelpModal = false
local jsfxBgColor = {0.93, 0.95, 0.65}
local isDirty = false
local jsfxFontScale = 1.30
local jsfxForceLarge = false
local jsfxBgColorU32 = nil
local showConfirmClear = false
local lastProjectPath = nil
local lastProjectPtr = nil
local wasTextFocused = false

local function log(msg)
end

local function Toggle(label, value)
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

-- ImGui compatibility wrapper
local function SliderFloatCompat(label, value, min, max)
  min = min or 0.0
  max = max or 1.0
  if reaper.ImGui_SliderFloat then
    return reaper.ImGui_SliderFloat(ctx, label, value, min, max)
  elseif reaper.ImGui_SliderDouble then
    return reaper.ImGui_SliderDouble(ctx, label, value, min, max)
  elseif reaper.ImGui_DragFloat then
    return reaper.ImGui_DragFloat(ctx, label, value, 0.01, min, max)
  elseif reaper.ImGui_DragDouble then
    return reaper.ImGui_DragDouble(ctx, label, value, 0.01, min, max)
  else
    if reaper.ImGui_InputDouble then
      local changed, newVal = reaper.ImGui_InputDouble(ctx, label, value)
      return changed, newVal
    else
      local changed, str = reaper.ImGui_InputText(ctx, label, tostring(value))
      local newVal = value
      if changed then
        local parsed = tonumber(str)
        if parsed then newVal = parsed end
      end
      return changed, newVal
    end
  end
end

-- Data management
local function saveNoteState(trackGUID, fontScale, bgColorTable, content)
  if not trackGUID then return false end
  
  local r = string.format("%.3f", bgColorTable and bgColorTable[1] or 0.93)
  local g = string.format("%.3f", bgColorTable and bgColorTable[2] or 0.95)
  local b = string.format("%.3f", bgColorTable and bgColorTable[3] or 0.65)
  local safeContent = content or ""
  
  -- V3 Format: V3|fontScale|r|g|b|content_length|content
  local dataString = string.format("V3|%s|%s|%s|%s|%d|%s", tostring(fontScale), r, g, b, #safeContent, safeContent)
  
  reaper.SetProjExtState(0, "FloopScratchpad", trackGUID, dataString)
  return true
end

local function loadNoteState(trackGUID)
  if not trackGUID then return "", 1.30, {0.93, 0.95, 0.65} end
  local retval, dataString = reaper.GetProjExtState(0, "FloopScratchpad", trackGUID)
  
  if retval and dataString ~= "" then
      if dataString:sub(1, 3) == "V3|" then
          local fs_str, r_str, g_str, b_str, len_str, content_start = dataString:match("^V3|([^|]+)|([^|]+)|([^|]+)|([^|]+)|(%d+)|(.*)$")
          if fs_str then
              local fs = tonumber(fs_str) or 1.30
              local r = tonumber(r_str) or 0.93
              local g = tonumber(g_str) or 0.95
              local b = tonumber(b_str) or 0.65
              local expected_len = tonumber(len_str) or 0
              local content = content_start:sub(1, expected_len)
              return content, fs, {r, g, b}
          end
      end
      
      -- Legacy V2 parsing
      local parts = {}
      for part in string.gmatch(dataString .. "\x1F", "(.-)\x1F") do
          table.insert(parts, part)
      end
      
      if #parts >= 5 then
          local fs = tonumber(parts[1]) or 1.30
          local r = tonumber(parts[2]) or 0.93
          local g = tonumber(parts[3]) or 0.95
          local b = tonumber(parts[4]) or 0.65
          local content = parts[5]
          for i=6, #parts-1 do content = content .. "\x1F" .. parts[i] end
          return content, fs, {r, g, b}
      elseif #parts >= 2 then
          local fs = tonumber(parts[1]) or 1.30
          local content = parts[2]
          for i=3, #parts-1 do content = content .. "\x1F" .. parts[i] end
          return content, fs, {0.93, 0.95, 0.65}
      end
  end
  return "", 1.30, {0.93, 0.95, 0.65}
end

-- Manage tracks
local function isValidTrack(track)
  if not track then return false end
  if reaper.ValidatePtr2 then
    return reaper.ValidatePtr2(0, track, "MediaTrack*")
  end
  return true
end

local function getTrackGUID(track)
  if not isValidTrack(track) then return nil end
  return reaper.GetTrackGUID(track)
end

local function getTrackName(track)
  if not isValidTrack(track) then return "Unknown Track" end
  local _, name = reaper.GetTrackName(track)
  return name
end

local function getSelectedTrack()
  local trackCount = reaper.CountSelectedTracks(0)
  if trackCount > 0 then
    return reaper.GetSelectedTrack(0, 0)
  else
    return nil
  end
end

-- Note handlers
local function getNoteForTrack(trackGUID)
  if not trackGUID then return "" end
  local content, _, _ = loadNoteState(trackGUID)
  return content
end

local function getFontScaleForTrack(trackGUID)
  if not trackGUID then return 1.30 end
  local _, fs, _ = loadNoteState(trackGUID)
  return fs
end

local function getBgColorForTrack(trackGUID)
  local def_r, def_g, def_b = 0.93, 0.95, 0.65
  if reaper.HasExtState("FloopScratchpad", "default_bg_r") then
    def_r = tonumber(reaper.GetExtState("FloopScratchpad", "default_bg_r")) or def_r
    def_g = tonumber(reaper.GetExtState("FloopScratchpad", "default_bg_g")) or def_g
    def_b = tonumber(reaper.GetExtState("FloopScratchpad", "default_bg_b")) or def_b
  end
  
  if not trackGUID then return {def_r, def_g, def_b} end
  
  local retval, dataString = reaper.GetProjExtState(0, "FloopScratchpad", trackGUID)
  if not retval or dataString == "" then
    return {def_r, def_g, def_b}
  end

  local _, _, color = loadNoteState(trackGUID)
  return color
end

local function saveNoteForTrack(trackGUID, noteContent)
  if not trackGUID then return false, "Missing track GUID" end
  return saveNoteState(trackGUID, jsfxFontScale or 1.30, jsfxBgColor, noteContent)
end

-- Track ID & gmem synchronization
local project_session_ids = {}

local function getProjectID()
  local proj, _ = reaper.EnumProjects(-1)
  local proj_key = tostring(proj)
  if not project_session_ids[proj_key] then
    project_session_ids[proj_key] = math.floor(reaper.time_precise() * 1000) % 1000000 + 1
  end
  return project_session_ids[proj_key]
end

local function getTrackID(track)
  local track_guid = reaper.GetTrackGUID(track)
  local retval, id_str = reaper.GetSetMediaTrackInfo_String(track, "P_EXT:FLOOP_NOTE_ID", "", false)
  local retval_guid, saved_guid = reaper.GetSetMediaTrackInfo_String(track, "P_EXT:FLOOP_ORIG_GUID", "", false)
  
  if retval and id_str ~= "" and retval_guid and saved_guid == track_guid then
    return tonumber(id_str)
  else
    local _, max_id_str = reaper.GetProjExtState(0, "FloopScratchpad", "MaxTrackID")
    local new_id = (tonumber(max_id_str) or 0) + 1
    reaper.SetProjExtState(0, "FloopScratchpad", "MaxTrackID", tostring(new_id))
    reaper.GetSetMediaTrackInfo_String(track, "P_EXT:FLOOP_NOTE_ID", tostring(new_id), true)
    reaper.GetSetMediaTrackInfo_String(track, "P_EXT:FLOOP_ORIG_GUID", track_guid, true)
    return new_id
  end
end

local function writeNoteToGmem(track_id, noteContent, fontScale, forceLarge, bgColorTable)
  reaper.gmem_attach("FloopScratchpad")
  local proj_id = getProjectID()
  reaper.gmem_write(0, proj_id)
  
  local offset = track_id * 1024
  local safeNote = noteContent or ""
  if #safeNote > 1000 then safeNote = safeNote:sub(1, 997) .. "..." end
  local len = #safeNote
  reaper.gmem_write(offset, len)
  for i = 1, len do
    reaper.gmem_write(offset + i, string.byte(safeNote, i))
  end
  reaper.gmem_write(offset + 1018, fontScale or 1.30)
  reaper.gmem_write(offset + 1019, forceLarge and 1 or 0)
  
  if bgColorTable and #bgColorTable >= 3 then
    reaper.gmem_write(offset + 1020, bgColorTable[1])
    reaper.gmem_write(offset + 1021, bgColorTable[2])
    reaper.gmem_write(offset + 1022, bgColorTable[3])
  else
    reaper.gmem_write(offset + 1020, 0.93)
    reaper.gmem_write(offset + 1021, 0.95)
    reaper.gmem_write(offset + 1022, 0.65)
  end
  
  local ver = reaper.gmem_read(offset + 1023)
  reaper.gmem_write(offset + 1023, (ver + 1) % 1000000)
end

-- Static JSFX creation
local JSFX_FILE_NAME = 'FloopNoteReader.jsfx'

local jsfx_verified = false

local function createStaticJSFXFile()
  local resourcePath = reaper.GetResourcePath()
  local effectsDir = resourcePath .. package.config:sub(1,1) .. 'Effects'
  local jsfxPath = effectsDir .. package.config:sub(1,1) .. JSFX_FILE_NAME
  
  reaper.RecursiveCreateDirectory(effectsDir, 0)
  
  local jsfxContent = [[desc:Floop Note Reader
// @version 2.1.0
// @author Floop-s
// @about Static JSFX reader for Floop Scratchpad. Uses gmem to receive notes and @serialize for auto-persistence.

slider1:0<0,1000000,1>-Track ID (Hidden)
slider2:0<0,1000000,1>-Project ID (Hidden)

options:gmem=FloopScratchpad

@init
last_version = -1;
last_track_id = -1;
force_init = 1;

@serialize
file_var(0, font_scale);
file_var(0, force_big);
file_var(0, bg_r);
file_var(0, bg_g);
file_var(0, bg_b);
file_string(0, #note_text);
file_var(0, slider2);

// Detect fresh uninitialized plugin (font_scale is 0 in fresh memory)
(font_scale == 0) ? (
  font_scale = 1.30;
  bg_r = 0.93;
  bg_g = 0.95;
  bg_b = 0.65;
);

@gfx 400 140
// DPI support for Retina macOS / HiDPI Windows
scale = max(gfx_ext_retina, 1);

track_id = slider1;
proj_id = slider2;
offset = track_id * 1024;

// Read only if the global gmem[0] matches this plugin's Project ID
gmem_active = (gmem[0] == proj_id);

gmem_active ? (
  version = gmem[offset + 1023];
) : (
  version = last_version; // don't update if inactive project
);

// Update only if Lua bumps version for this track.
gmem_active && (track_id != last_track_id || version != last_version) ? (
  last_track_id = track_id;
  last_version = version;
  
  version > 0 ? (
    len = gmem[offset];
    #note_text = "";
    i = 0;
    // Fast native string building via strcpy avoidance
    while (i < len && i < 1000) (
      str_setchar(#note_text, i, gmem[offset + 1 + i]);
      i += 1;
    );
    str_setlen(#note_text, i);
    
    font_scale = gmem[offset + 1018];
    font_scale <= 0 ? font_scale = 1.30 : font_scale;
    force_big = gmem[offset + 1019];
    bg_r = gmem[offset + 1020];
    bg_g = gmem[offset + 1021];
    bg_b = gmem[offset + 1022];
    
    force_init = 1;
  );
);

gfx_r = bg_r; gfx_g = bg_g; gfx_b = bg_b;
gfx_rect(0,0,gfx_w,gfx_h);

pad = 6 * scale;
area_w = max(10, gfx_w - pad*2);
area_h = max(10, gfx_h - pad*2);

compact = (gfx_w < 260 * scale) || (gfx_h < 90 * scale);
base_sz = (compact ? 14 : 18) * font_scale * scale;
sz = min(max(base_sz, 12 * scale), 40 * scale);

force_big ? (
  sz = sz;
) : (
  while (sz > 10 * scale && area_w < (sz*3)) (
    sz -= 1;
  );
);

gfx_setfont(1, "sans-serif", sz);

strlen(#note_text) > 0 ? (
    // Lazy String Wrapping Optimization
    (force_init || gfx_w != last_gfx_w || font_scale != last_font_scale) ? (
      last_gfx_w = gfx_w;
      last_font_scale = font_scale;
      force_init = 0;
      
      #wrapped_text = "";
      #word = "";
      j = 0;
      text_len = strlen(#note_text);
      curr_x = pad;
      
      while (j <= text_len) (
        c = j < text_len ? str_getchar(#note_text, j) : 32;
        
        c == 13 ? (
          0; // Ignore \r
        ) : (
          (c == 32 || c == 10 || j == text_len) ? (
            gfx_measurestr(#word, w, h);
            
            (curr_x + w > gfx_w - pad) && (curr_x > pad) ? (
               strcat(#wrapped_text, "\n");
               curr_x = pad;
            );
            
            strcat(#wrapped_text, #word);
            curr_x += w;
            
            (c == 32 && j < text_len) ? (
               strcat(#wrapped_text, " ");
               gfx_measurestr(" ", spc_w, h);
               curr_x += spc_w;
            );
            
            (c == 10) ? (
               strcat(#wrapped_text, "\n");
               curr_x = pad;
            );
            
            #word = "";
            str_setlen(#word, 0);
          ) : (
            w_len = strlen(#word);
            str_setchar(#word, w_len, c);
            str_setlen(#word, w_len + 1);
          );
        );
        j += 1;
      );
    );

  // Dynamic text color based on background luminance
  luma = (0.299 * bg_r) + (0.587 * bg_g) + (0.114 * bg_b);
  luma < 0.4 ? (
    gfx_r = 0.95; gfx_g = 0.95; gfx_b = 0.95; // Light text
  ) : (
    gfx_r = 0.15; gfx_g = 0.15; gfx_b = 0.15; // Dark text
  );
  
  gfx_x = pad; gfx_y = pad;
  gfx_drawstr(#wrapped_text);
) : (
  gfx_r = 0.8; gfx_g = 0.5; gfx_b = 0.5;
  gfx_x = pad; gfx_y = pad; gfx_drawstr("No saved note for this track");
);
]]

  if jsfx_verified then
    return true, jsfxPath
  end

  local f = io.open(jsfxPath, "rb")
  local existingContent = nil
  if f then
    existingContent = f:read("*all"):gsub("\r\n", "\n")
    f:close()
  end
  
  if existingContent == jsfxContent then
    jsfx_verified = true
    return true, jsfxPath
  end
  
  -- Write/overwrite JSFX file to disk
  local file, ferr = io.open(jsfxPath, 'w')
  if file then
    file:write(jsfxContent)
    file:close()
    jsfx_verified = true
    return true, jsfxPath
  else
    return false, "Cannot create JSFX file"
  end
end

-- JSFX insertion & refreshing
local function addJSFXToTrack(track, fontScale, forceLarge, bgColorTable)
  if not isValidTrack(track) then
    return false, "No valid track selected"
  end
  
  local trackGUID = getTrackGUID(track)
  local noteContent = getNoteForTrack(trackGUID)
  local track_id = getTrackID(track)
  local proj_id = getProjectID()
  
  writeNoteToGmem(track_id, noteContent, fontScale, forceLarge, bgColorTable)
  
  local fxCount = reaper.TrackFX_GetCount(track)
  for i = 0, fxCount - 1 do
    local _, fxName = reaper.TrackFX_GetFXName(track, i, '')
    if fxName and (fxName:find('FloopNoteReader') or fxName:find('Floop Note Reader')) then
      reaper.TrackFX_SetParam(track, i, 0, track_id)
      reaper.TrackFX_SetParam(track, i, 1, proj_id)
      return true, "JSFX already present on this track"
    end
  end
  
  local success, jsfxPath = createStaticJSFXFile()
  if not success then
    return false, jsfxPath
  end
  
  local fxIndex = reaper.TrackFX_AddByName(track, JSFX_FILE_NAME, false, -1)
  
  if fxIndex >= 0 then
    reaper.TrackFX_SetNamedConfigParm(track, fxIndex, "ui_embed", "1")
    reaper.TrackFX_SetParam(track, fxIndex, 0, track_id)
    reaper.TrackFX_SetParam(track, fxIndex, 1, proj_id)
    reaper.TrackList_AdjustWindows(false)
    reaper.UpdateArrange()
    return true, "JSFX embedded in TCP"
  else
    return false, "Error adding JSFX"
  end
end

local function refreshJSFXForTrack(track)
  if not track then return end
  local trackGUID = getTrackGUID(track)
  local noteContent = getNoteForTrack(trackGUID)
  local track_id = getTrackID(track)
  local proj_id = getProjectID()
  local scale = getFontScaleForTrack(trackGUID)
  local bgColor = getBgColorForTrack(trackGUID)
  
  local hasNotes = noteContent and noteContent:match('%S')
  local hasJSFX = false
  local fxCount = reaper.TrackFX_GetCount(track)
  
  if hasNotes then
    writeNoteToGmem(track_id, noteContent, scale, false, bgColor)
  end
  
  for i = fxCount - 1, 0, -1 do
    local _, fxName = reaper.TrackFX_GetFXName(track, i, '')
    if fxName and (fxName:find('FloopNoteReader') or fxName:find('Floop Note Reader')) then
      hasJSFX = true
      if not hasNotes then
        reaper.TrackFX_Delete(track, i)
      else
        reaper.TrackFX_SetParam(track, i, 0, track_id)
        reaper.TrackFX_SetParam(track, i, 1, proj_id)
      end
    end
  end
  
  if hasNotes and not hasJSFX then
    addJSFXToTrack(track, scale, false, bgColor)
  end
end

local function refreshAllJSFXReaders()
  createStaticJSFXFile()
  
  local proj_id = getProjectID()
  
  local total = reaper.CountTracks(0)
  for t = 0, total - 1 do
    local tr = reaper.GetTrack(0, t)
    local trackGUID = getTrackGUID(tr)
    local noteContent = getNoteForTrack(trackGUID)
    
    if noteContent and noteContent:match('%S') then
      local track_id = getTrackID(tr)
      local scale = getFontScaleForTrack(trackGUID)
      local bgColor = getBgColorForTrack(trackGUID)
      writeNoteToGmem(track_id, noteContent, scale, false, bgColor)
      
      local fxCount = reaper.TrackFX_GetCount(tr)
      for i = 0, fxCount - 1 do
        local _, fxName = reaper.TrackFX_GetFXName(tr, i, '')
        if fxName and (fxName:find('FloopNoteReader') or fxName:find('Floop Note Reader')) then
          reaper.TrackFX_SetParam(tr, i, 0, track_id)
          reaper.TrackFX_SetParam(tr, i, 1, proj_id)
        end
      end
    end
  end
end

local function migrateLegacyTxtFile()
  local _, projfn = reaper.EnumProjects(-1)
  if not projfn or projfn == "" then 
    return false, "❌ Project not saved. Cannot migrate."
  end
  
  local dir = projfn:match("^(.*)[/\\]")
  local name = projfn:match("([^/\\]+)%.rpp$")
  if not dir or not name then 
    return false, "❌ Invalid project path." 
  end
  
  local sep = package.config:sub(1,1)
  local legacyPath = dir .. sep .. name .. "_notes.txt"
  local f = io.open(legacyPath, "r")
  
  if not f then
    local fallbackDir = reaper.GetProjectPath("")
    if fallbackDir and fallbackDir ~= "" then
      legacyPath = fallbackDir .. sep .. name .. "_notes.txt"
      f = io.open(legacyPath, "r")
    end
  end
  
  if not f then
    local retval, file = reaper.GetUserFileNameForRead(dir .. sep, "Locate V1 _notes.txt file", ".txt")
    if retval and file ~= "" then
      legacyPath = file
      f = io.open(legacyPath, "r")
    end
  end
  
  if not f then 
    return false, "❌ V1 notes file not found or operation cancelled." 
  end
  
  local content = f:read("*all")
  f:close()
  
  if content and content:match("%S") then
    -- Migrate
    local padded = content:gsub("\r\n", "\n")
    if not padded:match("\n=====\n$") then padded = padded .. "\n=====\n" end
    
    local count = 0
    for block in padded:gmatch("(.-)\n=====\n") do
      if block:match("%S") then
        local guid = block:match("GUID:%s*(%S+)")
        if guid then
          local fsStr = block:match("FontScale:%s*([%d%.]+)")
          local fs = tonumber(fsStr) or 1.30
          local cPos = block:find("Content:")
          local noteContent = ""
          if cPos then
            noteContent = block:sub(cPos + #("Content:"))
            noteContent = noteContent:gsub("^%s*", "")
          end
          -- Legacy V1 uses default color table
          saveNoteState(guid, fs, {0.93, 0.95, 0.65}, noteContent)
          count = count + 1
        end
      end
    end
    -- Rename file to backup
    os.rename(legacyPath, legacyPath .. ".bak")
    return true, "✅ Successfully migrated " .. count .. " notes to V2! (Backup created)"
  end
  
  return false, "❌ Notes file is empty or invalid."
end

-- UI Functions
local function performSave(track, text)
  if not track or not isValidTrack(track) then return false, "No valid track selected" end
  local trackGUID = getTrackGUID(track)
  local success, info = saveNoteForTrack(trackGUID, text)
  if success then
    -- Update JSFX
    local track_id = getTrackID(track)
    local hasNotes = text and text:match('%S')
    local fxCount = reaper.TrackFX_GetCount(track)
    local hasJSFX = false
    
    if hasNotes then
      writeNoteToGmem(track_id, text, jsfxFontScale, jsfxForceLarge, jsfxBgColor)
    end
    
    for i = fxCount - 1, 0, -1 do
      local _, fxName = reaper.TrackFX_GetFXName(track, i, '')
      if fxName:find('FloopNoteReader') or fxName:find('Floop Note Reader') then
        hasJSFX = true
        if not hasNotes then
          reaper.TrackFX_Delete(track, i)
        else
          reaper.TrackFX_SetParam(track, i, 0, track_id)
          reaper.TrackFX_SetParam(track, i, 1, getProjectID())
        end
      end
    end
    
    if hasNotes and not hasJSFX then
       addJSFXToTrack(track, jsfxFontScale, jsfxForceLarge, jsfxBgColor)
    end
    isDirty = false
    return true, "Note saved"
  end
  return false, info or "unknown error"
end

local function initializeUI()
  local proj, projPath = reaper.EnumProjects(-1)
  lastProjectPtr = proj
  lastProjectPath = projPath
  
  refreshAllJSFXReaders()
  
  currentTrack = getSelectedTrack()
  if currentTrack and isValidTrack(currentTrack) then
    local trackGUID = getTrackGUID(currentTrack)
    noteText = getNoteForTrack(trackGUID)
    jsfxFontScale = getFontScaleForTrack(trackGUID)
    jsfxBgColor = getBgColorForTrack(trackGUID)
    jsfxBgColorU32 = pack_argb(jsfxBgColor[1], jsfxBgColor[2], jsfxBgColor[3], 1.0)
  else
    noteText = ""
    jsfxFontScale = 1.30
    jsfxBgColor = {0.93, 0.95, 0.65}
    jsfxBgColorU32 = pack_argb(0.93, 0.95, 0.65, 1.0)
  end
end

local function renderUI()
  local requestClose = false
  local newSelectedTrack = getSelectedTrack()
  if newSelectedTrack ~= currentTrack then
    if isDirty and isValidTrack(currentTrack) then
      local success, info = performSave(currentTrack, noteText)
      if success then
        statusMsg = '✅ Note autosaved for track: ' .. getTrackName(currentTrack)
      else
        statusMsg = '❌ Autosave failed: ' .. (info or 'unknown')
      end
    end
    
    currentTrack = newSelectedTrack
    if currentTrack and isValidTrack(currentTrack) then
      local trackGUID = getTrackGUID(currentTrack)
      noteText = getNoteForTrack(trackGUID)
      jsfxFontScale = getFontScaleForTrack(trackGUID)
      jsfxBgColor = getBgColorForTrack(trackGUID)
      jsfxBgColorU32 = pack_argb(jsfxBgColor[1], jsfxBgColor[2], jsfxBgColor[3], 1.0)
      isDirty = false
    else
      noteText = ""
      jsfxFontScale = 1.30
      jsfxBgColor = {0.93, 0.95, 0.65}
      jsfxBgColorU32 = pack_argb(0.93, 0.95, 0.65, 1.0)
    end
  end
  
  reaper.ImGui_Text(ctx, '✅ Floop Scratchpad')
  
  local toggle_label = "UI Theme"
  local toggle_width = 85 
  reaper.ImGui_SameLine(ctx, reaper.ImGui_GetWindowWidth(ctx) - toggle_width - reaper.ImGui_GetStyleVar(ctx, reaper.ImGui_StyleVar_WindowPadding()))
  
  local toggled, clicked = Toggle(toggle_label, use_reaper_theme)
  if clicked then
    use_reaper_theme = toggled
    reaper.SetExtState("FloopScratchpad", "use_reaper_theme", use_reaper_theme and "1" or "0", true)
  end
  
  reaper.ImGui_Separator(ctx)
  
  if currentTrack and isValidTrack(currentTrack) then
    local trackName = getTrackName(currentTrack)
    local trackGUID = getTrackGUID(currentTrack)
    reaper.ImGui_Text(ctx, '🎯 Track: ' .. trackName)
    reaper.ImGui_Text(ctx, '🔑 GUID: ' .. trackGUID)
  else
    reaper.ImGui_Text(ctx, '⚠️  No track selected')
  end
  
  reaper.ImGui_Separator(ctx)
  reaper.ImGui_Text(ctx, '📝 Notes:')
  
  local availWidth, availHeight = reaper.ImGui_GetContentRegionAvail(ctx)
  local textareaWidth = math.max(150, availWidth - 10)
  local textareaHeight = math.max(120, math.min(150, availHeight - 120)) 
  
  local changed, newText = reaper.ImGui_InputTextMultiline(ctx, '##note_textarea', noteText, textareaWidth, textareaHeight)
  local isTextFocused = reaper.ImGui_IsItemActive(ctx)
  if changed then
    noteText = newText
    isDirty = true
  end
  
  reaper.ImGui_Spacing(ctx)
  reaper.ImGui_Text(ctx, "📊 Text Length: " .. #noteText .. " characters")
  reaper.ImGui_Separator(ctx)
  reaper.ImGui_Spacing(ctx)
  
  local baseAbsSize = 18
  local currentAbsSize = math.floor(jsfxFontScale * baseAbsSize + 0.5)
  
  reaper.ImGui_Text(ctx, 'Aa Text Size')
  reaper.ImGui_SameLine(ctx)
  reaper.ImGui_TextDisabled(ctx, string.format("%d px", currentAbsSize))
  
  local scaleChanged, newScale = SliderFloatCompat('##jsfx_font_scale', jsfxFontScale, 0.8, 2.25)
  if scaleChanged then
    jsfxFontScale = newScale
    isDirty = true
  end
  
  if reaper.ImGui_IsItemDeactivatedAfterEdit and reaper.ImGui_IsItemDeactivatedAfterEdit(ctx) then
    if currentTrack and isValidTrack(currentTrack) then
      local success, info = performSave(currentTrack, noteText)
      if success then
        statusMsg = '✅ Font scale updated'
      else
        statusMsg = '❌ Autosave failed: ' .. info
      end
    end
  end
  
  local absChanged = false
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_SetNextItemWidth then
    reaper.ImGui_SetNextItemWidth(ctx, 60)
  end
  local ch, str = reaper.ImGui_InputText(ctx, '##jsfx_font_abs', tostring(currentAbsSize))
  absChanged = ch
  if absChanged then
    local parsed = tonumber(str)
    if parsed then
      local newAbs = math.floor(parsed + 0.5)
      if newAbs < 14 then newAbs = 14 end
      if newAbs > 40 then newAbs = 40 end
      jsfxFontScale = newAbs / baseAbsSize
      isDirty = true
    end
  end
  if reaper.ImGui_IsItemDeactivatedAfterEdit and reaper.ImGui_IsItemDeactivatedAfterEdit(ctx) then
    if currentTrack and isValidTrack(currentTrack) then
      local success, info = performSave(currentTrack, noteText)
      if success then
        statusMsg = '✅ Font size updated'
      else
        statusMsg = '❌ Autosave failed: ' .. info
      end
    end
  end
  
  -- JSFX Background Color Picker
  reaper.ImGui_SameLine(ctx)
  
  if not jsfxBgColorU32 then
    jsfxBgColorU32 = pack_argb(jsfxBgColor[1], jsfxBgColor[2], jsfxBgColor[3], 1.0)
  end
  
  local changed = false
  local color_edit_finished = false
  local new_packed_color = jsfxBgColorU32
  
  local main_btn_flags = reaper.ImGui_ColorEditFlags_NoAlpha()
  if reaper.ImGui_ColorButton(ctx, '🎨 BG Color', jsfxBgColorU32, main_btn_flags) then
    reaper.ImGui_OpenPopup(ctx, 'ColorPickerPopup')
  end
  if reaper.ImGui_IsItemHovered(ctx) then
    reaper.ImGui_SetTooltip(ctx, "Click to change JSFX Background Color")
  end
  
  if reaper.ImGui_BeginPopup(ctx, 'ColorPickerPopup') then
    
    reaper.ImGui_Text(ctx, "Saved Colors:")
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "Save Current") then
       local palette_str = reaper.GetExtState("FloopScratchpad", "ColorPalette") or ""
       local colors = {}
       local seen = {}
       local current_u32 = (jsfxBgColorU32 or 0) & 0xFFFFFFFF
       local current_hex = string.format("%08X", current_u32)
       for hex in palette_str:gmatch("%S+") do
         local h = tostring(hex):upper():match("(%x%x%x%x%x%x%x%x)$")
         if h and h ~= current_hex and not seen[h] then
           table.insert(colors, h)
           seen[h] = true
         end
       end
       table.insert(colors, 1, current_hex)
       while #colors > 5 do table.remove(colors) end
       reaper.SetExtState("FloopScratchpad", "ColorPalette", table.concat(colors, " "), true)
    end
    
    local palette_str = reaper.GetExtState("FloopScratchpad", "ColorPalette") or ""
     if palette_str ~= "" then
        reaper.ImGui_Spacing(ctx)
        local i = 0
        local colors_to_keep = {}
        local palette_changed = false
        
        for hex in palette_str:gmatch("%S+") do
           local u32_color = tonumber(hex, 16)
           if u32_color then
              if i > 0 and (i % 5) ~= 0 then reaper.ImGui_SameLine(ctx) end
              
              local pal_btn_flags = reaper.ImGui_ColorEditFlags_NoAlpha()
              
              if reaper.ImGui_ColorButton(ctx, "##pal_"..i, u32_color, pal_btn_flags) then
                 changed = true
                 new_packed_color = u32_color
                 color_edit_finished = true
              end
              
              if reaper.ImGui_IsItemHovered(ctx) then
                reaper.ImGui_SetTooltip(ctx, "Left-click: Apply\nRight-click: Delete")
              end
              
              if reaper.ImGui_IsItemClicked(ctx, 1) then
                 palette_changed = true
              else
                 table.insert(colors_to_keep, hex)
              end
              
              i = i + 1
           end
        end
        
        if palette_changed then
           reaper.SetExtState("FloopScratchpad", "ColorPalette", table.concat(colors_to_keep, " "), true)
        end
     end
    
    reaper.ImGui_Separator(ctx)
    
    local picker_flags = reaper.ImGui_ColorEditFlags_NoAlpha() | reaper.ImGui_ColorEditFlags_DisplayHex() | reaper.ImGui_ColorEditFlags_NoSidePreview()
    local picker_changed, picker_color = reaper.ImGui_ColorPicker4(ctx, '##picker', jsfxBgColorU32, picker_flags)
    if picker_changed then
       changed = true
       new_packed_color = picker_color
    end
    if reaper.ImGui_IsItemDeactivatedAfterEdit(ctx) then
       color_edit_finished = true
    end
    
    reaper.ImGui_EndPopup(ctx)
  end
  
  if changed then
    jsfxBgColorU32 = new_packed_color
    local new_r, new_g, new_b, _ = unpack_argb(new_packed_color)
    
    jsfxBgColor = {new_r, new_g, new_b}
    isDirty = true
    
    if currentTrack and isValidTrack(currentTrack) then
      local track_id = getTrackID(currentTrack)
      writeNoteToGmem(track_id, noteText, jsfxFontScale, jsfxForceLarge, jsfxBgColor)
    end
  end
  
  if color_edit_finished then
    if currentTrack and isValidTrack(currentTrack) then
      performSave(currentTrack, noteText)
    end
    reaper.SetExtState("FloopScratchpad", "default_bg_r", tostring(jsfxBgColor[1]), true)
    reaper.SetExtState("FloopScratchpad", "default_bg_g", tostring(jsfxBgColor[2]), true)
    reaper.SetExtState("FloopScratchpad", "default_bg_b", tostring(jsfxBgColor[3]), true)
  end
  
  local isCtrlDown = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Mod_Ctrl())
  local isSuperDown = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Mod_Super())
  local isSKeyPressed = reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_S())
  local isEnterKeyPressed = reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Enter()) or reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_KeypadEnter())
  local isEscKeyPressed = reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Escape())
  
  if (isCtrlDown or isSuperDown) and isSKeyPressed then
    if currentTrack and isValidTrack(currentTrack) then
      local success, info = performSave(currentTrack, noteText)
      if success then
        statusMsg = '✅ Note saved (Shortcut) for track: ' .. getTrackName(currentTrack)
      else
        statusMsg = '❌ Error: ' .. info
      end
    end
  end
  
  if (isCtrlDown or isSuperDown) and isEnterKeyPressed then
    if currentTrack and isValidTrack(currentTrack) then
      performSave(currentTrack, noteText)
    end
    requestClose = true
  end
  
  local isPopupOpen = reaper.ImGui_IsPopupOpen(ctx, "", reaper.ImGui_PopupFlags_AnyPopupId() | reaper.ImGui_PopupFlags_AnyPopupLevel())
  if isEscKeyPressed and not wasTextFocused and not isPopupOpen then
    requestClose = true
  end
  wasTextFocused = isTextFocused
  
  reaper.ImGui_Spacing(ctx)
  
  if reaper.ImGui_Button(ctx, '💾 Save') then
    if currentTrack and isValidTrack(currentTrack) then
      local success, info = performSave(currentTrack, noteText)
      if success then
        statusMsg = '✅ Note saved for track: ' .. getTrackName(currentTrack)
      else
        statusMsg = '❌ Error: ' .. info
      end
    else
      statusMsg = '❌ Error: Select a track before saving'
    end
  end
  
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, '+ Add JSFX') then
    if currentTrack and isValidTrack(currentTrack) then
      local success, info = addJSFXToTrack(currentTrack, jsfxFontScale, jsfxForceLarge, jsfxBgColor)
      if success then
        statusMsg = '✅ ' .. info
      else
        statusMsg = '❌ ' .. info
      end
    else
      statusMsg = '❌ Error: Select a track before adding JSFX'
    end
  end
  
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, 'Clear All Notes') then
    showConfirmClear = true
    reaper.ImGui_OpenPopup(ctx, 'Confirm Clear')
  end
  
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, 'Migrate V1') then
    local ok, msg = migrateLegacyTxtFile()
    statusMsg = msg
    if ok then
      refreshAllJSFXReaders()
      if currentTrack and isValidTrack(currentTrack) then
        local trackGUID = getTrackGUID(currentTrack)
        noteText = getNoteForTrack(trackGUID)
        jsfxFontScale = getFontScaleForTrack(trackGUID)
        jsfxBgColor = getBgColorForTrack(trackGUID)
        jsfxBgColorU32 = pack_argb(jsfxBgColor[1], jsfxBgColor[2], jsfxBgColor[3], 1.0)
      end
    end
  end
  
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, ' ? ') then
    showHelpModal = true
    reaper.ImGui_OpenPopup(ctx, 'Help Guide')
  end
  
  reaper.ImGui_Spacing(ctx)
  reaper.ImGui_Text(ctx, statusMsg)
  
  if showHelpModal then
    local winX, winY = reaper.ImGui_GetWindowPos(ctx)
    local winW, winH = reaper.ImGui_GetWindowSize(ctx)
    
    local modalW = winW * 0.9
    local modalH = winH * 0.85
    if modalW > 600 then modalW = 600 end
    if modalH > 500 then modalH = 500 end
    
    reaper.ImGui_SetNextWindowSize(ctx, modalW, modalH, reaper.ImGui_Cond_Always())

    if winX and winY and winW and winH then
      local posX = winX + (winW - modalW) * 0.5
      local posY = winY + (winH - modalH) * 0.5
      reaper.ImGui_SetNextWindowPos(ctx, posX, posY, reaper.ImGui_Cond_Appearing())
    else
      local viewport = reaper.ImGui_GetMainViewport(ctx)
      local work_pos_x, work_pos_y = reaper.ImGui_Viewport_GetWorkPos(viewport)
      reaper.ImGui_SetNextWindowPos(ctx, work_pos_x + 50, work_pos_y + 50, reaper.ImGui_Cond_Appearing())
    end

    local flags = reaper.ImGui_WindowFlags_NoResize() | reaper.ImGui_WindowFlags_NoMove()
    if reaper.ImGui_BeginPopupModal(ctx, 'Help Guide', true, flags) then
      reaper.ImGui_PushTextWrapPos(ctx, 0.0)
      
      if reaper.ImGui_BeginChild(ctx, "HelpContent", 0, -48) then
        reaper.ImGui_Text(ctx, 'FLOOP SCRATCHPAD - HELP')
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Spacing(ctx)
        
        reaper.ImGui_Text(ctx, 'WHAT THIS SCRIPT DOES')
        reaper.ImGui_TextWrapped(ctx, 'Per-track notes editor for REAPER. Notes are stored in the project file (ProjExtState) and can be displayed in the track panels via a companion JSFX.')
        reaper.ImGui_Spacing(ctx)
        
        reaper.ImGui_Text(ctx, 'GETTING STARTED')
        reaper.ImGui_BulletText(ctx, 'Select a track in REAPER to start taking notes')
        reaper.ImGui_BulletText(ctx, 'The selected track name and GUID are shown in the UI')
        reaper.ImGui_BulletText(ctx, 'Notes are loaded automatically when switching tracks')
        reaper.ImGui_Spacing(ctx)
        
        reaper.ImGui_Text(ctx, 'TAKING NOTES')
        reaper.ImGui_BulletText(ctx, 'Type your notes in the text area')
        reaper.ImGui_BulletText(ctx, 'JSFX displays up to 200 characters (extra text is truncated)')
        reaper.ImGui_BulletText(ctx, 'Character count is displayed below the text area')
        reaper.ImGui_Spacing(ctx)
        
        reaper.ImGui_Text(ctx, 'SAVING & SHORTCUTS')
        reaper.ImGui_BulletText(ctx, 'Save button: manually saves notes (Ctrl+S / Cmd+S)')
        reaper.ImGui_BulletText(ctx, 'Ctrl+Enter / Cmd+Enter: save note and close the window')
        reaper.ImGui_BulletText(ctx, 'ESC: close the window (auto-saves if needed)')
        reaper.ImGui_BulletText(ctx, '+ Add JSFX: adds a visual note reader to the track TCP/MCP')
        reaper.ImGui_BulletText(ctx, 'Aa Text Size: Use slider or numeric input (14–40 px). Updates on release.')
        reaper.ImGui_BulletText(ctx, 'BG Color: pick a custom background color (with a saved palette)')
        reaper.ImGui_BulletText(ctx, 'Clear All Notes: Deletes all notes and JSFX from the current project.')
        reaper.ImGui_Spacing(ctx)
        
        reaper.ImGui_Text(ctx, 'JSFX SETUP (TCP / MCP)')
        reaper.ImGui_BulletText(ctx, 'Open FX Browser and press F5 to refresh the JSFX list')
        reaper.ImGui_BulletText(ctx, 'Find FloopNoteReader, right-click, and select "Default settings for new instance"')
        reaper.ImGui_BulletText(ctx, 'Enable "Show embedded UI in TCP or MCP"')
        reaper.ImGui_Spacing(ctx)
        
        reaper.ImGui_Text(ctx, 'DATA & MIGRATION')
        reaper.ImGui_BulletText(ctx, 'Notes are stored in the .rpp project file (ProjExtState)')
        reaper.ImGui_BulletText(ctx, 'Migrate V1: imports legacy _notes.txt files into the V2 format')
        reaper.ImGui_Spacing(ctx)
        
        reaper.ImGui_Text(ctx, 'SUPPORT')
        reaper.ImGui_TextWrapped(ctx, 'If this script saves you time, a coffee is always appreciated.')
        reaper.ImGui_Spacing(ctx)
        if reaper.ImGui_Button(ctx, "Support Floop's Reaper Scripts on Ko-fi") then
          open_url("https://ko-fi.com/floopsreaperscripts")
        end
        reaper.ImGui_EndChild(ctx)
      end
      
      reaper.ImGui_PopTextWrapPos(ctx)
      
      reaper.ImGui_Spacing(ctx)
      reaper.ImGui_Separator(ctx)
      reaper.ImGui_Spacing(ctx)
      
      local availWidth = reaper.ImGui_GetContentRegionAvail(ctx)
      local buttonWidth = 100
      reaper.ImGui_SetCursorPosX(ctx, (availWidth - buttonWidth) * 0.5)
      if reaper.ImGui_Button(ctx, 'Close', buttonWidth, 30) then
        showHelpModal = false
        reaper.ImGui_CloseCurrentPopup(ctx)
      end
      
      reaper.ImGui_EndPopup(ctx)
    else
      showHelpModal = false
    end
  end
  
  if showConfirmClear then
    local flags = reaper.ImGui_WindowFlags_NoResize() | reaper.ImGui_WindowFlags_NoMove()
    if reaper.ImGui_BeginPopupModal(ctx, 'Confirm Clear', true, flags) then
      reaper.ImGui_Text(ctx, 'Clear all saved notes? This cannot be undone.')
      if reaper.ImGui_Button(ctx, 'Yes', 100, 30) then
        local total = reaper.CountTracks(0)
        for t = 0, total - 1 do
          local tr = reaper.GetTrack(0, t)
          local guid = reaper.GetTrackGUID(tr)
          if guid then
             reaper.SetProjExtState(0, "FloopScratchpad", guid, "")
             refreshJSFXForTrack(tr)
          end
        end
        noteText = ""
        isDirty = false
        statusMsg = '✅ All notes cleared from project'
        showConfirmClear = false
        reaper.ImGui_CloseCurrentPopup(ctx)
      end
      reaper.ImGui_SameLine(ctx)
      if reaper.ImGui_Button(ctx, 'No', 100, 30) then
        showConfirmClear = false
        reaper.ImGui_CloseCurrentPopup(ctx)
      end
      reaper.ImGui_EndPopup(ctx)
    else
      showConfirmClear = false
    end
  end
  
  return requestClose
end

local non_sync_boot = true

local function mainLoop()
  local currentProject, currentProjectPath = reaper.EnumProjects(-1)
  
  if lastProjectPtr ~= nil then
    if currentProject ~= lastProjectPtr then
       -- Sync ExtState to gmem on project change
       lastProjectPtr = currentProject
       lastProjectPath = currentProjectPath
       currentTrack = nil 
       refreshAllJSFXReaders()
       statusMsg = "✅ Project changed: Notes synced"
    end
  else
    lastProjectPtr = currentProject
    lastProjectPath = currentProjectPath
  end

  reaper.ImGui_PushFont(ctx, sans_serif_font, 12)
  local color_count = apply_theme()
  
  if lastProjectPtr ~= nil and currentProject ~= lastProjectPtr then
     -- Handled above
  elseif non_sync_boot then
     refreshAllJSFXReaders()
     non_sync_boot = false
  end
  
  reaper.ImGui_SetNextWindowSizeConstraints(ctx, 440, 480, 4000, 4000)
  reaper.ImGui_SetNextWindowSize(ctx, 460, 560, reaper.ImGui_Cond_FirstUseEver())
  -- Remove NoSavedSettings to allow palette saving
  local visible, open = reaper.ImGui_Begin(ctx, 'Floop Scratchpad', true, reaper.ImGui_WindowFlags_NoCollapse())
  local requestClose = false
  
  if visible then
    requestClose = renderUI()
    reaper.ImGui_End(ctx)
  end
  
  end_theme(color_count)
  reaper.ImGui_PopFont(ctx)
  
  if open and not requestClose then
    reaper.defer(mainLoop)
  end
end

-- Init
initializeUI()
mainLoop()

reaper.atexit(function()
  if isDirty and currentTrack and isValidTrack(currentTrack) then
    performSave(currentTrack, noteText)
  end
end)
