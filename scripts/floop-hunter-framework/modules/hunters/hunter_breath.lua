-- @noindex
-- @description Floop Hunter Framework - Breath hunter
-- @author Floop-s
-- @license GPL-3.0
local DSP = require("floop_dsp")
local Logger = require("floop_logger")

local Hunter = {}
Hunter.name = "Breath Hunter"

Hunter.default_config = {
  source_profile = 0, -- 0: Unselected, 1: Female, 2: Male, 3: Spoken, 4: Rap
  window_ms = 20,
  hop_ms = 10,
  min_level_db = -50.0,
  max_level_db = -20.0,
  min_seg_ms = 80,
  max_gap_ms = 40,
  reduction_db = 12.0,
  pre_ramp_ms = 20,
  post_ramp_ms = 20,
  overwrite = true,
  use_prefx = false,
  level_auto = true,
  sensitivity = 0.0
}

function Hunter.init(sr, config)
  local profile = config.source_profile or 1
  Logger:debug(string.format("BREATH_INIT | profile:%d | sr:%d", profile, sr))
  
  local air_freq = 1000
  if profile == 1 then air_freq = 1200 end -- Female
  if profile == 2 or profile == 3 or profile == 4 then air_freq = 800 end -- Male/Spoken
  
  local chest_freq = 400
  if profile == 2 or profile == 3 or profile == 4 then chest_freq = 250 end
  Logger:debug(string.format("BREATH_CFG | air_hp:%d | chest_lp:%d", air_freq, chest_freq))

  local num_hops = math.max(1, math.floor(config.window_ms / config.hop_ms))
  local hist = { wb={}, air={}, chest={}, zcr={}, b1={}, b2={}, b3={} }
  for i=1,num_hops do
      hist.wb[i] = 0.0
      hist.air[i] = 0.0
      hist.chest[i] = 0.0
      hist.zcr[i] = 0
      hist.b1[i] = 0.0
      hist.b2[i] = 0.0
      hist.b3[i] = 0.0
  end

  return {
    sr = sr,
    hp_air = DSP.biquad_new(DSP.rbj_highpass(air_freq, 0.707, sr)),
    lp_chest = DSP.biquad_new(DSP.rbj_lowpass(chest_freq, 0.707, sr)),
    bp1 = DSP.biquad_new(DSP.rbj_bandpass(2000, 1.0, sr)),
    bp2 = DSP.biquad_new(DSP.rbj_bandpass(4000, 1.0, sr)),
    bp3 = DSP.biquad_new(DSP.rbj_bandpass(8000, 1.0, sr)),
    prev_sign = 0,
    num_hops = num_hops,
    hist = hist,
    hist_idx = 1
  }
end

