-- @description Floop Startup Refresh
-- @version 1.3.0
-- @author Floop-s
-- @date 17-02-2026
-- @noindex


-- Purpose: Refresh per-track JSFX note readers on project load.
-- Reads the notes file, rewrites the shared JSFX, and re-inserts it only on tracks with non-empty notes.

local reaper = reaper

-- Path utilities
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
  -- Extracts root project path, bypassing GetProjectPath media directory overrides.
  local _, projfn = reaper.EnumProjects(-1)
  if projfn and projfn ~= "" then
    local dir = projfn:match("^(.*)[/\\]")
    if dir and dir ~= "" then
      return dir
    end
  end

  -- Fallback for unsaved projects.
  local projectPath = reaper.GetProjectPath("")
  if not projectPath or projectPath == "" or not projfn or projfn == "" then
    local docs = joinPath(getSystemHome(), "Documents")
    return joinPath(docs, "REAPER Media")
  end
  
  return projectPath
end



local function isDirWritable(filePath)
  local dir = filePath:match("^(.*)[/\\][^/\\]+$")
  if not dir or dir == "" then return false end
  local sep = package.config:sub(1,1)
  local testPath = dir .. sep .. ".floop_writable_test_" .. tostring(math.random(1000000))
  local f = io.open(testPath, "w")
  if not f then return false end
  f:write("ok")
  f:close()
  os.remove(testPath)
  return true
end

local function getNotesFilePath()
  local projectPath = getProjectPath()
  local r1, r2 = reaper.GetProjectName(0, "")
  local projectName = (type(r2) == "string" and r2 ~= "" and r2) or (type(r1) == "string" and r1 or "")
  if projectName == "" then
    projectName = "unsaved_project"
  else
    projectName = projectName:gsub("%.rpp$", "")
  end
  
  local candidate = joinPath(projectPath, projectName .. "_notes.txt")
  local writable = isDirWritable(candidate)
  if writable then
    return candidate
  else
    local fallbackDir = joinPath(reaper.GetResourcePath(), "FloopNotes")
    reaper.RecursiveCreateDirectory(fallbackDir, 0)
    return joinPath(fallbackDir, projectName .. "_notes.txt")
  end
end

local function readFile(filePath)
  local f = io.open(filePath, "r")
  if not f then return nil end
  local c = f:read("*all")
  f:close()
  return c
end

-- Data parsers
local function getNoteForGUID(allNotes, guid)
  if not allNotes or allNotes == "" or not guid then return "" end
  
  local padded = allNotes:gsub("\r\n", "\n")
  if not padded:match("\n=====\n$") then padded = padded .. "\n=====\n" end
  
  for block in padded:gmatch("(.-)\n=====\n") do
    if block:match("%S") then
      local bguid = block:match("GUID:%s*(%S+)")
      if bguid == guid then
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

local function getFontScaleForGUID(allNotes, guid)
  if not allNotes or allNotes == "" or not guid then return 1.30 end
  
  local padded = allNotes:gsub("\r\n", "\n")
  if not padded:match("\n=====\n$") then padded = padded .. "\n=====\n" end
  
  for block in padded:gmatch("(.-)\n=====\n") do
    if block:match("%S") then
      local bguid = block:match("GUID:%s*(%S+)")
      if bguid == guid then
        local fs = block:match("FontScale:%s*([%d%.]+)")
        local n = tonumber(fs)
        if n then return n end
        break
      end
    end
  end
  return 1.30
end

