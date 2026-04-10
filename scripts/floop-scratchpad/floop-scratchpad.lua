-- Floop Scratchpad - Per-track notes system for REAPER.
-- @description Floop Scratchpad: per-track notes system
-- @version 1.3.0
-- @author Floop-s
-- @license GPL-3.0
-- @changelog
--   + Added: Global Memory (gmem) architecture for JSFX readers, vastly improving performance.
--   + Fixed: Resolved a bug where all JSFX instances shared the same text.
--   + Fixed: Background startup script now automatically restores notes on project load.
--   + Note: Notes written in unsaved projects cannot currently be migrated. Please save your project before adding notes.
-- @about
--   Per-track notes system for REAPER.
--
--   Allows writing, viewing, and managing notes for each track.
--   Notes are automatically saved and recalled when switching tracks.
--
--   Requires:
--     - ReaImGui (ReaTeam Extensions repository), v0.10.2 or newer
--     - SWS/S&M extension
--
--   Dynamically generates a companion JSFX (FloopNoteReader)
--   to display notes in the Track Control Panel.
--
--   Keywords: notes, track, text, workflow.
-- @provides
--   [main] floop-scratchpad.lua
--   [main] floop-startup-refresh.lua


local reaper = reaper

-- Dependencies check
if not reaper or not reaper.ImGui_CreateContext then
  reaper.ShowMessageBox("ReaImGui API not found!\nPlease install 'ReaImGui' via ReaPack and restart REAPER.", "Error", 0)
  return
end

if not reaper.NF_SetProjectStartupAction then
  reaper.ShowMessageBox("SWS/S&M extension not installed.\nThe project startup action for headless refresh cannot be set automatically.\nInstall SWS to enable auto-refresh on project open.", "Floop Scratchpad", 0)
end

-- Context initialization
local ctx = reaper.ImGui_CreateContext('Floop Scratchpad')

if not ctx then
  reaper.ShowMessageBox("Failed to create ImGui context.\nPlease verify ReaImGui installation and compatibility.", "Error", 0)
  return
end

local sans_serif_font = reaper.ImGui_CreateFont('sans-serif', 12)
reaper.ImGui_Attach(ctx, sans_serif_font)

