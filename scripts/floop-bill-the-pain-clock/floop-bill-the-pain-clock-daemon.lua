-- @noindex
-- @description Floop Bill The Pain Clock (Daemon)
-- @version 1.0.0
-- @author Floop-s
-- @license GPL-3.0
-- @about
--   Background engine for Floop Bill The Pain Clock.
--   This script is automatically launched by REAPER on startup (if enabled in the main UI).
--   It tracks time and manages states for all open projects without requiring the UI to be open.

local EXT_SECTION = "FLOOP_BILL_PAIN_CLOCK"
local EXT_KEY = "v2"
local PROJ_ID_KEY = "PERSIST_ID"

local KEY_HB = "DAEMON_HB"
local KEY_LOCK = "DAEMON_LOCK"
local KEY_CMD = "CMD"
local KEY_CMD_ACK = "CMD_ACK"
local KEY_LIVE_PREFIX = "LIVE_"
local KEY_DAEMON_CPU = "DAEMON_CPU"

local IDLE_SEC = 300
local ACTIVITY_POLL_SEC = 1.0
local LIVE_POLL_SEC = 0.25
local DAEMON_ALIVE_SEC = 5.0
local DAEMON_LOCK_SEC = 5.0

local function now() return reaper.time_precise() end
local function clamp0(x) return (x and x > 0) and x or 0 end

local function proj_guid(proj)
  if type(proj) ~= "userdata" then return "" end
  if not reaper.GetProjectGUID then return "" end
  return reaper.GetProjectGUID(proj) or ""
end

local function proj_persist_id(proj)
  if type(proj) ~= "userdata" then return "" end
  
  local guid = reaper.GetProjectGUID and (reaper.GetProjectGUID(proj) or "") or ""
  local _, id = reaper.GetProjExtState(proj, EXT_SECTION, PROJ_ID_KEY)
  
  if not id or id == "" then
    id = reaper.genGuid and reaper.genGuid("") or string.format("PERSIST_%d", math.floor(now() * 1000000))
    reaper.SetProjExtState(proj, EXT_SECTION, PROJ_ID_KEY, id)
  end
  
  return id
end

