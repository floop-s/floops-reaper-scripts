-- @description Floop Hunter Framework
-- @version 1.0.0
-- @author Floop-s
-- @license GPL-3.0
-- @about
--   # Floop Hunter Framework
--   Artifact detection and gain-reduction helper for REAPER (Ess / Plosive / Breath).
--   Requires ReaImGui.
-- @metapackage
-- @provides
--   [main] . > Floop Hunter Framework/floop-hunter-framework.lua
--   [nomain] modules/floop_cache.lua > Floop Hunter Framework/modules/floop_cache.lua
--   [nomain] modules/floop_dsp.lua > Floop Hunter Framework/modules/floop_dsp.lua
--   [nomain] modules/floop_engine.lua > Floop Hunter Framework/modules/floop_engine.lua
--   [nomain] modules/floop_imgui.lua > Floop Hunter Framework/modules/floop_imgui.lua
--   [nomain] modules/floop_logger.lua > Floop Hunter Framework/modules/floop_logger.lua
--   [nomain] modules/floop_ui.lua > Floop Hunter Framework/modules/floop_ui.lua
--   [nomain] modules/hunters/hunter_breath.lua > Floop Hunter Framework/modules/hunters/hunter_breath.lua
--   [nomain] modules/hunters/hunter_ess.lua > Floop Hunter Framework/modules/hunters/hunter_ess.lua
--   [nomain] modules/hunters/hunter_plosive.lua > Floop Hunter Framework/modules/hunters/hunter_plosive.lua

-- Add current script path to package.path
local script_path = debug.getinfo(1,'S').source:match([[^@?(.*[\/])[^\/]-$]])
package.path = script_path .. "?.lua;" .. script_path .. "modules/?.lua;" .. package.path

local reaper = reaper

-- Requirements
if not reaper.ImGui_CreateContext then
    reaper.ShowMessageBox("ReaImGui API not found!\nPlease install 'ReaImGui' via ReaPack and restart Reaper.", "Error", 0)
    return
end

-- Ensure: "Move envelope points with media items" (40070).
if reaper.GetToggleCommandState(40070) == 0 then
    reaper.Main_OnCommand(40070, 0) -- Toggle ON
end

local ImGui = require("floop_imgui")
local Logger = require("floop_logger")
local UI = require("floop_ui")

local function loop()
  if UI.wants_close then return end
  local status, err = pcall(UI.draw)
  if not status then
      reaper.ShowConsoleMsg("Floop Hunter Error: " .. tostring(err) .. "\n")
  end
  reaper.defer(loop)
end

-- Main
reaper.defer(loop)