-- Theme configuration
local THEME_COLORS = {
    [reaper.ImGui_Col_WindowBg()]         = 0x1e2328FF,
    [reaper.ImGui_Col_TitleBg()]          = 0xe99854FF,
    [reaper.ImGui_Col_TitleBgActive()]    = 0xd77624FF,
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

-- Global state
local noteText = ''
local currentTrack = nil
local statusMsg = '✅ System ready'
local lastTrackGUID = nil
local showHelpModal = false
local isDirty = false
local jsfxFontScale = 1.30
local jsfxForceLarge = false
local showConfirmClear = false
local notesCache = nil
local notesCachePath = nil
local lastProjectPath = nil
local lastProjectPtr = nil

local function log(msg)
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

-- Path utilities
local function getResourcePath()
  local path = reaper.GetResourcePath()
  return path
end

local ensureDirectoryExists, readFile, writeFile, getProjectTrackGUIDSet, filterNotesByGUIDSet, isDirWritable

local function joinPath(...)
  local parts = {...}
  local sep = package.config:sub(1,1)
  return table.concat(parts, sep)
end

local function getSystemHome()
  if package.config:sub(1,1) == "\\" then
    return os.getenv("USERPROFILE") or os.getenv("HOME") or ""
  else
    return os.getenv("HOME") or ""
  end
end

local function getProjectPath()
  -- SWS/REAPER API difference handling:
  -- Force root directory of .rpp to avoid Media/Audio subfolder split
  local _, projfn = reaper.EnumProjects(-1)
  if projfn and projfn ~= "" then
    local dir = projfn:match("^(.*)[/\\]")
    if dir and dir ~= "" then
      return dir
    end
  end

  -- If EnumProjects returns empty, the project has NEVER been saved.
  local projectPath = reaper.GetProjectPath("")
  if not projectPath or projectPath == "" or not projfn or projfn == "" then
    local docs = joinPath(getSystemHome(), "Documents")
    return joinPath(docs, "REAPER Media")
  end
  
  return projectPath
end

local function getNotesFilePath()
  local projectPath = getProjectPath()

  local r1, r2 = reaper.GetProjectName(0, "")
  local projectName = (type(r2) == "string" and r2 ~= "" and r2)
                      or (type(r1) == "string" and r1 or "")
  
  if projectName == "" then
    projectName = "unsaved_project"
  else
    projectName = projectName:gsub("%.rpp$", "")
  end
  
  local candidate = joinPath(projectPath, projectName .. "_notes.txt")
  local writable = select(1, isDirWritable(candidate))
  
  if writable then
    return candidate
  else
    local fallbackDir = joinPath(getResourcePath(), "FloopNotes")
    reaper.RecursiveCreateDirectory(fallbackDir, 0)
    return joinPath(fallbackDir, projectName .. "_notes.txt")
  end
end

local function ensureDirectoryExists(filePath)
  local dir = filePath:match("^(.*)[/\\][^/\\]+$")
  if dir and dir ~= "" then
    return reaper.RecursiveCreateDirectory(dir, 0)
  end
  return false
end

local function readFile(filePath)
  local file, err = io.open(filePath, "r")
  if file then
    local content = file:read("*all")
    file:close()
    return content
  else
    return nil, err
  end
end

local function writeFile(filePath, content)
  ensureDirectoryExists(filePath)
  local file, err = io.open(filePath, "w")
  if not file then
    return false, err
  end
  file:write(content)
  file:close()
  return true
end

local function appendFile(filePath, content)
  ensureDirectoryExists(filePath)
  local file, err = io.open(filePath, "a")
  if not file then
    return false, err
  end
  file:write(content)
  file:close()
  return true
end

function isDirWritable(filePath)
  local dir = filePath:match("^(.*)[/\\][^/\\]+$")
  if not dir or dir == "" then return false, "Invalid directory" end
  local sep = package.config:sub(1,1)
  local testPath = dir .. sep .. ".floop_writable_test_" .. tostring(math.random(1000000))
  local f, err = io.open(testPath, "w")
  if not f then return false, err end
  f:write("ok")
  f:close()
  os.remove(testPath)
  return true
end

-- Data management
local function loadNotesFromFile()
  local filePath = getNotesFilePath()
  if notesCache and notesCachePath == filePath then
    return notesCache
  end
  local content, err = readFile(filePath)
  
  if content and content:match("%S") then
    notesCache = content
    notesCachePath = filePath
    return content
  end
  
  local projectPath = reaper.GetProjectPath("")
  if projectPath ~= "" then
    local docs = joinPath(getSystemHome(), "Documents")
    local reaperMedia = joinPath(docs, "REAPER Media")
    local unsavedPath = joinPath(reaperMedia, "unsaved_project_notes.txt")
    local unsavedContent = readFile(unsavedPath)
    
    if unsavedContent and unsavedContent:match("%S") then
      local success, err = writeFile(filePath, unsavedContent)
      if success then
        local ts = os.date('%Y%m%d_%H%M%S')
        local backup = joinPath(reaperMedia, 'unsaved_project_notes.bak.' .. ts .. '.txt')
        writeFile(backup, unsavedContent)
        os.remove(unsavedPath)
        notesCache = unsavedContent
        notesCachePath = filePath
        return unsavedContent
      end
    end
    
    local desktop = joinPath(getSystemHome(), "Desktop")
    local legacyPath = joinPath(desktop, "unsaved_project_notes.txt")
    local legacyContent = readFile(legacyPath)
    
    if legacyContent and legacyContent:match("%S") then
      local success, err = writeFile(filePath, legacyContent)
      if success then
        local ts = os.date('%Y%m%d_%H%M%S')
        local backup = joinPath(desktop, 'unsaved_project_notes.bak.' .. ts .. '.txt')
        writeFile(backup, legacyContent)
        os.remove(legacyPath)
        notesCache = legacyContent
        notesCachePath = filePath
        return legacyContent
      end
    end
    
    if not content then
      writeFile(filePath, "")
      notesCache = ""
      notesCachePath = filePath
      return ""
    end
    notesCache = content or ""
    notesCachePath = filePath
    return content or ""
  else
    local docs = joinPath(getSystemHome(), "Documents")
    local reaperMedia = joinPath(docs, "REAPER Media")
    local fallbackPath = joinPath(reaperMedia, "unsaved_project_notes.txt")
    local fallbackContent = readFile(fallbackPath)
    
    if fallbackContent and fallbackContent:match("%S") then
      notesCache = fallbackContent
      notesCachePath = filePath
      return fallbackContent
    end
    
    local desktop = joinPath(getSystemHome(), "Desktop")
    local legacyPath = joinPath(desktop, "unsaved_project_notes.txt")
    local legacyContent = readFile(legacyPath)
    
    if legacyContent and legacyContent:match("%S") then
      notesCache = legacyContent
      notesCachePath = filePath
      return legacyContent
    end
  end
  
  notesCache = ""
  notesCachePath = filePath
  return ""
end

local function saveNotesToFile(notes)
  local filePath = getNotesFilePath()
  local oldContent = select(1, readFile(filePath))
  local writable, werr = isDirWritable(filePath)
  if not writable then
    -- logError("Write permission error for " .. filePath .. ": " .. tostring(werr))
    return false, werr or "Permission denied"
  end
  local success, err = writeFile(filePath, notes)
  if success then
    notesCache = notes
    notesCachePath = filePath
    return true, filePath
  else
    -- logError("Failed to write notes to " .. filePath .. ": " .. tostring(err))
    if oldContent ~= nil then
      local rbOk = select(1, writeFile(filePath, oldContent))
    end
    return false, err or "Error writing file"
  end
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
  if not isValidTrack(track) then
    return nil
  end
  return reaper.GetTrackGUID(track)
end

local function getTrackName(track)
  if not isValidTrack(track) then
    return "Unknown Track"
  end
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
  local allNotes = loadNotesFromFile() or ""
  if allNotes == "" then return "" end

  local padded = allNotes:gsub("\r\n", "\n")
  if not padded:match("\n=====\n$") then padded = padded .. "\n=====\n" end

  for block in padded:gmatch("(.-)\n=====\n") do
    if block:match("%S") then
      local guid = block:match("GUID:%s*(%S+)")
      if guid == trackGUID then
        local contentPos = block:find("Content:")
        if contentPos then
          local content = block:sub(contentPos + #("Content:"))
          content = content:gsub("^%s*", "")
          return content
        end
        return ""
      end
    end
  end
  return ""
end

local function getFontScaleForTrack(trackGUID)
  if not trackGUID then return 1.30 end
  local allNotes = loadNotesFromFile() or ""
  if allNotes == "" then return 1.30 end

  local padded = allNotes:gsub("\r\n", "\n")
  if not padded:match("\n=====\n$") then padded = padded .. "\n=====\n" end

  for block in padded:gmatch("(.-)\n=====\n") do
    if block:match("%S") then
      local guid = block:match("GUID:%s*(%S+)")
      if guid == trackGUID then
        local fs = block:match("FontScale:%s*([%d%.]+)")
        local n = tonumber(fs)
        if n then return n end
        break
      end
    end
  end
  return 1.30
end

local function saveNoteForTrack(trackGUID, noteContent)
  if not trackGUID then return false, "Missing track GUID" end
  local allNotes = loadNotesFromFile() or ""

  local padded = allNotes:gsub("\r\n", "\n")
  if not padded:match("\n=====\n$") then padded = padded .. "\n=====\n" end

  local blocks = {}
  
  for block in padded:gmatch("(.-)\n=====\n") do
    if block:match("%S") then
      local guid = block:match("GUID:%s*(%S+)")
      if guid and guid ~= trackGUID then
        table.insert(blocks, block)
      end
    end
  end

  local newNote = "GUID: " .. trackGUID .. "\nFontScale: " .. (jsfxFontScale or 1.30) .. "\nContent: " .. (noteContent or "")
  table.insert(blocks, newNote)

  local newAll = table.concat(blocks, "\n=====\n") .. "\n=====\n"
  local success, info = saveNotesToFile(newAll)
  return success, info
end

-- Track ID & gmem synchronization
local function getTrackID(track)
  local retval, id_str = reaper.GetSetMediaTrackInfo_String(track, "P_EXT:FLOOP_NOTE_ID", "", false)
  if retval and id_str ~= "" then
    return tonumber(id_str)
  else
    local _, max_id_str = reaper.GetProjExtState(0, "FloopScratchpad", "MaxTrackID")
    local new_id = (tonumber(max_id_str) or 0) + 1
    reaper.SetProjExtState(0, "FloopScratchpad", "MaxTrackID", tostring(new_id))
    reaper.GetSetMediaTrackInfo_String(track, "P_EXT:FLOOP_NOTE_ID", tostring(new_id), true)
    return new_id
  end
end

local function writeNoteToGmem(track_id, noteContent, fontScale, forceLarge)
  reaper.gmem_attach("FloopScratchpad")
  local offset = track_id * 256
  local safeNote = noteContent or ""
  if #safeNote > 200 then safeNote = safeNote:sub(1, 200) .. "..." end
  local len = #safeNote
  reaper.gmem_write(offset, len)
  for i = 1, len do
    reaper.gmem_write(offset + i, string.byte(safeNote, i))
  end
  reaper.gmem_write(offset + 250, fontScale or 1.30)
  reaper.gmem_write(offset + 251, forceLarge and 1 or 0)
  
  local ver = reaper.gmem_read(offset + 255)
  reaper.gmem_write(offset + 255, (ver + 1) % 1000000)
end

-- Static JSFX creation
local JSFX_FILE_NAME = 'FloopNoteReader.jsfx'

local function createStaticJSFXFile()
  local resourcePath = getResourcePath()
  local effectsDir = joinPath(resourcePath, 'Effects')
  local jsfxPath = joinPath(effectsDir, JSFX_FILE_NAME)
  
  reaper.RecursiveCreateDirectory(effectsDir, 0)
  
  local jsfxContent = [[desc:Floop Note Reader
// @version 1.3.0
// @author Floop-s
// @about Static JSFX reader for Floop Scratchpad. Uses gmem to receive notes.

slider1:0<0,1000000,1>-Track ID (Hidden)

options:gmem=FloopScratchpad

@init
last_version = -1;
last_track_id = -1;
init_done = 0;

@gfx 400 140
track_id = slider1;
offset = track_id * 256;
version = gmem[offset + 255];

track_id != last_track_id || version != last_version || init_done == 0 ? (
  init_done = 1;
  last_track_id = track_id;
  last_version = version;
  len = gmem[offset];
  #note_text = "";
  i = 0;
  while (i < len && i < 200) (
    char = gmem[offset + 1 + i];
    sprintf(#char_str, "%c", char);
    strcat(#note_text, #char_str);
    i += 1;
  );
  font_scale = gmem[offset + 250];
  font_scale <= 0 ? font_scale = 1.30 : font_scale;
  force_big = gmem[offset + 251];
);

track_id = slider1;
offset = track_id * 256;
version = gmem[offset + 255];

gfx_r = 0.93; gfx_g = 0.95; gfx_b = 0.65;
gfx_rect(0,0,gfx_w,gfx_h);

pad = 6;
area_w = max(10, gfx_w - pad*2);
area_h = max(10, gfx_h - pad*2);

compact = (gfx_w < 260) || (gfx_h < 90);
base_sz = (compact ? 14 : 18) * font_scale;
sz = min(max(base_sz, 12), 40);

force_big ? (
  sz = sz;
) : (
  while (sz > 10 && area_w < (sz*3)) (
    sz -= 1;
  );
);

gfx_setfont(1, "sans-serif", sz);

strlen(#note_text) > 0 ? (
  gfx_r = 0.31; gfx_g = 0.31; gfx_b = 0.30;
  gfx_x = pad; gfx_y = pad; gfx_drawstr(#note_text);
) : (
  gfx_r = 0.8; gfx_g = 0.5; gfx_b = 0.5;
  gfx_x = pad; gfx_y = pad; gfx_drawstr("No saved note for this track");
);
]]

  local existingContent = select(1, readFile(jsfxPath))
  if existingContent == jsfxContent then
    return true, jsfxPath
  end
  
  local writable, werr = isDirWritable(jsfxPath)
  if not writable then
    return false, "JSFX path not writable"
  end
  local file, ferr = io.open(jsfxPath, 'w')
  if file then
    file:write(jsfxContent)
    file:close()
    return true, jsfxPath
  else
    return false, "Cannot create JSFX file"
  end
end

-- JSFX insertion & refreshing
local function addJSFXToTrack(track, fontScale, forceLarge)
  if not isValidTrack(track) then
    return false, "No valid track selected"
  end
  
  local trackGUID = getTrackGUID(track)
  local noteContent = getNoteForTrack(trackGUID)
  local track_id = getTrackID(track)
  
  writeNoteToGmem(track_id, noteContent, fontScale, forceLarge)
  
  local fxCount = reaper.TrackFX_GetCount(track)
  for i = 0, fxCount - 1 do
    local _, fxName = reaper.TrackFX_GetFXName(track, i, '')
    if fxName and (fxName:find('FloopNoteReader') or fxName:find('Floop Note Reader')) then
      reaper.TrackFX_SetParam(track, i, 0, track_id)
      return true, "JSFX already present on this track (no new instance)"
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
    reaper.TrackList_AdjustWindows(false)
    reaper.UpdateArrange()
    return true, "JSFX added to track with dynamic notes (embedded in TCP)"
  else
    return false, "Error adding JSFX"
  end
end

local function refreshJSFXForTrack(track)
  if not track then return end
  local trackGUID = getTrackGUID(track)
  local noteContent = getNoteForTrack(trackGUID)
  local track_id = getTrackID(track)
  local scale = getFontScaleForTrack(trackGUID)
  
  local hasNotes = noteContent and noteContent:match('%S')
  local hasJSFX = false
  local fxCount = reaper.TrackFX_GetCount(track)
  
  if hasNotes then
    writeNoteToGmem(track_id, noteContent, scale, false)
  end
  
  for i = fxCount - 1, 0, -1 do
    local _, fxName = reaper.TrackFX_GetFXName(track, i, '')
    if fxName and (fxName:find('FloopNoteReader') or fxName:find('Floop Note Reader')) then
      hasJSFX = true
      if not hasNotes then
        reaper.TrackFX_Delete(track, i)
      else
        reaper.TrackFX_SetParam(track, i, 0, track_id)
      end
    end
  end
  
  if hasNotes and not hasJSFX then
    addJSFXToTrack(track, scale, false)
  end
end

local function refreshAllJSFXReaders()
  createStaticJSFXFile()
  
  local total = reaper.CountTracks(0)
  for t = 0, total - 1 do
    local tr = reaper.GetTrack(0, t)
    local trackGUID = getTrackGUID(tr)
    local noteContent = getNoteForTrack(trackGUID)
    
    if noteContent and noteContent:match('%S') then
      local track_id = getTrackID(tr)
      local scale = getFontScaleForTrack(trackGUID)
      writeNoteToGmem(track_id, noteContent, scale, false)
      
      local fxCount = reaper.TrackFX_GetCount(tr)
      for i = 0, fxCount - 1 do
        local _, fxName = reaper.TrackFX_GetFXName(tr, i, '')
        if fxName and (fxName:find('FloopNoteReader') or fxName:find('Floop Note Reader')) then
          reaper.TrackFX_SetParam(tr, i, 0, track_id)
        end
      end
    end
  end
end

-- UI Functions
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
  else
    noteText = ""
    jsfxFontScale = 1.30
  end
end

local function renderUI()
  local newSelectedTrack = getSelectedTrack()
  if newSelectedTrack ~= currentTrack then
    if isDirty and isValidTrack(currentTrack) then
      local trackGUID = getTrackGUID(currentTrack)
      local success, info = saveNoteForTrack(trackGUID, noteText)
      if success then
        statusMsg = '✅ Note autosaved for track: ' .. getTrackName(currentTrack)
        isDirty = false
        refreshJSFXForTrack(currentTrack)
      else
        statusMsg = '❌ Autosave failed: ' .. (info or 'unknown')
      end
    end
    
    currentTrack = newSelectedTrack
    if currentTrack and isValidTrack(currentTrack) then
      local trackGUID = getTrackGUID(currentTrack)
      noteText = getNoteForTrack(trackGUID)
      jsfxFontScale = getFontScaleForTrack(trackGUID)
      isDirty = false
    else
      noteText = ""
      jsfxFontScale = 1.30
    end
  end
  
  reaper.ImGui_Text(ctx, '✅ Floop Scratchpad')
  reaper.ImGui_Separator(ctx)
  
  if currentTrack and isValidTrack(currentTrack) then
    local trackName = getTrackName(currentTrack)
    local trackGUID = getTrackGUID(currentTrack)
    reaper.ImGui_Text(ctx, '🎯 Track: ' .. trackName)
    reaper.ImGui_Text(ctx, '🔑 GUID: ' .. trackGUID)
  else
    reaper.ImGui_Text(ctx, '⚠️  No track selected')
  end
  
  local notesPath = getNotesFilePath()
  reaper.ImGui_Text(ctx, '📁 Notes file: ' .. notesPath)
  
  reaper.ImGui_Separator(ctx)
  reaper.ImGui_Text(ctx, '📝 Notes:')
  
  local availWidth, availHeight = reaper.ImGui_GetContentRegionAvail(ctx)
  local textareaWidth = math.max(150, availWidth - 10)
  local textareaHeight = math.max(120, math.min(150, availHeight - 120)) 
  
  local changed, newText = reaper.ImGui_InputTextMultiline(ctx, '##note_textarea', noteText, textareaWidth, textareaHeight)
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
  
  reaper.ImGui_Text(ctx, '🔡 JSFX font')
  reaper.ImGui_SameLine(ctx)
  reaper.ImGui_TextDisabled(ctx, string.format("%d px", currentAbsSize))
  
  local scaleChanged, newScale = SliderFloatCompat('##jsfx_font_scale', jsfxFontScale, 0.8, 2.25)
  if scaleChanged then
    jsfxFontScale = newScale
    isDirty = true
  end
  
  if reaper.ImGui_IsItemDeactivatedAfterEdit and reaper.ImGui_IsItemDeactivatedAfterEdit(ctx) then
    if currentTrack and isValidTrack(currentTrack) then
      local trackGUID = getTrackGUID(currentTrack)
      local saved, err = saveNoteForTrack(trackGUID, noteText)
      
      if saved then
        refreshJSFXForTrack(currentTrack)
        statusMsg = '✅ Font scale updated'
        isDirty = false
      else
        statusMsg = '❌ Autosave failed: ' .. (err or "unknown")
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
      local trackGUID = getTrackGUID(currentTrack)
      local saved, err = saveNoteForTrack(trackGUID, noteText)
      if saved then
        refreshJSFXForTrack(currentTrack)
        statusMsg = '✅ Font size updated'
        isDirty = false
      else
        statusMsg = '❌ Autosave failed: ' .. (err or "unknown")
      end
    end
  end
  reaper.ImGui_Spacing(ctx)
  
  if reaper.ImGui_Button(ctx, '💾 Save') then
    if currentTrack and isValidTrack(currentTrack) then
      local trackGUID = getTrackGUID(currentTrack)
      local success, info = saveNoteForTrack(trackGUID, noteText)
      if success then
        statusMsg = '✅ Note saved for track: ' .. getTrackName(currentTrack)
        
        -- Update JSFX
        local track_id = getTrackID(currentTrack)
        local hasNotes = noteText and noteText:match('%S')
        local fxCount = reaper.TrackFX_GetCount(currentTrack)
        local hasJSFX = false
        
        if hasNotes then
          writeNoteToGmem(track_id, noteText, jsfxFontScale, jsfxForceLarge)
        end
        
        for i = fxCount - 1, 0, -1 do
          local _, fxName = reaper.TrackFX_GetFXName(currentTrack, i, '')
          
          -- Search for "FloopNoteReader" or "Floop Note Reader"
          if fxName:find('FloopNoteReader') or fxName:find('Floop Note Reader') then
            hasJSFX = true
            if not hasNotes then
              reaper.TrackFX_Delete(currentTrack, i)
              statusMsg = statusMsg .. ' - JSFX removed (empty note)'
            else
              reaper.TrackFX_SetParam(currentTrack, i, 0, track_id)
              statusMsg = statusMsg .. ' - JSFX updated automatically'
            end
          end
        end
        
        if hasNotes and not hasJSFX then
           local newSuccess, newInfo = addJSFXToTrack(currentTrack, jsfxFontScale, jsfxForceLarge)
           if newSuccess then
             statusMsg = statusMsg .. ' - JSFX updated automatically'
           else
             statusMsg = statusMsg .. ' - Error updating JSFX'
           end
        end
        
      else
        statusMsg = '❌ Error: ' .. info
      end
    else
      statusMsg = '❌ Error: Select a track before saving'
    end
  end
  
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, '🎨 Add JSFX') then
    if currentTrack and isValidTrack(currentTrack) then
      local success, info = addJSFXToTrack(currentTrack, jsfxFontScale, jsfxForceLarge)
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
  if reaper.ImGui_Button(ctx, '🗑 Clear Note File') then
    showConfirmClear = true
    reaper.ImGui_OpenPopup(ctx, 'Confirm Clear')
  end
  
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, '❔ Help') then
    showHelpModal = true
    reaper.ImGui_OpenPopup(ctx, 'Help Guide')
  end
  
  if showHelpModal then
    local modalW, modalH = 600, 500
    reaper.ImGui_SetNextWindowSize(ctx, modalW, modalH, reaper.ImGui_Cond_Always())

    local winX, winY = reaper.ImGui_GetWindowPos(ctx)
    local winW, winH = reaper.ImGui_GetWindowSize(ctx)
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
      reaper.ImGui_Text(ctx, '📖 Floop Scratchpad - User Guide')
      reaper.ImGui_Separator(ctx)
      reaper.ImGui_Spacing(ctx)
      
      reaper.ImGui_Text(ctx, '🚀 Getting Started:')
      reaper.ImGui_BulletText(ctx, 'Select a track in REAPER to start taking notes')
      reaper.ImGui_BulletText(ctx, 'The track name and GUID will appear in the interface')
      reaper.ImGui_BulletText(ctx, 'Notes are automatically loaded when switching tracks')
      reaper.ImGui_BulletText(ctx, 'JSFX Setup: open FX Browser and press F5 to refresh plugins')
      reaper.ImGui_BulletText(ctx, 'Find FloopNoteReader, right-click and select "Default settings for new instance"')
      reaper.ImGui_BulletText(ctx, 'Enable "Show embedded UI in TCP or MCP" for automatic display')
      reaper.ImGui_Spacing(ctx)
      
      reaper.ImGui_Text(ctx, '📝 Taking Notes:')
      reaper.ImGui_BulletText(ctx, 'Type your notes in the text area')
      reaper.ImGui_BulletText(ctx, 'JSFX displays up to 200 characters (extra text is truncated)')
      reaper.ImGui_BulletText(ctx, 'Character count is displayed below the text area')
      reaper.ImGui_Spacing(ctx)
      
      reaper.ImGui_Text(ctx, '💾 Saving & JSFX:')
      reaper.ImGui_BulletText(ctx, '💾 Save: Manually saves notes to the file')
      reaper.ImGui_BulletText(ctx, '🎨 Add JSFX: Adds a visual note reader to the track TCP')
      reaper.ImGui_BulletText(ctx, '🔡 Font Size: Use slider or numeric input (14–40 px). Updates on release.')
      reaper.ImGui_BulletText(ctx, '🔁 Autosave: Notes are saved automatically when switching tracks or tabs')
      reaper.ImGui_BulletText(ctx, '🗓 Startup: Notes restore automatically. SWS extension enables auto-refresh.')
      reaper.ImGui_BulletText(ctx, '🗑️ Clear: Deletes all notes for the current project (creates backup)')
      reaper.ImGui_Spacing(ctx)
      
      reaper.ImGui_Text(ctx, '📁 File Management:')
      reaper.ImGui_BulletText(ctx, 'Saved Projects: Notes stored in [ProjectName]_notes.txt')
      reaper.ImGui_BulletText(ctx, 'Unsaved Projects: Notes stored in a central fallback file')
      reaper.ImGui_BulletText(ctx, '⚠️ Migration: Notes from unsaved projects cannot currently be migrated. Please save your project first.')
      reaper.ImGui_BulletText(ctx, '📍 Path: The current note file path is displayed in the main window.')
      reaper.ImGui_Spacing(ctx)
      
      reaper.ImGui_Text(ctx, '💡 Tips:')
      reaper.ImGui_BulletText(ctx, 'Keep notes concise for better JSFX display')
      reaper.ImGui_BulletText(ctx, 'Use the JSFX for quick reference while mixing')
      reaper.ImGui_BulletText(ctx, 'Notes and font settings persist across REAPER sessions')
      reaper.ImGui_BulletText(ctx, 'Each track has its own note and font settings')
      
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
        local filePath = getNotesFilePath()
        local existing, _ = readFile(filePath)
        if existing and existing ~= "" then
          local ts = os.date('%Y%m%d_%H%M%S')
          local backupPath = filePath .. '.bak.' .. ts
          local okb, errb = writeFile(backupPath, existing)
        if not okb then
          statusMsg = '❌ Backup failed: ' .. (errb or 'unknown')
          -- logError('Backup failed: ' .. tostring(errb))
        end
      end
      local ok, err = writeFile(filePath, "")
      if ok then
        notesCache = ""
        notesCachePath = filePath
        noteText = ""
        isDirty = false
        statusMsg = '✅ Note file cleared (backup created)'
        refreshAllJSFXReaders()
      else
        statusMsg = '❌ Error clearing note file: ' .. (err or "unknown")
        -- logError('Clear failed: ' .. tostring(err))
      end
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
  
  reaper.ImGui_Spacing(ctx)
  reaper.ImGui_Separator(ctx)
  
  reaper.ImGui_Text(ctx, statusMsg)
  reaper.ImGui_Spacing(ctx)
end

-- SWS Project Startup Action setup
local function SetupProjectStartupAction()
    if not reaper.NF_SetProjectStartupAction then return end

    local _, this_file = reaper.get_action_context()
    local dir = this_file:match('^(.+)[\\/]')
    if not dir then return end
    
    local sep = package.config:sub(1, 1)
    local target = dir .. sep .. 'floop-startup-refresh.lua'
    
    local f = io.open(target, "r")
    if not f then return end
    f:close()

    local cmd_id = reaper.AddRemoveReaScript(true, 0, target, true)
    if cmd_id == 0 then return end
    
    local named = '_' .. reaper.ReverseNamedCommandLookup(cmd_id)
    if not named or named == '_' then return end

    reaper.NF_SetProjectStartupAction(named)
end

pcall(SetupProjectStartupAction)

-- Main execution loop
local function mainLoop()
  local currentProject, currentProjectPath = reaper.EnumProjects(-1)
  
  if lastProjectPtr ~= nil then
    if currentProject == lastProjectPtr then
      if currentProjectPath ~= lastProjectPath then
        if notesCache and notesCache:match("%S") then
          local saved, path = saveNotesToFile(notesCache)
          if saved then
            statusMsg = "✅ Project saved: Notes migrated to new location"
          else
            -- logError("In-memory migration failed.")
            statusMsg = "❌ Migration failed"
          end
        end
        lastProjectPath = currentProjectPath
      end
    else
      if currentProject ~= lastProjectPtr then
         notesCache = nil
         notesCachePath = nil
         lastProjectPtr = currentProject
         lastProjectPath = currentProjectPath
         currentTrack = nil 
      end
    end
  else
    lastProjectPtr = currentProject
    lastProjectPath = currentProjectPath
  end

  reaper.ImGui_PushFont(ctx, sans_serif_font, 12)
  local color_count = apply_theme()
  
  reaper.ImGui_SetNextWindowSize(ctx, 460, 560, reaper.ImGui_Cond_FirstUseEver())
  local visible, open = reaper.ImGui_Begin(ctx, 'Floop Scratchpad', true, reaper.ImGui_WindowFlags_NoCollapse())
  
  if visible then
    renderUI()
    reaper.ImGui_End(ctx)
  end
  
  end_theme(color_count)
  reaper.ImGui_PopFont(ctx)
  
  if open then
    reaper.defer(mainLoop)
  end
end

-- Init
initializeUI()
mainLoop()