-- Static JSFX creation
local function createStaticJSFXFile()
  local resourcePath = reaper.GetResourcePath()
  local effectsDir = joinPath(resourcePath, 'Effects')
  local jsfxPath = joinPath(effectsDir, 'FloopNoteReader.jsfx')
  reaper.RecursiveCreateDirectory(effectsDir, 0)

  local jsfx = [[desc:Floop Note Reader
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

  local existingContent = readFile(jsfxPath)
  if existingContent == jsfx then
    return true, jsfxPath
  end
  
  if not isDirWritable(jsfxPath) then
    return false, 'Cannot create JSFX file'
  end
  local f, ferr = io.open(jsfxPath, 'w')
  if not f then
    return false, 'Cannot create JSFX file'
  end
  f:write(jsfx)
  f:close()
  return true, jsfxPath
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

-- Data initialization
local function readNotesWithFallback()
  local primary = getNotesFilePath()
  local c = readFile(primary)
  if c and c:match("%S") then return c end
  
  local projectPath = reaper.GetProjectPath("")
  if projectPath ~= "" then
    local docs = joinPath(getSystemHome(), "Documents")
    local reaperMedia = joinPath(docs, "REAPER Media")
    local unsavedPath = joinPath(reaperMedia, "unsaved_project_notes.txt")
    local unsavedContent = readFile(unsavedPath)
    
    if unsavedContent and unsavedContent:match("%S") then
      local file = io.open(primary, "w")
      if file then
        file:write(unsavedContent)
        file:close()
        local ts = os.date('%Y%m%d_%H%M%S')
        local backup = joinPath(reaperMedia, 'unsaved_project_notes.bak.' .. ts .. '.txt')
        local bf = io.open(backup, 'w')
        if bf then bf:write(unsavedContent); bf:close() end
        os.remove(unsavedPath)
        return unsavedContent
      end
    end
    
    local desktop = joinPath(getSystemHome(), "Desktop")
    local legacyPath = joinPath(desktop, "unsaved_project_notes.txt")
    local legacyContent = readFile(legacyPath)
    if legacyContent and legacyContent:match("%S") then
      local file = io.open(primary, "w")
      if file then
        file:write(legacyContent)
        file:close()
        local ts = os.date('%Y%m%d_%H%M%S')
        local backup = joinPath(desktop, 'unsaved_project_notes.bak.' .. ts .. '.txt')
        local bf = io.open(backup, 'w')
        if bf then bf:write(legacyContent); bf:close() end
        os.remove(legacyPath)
        return legacyContent
      end
    end
    
    if not c then
      local f = io.open(primary, "w")
      if f then f:write(""); f:close() end
      return ""
    end
    return c or ""
  else
    local docs = joinPath(getSystemHome(), "Documents")
    local reaperMedia = joinPath(docs, "REAPER Media")
    local fallback = joinPath(reaperMedia, "unsaved_project_notes.txt")
    local fc = readFile(fallback)
    if fc and fc:match("%S") then return fc end
    
    local desktop = joinPath(getSystemHome(), "Desktop")
    local legacy = joinPath(desktop, "unsaved_project_notes.txt")
    local lc = readFile(legacy)
    if lc and lc:match("%S") then return lc end
    return ""
  end
  
  return ""
end

-- Refresh execution
local function refreshAll()
  local notes = readNotesWithFallback()
  
  local ok = createStaticJSFXFile()
  if not ok then return end
  
  local total = reaper.CountTracks(0)
  
  for t = 0, total - 1 do
    local tr = reaper.GetTrack(0, t)
    local guid = reaper.GetTrackGUID(tr)
    local note = getNoteForGUID(notes, guid)
    local scale = getFontScaleForGUID(notes, guid)
    
    if note and note:match('%S') then
      local track_id = getTrackID(tr)
      writeNoteToGmem(track_id, note, scale, false)
      
      local fxCount = reaper.TrackFX_GetCount(tr)
      for i = 0, fxCount - 1 do
        local _, fxName = reaper.TrackFX_GetFXName(tr, i, '')
        if fxName and (fxName:find('FloopNoteReader') or fxName:find('Floop Note Reader')) then
          reaper.TrackFX_SetParam(tr, i, 0, track_id)
        end
      end
    end
  end
  reaper.TrackList_AdjustWindows(false)
  reaper.UpdateArrange()
end

refreshAll()
