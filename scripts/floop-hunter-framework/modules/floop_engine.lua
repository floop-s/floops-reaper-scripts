-- @noindex
-- @description Floop Hunter Framework - Engine module
-- @author Floop-s
-- @license GPL-3.0
--
-- Audio analysis (streaming), feature collection, overlap resolution, and envelope writing.

local Engine = {}
local DSP = require("floop_dsp")
local Logger = require("floop_logger")

local FEATURE_KEYS = {
  "level", "ratio", "zcr", "air_ratio", "air_db", "chest_ratio",
  "air_conc", "chest_zcr", "voiced_score", "hf_conc", "hf_tilt", "hf_entropy", "hf_flatness", "low_ratio", "flat", "low_db",
  "ess_ratio", "ess_zcr", "high_db", "diff_db", "spectral_balance_db", "crest_low", "ma_low_db", "ma_high_db"
}

-- JSFX
local JSFX_NAME = "Floop Hunter.jsfx"
local JSFX_CONTENT = [[
desc:Floop Hunter (Unified)
version: 1.1.0
author: Floop
about: Unified artifact reduction. Slider 1 for Gain, Slider 2 for Plosive HPF.

slider1:0<-60,12,0.1>Artifact Gain (dB)
slider2:20<20,500,1>Plosive HPF Cutoff (Hz)

@init
db_scale = 1/20;
smooth = 0.999;
current_gain = 1;
current_hpf_hz = 20;

// HPF Biquad Init
hpf_b0=1; hpf_b1=0; hpf_b2=0; hpf_a1=0; hpf_a2=0;
hpf_x1=0; hpf_x2=0; hpf_y1=0; hpf_y2=0;
hpf_rx1=0; hpf_rx2=0; hpf_ry1=0; hpf_ry2=0;

function update_hpf(fc, Q) (
  w0 = 2 * $pi * fc / srate;
  cosw0 = cos(w0);
  sinw0 = sin(w0);
  alpha = sinw0 / (2 * Q);
  
  a0 = 1 + alpha;
  hpf_b0 = ((1 + cosw0) / 2) / a0;
  hpf_b1 = (-(1 + cosw0)) / a0;
  hpf_b2 = ((1 + cosw0) / 2) / a0;
  hpf_a1 = (-2 * cosw0) / a0;
  hpf_a2 = (1 - alpha) / a0;
);
update_hpf(20, 0.707);

@slider
target_gain = 10 ^ (slider1 * db_scale);
target_hpf_hz = slider2;

@block
// Smooth and update filter parameters per-block to save CPU, instead of per-sample
current_hpf_hz = current_hpf_hz * 0.90 + target_hpf_hz * 0.10;
current_hpf_hz > 21 ? (
  update_hpf(current_hpf_hz, 0.707);
);

@sample
current_gain = current_gain * smooth + target_gain * (1 - smooth);
spl0 *= current_gain;
spl1 *= current_gain;

// HPF Processing
current_hpf_hz > 21 ? (
  out0 = hpf_b0*spl0 + hpf_b1*hpf_x1 + hpf_b2*hpf_x2 - hpf_a1*hpf_y1 - hpf_a2*hpf_y2;
  hpf_x2 = hpf_x1; hpf_x1 = spl0;
  hpf_y2 = hpf_y1; hpf_y1 = out0;
  spl0 = out0;
  
  out1 = hpf_b0*spl1 + hpf_b1*hpf_rx1 + hpf_b2*hpf_rx2 - hpf_a1*hpf_ry1 - hpf_a2*hpf_ry2;
  hpf_rx2 = hpf_rx1; hpf_rx1 = spl1;
  hpf_ry2 = hpf_ry1; hpf_ry1 = out1;
  spl1 = out1;
);
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
local function ensure_track_envelope(track, param_idx)
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

  return reaper.GetFXEnvelope(track, fx_idx, param_idx, true)
end

local function ensure_take_envelope(take, param_idx)
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

  return reaper.TakeFX_GetEnvelope(take, fx_idx, param_idx, true)
end

local function insert_reduction_points(env, t_start, t_end, target_val, pre_sec, post_sec, overwrite, shape, baseline_val)
  local pre = math.max(0, pre_sec)
  local post = math.max(0, post_sec)
  local env_shape = shape or 0

  local t1 = math.max(0, t_start - pre)
  local t2 = t_start
  local t3 = t_end
  local t4 = t_end + post

  local v_current = baseline_val or 0.0
  local v_target = target_val

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

local function simplify_curve(points, eps)
  local n = #points
  if n <= 2 then return points end
  local keep = {}
  for i = 1, n do keep[i] = false end
  keep[1] = true
  keep[n] = true

  local stack_a = { 1 }
  local stack_b = { n }

  while #stack_a > 0 do
    local a = stack_a[#stack_a]
    local b = stack_b[#stack_b]
    stack_a[#stack_a] = nil
    stack_b[#stack_b] = nil

    local t1 = points[a].t
    local v1 = points[a].v
    local t2 = points[b].t
    local v2 = points[b].v
    local dt = t2 - t1

    local max_dev = -1.0
    local max_i = -1
    for i = a + 1, b - 1 do
      local ti = points[i].t
      local vi = points[i].v
      local vlin
      if dt ~= 0 then
        vlin = v1 + (v2 - v1) * ((ti - t1) / dt)
      else
        vlin = v1
      end
      local dev = math.abs(vi - vlin)
      if dev > max_dev then
        max_dev = dev
        max_i = i
      end
    end

    if max_i > 0 and max_dev > eps then
      keep[max_i] = true
      if (max_i - a) > 1 then
        stack_a[#stack_a + 1] = a
        stack_b[#stack_b + 1] = max_i
      end
      if (b - max_i) > 1 then
        stack_a[#stack_a + 1] = max_i
        stack_b[#stack_b + 1] = b
      end
    end
  end

  local out = {}
  for i = 1, n do
    if keep[i] then
      out[#out + 1] = points[i]
    end
  end
  return out
end

local function insert_hpf_curve(env, t_start, t_end, seg_points, pre_sec, post_sec, env_shape, base_hz, max_hz, strength_db)
  local pre = math.max(0, pre_sec)
  local post = math.max(0, post_sec)
  local shape = env_shape or 0
  local base = base_hz or 20.0
  local maxv = max_hz or 500.0
  local db = strength_db or 6.0
  if db < 0 then db = 0 end
  if db > 60 then db = 60 end
  local intensity = db / 6.0

  local t0 = math.max(0, t_start - pre)
  local t4 = t_end + post

  local pts = {}
  for i = 1, #seg_points do
    local pt = seg_points[i]
    if pt and pt.offset_sec and pt.val then
      local tt = t_start + pt.offset_sec
      if tt < t_start then tt = t_start end
      if tt > t_end then tt = t_end end
      local vv = base + (pt.val - base) * intensity
      if vv < base then vv = base end
      if vv > maxv then vv = maxv end
      pts[#pts + 1] = { t = tt, v = vv }
    end
  end

  table.sort(pts, function(a, b) return a.t < b.t end)

  if #pts == 0 then
    reaper.InsertEnvelopePointEx(env, -1, t0, base, 0, 0, false, true)
    reaper.InsertEnvelopePointEx(env, -1, t4, base, 0, 0, false, true)
    return
  end

  if pts[1].t > t_start then
    table.insert(pts, 1, { t = t_start, v = pts[1].v })
  else
    pts[1].t = t_start
  end

  if pts[#pts].t < t_end then
    pts[#pts + 1] = { t = t_end, v = pts[#pts].v }
  else
    pts[#pts].t = t_end
  end

  local simplified = simplify_curve(pts, 0.75)

  reaper.InsertEnvelopePointEx(env, -1, t0, base, 0, 0, false, true)
  for i = 1, #simplified do
    local p = simplified[i]
    reaper.InsertEnvelopePointEx(env, -1, p.t, p.v, shape, 0, false, true)
  end
  reaper.InsertEnvelopePointEx(env, -1, t4, base, 0, 0, false, true)
end

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

  local buf = reaper.new_array(H * ch)
  
  if hunter then
    Logger:set_target_hunter(hunter.name)
  end
  
  local state = hunter.init(sr, config)
  
  local result_buf = {}

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

        -- Accumulate RMS (only count unique samples, not overlapping windows)
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

        for _, key in ipairs(FEATURE_KEYS) do
          if self.result_buf[key] ~= nil then
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
  local env_gain, env_hpf
  
  if config.use_take_fx then
    local take = reaper.GetActiveTake(item)
    if not take then return 0 end
    env_gain = ensure_take_envelope(take, 0)
    env_hpf = ensure_take_envelope(take, 1)
  else
    local track = reaper.GetMediaItem_Track(item)
    if not track then return 0 end
    env_gain = ensure_track_envelope(track, 0)
    env_hpf = ensure_track_envelope(track, 1)
  end

  if not env_gain or not env_hpf then
    reaper.MB("Could not create/find envelope for Floop Hunter.jsfx.", "Floop Hunter Error", 0)
    return 0
  end

  reaper.Envelope_SortPoints(env_gain)
  reaper.Envelope_SortPoints(env_hpf)

  local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  local item_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")

  local pre_sec = (config.pre_ramp_ms or 0) / 1000
  local post_sec = (config.post_ramp_ms or 0) / 1000

  if config.overwrite then
    if config.use_take_fx then
      local take = reaper.GetActiveTake(item)
      local play_rate = take and reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE") or 1.0
      reaper.DeleteEnvelopePointRange(env_gain, 0, item_len * play_rate + 1.0)
      reaper.DeleteEnvelopePointRange(env_hpf, 0, item_len * play_rate + 1.0)
    else
      reaper.DeleteEnvelopePointRange(env_gain, math.max(0, item_pos - pre_sec), item_pos + item_len + post_sec)
      reaper.DeleteEnvelopePointRange(env_hpf, math.max(0, item_pos - pre_sec), item_pos + item_len + post_sec)
    end
  end

  local shape = config.env_shape or 0

  for _, seg in ipairs(segments) do
    local t_start = seg.start_time
    local t_end = seg.end_time

    if config.use_take_fx then
      t_start = t_start - item_pos
      t_end = t_end - item_pos
    end

    if seg.points and #seg.points > 0 then
        local strength_db = seg.hpf_strength or seg.gain_db or seg.reduction_db or config.reduction_db or 6.0
        insert_hpf_curve(env_hpf, t_start, t_end, seg.points, pre_sec, post_sec, shape, 20.0, 500.0, strength_db)
    else
        -- This is a Gain envelope for Ess/Breath/Unified default
        local seg_val = seg.gain_db or seg.reduction_db or config.reduction_db or 0
        seg_val = -math.abs(seg_val)
        insert_reduction_points(env_gain, t_start, t_end, seg_val, pre_sec, post_sec, false, shape, 0)
    end
  end

  reaper.Envelope_SortPoints(env_gain)
  reaper.Envelope_SortPoints(env_hpf)
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

  local function sanitize_csv_field(s)
    s = tostring(s or "")
    s = s:gsub("[\r\n]", " ")
    s = s:gsub(",", "_")
    return s
  end

  local function get_item_file_id(item)
    local take = reaper.GetActiveTake(item)
    if take then
      local src = reaper.GetMediaItemTake_Source(take)
      if src and reaper.GetMediaSourceFileName then
        local _, fn = reaper.GetMediaSourceFileName(src, "")
        if fn and fn ~= "" then
          local base = fn:match("([^/\\]+)$") or fn
          if base and base ~= "" then return sanitize_csv_field(base) end
        end
      end
      if reaper.GetTakeName then
        local tn = reaper.GetTakeName(take)
        if tn and tn ~= "" then return sanitize_csv_field(tn) end
      end
    end
    local _, guid = reaper.GetSetMediaItemInfo_String(item, "GUID", "", false)
    return sanitize_csv_field(guid)
  end

  for i = 0, cnt - 1 do
    local item = reaper.GetSelectedMediaItem(0, i)
    local item_pos_proj = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local file_id = get_item_file_id(item)
    local features, time_map = Engine.analyze_item(item, hunter, config)

    if features and features.level and #features.level > 0 then
      local segments_idx, stats = hunter.detect_segments(features, config)
      local profile_id = tonumber(config.source_profile or 0) or 0

      if hunter then
        Logger:set_target_hunter(hunter.name)
        Logger:debug(string.format("EVAL_FILE | file_id:%s | profile:%d", file_id, profile_id))
        if stats and stats.rejected then
          for _, r in ipairs(stats.rejected) do
            local t1 = time_map[r.start_idx]
            local t2 = time_map[r.end_idx]
            if t1 and t2 then
              local t_end_real = t2 + (config.hop_ms / 1000)
              local s_ms = math.floor(((t1 - item_pos_proj) * 1000) + 0.5)
              local e_ms = math.floor(((t_end_real - item_pos_proj) * 1000) + 0.5)
              Logger:csv(string.format("%s,%d,%d,%d,%s", file_id, profile_id, s_ms, e_ms, "rej_" .. tostring(r.reason or "unk")))
            end
          end
        end
      end

      local segments_time = {}
      local csv_label = "det_generic"
      if hunter and hunter.name == "Breath Hunter" then csv_label = "det_breath_inhale"
      elseif hunter and hunter.name == "Ess Hunter" then csv_label = "det_ess"
      elseif hunter and hunter.name == "Plosive Hunter" then csv_label = "det_plosive" end

      for _, seg in ipairs(segments_idx) do
        local t1 = time_map[seg.start_idx]
        local t2 = time_map[seg.end_idx]
        if t1 and t2 then
          local t_end_real = t2 + (config.hop_ms / 1000)
          table.insert(segments_time, { 
            start_time = t1, 
            end_time = t_end_real,
            points = seg.points,
            target_hz = seg.target_hz,
            gain_db = seg.gain_db
          })

          if hunter then
            local s_ms = math.floor(((t1 - item_pos_proj) * 1000) + 0.5)
            local e_ms = math.floor(((t_end_real - item_pos_proj) * 1000) + 0.5)
            Logger:csv(string.format("%s,%d,%d,%d,%s", file_id, profile_id, s_ms, e_ms, csv_label))
          end
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