function Hunter.process_window(buf, ch, state, result_buf)
  local H_samples = (#buf) / ch
  local hop_wb = 0.0
  local hop_air = 0.0
  local hop_chest = 0.0
  local hop_zcr = 0
  local hop_b1 = 0.0
  local hop_b2 = 0.0
  local hop_b3 = 0.0
  local prev_sign = state.prev_sign or 0

  for i = 0, H_samples - 1 do
    local mono = 0.0
    for c = 0, ch - 1 do mono = mono + buf[(i * ch) + c + 1] end
    mono = mono / ch
    hop_wb = hop_wb + mono * mono

    local air = DSP.biquad_process(state.hp_air, mono)
    hop_air = hop_air + air * air

    local sign = (air >= 0) and 1 or -1
    if prev_sign ~= 0 and sign ~= prev_sign then hop_zcr = hop_zcr + 1 end
    prev_sign = sign

    local chest = DSP.biquad_process(state.lp_chest, mono)
    hop_chest = hop_chest + chest * chest

    local b1 = DSP.biquad_process(state.bp1, mono)
    local b2 = DSP.biquad_process(state.bp2, mono)
    local b3 = DSP.biquad_process(state.bp3, mono)
    hop_b1 = hop_b1 + b1 * b1
    hop_b2 = hop_b2 + b2 * b2
    hop_b3 = hop_b3 + b3 * b3
  end

  state.prev_sign = prev_sign

  local idx = state.hist_idx
  state.hist.wb[idx] = hop_wb
  state.hist.air[idx] = hop_air
  state.hist.chest[idx] = hop_chest
  state.hist.zcr[idx] = hop_zcr
  state.hist.b1[idx] = hop_b1
  state.hist.b2[idx] = hop_b2
  state.hist.b3[idx] = hop_b3
  
  state.hist_idx = idx + 1
  if state.hist_idx > state.num_hops then state.hist_idx = 1 end

  local sum_sq_wb = 0.0
  local sum_sq_air = 0.0
  local sum_sq_chest = 0.0
  local total_zcr = 0
  local sum_b1 = 0.0
  local sum_b2 = 0.0
  local sum_b3 = 0.0

  for i=1, state.num_hops do
      sum_sq_wb = sum_sq_wb + state.hist.wb[i]
      sum_sq_air = sum_sq_air + state.hist.air[i]
      sum_sq_chest = sum_sq_chest + state.hist.chest[i]
      total_zcr = total_zcr + state.hist.zcr[i]
      sum_b1 = sum_b1 + state.hist.b1[i]
      sum_b2 = sum_b2 + state.hist.b2[i]
      sum_b3 = sum_b3 + state.hist.b3[i]
  end

  local N = H_samples * state.num_hops

  local rms_wb = math.sqrt(sum_sq_wb / math.max(1, N))
  local rms_air = math.sqrt(sum_sq_air / math.max(1, N))
  local rms_chest = math.sqrt(sum_sq_chest / math.max(1, N))

  local zcr_norm = total_zcr / math.max(1, (N - 1))
  local level_db = DSP.amp_to_db(rms_wb)
  local air_db = DSP.amp_to_db(rms_air)

  local air_ratio = (rms_air + 1e-9) / (rms_wb + 1e-9)
  local chest_ratio = (rms_chest + 1e-9) / (rms_wb + 1e-9)
  local sum_b = sum_b1 + sum_b2 + sum_b3
  local max_b = math.max(sum_b1, math.max(sum_b2, sum_b3))
  local air_conc = max_b / math.max(1e-12, sum_b)

  if result_buf then
    result_buf.level = level_db
    result_buf.air_ratio = air_ratio
    result_buf.air_db = air_db
    result_buf.chest_ratio = chest_ratio
    result_buf.zcr = zcr_norm
    result_buf.air_conc = air_conc
    return result_buf
  else
    return {
      level = level_db,
      air_ratio = air_ratio,
      air_db = air_db,
      chest_ratio = chest_ratio,
      zcr = zcr_norm,
      air_conc = air_conc
    }
  end
end

function Hunter.detect_segments(features_arrays, config)
  local raw_segments = {}
  local segments = {}

  local levels = features_arrays.level
  local air_ratios = features_arrays.air_ratio
  local air_dbs = features_arrays.air_db
  local chest_ratios = features_arrays.chest_ratio
  local zcrs = features_arrays.zcr
  local air_concs = features_arrays.air_conc

  if not levels or not air_ratios or not air_dbs or not chest_ratios or not zcrs or not air_concs then return {} end

  local num_frames = #levels
  local inS = false
  local seg_start_idx = 0
  local gap_run_ms = 0
  local last_valid_idx = 0

  local profile = config.source_profile or 1
  local sens = config.sensitivity or 0.0
  local sens_used = sens
  if profile == 4 then sens_used = sens * 0.90 end

  local air_thresh = 0.40 - (sens_used * 0.10)
  
  local chest_thresh = 0.30 + (sens_used * 0.10)
  if profile == 2 or profile == 3 or profile == 4 then chest_thresh = 0.45 + (sens_used * 0.15) end
  
  local zcr_thresh = 0.15 - (sens_used * 0.05)
  local conc_thresh = 0.60 + (sens_used * 0.15)
  if conc_thresh < 0.45 then conc_thresh = 0.45 end
  if conc_thresh > 0.85 then conc_thresh = 0.85 end
  local max_air_attack_db = 12.0 + (sens_used * 6.0)
  local var_win = math.max(3, math.floor(200 / config.hop_ms + 0.5))
  local var_thr = 1.0 + (sens_used * 1.0)
  if var_thr < 0.25 then var_thr = 0.25 end
  if var_thr > 3.0 then var_thr = 3.0 end
  
  if profile == 4 then
    air_thresh = air_thresh + 0.02
    chest_thresh = chest_thresh - 0.06
    zcr_thresh = zcr_thresh + 0.04
    conc_thresh = conc_thresh - 0.08
    max_air_attack_db = max_air_attack_db - 4.0
  end
  
  if air_thresh < 0.20 then air_thresh = 0.20 end
  if air_thresh > 0.70 then air_thresh = 0.70 end
  if chest_thresh < 0.18 then chest_thresh = 0.18 end
  if chest_thresh > 0.60 then chest_thresh = 0.60 end
  if zcr_thresh < 0.05 then zcr_thresh = 0.05 end
  if zcr_thresh > 0.30 then zcr_thresh = 0.30 end
  if conc_thresh < 0.35 then conc_thresh = 0.35 end
  if conc_thresh > 0.85 then conc_thresh = 0.85 end
  if max_air_attack_db < 4.0 then max_air_attack_db = 4.0 end
  if var_thr > 3.0 then var_thr = 3.0 end

  local item_rms = config.item_rms_db or -25.0
  local min_level = config.min_level_db
  local max_level = config.max_level_db

  local env_var = features_arrays.env_var
  if not env_var then
    env_var = {}
    local sum = 0.0
    for i = 1, num_frames do
      local x = air_dbs[i]
      sum = sum + x
      if i > var_win then
        local xo = air_dbs[i - var_win]
        sum = sum - xo
      end
      
      local n = math.min(i, var_win)
      local mean = sum / n
      
      local start_idx = math.max(1, i - var_win + 1)
      local var_sum = 0.0
      for j = start_idx, i do
        local diff = air_dbs[j] - mean
        var_sum = var_sum + diff * diff
      end
      
      env_var[i] = var_sum / n
    end
    features_arrays.env_var = env_var
  end

  local function calculate_breath_segments(levels, env_var, air_dbs, chest_ratios, air_ratios, zcrs, air_concs, env_array)
      local inS = false
      local seg_start_idx = 0
      local gap_run_ms = 0
      local last_valid_idx = 0
      local prev_air_db = nil
      local raw_segments = {}
      local base_depth = 12.0 - (sens * 3.0)

      for i = 1, num_frames do
          local f_level = levels[i]
          local is_breath = false
          
          local pass_level = false
          local current_env = 0
          if env_array then
              current_env = env_array[i]
              local dyn_min = math.max(-80.0, current_env - base_depth - 15.0)
              local dyn_max = math.max(max_level, current_env - 2.0)
              pass_level = (f_level > dyn_min and f_level < dyn_max)
          else
              current_env = max_level
              pass_level = (f_level > min_level and f_level < max_level)
          end
          
          if pass_level then
              local f_chest = chest_ratios[i]
              local f_air = air_ratios[i]
              local f_zcr = zcrs[i]
              local f_conc = air_concs[i]
              local f_var = env_var[i]
              
              local core = (f_chest < chest_thresh and f_air > air_thresh and f_zcr > zcr_thresh)
              if core then
                  local air_db = air_dbs[i]
                  local delta_air_db = 0.0
                  if prev_air_db then delta_air_db = air_db - prev_air_db end
                  prev_air_db = air_db
                  
                  if delta_air_db <= max_air_attack_db and ((f_conc < conc_thresh) or (f_var > var_thr)) then
                      local sib_air = 0.85
                      local sib_db = 6.0
                      if profile == 4 then sib_air = 0.82; sib_db = 8.0 end
                      local is_sibilant = (f_air > sib_air and f_level > (current_env - sib_db))
                      if not is_sibilant then
                          is_breath = true
                      end
                  end
              else
                  prev_air_db = nil
              end
          else
              prev_air_db = nil
          end

          if is_breath then
              if not inS then
                  inS = true
                  seg_start_idx = i
              end
              gap_run_ms = 0
              last_valid_idx = i
          else
              if inS then
                  gap_run_ms = gap_run_ms + config.hop_ms
                  if gap_run_ms >= config.max_gap_ms then
                      local dur_ms = (last_valid_idx - seg_start_idx) * config.hop_ms
                      if dur_ms >= config.min_seg_ms then
                          table.insert(raw_segments, { start_idx = seg_start_idx, end_idx = last_valid_idx })
                      end
                      inS = false
                      gap_run_ms = 0
                  end
              end
          end
      end
      
      if inS then
          local dur_ms = (last_valid_idx - seg_start_idx) * config.hop_ms
          if dur_ms >= config.min_seg_ms then
              table.insert(raw_segments, { start_idx = seg_start_idx, end_idx = last_valid_idx })
          end
      end
      
      return raw_segments
  end

  if config.level_auto then
    local win_frames = math.floor(3000 / config.hop_ms)
    local half_win = math.floor(win_frames / 2)
    local local_env = features_arrays.local_env
    
    if not local_env then
        local_env = {}
        local last_valid_env = item_rms > -60 and item_rms or -25.0 
        for i = 1, num_frames do
           local start_i = math.max(1, i - half_win)
           local end_i = math.min(num_frames, i + half_win)
           local sum, cnt = 0, 0
           for k = start_i, end_i, 5 do
              local l = levels[k]
              if l and l > -55.0 then 
                 sum = sum + l
                 cnt = cnt + 1
              end
           end
           if cnt > 0 then
              local_env[i] = sum / cnt
              last_valid_env = local_env[i]
           else
              local_env[i] = last_valid_env
           end
        end
        features_arrays.local_env = local_env
    end
    
    raw_segments = calculate_breath_segments(levels, env_var, air_dbs, chest_ratios, air_ratios, zcrs, air_concs, local_env)
  else
    -- Manual mode
    raw_segments = calculate_breath_segments(levels, env_var, air_dbs, chest_ratios, air_ratios, zcrs, air_concs, nil)
  end

  -- Expansion phase (Lookaround to capture tails)
  local extend_margin_db = 6.0 - 2.0 * sens
  for _, seg in ipairs(raw_segments) do
    local s, e = seg.start_idx, seg.end_idx
    local sum_lvl, cnt = 0, 0
    for i=s, e do sum_lvl = sum_lvl + levels[i]; cnt = cnt + 1 end
    local seg_mean = sum_lvl / math.max(1, cnt)

    local new_s, new_e = s, e
    
    -- Expand left
    local i = s - 1
    while i >= 1 do
        if not levels[i] or levels[i] < seg_mean - extend_margin_db then break end
        if chest_ratios[i] > chest_thresh then break end -- Hit a vowel
        new_s = i; i = i - 1
    end
    
    -- Expand right
    i = e + 1
    while i <= num_frames do
        if not levels[i] or levels[i] < seg_mean - extend_margin_db then break end
        if chest_ratios[i] > chest_thresh then break end -- Hit a vowel
        new_e = i; i = i + 1
    end
    
    local dur_ms = (new_e - new_s) * config.hop_ms
    local max_expansion_ms = 1500 -- safety upper bound
    if dur_ms >= config.min_seg_ms and dur_ms <= max_expansion_ms then
      table.insert(segments, { start_idx = new_s, end_idx = new_e })
    end
  end

  return segments, {}
end

return Hunter
