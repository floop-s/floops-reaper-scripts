-- @noindex
-- @description Floop Hunter Framework - ReaImGui compatibility shims
-- @author Floop-s
-- @license GPL-3.0

local reaper = reaper

if not reaper.ImGui_CreateContext then
  return nil
end

local ImGui = {}

-- Proxy missing ImGui methods to reaper.ImGui_* functions.
setmetatable(ImGui, {
  __index = function(t, k)
    local f = reaper["ImGui_" .. k]
    if f then return f end
    return nil
  end
})



-- SliderFloat: older versions might use SliderDouble
function ImGui.SliderFloat(ctx, label, v, min, max, format, flags)
  local f = reaper.ImGui_SliderFloat or reaper.ImGui_SliderDouble
  if f then 
    return f(ctx, label, v, min, max, format, flags)
  end
  return false, v
end

-- SliderInt: wrapper
function ImGui.SliderInt(ctx, label, v, min, max, format, flags)
  local f = reaper.ImGui_SliderInt
  if f then
    return f(ctx, label, v, min, max, format, flags)
  end
  return false, v
end

-- ProgressBar compatibility for older ReaImGui versions.
if not reaper.ImGui_ProgressBar then
  function ImGui.ProgressBar(ctx, frac, w, h, overlay)
    reaper.ImGui_Text(ctx, string.format('Progress: %d%%', math.floor((frac or 0)*100+0.5)))
    return true
  end
end

return ImGui
