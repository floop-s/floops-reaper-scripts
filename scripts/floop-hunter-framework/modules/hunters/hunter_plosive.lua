-- @noindex
-- @description Floop Hunter Framework - Plosive hunter
-- @author Floop-s
-- @license GPL-3.0
local DSP = require("floop_dsp")
local Logger = require("floop_logger")

local Hunter = {}
Hunter.name = "Plosive Hunter"

Hunter.default_config = {
  source_profile = 0, -- 0: Unselected, 1: Female, 2: Male, 3: Spoken, 4: Rap
  low_pass = 150, 
  min_low_db = -50.0,
  ratio_thresh = 12.0, 
  transient_thresh = 3.0,
  crest_thresh = 2.5,
  decay_thresh = 3.0,
  window_ms = 20,
  hop_ms = 5,
  min_seg_ms = 15,
  max_gap_ms = 20,
  pre_ramp_ms = 10,
  post_ramp_ms = 20,
  reduction_db = 6.0
}

function Hunter.init(sr, config)
  local profile = config.source_profile or 1
  Logger:debug(string.format("PLOSIVE_INIT | profile:%d | sr:%d", profile, sr))
  local lp_freq = config.low_pass
  if profile == 2 or profile == 3 or profile == 4 then
      lp_freq = math.min(120, config.low_pass)
  end
  Logger:debug(string.format("PLOSIVE_CFG | lp:%d | hp:%d", lp_freq, 500))

  local num_hops = math.max(1, math.floor(config.window_ms / config.hop_ms))
  local crest_frames = math.max(1, math.floor(15 / config.hop_ms))
  
  local hist = { wb={}, low={}, high={}, peak_low={} }
  for i=1,num_hops do hist.wb[i]=0.0; hist.low[i]=0.0; hist.high[i]=0.0; hist.peak_low[i]=0.0; end

  return {
    sr = sr,
    lp_filter = DSP.biquad_new(DSP.rbj_lowpass(lp_freq, 0.707, sr)),
    hp_filter = DSP.biquad_new(DSP.rbj_highpass(500, 0.707, sr)),
    dc_blocker = DSP.biquad_new(DSP.rbj_highpass(20, 0.707, sr)),
    num_hops = num_hops,
    crest_frames = crest_frames,
    hist = hist,
    hist_idx = 1
  }
end

