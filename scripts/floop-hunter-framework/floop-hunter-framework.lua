-- @description Floop Hunter Framework
-- @version 1.2.0
-- @author Floop-s
-- @license GPL-3.0
-- @changelog
--   + Non-Destructive State Management: P_EXT memory allows multiple Hunters on the same item without destructive overwrites.
--   + Continuous Filter Processing: JSFX HPF is always-on, eliminating zipper noise/phase clicks.
--   + Geometric Envelope Anchoring: strictly anchored envelope boundaries to prevent legacy-point sloping.
-- @about
--   # Floop Hunter Framework
--   Artifact detection and gain-reduction helper for REAPER (Ess / Plosive / Breath).
--   Requires ReaImGui.
--
--   This script is a workflow accelerator, designed to find candidates quickly 
--   and provide you with an interactive editor to rapidly confirm, delete, or adjust the 
--   automation. It is a starting point to save you hours of manual clicking, but your ears 
--   remain the final judge.
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