local function serialize(d, guid)
  local parts = {
    "6", -- Bumped serialization version to 6 for notes
    guid or "",
    tostring(d.phase or 1),
    (d.auto_tracking and "1" or "0"),
    tostring(d.autosave_min or 10),
    tostring(#(d.sessions or {}))
  }
  
  for _, sess in ipairs(d.sessions or {}) do
    local encoded_note = ""
    if sess.note and sess.note ~= "" then
      -- Base64 encode the note
      local b='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
      encoded_note = ((sess.note:gsub('.', function(x) 
          local r,b='',x:byte()
          for i=8,1,-1 do r=r..(b%2^i-b%2^(i-1)>0 and '1' or '0') end
          return r;
      end)..'0000'):gsub('%d%d%d?%d?%d?%d?', function(x)
          if (#x < 6) then return '' end
          local c=0
          for i=1,6 do c=c+(x:sub(i,i)=='1' and 2^(6-i) or 0) end
          return b:sub(c+1,c+1)
      end)..({ '', '==', '=' })[#sess.note%3+1])
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
          if (v == "6" or v == "5") and s_parts[8] and s_parts[8] ~= "" then
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
  if d.phase > 6 then d.phase = 6 end
  
  if #d.sessions == 0 then
    table.insert(d.sessions, { start_time = os.time(), t = {0,0,0,0,0,0} })
  end

  for _, sess in ipairs(d.sessions) do
    for i = 1, 6 do sess.t[i] = clamp0(sess.t[i]) end
  end

  return d
end

local function get_current_session(d)
  if not d.sessions or #d.sessions == 0 then
    d.sessions = { { start_time = os.time(), t = {0,0,0,0,0,0} } }
  end
  return d.sessions[#d.sessions]
end

local function add_new_session(d)
  table.insert(d.sessions, { start_time = os.time(), t = {0,0,0,0,0,0} })
  return d.sessions[#d.sessions]
end

local function get_snapshot(proj)
  local cur = reaper.GetCursorPositionEx(proj)
  local ts_s, ts_e = reaper.GetSet_LoopTimeRange2(proj, false, false, 0, 0, false)
  local mx, my = reaper.GetMousePosition()
  return {
    cur = cur,
    ts_s = ts_s,
    ts_e = ts_e,
    si = reaper.CountSelectedMediaItems(proj),
    st = reaper.CountSelectedTracks(proj),
    mx = mx,
    my = my,
  }
end

local function snap_changed(a, b)
  if not a or not b then return true end
  return a.cur ~= b.cur
      or a.ts_s ~= b.ts_s
      or a.ts_e ~= b.ts_e
      or a.si ~= b.si
      or a.st ~= b.st
      or a.mx ~= b.mx
      or a.my ~= b.my
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

local function load_proj_data(proj)
  local guid = proj_guid(proj)
  local has_ext, s = reaper.GetProjExtState(proj, EXT_SECTION, EXT_KEY)
  
  -- Backward compatibility check for v1 -> v2 transition
  if not has_ext or s == "" then
    local has_ext_v1, s_v1 = reaper.GetProjExtState(proj, EXT_SECTION, "v1")
    if has_ext_v1 and s_v1 ~= "" then
      local d = deserialize(s_v1, guid)
      if d then return d end
    end
    return nil
  end
  
  return deserialize(s, guid)
end

local function save_proj_data(proj, d, guid)
  reaper.SetProjExtState(proj, EXT_SECTION, EXT_KEY, serialize(d, guid))
end

local function serialize_live(guid, d, status)
  local parts = {
    "3", -- Bumped live serialization version to 3 for notes
    guid or "",
    status or "",
    tostring(d.phase or 1),
    (d.auto_tracking and "1" or "0"),
    tostring(d.autosave_min or 10),
    tostring(#(d.sessions or {}))
  }
  
  for _, sess in ipairs(d.sessions or {}) do
    local encoded_note = ""
    if sess.note and sess.note ~= "" then
      local b='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
      encoded_note = ((sess.note:gsub('.', function(x) 
          local r,b='',x:byte()
          for i=8,1,-1 do r=r..(b%2^i-b%2^(i-1)>0 and '1' or '0') end
          return r;
      end)..'0000'):gsub('%d%d%d?%d?%d?%d?', function(x)
          if (#x < 6) then return '' end
          local c=0
          for i=1,6 do c=c+(x:sub(i,i)=='1' and 2^(6-i) or 0) end
          return b:sub(c+1,c+1)
      end)..({ '', '==', '=' })[#sess.note%3+1])
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

local is_global_pause = false

local function b64_decode(value)
  if not value or value == "" then return "" end
  local b='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
  local data = tostring(value):gsub('[^'..b..'=]', '')
  return (data:gsub('.', function(x)
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

local function apply_cmd_to_session(sess, action, value)
  if action == "ACTIVATE" then
    sess.is_active = true
    sess.dirty = true
    return true
  end
  if action == "RESET" then
    sess.data.phase = 1
    sess.data.sessions = { { start_time = os.time(), t = {0,0,0,0,0,0} } }
    sess.dirty = true
    return true
  end
  if action == "SET_NOTE" then
    local cur_sess = get_current_session(sess.data)
    if cur_sess then
      cur_sess.note = b64_decode(value)
      sess.dirty = true
      return true
    end
    return false
  end
  if action == "SET_NOTE_SESSION" then
    local idx_s, start_s, encoded = tostring(value or ""):match("^(%d+)|(%d+)|(.*)$")
    local idx = tonumber(idx_s or "") or 0
    local start_time = tonumber(start_s or "") or 0
    if idx <= 0 then return false end
    local target = sess.data.sessions and sess.data.sessions[idx]
    if not target then return false end
    if start_time > 0 and tonumber(target.start_time or 0) ~= start_time then
      for i, s in ipairs(sess.data.sessions or {}) do
        if tonumber(s.start_time or 0) == start_time then
          target = s
          break
        end
      end
    end
    if not target then return false end
    target.note = b64_decode(encoded)
    sess.dirty = true
    return true
  end
  if action == "SET_PHASE" then
    local p = tonumber(value) or 1
    if p < 1 then p = 1 end
    if p > 6 then p = 6 end
    sess.data.phase = p
    sess.dirty = true
    return true
  end
  if action == "SET_AUTOTRACK" then
    sess.data.auto_tracking = (tostring(value) == "1")
    sess.dirty = true
    return true
  end
  if action == "SET_AUTOSAVE" then
    local m = tonumber(value) or 0
    if m < 0 then m = 0 end
    sess.data.autosave_min = m
    sess.dirty = true
    return true
  end
  return false
end

local function read_cmd()
  local payload = reaper.GetExtState(EXT_SECTION, KEY_CMD)
  if not payload or payload == "" then return nil end
  local id, key, action, value = payload:match("^(%d+)\t([^\t]*)\t([%w_]+)\t?(.*)$")
  if not id then return nil end
  return tonumber(id) or 0, key or "", action or "", value or ""
end

local daemon_token = (reaper.genGuid and reaper.genGuid("")) or string.format("DAEMON_%d", math.floor(now() * 1000000))

local function write_hb(t)
  reaper.SetExtState(EXT_SECTION, KEY_HB, string.format("%.6f", t), false)
end

local function write_lock(t)
  reaper.SetExtState(EXT_SECTION, KEY_LOCK, daemon_token .. "\t" .. string.format("%.6f", t), false)
end

local function lock_recent()
  local payload = reaper.GetExtState(EXT_SECTION, KEY_LOCK)
  if not payload or payload == "" then return false end
  local token, ts = payload:match("^([^\t]*)\t([%d%.]+)$")
  local t0 = tonumber(ts or "") or 0
  if t0 <= 0 then return false end
  return (now() - t0) < DAEMON_LOCK_SEC
end

local function daemon_already_running()
  local hb = tonumber(reaper.GetExtState(EXT_SECTION, KEY_HB) or "")
  if not hb then return false end
  return (now() - hb) < DAEMON_ALIVE_SEC
end

if lock_recent() or daemon_already_running() then
  return
end

write_lock(now())

local Sessions = {}
local Active = { proj = nil, key = "" }
local last_cmd_id = tonumber(reaper.GetExtState(EXT_SECTION, KEY_CMD_ACK) or "") or 0

local function get_or_create_session(proj)
  local key = proj_persist_id(proj)
  local sess = Sessions[key]
  if sess then return sess, key end
  
  local data = load_proj_data(proj)
  local is_active = data ~= nil

  -- Only start a new session if we just loaded existing data
  if data then
    local cur_sess = get_current_session(data)
    local sess_total = 0
    for i = 1, 6 do sess_total = sess_total + (cur_sess.t[i] or 0) end
    -- If the current session has ANY recorded time, start a new one when opening the project
    if sess_total > 0 then
      add_new_session(data)
      -- We must immediately save this to project state and force live serialization to update
      save_proj_data(proj, data, proj_guid(proj))
    end
  end

  sess = {
    data = data or { phase = 1, auto_tracking = true, autosave_min = 10, sessions = { { start_time = os.time(), t = {0, 0, 0, 0, 0, 0} } } },
    is_active = is_active,
    dirty = false,
    status = "Idle",
    last_tick = now(),
    last_activity = now(),
    next_activity_poll = 0,
    next_live_push = 0,
    last_persist_save = now(),
    snap = nil,
    was_rec = false,
  }
  Sessions[key] = sess
  return sess, key
end

local function persist_if_needed(proj, guid, sess, force)
  if not sess.dirty and not force then return end
  save_proj_data(proj, sess.data, guid)
  sess.dirty = false
  sess.last_persist_save = now()
end

local function find_project_by_key(target_key)
  if not target_key or target_key == "" then return nil end
  local idx = 0
  while true do
    local proj, fn = reaper.EnumProjects(idx, "")
    if not proj then break end
    local _, id = reaper.GetProjExtState(proj, EXT_SECTION, PROJ_ID_KEY)
    if id == target_key then return proj end
    idx = idx + 1
  end
  return nil
end

local function tick_active_project()
  local proj, fn = reaper.EnumProjects(-1, "")
  fn = fn or ""
  if not proj then return end

  local key = proj_persist_id(proj)
  if key ~= Active.key then
    if is_project_valid(Active.proj) and Active.key ~= "" then
      local prev_sess = Sessions[Active.key]
      if prev_sess and prev_sess.dirty then

        local _, old_id = reaper.GetProjExtState(Active.proj, EXT_SECTION, PROJ_ID_KEY)
        if old_id == Active.key then
  
          persist_if_needed(Active.proj, Active.key, prev_sess, false)
        end
      end
    end
    Active.proj = proj
    Active.key = key
  end

  local sess = get_or_create_session(proj)
  local t = now()

  if t >= (sess.next_cmd_poll or 0) then
    local cmd_id, cmd_key, action, value = read_cmd()
    if cmd_id and cmd_id > last_cmd_id then
      if action == "PAUSE_GLOBAL" then
        if tostring(value) == "TOGGLE" then
          is_global_pause = not is_global_pause
        else
          is_global_pause = (tostring(value) == "1")
        end
      else
        local target_key = (cmd_key ~= "" and cmd_key) or Active.key
        local target_proj = (target_key == Active.key) and Active.proj or find_project_by_key(target_key)
        if is_project_valid(target_proj) then
          local target_sess = Sessions[target_key]
          if not target_sess then
            target_sess = get_or_create_session(target_proj)
          end
          if apply_cmd_to_session(target_sess, action, value) then
            persist_if_needed(target_proj, proj_persist_id(target_proj), target_sess, true)
          end
        end
      end
      last_cmd_id = cmd_id
      reaper.SetExtState(EXT_SECTION, KEY_CMD_ACK, tostring(last_cmd_id), false)
    end
    sess.next_cmd_poll = t + 0.1
  end

  local t = now()
  local dt = t - (sess.last_tick or t)
  sess.last_tick = t
  if dt < 0 then dt = 0 end

  local ps = reaper.GetPlayStateEx(proj)
  local is_rec = (ps & 4) == 4
  local is_play = ((ps & 1) == 1) and ((ps & 2) == 0)
  local transport_running = is_rec or is_play

  if transport_running then
    sess.last_activity = t
  elseif t >= (sess.next_activity_poll or 0) then
    local s = get_snapshot(proj)
    if snap_changed(sess.snap, s) then
      sess.last_activity = t
      sess.snap = s
    end
    sess.next_activity_poll = t + ACTIVITY_POLL_SEC
  end

  if is_rec and (not sess.was_rec) and sess.data.auto_tracking and sess.data.phase ~= 2 then
    sess.data.phase = 2
    sess.dirty = true
  end
  sess.was_rec = is_rec

  local running
  if is_rec or is_play then
    running = true
  else
    running = (t - (sess.last_activity or t)) <= IDLE_SEC
  end

  if not sess.is_active then
    running = false
  end

  local prev_status = sess.status
  if not sess.is_active then
    sess.status = "Inactive"
  elseif is_global_pause then
    sess.status = "Global Pause"
    running = false
  elseif transport_running then
    sess.status = "Running"
  elseif running then
    sess.status = "Idle"
  else
    sess.status = "Paused"
  end

  local autosave_sec = (sess.data.autosave_min or 0) * 60
  local time_to_autosave = autosave_sec > 0 and (t - (sess.last_persist_save or 0)) >= autosave_sec

  if (prev_status == "Running" and sess.status ~= "Running") or time_to_autosave then
    persist_if_needed(proj, proj_persist_id(proj), sess, false)
  end

  if (prev_status ~= "Inactive" and sess.status == "Inactive") then
    persist_if_needed(proj, proj_persist_id(proj), sess, false)
  elseif (prev_status == "Inactive" and sess.status ~= "Inactive") then
    local cur_sess = get_current_session(sess.data)
    local sess_total = 0
    for i = 1, 6 do sess_total = sess_total + (cur_sess.t[i] or 0) end
    if sess_total > 0 then
      add_new_session(sess.data)
      sess.dirty = true
      save_proj_data(proj, sess.data, proj_guid(proj))
      -- Force live serialization immediately so the UI sees the new session
      sess.next_live_push = t
    end
  end

  if running and dt > 0 then
    local idx = sess.data.phase or 1
    if idx < 1 then idx = 1 end
    if idx > 6 then idx = 6 end
    local cur_sess = get_current_session(sess.data)
    cur_sess.t[idx] = (cur_sess.t[idx] or 0) + dt
    sess.dirty = true
  end

  if t >= (sess.next_live_push or 0) then
    reaper.SetExtState(EXT_SECTION, KEY_LIVE_PREFIX .. key, serialize_live(key, sess.data, sess.status), false)
    sess.next_live_push = t + LIVE_POLL_SEC
  end
end

local function CleanUp()
  for key, sess in pairs(Sessions) do
    reaper.DeleteExtState(EXT_SECTION, KEY_LIVE_PREFIX .. key, false)
  end
  local payload = reaper.GetExtState(EXT_SECTION, KEY_LOCK)
  local token = payload and payload:match("^([^\t]*)\t") or ""
  if token ~= "" and token == daemon_token then
    reaper.DeleteExtState(EXT_SECTION, KEY_HB, false)
    reaper.DeleteExtState(EXT_SECTION, KEY_LOCK, false)
    reaper.DeleteExtState(EXT_SECTION, KEY_DAEMON_CPU, false)
  end
end
reaper.atexit(CleanUp)

local profiler = {
  frames = 0,
  total_t = 0,
  last_report = now()
}

local last_hb_t = 0
local function Main()
  local t_start = now()
  
  if t_start - last_hb_t >= 1.0 then
    write_hb(t_start)
    write_lock(t_start)
    last_hb_t = t_start
  end
  
  tick_active_project()
  
  local t_end = now()
  profiler.total_t = profiler.total_t + (t_end - t_start)
  profiler.frames = profiler.frames + 1
  
  if t_end - profiler.last_report >= 1.0 then
    -- Calculate execution time per second (as percentage)
    -- e.g., if total execution time was 0.005s over 1 real second, CPU is 0.5%
    local cpu_pct = (profiler.total_t / (t_end - profiler.last_report)) * 100
    reaper.SetExtState(EXT_SECTION, KEY_DAEMON_CPU, string.format("%.2f", cpu_pct), false)
    
    profiler.frames = 0
    profiler.total_t = 0
    profiler.last_report = t_end
  end
  
  reaper.defer(Main)
end

reaper.defer(Main)
