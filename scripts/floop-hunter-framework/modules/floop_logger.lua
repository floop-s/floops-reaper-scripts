-- @noindex
-- @description Floop Hunter Framework - Logger
-- @author Floop-s
-- @license GPL-3.0

local Logger = {}
local reaper = reaper

-- Configuration
Logger.debug_mode = false

-- Log Levels
local LEVELS = {
  DEBUG = { val = 0, label = "DEBUG", color = "xd" },
  INFO  = { val = 1, label = "INFO",  color = "i" },
  WARN  = { val = 2, label = "WARN",  color = "!" },
  ERROR = { val = 3, label = "ERROR", color = "!!" }
}

-- Internal helper
function Logger:log(level_key, msg)
  local lvl = LEVELS[level_key] or LEVELS.INFO
  
  -- If in debug mode, print to console
  if self.debug_mode then
    reaper.ShowConsoleMsg(string.format("[%s] %s\n", lvl.label, msg))
  end
end

-- Public Methods
function Logger:debug(msg) self:log("DEBUG", msg) end
function Logger:info(msg)  self:log("INFO", msg) end
function Logger:warn(msg)  self:log("WARN", msg) end
function Logger:error(msg) self:log("ERROR", msg) end

return Logger
