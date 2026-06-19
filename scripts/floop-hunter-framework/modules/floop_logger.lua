-- @noindex
-- @description Floop Hunter Framework - Logger
-- @author Floop-s
-- @license GPL-3.0

local Logger = {}
local reaper = reaper

-- Configuration
Logger.enabled = true
Logger.console_enabled = false
Logger.file_enabled = false
Logger.flush_each_write = true

-- State for unified logging
Logger.buffering = false
Logger.debug_buffer = {}

-- Log Levels
local LEVELS = {
  DEBUG = { val = 0, label = "DEBUG", color = "xd" },
  INFO  = { val = 1, label = "INFO",  color = "i" },
  WARN  = { val = 2, label = "WARN",  color = "!" },
  ERROR = { val = 3, label = "ERROR", color = "!!" }
}

local session_time = os.time()
local script_dir = (debug.getinfo(1, "S").source:match("@?(.*[\\/])") or "")
local path_sep = package.config:sub(1, 1)
local log_dir = script_dir .. "log_raw" .. path_sep
if reaper and reaper.RecursiveCreateDirectory then
  reaper.RecursiveCreateDirectory(log_dir, 0)
end
local warned_file_open = false

local log_handles = {}
local active_target = "Global"

function Logger:set_target_hunter(hunter_name)
  if not hunter_name or hunter_name == "" then hunter_name = "Global" end
  active_target = hunter_name
  if not log_handles[active_target] and self.file_enabled then
    local safe_name = active_target:gsub("[^%w]", "_")
    local log_path = log_dir .. "floop_log_" .. safe_name .. "_" .. tostring(session_time) .. ".txt"
    local fh = io.open(log_path, "a")
    if fh then
      log_handles[active_target] = fh
    end
  end
end

local function warn_file_open_failed()
  if warned_file_open then return end
  warned_file_open = true
  if reaper and reaper.MB then
    reaper.MB("Could not open log file for writing.\nLogging to file has been disabled.\nCheck permissions/path.", "Floop Hunter Logger Error", 0)
  end
end

function Logger:close()
  for k, fh in pairs(log_handles) do
    if self.flush_each_write then fh:flush() end
    fh:close()
  end
  log_handles = {}
end

if reaper and reaper.atexit then
  reaper.atexit(function()
    Logger:close()
  end)
end

-- Internal helper
function Logger:log(level_key, msg)
  local lvl = LEVELS[level_key] or LEVELS.INFO
  local formatted_msg = string.format("[%s] %s\n", lvl.label, msg)
  
  if not self.enabled then return end

  if self.console_enabled and reaper and reaper.ShowConsoleMsg then
    reaper.ShowConsoleMsg(formatted_msg)
  end

  if self.file_enabled then
    local fh = log_handles[active_target]
    if not fh then
      self:set_target_hunter(active_target)
      fh = log_handles[active_target]
      if not fh then
        warn_file_open_failed()
        self.file_enabled = false
        return
      end
    end

    -- Check if we should start buffering
    if string.find(msg, "_INIT") then
      self.buffering = true
      self.debug_buffer = {}
    end

    if self.buffering then
      table.insert(self.debug_buffer, formatted_msg)
    else
      fh:write(formatted_msg)
      if self.flush_each_write then
        fh:flush()
      end
    end
  end
end

-- Public Methods
function Logger:debug(msg) self:log("DEBUG", msg) end
function Logger:info(msg)  self:log("INFO", msg) end
function Logger:warn(msg)  self:log("WARN", msg) end
function Logger:error(msg) self:log("ERROR", msg) end

function Logger:csv(line)
  if not self.enabled then return end
  if not self.file_enabled then return end
  local fh = log_handles[active_target]
  if not fh then
    self:set_target_hunter(active_target)
    fh = log_handles[active_target]
    if not fh then
      warn_file_open_failed()
      return
    end
  end

  -- Write the CSV line
  fh:write(tostring(line) .. "\n")
  if self.flush_each_write then
    fh:flush()
  end

  if string.find(line, "eval_end") then
    if #self.debug_buffer > 0 then
      fh:write("\n[COMPLETE LOGS]\n\n")
      for _, msg in ipairs(self.debug_buffer) do
        fh:write(msg)
      end
      fh:write("_________________________________________________________\n\n")
      if self.flush_each_write then
        fh:flush()
      end
    end
    self.debug_buffer = {}
    self.buffering = false
  end
end

return Logger
