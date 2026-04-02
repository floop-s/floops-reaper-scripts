-- @noindex
-- @description Floop Hunter Framework - Engine module
-- @author Floop-s
-- @license GPL-3.0
--
-- Audio analysis (streaming), feature collection, overlap resolution, and envelope writing.

local Engine = {}
local DSP = require("floop_dsp")
local Logger = require("floop_logger")

-- JSFX
local JSFX_NAME = "Floop Hunter.jsfx"
local JSFX_CONTENT = [[
desc:Floop Hunter (Unified)
version: 1.0.0
author: Floop
about: Unified gain reduction for Ess, Plosive, and Breath hunters (Master Reduction).

slider1:0<-60,12,0.1>Artifact Gain (dB)

@init
db_scale = 1/20;
smooth = 0.999;
current_gain = 1;

@slider
// Only one master slider for all artifacts
target_gain = 10 ^ (slider1 * db_scale);

@sample
current_gain = current_gain * smooth + target_gain * (1 - smooth);
spl0 *= current_gain;
spl1 *= current_gain;
]]

local function install_jsfx()
  local resource_path = reaper.GetResourcePath()
  local sep = package.config:sub(1, 1)
  local effects_dir = resource_path .. sep .. "Effects" .. sep .. "Floop"
  local jsfx_path = effects_dir .. sep .. JSFX_NAME

  reaper.RecursiveCreateDirectory(effects_dir, 0)

  local file = io.open(jsfx_path, "w")
  if file then
    file:write(JSFX_CONTENT)
    file:close()
    return true
  else
    reaper.MB("Could not install Floop Hunter JSFX at " .. jsfx_path .. "\nCheck file permissions.", "Floop Hunter Error",
      0)
    return false
  end
end

install_jsfx()

-- Envelope helpers
local function ensure_track_envelope(track, hunter_type)
  local fx_name = "Floop Hunter.jsfx"
  local fx_idx = reaper.TrackFX_AddByName(track, fx_name, false, 1)
  if fx_idx < 0 then
    fx_idx = reaper.TrackFX_AddByName(track, "Effects/Floop/" .. fx_name, false, 1)
  end

  if fx_idx < 0 then return nil end

  local target_pos = 0
  local inst_idx = reaper.TrackFX_GetInstrument(track)
  if inst_idx and inst_idx >= 0 then
    target_pos = inst_idx + 1
  end
  
  -- Check if user manually moved it
  local current_pos = reaper.TrackFX_GetByName(track, fx_name, false)
  if current_pos >= 0 then
      fx_idx = current_pos
  elseif fx_idx ~= target_pos then
    reaper.TrackFX_CopyToTrack(track, fx_idx, track, target_pos, true)
    fx_idx = target_pos
  end

  local param_idx = 0
  return reaper.GetFXEnvelope(track, fx_idx, param_idx, true)
end

local function ensure_take_envelope(take, hunter_type)
  if not reaper.TakeFX_GetEnvelope then
    reaper.MB("reaper.TakeFX_GetEnvelope API not available.\nPlease update Reaper to v6+ or use Track FX.",
      "Floop Hunter Error", 0)
    return nil
  end

  local fx_name = "Floop Hunter.jsfx"
  local fx_idx = reaper.TakeFX_AddByName(take, fx_name, 1)
  if fx_idx < 0 then
    fx_idx = reaper.TakeFX_AddByName(take, "Effects/Floop/" .. fx_name, 1)
  end

  if fx_idx < 0 then return nil end

  local param_idx = 0
  return reaper.TakeFX_GetEnvelope(take, fx_idx, param_idx, true)
end

local function insert_reduction_points(env, t_start, t_end, reduction_db, pre_sec, post_sec, overwrite, shape)
  local pre = math.max(0, pre_sec)
  local post = math.max(0, post_sec)
  local env_shape = shape or 0

  local t1 = math.max(0, t_start - pre)
  local t2 = t_start
  local t3 = t_end
  local t4 = t_end + post

  local v_current = 0.0
  local dip = -math.abs(reduction_db)
  local v_target = dip

  if overwrite then
    reaper.DeleteEnvelopePointRange(env, t1, t4)
  end

  reaper.InsertEnvelopePointEx(env, -1, t1, v_current, env_shape, 0, false, true)
  reaper.InsertEnvelopePointEx(env, -1, t2, v_target, 0, 0, false, true)
  reaper.InsertEnvelopePointEx(env, -1, t3, v_target, env_shape, 0, false, true)
  reaper.InsertEnvelopePointEx(env, -1, t4, v_current, 0, 0, false, true)