function Hunter.process_window(buf, ch, state, result_buf)
  local H_samples = (#buf) / ch
  local hop_wb, hop_low, hop_high = 0.0, 0.0, 0.0
  local hop_peak_low = 0.0
  
  for i = 0, H_samples - 1 do
    local mono = 0.0
    for c = 0, ch - 1 do mono = mono + buf[(i * ch) + c + 1] end
    mono = mono / ch
    mono = DSP.biquad_process(state.dc_blocker, mono)
    hop_wb = hop_wb + mono * mono
    
    local low = DSP.biquad_process(state.lp_filter, mono)
    hop_low = hop_low + low * low
    local alow = math.abs(low)
    if alow > hop_peak_low then hop_peak_low = alow end

    local high = DSP.biquad_process(state.hp_filter, mono)
    hop_high = hop_high + high * high
  end

  local idx = state.hist_idx
  state.hist.wb[idx] = hop_wb
  state.hist.low[idx] = hop_low
  state.hist.high[idx] = hop_high
  state.hist.peak_low[idx] = hop_peak_low
  
  state.hist_idx = idx + 1
  if state.hist_idx > state.num_hops then state.hist_idx = 1 end
  
  local sum_sq_wb, sum_sq_low, sum_sq_high = 0.0, 0.0, 0.0
  local peak_low = 0.0
  for i=1, state.num_hops do
      sum_sq_wb = sum_sq_wb + state.hist.wb[i]
      sum_sq_low = sum_sq_low + state.hist.low[i]
      sum_sq_high = sum_sq_high + state.hist.high[i]
  end
  
  local crest_start = state.hist_idx - state.crest_frames
  if crest_start < 1 then crest_start = crest_start + state.num_hops end
  
  local crest_rms_sq = 0.0
  local c_idx = crest_start
  for i=1, state.crest_frames do
      if state.hist.peak_low[c_idx] > peak_low then peak_low = state.hist.peak_low[c_idx] end
      crest_rms_sq = crest_rms_sq + state.hist.low[c_idx]
      c_idx = c_idx + 1
      if c_idx > state.num_hops then c_idx = 1 end
  end

  local N = H_samples * state.num_hops
  local crest_N = H_samples * state.crest_frames
  local rms_wb = math.sqrt(sum_sq_wb / math.max(1, N))
  local rms_low = math.sqrt(sum_sq_low / math.max(1, N))
  local rms_high = math.sqrt(sum_sq_high / math.max(1, N))
  local crest_rms_low = math.sqrt(crest_rms_sq / math.max(1, crest_N))
  
  local wb_db = DSP.amp_to_db(rms_wb)
  local low_db = DSP.amp_to_db(rms_low)
  local high_db = DSP.amp_to_db(rms_high)
  
  local diff_db = low_db - high_db
  local crest_low = peak_low / math.max(1e-12, crest_rms_low)

  if result_buf then
    result_buf.level = wb_db
    result_buf.low_db = low_db
    result_buf.high_db = high_db
    result_buf.diff_db = diff_db
    result_buf.crest_low = crest_low
    return result_buf
  else
    return { level = wb_db, low_db = low_db, high_db = high_db, diff_db = diff_db, crest_low = crest_low }
  end
end

function Hunter.detect_segments(features, config)
  local lows = features.low_db
  local diffs = features.diff_db
  local crests = features.crest_low
  
  if not lows or not diffs or not crests then return {} end

  local segments = {}
  local inS = false
  local seg_start_idx = 0
  local gap_run_ms = 0
  local current_peak_low = -999
  
  local profile = config.source_profile or 1
  local max_plosive_ms = 120
  if profile == 3 then max_plosive_ms = 100 end
  if profile == 4 then max_plosive_ms = 90 end
  
  local min_low_db = config.min_low_db
  local ratio_thresh = config.ratio_thresh
  local transient_thresh = (config.transient_thresh or 3.0)
  local crest_thresh = (config.crest_thresh or 2.5)
  local decay_thresh = (config.decay_thresh or 3.0)
  
  if profile == 4 then
    min_low_db = min_low_db - 3.0
    ratio_thresh = math.max(2.0, ratio_thresh - 16.0)
    transient_thresh = transient_thresh - 1.5
    crest_thresh = crest_thresh - 0.3
    decay_thresh = decay_thresh - 1.0
  end
  
  if ratio_thresh < -18.0 then ratio_thresh = -18.0 end
  if transient_thresh < 0.5 then transient_thresh = 0.5 end
  if crest_thresh < 1.5 then crest_thresh = 1.5 end
  if decay_thresh < 1.0 then decay_thresh = 1.0 end
  
  local prev_low = -100
  local decay_lookahead = math.max(1, math.floor(20 / config.hop_ms + 0.5))
  local burst_hold_frames = math.max(1, math.floor(30 / config.hop_ms + 0.5))
  local burst_hold = 0
  
  for i = 1, #lows do
    local f_low_db = lows[i]
    local f_diff_db = diffs[i]
    local f_crest = crests[i]
    local next_low_db = lows[i + decay_lookahead]
    local decay_db = 0.0
    if next_low_db ~= nil then
      decay_db = f_low_db - next_low_db
    end
    
    local low_delta = f_low_db - prev_low
    prev_low = f_low_db
    
    if not inS and low_delta > transient_thresh then
        burst_hold = burst_hold_frames
    elseif burst_hold > 0 then
        burst_hold = burst_hold - 1
    end
    
    local is_loud = (f_low_db > min_low_db)
    local is_thump = (f_diff_db > ratio_thresh)
    local is_spiky = (f_crest > crest_thresh)
    local is_fast_decay = (next_low_db ~= nil) and (decay_db > decay_thresh)
    local has_impulse_shape = is_spiky or is_fast_decay
    
    local pass_on = false
    if inS then
        pass_on = is_loud and is_thump
    else
        pass_on = is_loud and is_thump and (burst_hold > 0) and has_impulse_shape
    end

    if pass_on then
       if not inS then
          inS = true
          seg_start_idx = i
          gap_run_ms = 0
          current_peak_low = f_low_db
       else
          gap_run_ms = 0
          if f_low_db > current_peak_low then current_peak_low = f_low_db end
       end
    else
       if inS then
          gap_run_ms = gap_run_ms + config.hop_ms
          if gap_run_ms >= config.max_gap_ms then
             local end_idx = i - math.floor(gap_run_ms / config.hop_ms)
             local dur_ms = (end_idx - seg_start_idx) * config.hop_ms
             
             if dur_ms >= config.min_seg_ms and dur_ms <= max_plosive_ms then
                table.insert(segments, {
                   start_idx = seg_start_idx, 
                   end_idx = end_idx,
                   peak_low_db = current_peak_low
                })
             end
             inS = false
             burst_hold = 0
             gap_run_ms = 0
             current_peak_low = -999
          end
       end
    end
  end
  
  if inS then
     local end_idx = #lows
     local dur_ms = (end_idx - seg_start_idx) * config.hop_ms
     if dur_ms >= config.min_seg_ms and dur_ms <= max_plosive_ms then
        table.insert(segments, {
           start_idx = seg_start_idx, 
           end_idx = end_idx,
           peak_low_db = current_peak_low
        })
     end
  end

  return segments, {
     min_level_use = config.min_low_db,
     thr_on = config.ratio_thresh
  }
end

return Hunter