end

Engine.ensure_track_envelope = ensure_track_envelope
Engine.ensure_take_envelope = ensure_take_envelope
Engine.insert_reduction_points = insert_reduction_points

-- Analysis (async)

local function deep_copy(obj, seen)
  if type(obj) ~= 'table' then return obj end
  if seen and seen[obj] then return seen[obj] end
  local s = seen or {}
  local res = {}
  s[obj] = res
  for k, v in pairs(obj) do res[deep_copy(k, s)] = deep_copy(v, s) end
  return res
end

function Engine.create_analysis_context(item, hunter, config_in)
  local config = deep_copy(config_in)
  local take = reaper.GetActiveTake(item)
  if not take or reaper.TakeIsMIDI(take) then return nil end

  local src = reaper.GetMediaItemTake_Source(take)
  if not src then return nil end

  local sr = reaper.GetMediaSourceSampleRate(src) or 48000
  sr = math.floor(sr + 0.5)
  local ch = reaper.GetMediaSourceNumChannels(src)

  local accessor = reaper.CreateTakeAudioAccessor(take)
  if not accessor then return nil end
  
  local acc_start = reaper.GetAudioAccessorStartTime(accessor)
  local acc_end = reaper.GetAudioAccessorEndTime(accessor)
  local item_pos_proj = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  local item_len_proj = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")

  local N = math.max(64, math.floor(sr * (config.window_ms / 1000)))
  local H = math.max(32, math.floor(sr * (config.hop_ms / 1000)))

  -- Pre-allocate buffer for hop-sized reads to reduce GC pressure.
  local buf = reaper.new_array(H * ch)
  local state = hunter.init(sr, config)
  
  local result_buf = {
    level = 0, ratio = 0, zcr = 0, air_ratio = 0, air_db = 0,
    chest_ratio = 0, air_conc = 0, hf_conc = 0, hf_tilt = 0,
    low_ratio = 0, flat = 0, low_db = 0, high_db = 0,
    diff_db = 0, crest_low = 0
  }

  return {
    take = take,
    accessor = accessor,
    sr = sr,
    ch = ch,
    N = N,
    H = H,
    item_pos = item_pos_proj,
    item_len = item_len_proj,
    buf = buf,
    state = state,
    hunter = hunter,

    t_acc = acc_start,
    t_proj = item_pos_proj,
    t_end = item_pos_proj + item_len_proj,
    sum_sq = 0.0,
    total_samples = 0,

    features_arrays = {},
    time_map = {},

    finished = false,
    idx = 1,
    result_buf = result_buf,

    run_chunk = function(self, time_budget_ms)
      if self.finished then return true end

      local t_start_chunk = reaper.time_precise()
      local time_budget_sec = (time_budget_ms or 10) / 1000.0

      while (reaper.time_precise() - t_start_chunk) < time_budget_sec do
        if self.t_proj + (self.H / self.sr) > self.t_end then
          self:finalize()
          return true
        end

        self.buf.clear()
        reaper.GetAudioAccessorSamples(self.accessor, self.sr, self.ch, self.t_acc, self.H, self.buf)

        -- Accumulate RMS
        for i = 1, self.H * self.ch do
          local s = self.buf[i]
          self.sum_sq = self.sum_sq + s * s
        end
        self.total_samples = self.total_samples + (self.H * self.ch)

        local ok, res = pcall(self.hunter.process_window, self.buf, self.ch, self.state, self.result_buf)
        if not ok then
            reaper.ShowConsoleMsg("Error in hunter.process_window: " .. tostring(res) .. "\n")
            self:finalize()
            return true
        end
        
        if res and res ~= self.result_buf then
            self.result_buf = res
        end

        local FEATURE_KEYS = {
          "level", "ratio", "zcr", "air_ratio", "air_db", "chest_ratio",
          "air_conc", "hf_conc", "hf_tilt", "low_ratio", "flat", "low_db",
          "high_db", "diff_db", "crest_low"
        }

        for _, key in ipairs(FEATURE_KEYS) do
          if self.result_buf[key] then
            if not self.features_arrays[key] then self.features_arrays[key] = {} end
            self.features_arrays[key][self.idx] = self.result_buf[key]
          end
        end

        self.time_map[self.idx] = self.t_proj
        self.idx = self.idx + 1

        local dt = (self.H / self.sr)
        self.t_acc = self.t_acc + dt
        self.t_proj = self.t_proj + dt
      end

      return false
    end,

    finalize = function(self)
      local rms_db = -144.0
      if self.total_samples > 0 then
        rms_db = DSP.amp_to_db(math.sqrt(self.sum_sq / self.total_samples))
      end
      reaper.DestroyAudioAccessor(self.accessor)
      self.finished = true
      self.rms_db = rms_db
      self.buf = nil
      self.result_buf = nil
    end,

    get_progress = function(self)
      if self.finished then return 1.0 end
      local dur = self.t_end - self.item_pos
      if dur <= 0 then return 1.0 end
      return (self.t_proj - self.item_pos) / dur
    end
  }
end

-- Analysis (blocking)
function Engine.analyze_item(item, hunter, config)
  local ctx = Engine.create_analysis_context(item, hunter, config)
  if not ctx then return nil end

  while not ctx:run_chunk(1000) do
  end

  config.item_rms_db = ctx.rms_db
  return ctx.features_arrays, ctx.time_map
end

-- Segments
function Engine.resolve_overlaps(all_segments)
  if #all_segments < 2 then return all_segments end

  -- Sort by start time, then by end time for stable iteration
  table.sort(all_segments, function(a, b) 
      if a.start_time == b.start_time then
          return a.end_time < b.end_time
      end
      return a.start_time < b.start_time 
  end)

  local resolved = {}
  local active_intervals = {}

  -- Build a list of all unique time boundaries (start and end points)
  local boundaries = {}
  for _, seg in ipairs(all_segments) do
      table.insert(boundaries, seg.start_time)
      table.insert(boundaries, seg.end_time)
  end
  table.sort(boundaries)

  -- Deduplicate boundaries with a small epsilon to avoid micro-segments
  local unique_bounds = {}
  local epsilon = 0.001
  for i, b in ipairs(boundaries) do
      if i == 1 or (b - unique_bounds[#unique_bounds]) > epsilon then
          table.insert(unique_bounds, b)
      end
  end

  -- Evaluate max reduction at each interval
  for i = 1, #unique_bounds - 1 do
      local t_start = unique_bounds[i]
      local t_end = unique_bounds[i+1]
      local t_mid = (t_start + t_end) / 2
      
      local max_reduction = 0
      local active_hunter = nil
      
      for _, seg in ipairs(all_segments) do
          if seg.start_time <= t_mid and seg.end_time >= t_mid then
              local db = math.abs(seg.reduction_db or 0)
              if db > max_reduction then
                  max_reduction = db
                  active_hunter = seg.hunter_name
              end
          end
      end
      
      if max_reduction > 0 then
          table.insert(active_intervals, {
              start_time = t_start,
              end_time = t_end,
              reduction_db = max_reduction,
              hunter_name = active_hunter
          })
      end
  end

  -- Merge adjacent intervals that share the same reduction and hunter
  if #active_intervals > 0 then
      local current = active_intervals[1]
      for i = 2, #active_intervals do
          local next_seg = active_intervals[i]
          local gap = next_seg.start_time - current.end_time
          
          if gap <= epsilon and math.abs(current.reduction_db - next_seg.reduction_db) < 0.1 then
              current.end_time = next_seg.end_time
          else
              table.insert(resolved, current)
              current = next_seg
          end
      end
      table.insert(resolved, current)
  end
  
  -- Final proximity merge (to prevent rapid-fire envelope zigzag)
  local final_resolved = {}
  if #resolved > 0 then
      local current = resolved[1]
      for i = 2, #resolved do
          local next_seg = resolved[i]
          local gap = next_seg.start_time - current.end_time
          local merge_threshold = 0.030
          
          if gap > 0 and gap < merge_threshold then
              local db_cur = current.reduction_db
              local db_next = next_seg.reduction_db
              if math.abs(db_cur - db_next) < 3.0 then
                  current.end_time = next_seg.end_time
                  if db_next > db_cur then current.reduction_db = db_next end
              else
                  table.insert(final_resolved, current)
                  current = next_seg
              end
          else
              table.insert(final_resolved, current)
              current = next_seg
          end
      end
      table.insert(final_resolved, current)
  end

  return final_resolved
end

-- Envelopes
function Engine.apply_reduction(item, segments, config)
  local env
  local hunter_type = config.hunter_type or "Ess"

  if config.use_take_fx then
    local take = reaper.GetActiveTake(item)
    if not take then return 0 end
    env = ensure_take_envelope(take, hunter_type)
  else
    local track = reaper.GetMediaItem_Track(item)
    if not track then return 0 end
    env = ensure_track_envelope(track, hunter_type)
  end

  if not env then
    reaper.MB("Could not create/find envelope for Floop Hunter.jsfx.", "Floop Hunter Error", 0)
    return 0
  end

  reaper.Envelope_SortPoints(env)

  local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  local item_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")

  local pre_sec = (config.pre_ramp_ms or 0) / 1000
  local post_sec = (config.post_ramp_ms or 0) / 1000

  if config.overwrite then
    if config.use_take_fx then
      local take = reaper.GetActiveTake(item)
      local play_rate = take and reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE") or 1.0
      reaper.DeleteEnvelopePointRange(env, 0, item_len * play_rate + 1.0)
    else
      reaper.DeleteEnvelopePointRange(env, math.max(0, item_pos - pre_sec), item_pos + item_len + post_sec)
    end
  end

  local shape = config.env_shape or 0

  for _, seg in ipairs(segments) do
    local seg_db = seg.reduction_db
    if seg_db == nil then
      seg_db = config.reduction_db or 0
    end

    local t_start = seg.start_time
    local t_end = seg.end_time

    if config.use_take_fx then
      t_start = t_start - item_pos
      t_end = t_end - item_pos
    end

    insert_reduction_points(env, t_start, t_end, seg_db, pre_sec, post_sec, false, shape)
  end

  reaper.Envelope_SortPoints(env)
  return #segments
end

-- Processing (batch/blocking)
function Engine.process_selection(hunter, config)
  local cnt = reaper.CountSelectedMediaItems(0)
  if cnt == 0 then return 0, "No items selected" end

  if (config.source_profile or 0) == 0 then
    reaper.MB("Please select a Source Profile before batch processing.", "Profile Required", 0)
    return 0, "Profile Required"
  end

  local t_start = reaper.time_precise()
  reaper.Undo_BeginBlock()

  local total_segments = 0

  for i = 0, cnt - 1 do
    local item = reaper.GetSelectedMediaItem(0, i)
    local features, time_map = Engine.analyze_item(item, hunter, config)

    if features and features.level and #features.level > 0 then
      local segments_idx, stats = hunter.detect_segments(features, config)

      local segments_time = {}
      for _, seg in ipairs(segments_idx) do
        local t1 = time_map[seg.start_idx]
        local t2 = time_map[seg.end_idx]
        if t1 and t2 then
          local t_end_real = t2 + (config.hop_ms / 1000)
          table.insert(segments_time, { start_time = t1, end_time = t_end_real })
        end
      end

      local num = Engine.apply_reduction(item, segments_time, config)
      total_segments = total_segments + num
    end
  end

  reaper.Undo_EndBlock("Floop Hunter: " .. hunter.name, -1)
  reaper.UpdateArrange()

  local elapsed = reaper.time_precise() - t_start
  return total_segments, string.format("Reduced %d segments in %.2fs", total_segments, elapsed)
end

return Engine
