-- @noindex
-- @description Floop Hunter Framework - Breath hunter
-- @author Floop-s
-- @license GPL-3.0
local DSP = require("floop_dsp")
local Logger = require("floop_logger")

local Hunter = {}
Hunter.name = "Breath Hunter"

local function clamp01(x)
  if x <= 0.0 then return 0.0 end
  if x >= 1.0 then return 1.0 end
  return x
end

-- =========================================================================
-- MATRIX DEI PROFILI ACUSTICI (CENTRALIZZATA)
-- =========================================================================
Hunter.Profiles = {
  [1] = { -- FEMALE
    name = "Female",
    air_freq = 1200,
    chest_freq = 950,
    chest_gate = 0.75,
    chest_thresh_base = 0.30,
    air_thresh_base = 0.40,
    zcr_thresh_base = 0.15,
    conc_thresh_base = 0.60,
    max_air_attack_db = 12.0,
    sib_air = 0.85,
    sib_db = 6.0,
    v_chest_min = 0.42,
    v_chest_max = 0.68,
    vr_chest_min = 0.52,
    vr_chest_max = 0.72
  },
  [2] = { -- MALE
    name = "Male",
    air_freq = 800,
    chest_freq = 250,
    chest_thresh_base = 0.45,
    air_thresh_base = 0.40,
    zcr_thresh_base = 0.15,
    conc_thresh_base = 0.60,
    max_air_attack_db = 12.0,
    sib_air = 0.85,
    sib_db = 6.0,
    v_chest_min = 0.26,
    v_chest_max = 0.50,
    vr_chest_min = 0.36,
    vr_chest_max = 0.56
  },
  [3] = {
    name = "Spoken Male",
    air_freq = 800,
    chest_freq = 250,
    chest_thresh_base = 0.45,
    air_thresh_base = 0.40,
    zcr_thresh_base = 0.15,
    conc_thresh_base = 0.60,
    max_air_attack_db = 12.0,
    sib_air = 0.85,
    sib_db = 6.0,
    v_chest_min = 0.26,
    v_chest_max = 0.50,
    vr_chest_min = 0.36,
    vr_chest_max = 0.56
  },
  [4] = {
    name = "Spoken Female",
    air_freq = 1200,
    chest_freq = 450,
    chest_gate = 0.72,
    chest_thresh_base = 0.45,
    air_thresh_base = 0.40,
    zcr_thresh_base = 0.15,
    conc_thresh_base = 0.60,
    max_air_attack_db = 12.0,
    sib_air = 0.85,
    sib_db = 6.0,
    v_chest_min = 0.42,
    v_chest_max = 0.68,
    vr_chest_min = 0.52,
    vr_chest_max = 0.72
  },
  [5] = { -- RAP
    name = "Rap",
    air_freq = 800,
    chest_freq = 250,
    chest_thresh_base = 0.39, -- (0.45 - 0.06)
    air_thresh_base = 0.42,   -- (0.40 + 0.02)
    zcr_thresh_base = 0.19,   -- (0.15 + 0.04)
    conc_thresh_base = 0.52,  -- (0.60 - 0.08)
    max_air_attack_db = 8.0,  -- (12.0 - 4.0)
    sib_air = 0.82,
    sib_db = 8.0,
    v_chest_min = 0.26,
    v_chest_max = 0.50,
    vr_chest_min = 0.36,
    vr_chest_max = 0.56
  }
}

Hunter.default_config = {
  source_profile = 2, -- Default su Male
  window_ms = 20,
  hop_ms = 10,
  min_level_db = -65.0,
  max_level_db = -20.0,
  min_seg_ms = 80,
  max_gap_ms = 40,
  reduction_db = 12.0,
  pre_ramp_ms = 20,
  post_ramp_ms = 20,
  overwrite = true,
  use_take_fx = false,
  level_auto = true,
  sensitivity = 0.0,
  focus = 0.5,
  style = 0.5,
  character = 0.5
}

function Hunter.init(sr, config)
  local profile_id = config.source_profile or 2
  local profile = Hunter.Profiles[profile_id] or Hunter.Profiles[2]
  
  Logger:debug(string.format("BREATH_INIT | Profilo:%s | sr:%d", profile.name, sr))
  
  local air_freq = profile.air_freq
  local chest_freq = profile.chest_freq
  local ess_freq = 3200
  if profile_id == 1 or profile_id == 4 then ess_freq = 4200 end
  
  Logger:debug(string.format("BREATH_CFG | air_hp:%d | chest_lp:%d", air_freq, chest_freq))

  local num_hops = math.max(1, math.floor(config.window_ms / config.hop_ms))
  local hist = { wb={}, air={}, chest={}, ess={}, zcr={}, chest_zcr={}, ess_zcr={}, b1={}, b2={}, b3={} }
  for i=1,num_hops do
      hist.wb[i] = 0.0
      hist.air[i] = 0.0
      hist.chest[i] = 0.0
      hist.ess[i] = 0.0
      hist.zcr[i] = 0
      hist.chest_zcr[i] = 0
      hist.ess_zcr[i] = 0
      hist.b1[i] = 0.0
      hist.b2[i] = 0.0
      hist.b3[i] = 0.0
  end

  return {
    sr = sr,
    hp_air = DSP.biquad_new(DSP.rbj_highpass(air_freq, 0.707, sr)),
    lp_chest = DSP.biquad_new(DSP.rbj_lowpass(chest_freq, 0.707, sr)),
    hp_ess1 = DSP.biquad_new(DSP.rbj_highpass(ess_freq, 0.707, sr)),
    hp_ess2 = DSP.biquad_new(DSP.rbj_highpass(ess_freq, 0.707, sr)),
    bp1 = DSP.biquad_new(DSP.rbj_bandpass(2000, 1.0, sr)),
    bp2 = DSP.biquad_new(DSP.rbj_bandpass(4000, 1.0, sr)),
    bp3 = DSP.biquad_new(DSP.rbj_bandpass(8000, 1.0, sr)),
    prev_sign = 0,
    prev_chest_sign = 0,
    prev_ess_sign = 0,
    num_hops = num_hops,
    hist = hist,
    hist_idx = 1,
    v_chest_min = profile.v_chest_min or 0.10,
    v_chest_max = profile.v_chest_max or 0.38
  }
end

function Hunter.process_window(buf, ch, state, result_buf)
  local H_samples = (#buf) / ch
  local hop_wb = 0.0
  local hop_air = 0.0
  local hop_chest = 0.0
  local hop_ess = 0.0
  local hop_zcr = 0
  local hop_chest_zcr = 0
  local hop_ess_zcr = 0
  local hop_b1 = 0.0
  local hop_b2 = 0.0
  local hop_b3 = 0.0
  local prev_sign = state.prev_sign or 0
  local prev_chest_sign = state.prev_chest_sign or 0
  local prev_ess_sign = state.prev_ess_sign or 0

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
    local chest_sign = (chest >= 0) and 1 or -1
    if prev_chest_sign ~= 0 and chest_sign ~= prev_chest_sign then hop_chest_zcr = hop_chest_zcr + 1 end
    prev_chest_sign = chest_sign
    
    local ess_stage1 = DSP.biquad_process(state.hp_ess1, mono)
    local ess = DSP.biquad_process(state.hp_ess2, ess_stage1)
    hop_ess = hop_ess + ess * ess
    local ess_sign = (ess >= 0) and 1 or -1
    if prev_ess_sign ~= 0 and ess_sign ~= prev_ess_sign then hop_ess_zcr = hop_ess_zcr + 1 end
    prev_ess_sign = ess_sign

    local b1 = DSP.biquad_process(state.bp1, mono)
    local b2 = DSP.biquad_process(state.bp2, mono)
    local b3 = DSP.biquad_process(state.bp3, mono)
    hop_b1 = hop_b1 + b1 * b1
    hop_b2 = hop_b2 + b2 * b2
    hop_b3 = hop_b3 + b3 * b3
  end

  state.prev_sign = prev_sign
  state.prev_chest_sign = prev_chest_sign
  state.prev_ess_sign = prev_ess_sign

  local idx = state.hist_idx
  state.hist.wb[idx] = hop_wb
  state.hist.air[idx] = hop_air
  state.hist.chest[idx] = hop_chest
  state.hist.ess[idx] = hop_ess
  state.hist.zcr[idx] = hop_zcr
  state.hist.chest_zcr[idx] = hop_chest_zcr
  state.hist.ess_zcr[idx] = hop_ess_zcr
  state.hist.b1[idx] = hop_b1
  state.hist.b2[idx] = hop_b2
  state.hist.b3[idx] = hop_b3
  
  state.hist_idx = idx + 1
  if state.hist_idx > state.num_hops then state.hist_idx = 1 end

  local sum_sq_wb = 0.0
  local sum_sq_air = 0.0
  local sum_sq_chest = 0.0
  local sum_sq_ess = 0.0
  local total_zcr = 0
  local total_chest_zcr = 0
  local total_ess_zcr = 0
  local sum_b1 = 0.0
  local sum_b2 = 0.0
  local sum_b3 = 0.0

  for i=1, state.num_hops do
      sum_sq_wb = sum_sq_wb + state.hist.wb[i]
      sum_sq_air = sum_sq_air + state.hist.air[i]
      sum_sq_chest = sum_sq_chest + state.hist.chest[i]
      sum_sq_ess = sum_sq_ess + state.hist.ess[i]
      total_zcr = total_zcr + state.hist.zcr[i]
      total_chest_zcr = total_chest_zcr + state.hist.chest_zcr[i]
      total_ess_zcr = total_ess_zcr + state.hist.ess_zcr[i]
      sum_b1 = sum_b1 + state.hist.b1[i]
      sum_b2 = sum_b2 + state.hist.b2[i]
      sum_b3 = sum_b3 + state.hist.b3[i]
  end

  local N = H_samples * state.num_hops

  local rms_wb = math.sqrt(sum_sq_wb / math.max(1, N))
  local rms_air = math.sqrt(sum_sq_air / math.max(1, N))
  local rms_chest = math.sqrt(sum_sq_chest / math.max(1, N))
  local rms_ess = math.sqrt(sum_sq_ess / math.max(1, N))

  local zcr_norm = total_zcr / math.max(1, (N - 1))
  local chest_zcr_norm = total_chest_zcr / math.max(1, (N - 1))
  local ess_zcr_norm = total_ess_zcr / math.max(1, (N - 1))
  local level_db = DSP.amp_to_db(rms_wb)
  local air_db = DSP.amp_to_db(rms_air)

  local air_ratio = (rms_air + 1e-9) / (rms_wb + 1e-9)
  local chest_ratio = (rms_chest + 1e-9) / (rms_wb + 1e-9)
  local ess_ratio = (rms_ess + 1e-9) / (rms_wb + 1e-9)
  local sum_b = sum_b1 + sum_b2 + sum_b3
  local max_b = math.max(sum_b1, math.max(sum_b2, sum_b3))
  local air_conc = max_b / math.max(1e-12, sum_b)
  local v_chest_min = state.v_chest_min or 0.10
  local v_chest_max = state.v_chest_max or 0.38
  local voiced_score = clamp01((chest_ratio - v_chest_min) / (v_chest_max - v_chest_min)) *
    clamp01((0.16 - chest_zcr_norm) / 0.10) *
    clamp01((0.88 - air_ratio) / 0.45)

  if result_buf then
    result_buf.level = level_db
    result_buf.air_ratio = air_ratio
    result_buf.air_db = air_db
    result_buf.chest_ratio = chest_ratio
    result_buf.zcr = zcr_norm
    result_buf.air_conc = air_conc
    result_buf.chest_zcr = chest_zcr_norm
    result_buf.voiced_score = voiced_score
    result_buf.ess_ratio = ess_ratio
    result_buf.ess_zcr = ess_zcr_norm
    return result_buf
  else
    return {
      level = level_db,
      air_ratio = air_ratio,
      air_db = air_db,
      chest_ratio = chest_ratio,
      zcr = zcr_norm,
      air_conc = air_conc,
      chest_zcr = chest_zcr_norm,
      voiced_score = voiced_score,
      ess_ratio = ess_ratio,
      ess_zcr = ess_zcr_norm
    }
  end
end

local function compute_file_statistics(features)
    local stats = {}
    if not features or not features.level then return stats end
    
    local function get_percentile(arr, p, subsample)
        if not arr or #arr == 0 then return 0 end
        local temp = {}
        local step = subsample and math.max(1, math.floor(#arr / 10000)) or 1
        for i = 1, #arr, step do
            local val = arr[i]
            if val ~= nil then temp[#temp + 1] = val end
        end
        if #temp == 0 then return 0 end
        table.sort(temp)
        return temp[math.max(1, math.floor(#temp * p + 0.5))]
    end

    local level_p10 = get_percentile(features.level, 0.10, true)
    local level_p90 = get_percentile(features.level, 0.90, true)
    stats.level_p10 = level_p10
    stats.level_p90 = level_p90
    
    local noise_zcr, noise_air, noise_chest, noise_voiced = {}, {}, {}, {}
    local noise_thr = level_p10 + 6.0
    
    local step = math.max(1, math.floor(#features.level / 10000))
    for i = 1, #features.level, step do
        local lvl = features.level[i]
        if lvl and lvl < noise_thr then
            if features.zcr[i] then noise_zcr[#noise_zcr + 1] = features.zcr[i] end
            if features.air_ratio[i] then noise_air[#noise_air + 1] = features.air_ratio[i] end
            if features.chest_ratio[i] then noise_chest[#noise_chest + 1] = features.chest_ratio[i] end
            if features.voiced_score[i] then noise_voiced[#noise_voiced + 1] = features.voiced_score[i] end
        end
    end
    
    stats.noise_zcr = get_percentile(noise_zcr, 0.50, false)
    stats.noise_air = get_percentile(noise_air, 0.50, false)
    stats.noise_chest = get_percentile(noise_chest, 0.50, false)
    stats.noise_voiced = get_percentile(noise_voiced, 0.50, false)

    return stats
end

local function resolve_macro_config(config, profile)
  -- Estrazione macro-sliders [0.0 - 1.0], default 0.5 (Neutrale)
  local focus = config.focus or 0.5
  local style = config.style or 0.5
  local character = config.character or 0.5

  local res = {}
  for k, v in pairs(config) do res[k] = v end

  -- 1. FOCUS (Sensitivity and Tolerance) -> Replaces legacy sparse logic
  -- 0.0 -> -1.0 (Conservative) | 0.5 -> 0.0 | 1.0 -> +1.0 (Aggressive)
  res.sensitivity = (focus - 0.5) * 2.0

  -- 2. STYLE (Geometria e Pacing del Respiro)
  local base_min_seg = config.min_seg_ms or profile.min_seg_ms or 80
  local base_max_gap = config.max_gap_ms or profile.max_gap_ms or 40
  local style_scale = 0.5 + style -- da 0.5x (Fast) a 1.5x (Deep)
  res.min_seg_ms = math.max(20, math.floor(base_min_seg * style_scale))
  res.max_gap_ms = math.max(10, math.floor(base_max_gap * style_scale))

  -- 3. CHARACTER (Timbro e Offset Spettrale)
  -- 0.0 (Dark/Chest) | 1.0 (Airy/Hiss)
  local char_offset = (character - 0.5) * 2.0
  res.air_thresh = profile.air_thresh_base + (char_offset * 0.04)
  res.chest_thresh = profile.chest_thresh_base - (char_offset * 0.04)
  res.zcr_thresh = profile.zcr_thresh_base - (char_offset * 0.02)

  return res
end

function Hunter.detect_segments(features_arrays, config)
  local raw_segments = {}
  local segments = {}
  local stats = { rejected = {} }
  local max_reject_store = 200

  local levels = features_arrays.level
  local air_ratios = features_arrays.air_ratio
  local air_dbs = features_arrays.air_db
  local chest_ratios = features_arrays.chest_ratio
  local zcrs = features_arrays.zcr
  local air_concs = features_arrays.air_conc
  local chest_zcrs = features_arrays.chest_zcr
  local voiced_scores = features_arrays.voiced_score
  local ess_ratios = features_arrays.ess_ratio
  local ess_zcrs = features_arrays.ess_zcr

  if not levels or not air_ratios or not air_dbs or not chest_ratios or not zcrs or not air_concs then return {} end
  if not chest_zcrs then chest_zcrs = {} end
  if not voiced_scores then voiced_scores = {} end
  if not ess_ratios then ess_ratios = {} end
  if not ess_zcrs then ess_zcrs = {} end

  local num_frames = #levels

  local file_stats = compute_file_statistics(features_arrays)
  local noise_floor = file_stats.level_p10 or -60.0
  local noise_factor = math.max(0, math.min(1, (noise_floor - (-60)) / 25.0))
  
  Logger:info(string.format("Pass 0 - Noise Stats: Lvl_p10=%.1f, factor=%.2f, ZCR_n=%.3f, Air_n=%.2f, Chest_n=%.2f, V_n=%.2f",
      noise_floor, noise_factor, file_stats.noise_zcr or 0, file_stats.noise_air or 0, file_stats.noise_chest or 0, file_stats.noise_voiced or 0))

  local profile_id = config.source_profile or 2
  local profile = Hunter.Profiles[profile_id] or Hunter.Profiles[2]
  
  local res_cfg = resolve_macro_config(config, profile)
  
  local sens = res_cfg.sensitivity or 0.0
  local sens_used = sens
  if profile_id == 5 then sens_used = sens * 0.90 end

  local air_base = (res_cfg.air_thresh ~= nil) and res_cfg.air_thresh or profile.air_thresh_base
  if noise_factor > 0 and file_stats.noise_air then
      local adaptive_air = math.max(0.30, file_stats.noise_air * 0.8)
      air_base = air_base * (1 - noise_factor) + adaptive_air * noise_factor
  end
  local air_thresh = air_base - (sens_used * 0.10)
  
  local chest_base = (res_cfg.chest_thresh ~= nil) and res_cfg.chest_thresh or profile.chest_thresh_base
  if noise_factor > 0 and file_stats.noise_chest then
      local adaptive_chest = math.min(0.45, file_stats.noise_chest * 1.2)
      chest_base = chest_base * (1 - noise_factor) + adaptive_chest * noise_factor
  end
  local chest_thresh = chest_base + (sens_used * 0.15)
  if profile_id == 2 or profile_id == 3 or profile_id == 4 or profile_id == 5 then 
      chest_thresh = chest_thresh + (sens_used * 0.05) 
  end
  
  local zcr_base = (res_cfg.zcr_thresh ~= nil) and res_cfg.zcr_thresh or profile.zcr_thresh_base
  if noise_factor > 0 and file_stats.noise_zcr then
      local adaptive_zcr = math.max(0.08, file_stats.noise_zcr * 0.8)
      zcr_base = zcr_base * (1 - noise_factor) + adaptive_zcr * noise_factor
  end
  local zcr_thresh = zcr_base - (sens_used * 0.05)
  local conc_thresh = profile.conc_thresh_base + (sens_used * 0.20)
  if conc_thresh < 0.45 then conc_thresh = 0.45 end
  if conc_thresh > 0.95 then conc_thresh = 0.95 end
  
  local max_air_attack_db = profile.max_air_attack_db + (sens_used * 6.0)
  
  local var_win = math.max(3, math.floor(200 / config.hop_ms + 0.5))
  local var_thr = 1.0 - (sens_used * 0.80)
  if var_thr < 0.25 then var_thr = 0.25 end
  if var_thr > 3.0 then var_thr = 3.0 end

  local reject_counts = {}
  local function inc_reject(key)
    reject_counts[key] = (reject_counts[key] or 0) + 1
  end
  local reject_debug_quota = { voiced = 999, ess = 999, sib = 999, ctx = 999, score = 999 }
  local function debug_reject(key, msg)
    local q = reject_debug_quota[key]
    if not q or q <= 0 then return end
    reject_debug_quota[key] = q - 1
    Logger:debug(msg)
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

  local item_rms = config.item_rms_db
  if not item_rms and levels then
      local sum_sq = 0.0
      local cnt = 0
      for i = 1, #levels do
          local lvl = levels[i]
          if lvl and lvl > -120 then
              local amp = 10 ^ (lvl / 20)
              sum_sq = sum_sq + amp * amp
              cnt = cnt + 1
          end
      end
      item_rms = (cnt > 0) and (20 * (math.log(math.sqrt(sum_sq / cnt) + 1e-12) / math.log(10))) or -25.0
  end
  item_rms = item_rms or -25.0
  local min_level = config.min_level_db
  local max_level = config.max_level_db

  local env_var = features_arrays.env_var
  if not env_var then
    env_var = {}
    local sum = 0.0
    local sumsq = 0.0
    for i = 1, num_frames do
      local x = air_dbs[i] or 0.0
      sum = sum + x
      sumsq = sumsq + (x * x)
      if i > var_win then
        local xo = air_dbs[i - var_win] or 0.0
        sum = sum - xo
        sumsq = sumsq - (xo * xo)
      end
      
      local n = math.min(i, var_win)
      local mean = sum / n
      local var = (sumsq / n) - (mean * mean)
      if var < 0.0 then var = 0.0 end
      env_var[i] = var
    end
    features_arrays.env_var = env_var
  end

  local function mean_range(arr, s, e, fallback)
    if not arr or s > e then return fallback or 0.0 end
    local sum = 0.0
    local cnt = 0
    for i = s, e do
      local v = arr[i]
      if v ~= nil then
        sum = sum + v
        cnt = cnt + 1
      end
    end
    if cnt == 0 then return fallback or 0.0 end
    return sum / cnt
  end

  local function collect_candidate_segments(levels, env_var, air_dbs, chest_ratios, air_ratios, zcrs, air_concs, env_array)
      local inS = false
      local seg_start_idx = 0
      local gap_run_ms = 0
      local last_valid_idx = 0
      local prev_air_db = nil
      local raw_segments = {}
      local base_depth = 12.0 + (sens_used * 6.0)
      local min_candidate_ms = math.max(25, math.floor((res_cfg.min_seg_ms or 80) * 0.5 + 0.5))

      for i = 1, num_frames do
          local f_level = levels[i]
          local is_breath = false
          
          local pass_level = false
          local current_env = 0
          local rms_corr = math.max(0.0, item_rms - (-25.0))
          if env_array then
              current_env = env_array[i]
              local current_env_for_floor = math.min(-24.0, current_env)
              local dyn_min = math.max(-80.0, current_env_for_floor - base_depth - 18.0 - rms_corr)
              pass_level = (f_level > dyn_min)
          else
              current_env = max_level
              pass_level = (f_level > min_level - rms_corr and f_level < max_level)
          end
          
          if pass_level then
              local f_chest = chest_ratios[i]
              local f_air = air_ratios[i]
              local f_zcr = zcrs[i]
              local f_conc = air_concs[i]
              local f_var = env_var[i]
              local f_ess_ratio = ess_ratios[i] or 0.0
              local f_ess_zcr = ess_zcrs[i] or 0.0
              local z_eff = math.max(f_zcr, f_ess_zcr)
              local chest_gate = profile.chest_gate or (chest_thresh * 1.40)
              if chest_gate < 0.20 then chest_gate = 0.20 end
              if chest_gate > 0.80 then chest_gate = 0.80 end
              
              local core = (f_chest < chest_gate) and
                           (f_air > (air_thresh * 0.75)) and
                           (z_eff > (zcr_thresh * 0.50)) and
                           (f_ess_ratio < 0.60)

              if core then
                  local air_db = air_dbs[i]
                  local delta_air_db = 0.0
                  if prev_air_db then delta_air_db = air_db - prev_air_db end
                  prev_air_db = air_db
                  
                  local breath_like = (f_conc < (conc_thresh + 0.06)) or (f_var > (var_thr * 0.85))
                  if delta_air_db <= (max_air_attack_db + 1.5) and breath_like then
                      local sib_air = profile.sib_air
                      local sib_db = profile.sib_db
                      local sib_level_ok = true
                      if env_array then sib_level_ok = (f_level > (current_env - sib_db)) end
                      local is_sibilant = (f_ess_ratio > 0.58) or
                                          ((f_air > (sib_air - 0.03)) and
                                           (z_eff > zcr_thresh) and
                                           sib_level_ok)
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
                  gap_run_ms = gap_run_ms + res_cfg.hop_ms
                  if gap_run_ms >= res_cfg.max_gap_ms then
                      local dur_ms = (last_valid_idx - seg_start_idx + 1) * res_cfg.hop_ms
                      if dur_ms >= min_candidate_ms then
                          table.insert(raw_segments, { start_idx = seg_start_idx, end_idx = last_valid_idx })
                      end
                      inS = false
                      gap_run_ms = 0
                  end
              end
          end
      end
      
      if inS then
          local dur_ms = (last_valid_idx - seg_start_idx + 1) * res_cfg.hop_ms
          if dur_ms >= min_candidate_ms then
              table.insert(raw_segments, { start_idx = seg_start_idx, end_idx = last_valid_idx })
          end
      end
      
      return raw_segments
  end

  local function validate_segment(seg, env_array)
    local s, e = seg.start_idx, seg.end_idx
    if not s or not e or e < s then
      inc_reject("badseg")
      return nil
    end

    local function reject(key)
      inc_reject(key)
      return nil
    end

    local len = (e - s) + 1
    local dur_ms = len * res_cfg.hop_ms
    local min_inhale_ms = math.max(50, (res_cfg.min_seg_ms or 80) * 0.8)
    if dur_ms < min_inhale_ms then
      if #stats.rejected < max_reject_store then
        stats.rejected[#stats.rejected + 1] = { start_idx = s, end_idx = e, reason = "dur" }
      end
      return reject("dur")
    end

    local sum_level = 0.0
    local sum_air_db = 0.0
    local sum_air_ratio = 0.0
    local sum_chest_ratio = 0.0
    local sum_zcr = 0.0
    local sum_air_conc = 0.0
    local sum_env_var = 0.0
    local sum_chest_zcr = 0.0
    local sum_voiced = 0.0
    local sum_ess_ratio = 0.0
    local sum_ess_zcr = 0.0
    local peak_air_db = -144.0
    local peak_level = -144.0
    local delta_abs_sum = 0.0
    local prev_air_db = nil

    for i = s, e do
      local lvl = levels[i] or -144.0
      local air_db = air_dbs[i] or -144.0
      local air_ratio = air_ratios[i] or 0.0
      local chest_ratio = chest_ratios[i] or 0.0
      local zcr = zcrs[i] or 0.0
      local air_conc = air_concs[i] or 1.0
      local envv = env_var[i] or 0.0
      local chest_zcr = chest_zcrs[i] or 1.0
      local voiced = voiced_scores[i] or 0.0
      local ess_ratio = ess_ratios[i] or 0.0
      local ess_zcr = ess_zcrs[i] or 0.0

      sum_level = sum_level + lvl
      sum_air_db = sum_air_db + air_db
      sum_air_ratio = sum_air_ratio + air_ratio
      sum_chest_ratio = sum_chest_ratio + chest_ratio
      sum_zcr = sum_zcr + zcr
      sum_air_conc = sum_air_conc + air_conc
      sum_env_var = sum_env_var + envv
      sum_chest_zcr = sum_chest_zcr + chest_zcr
      sum_voiced = sum_voiced + voiced
      sum_ess_ratio = sum_ess_ratio + ess_ratio
      sum_ess_zcr = sum_ess_zcr + ess_zcr

      if air_db > peak_air_db then peak_air_db = air_db end
      if lvl > peak_level then peak_level = lvl end
      if prev_air_db ~= nil then
        delta_abs_sum = delta_abs_sum + math.abs(air_db - prev_air_db)
      end
      prev_air_db = air_db
    end

    local inv_len = 1.0 / math.max(1, len)
    local mean_level = sum_level * inv_len
    local mean_air_db = sum_air_db * inv_len
    local mean_air_ratio = sum_air_ratio * inv_len
    local mean_chest_ratio = sum_chest_ratio * inv_len
    local mean_zcr = sum_zcr * inv_len
    local mean_air_conc = sum_air_conc * inv_len
    local mean_env_var = sum_env_var * inv_len
    local mean_chest_zcr = sum_chest_zcr * inv_len
    local mean_voiced = sum_voiced * inv_len
    local mean_ess_ratio = sum_ess_ratio * inv_len
    local mean_ess_zcr = sum_ess_zcr * inv_len
    local mean_abs_air_delta = delta_abs_sum / math.max(1, len - 1)

    local third = math.max(1, math.floor(len / 3))
    local first_mean = mean_range(air_dbs, s, math.min(e, s + third - 1), mean_air_db)
    local last_mean = mean_range(air_dbs, math.max(s, e - third + 1), e, mean_air_db)
    local mid_s = math.max(s, s + third)
    local mid_e = math.min(e, e - third)
    local mid_mean = mean_range(air_dbs, mid_s, mid_e, mean_air_db)

    local ctx_win = math.max(2, math.floor(120 / res_cfg.hop_ms + 0.5))
    local pre_mean = mean_range(levels, math.max(1, s - ctx_win), s - 1, mean_level)
    local post_mean = mean_range(levels, e + 1, math.min(num_frames, e + ctx_win), mean_level)
    local context_valley = math.max(pre_mean, post_mean) - mean_level
    local post_rise = post_mean - mean_level
    local pre_rise = pre_mean - mean_level
    local is_silent_ctx = ((pre_mean < -55.0) and (post_mean < -55.0)) or
                          ((pre_mean < -48.0) and (post_mean < -48.0) and (mean_level > pre_mean + 3.0) and (mean_level > post_mean + 3.0))
    local post_attack_score = is_silent_ctx and 1.0 or clamp01((post_rise + 1.0) / 8.0)
    local pre_gap_score = is_silent_ctx and 1.0 or clamp01((pre_rise + 0.5) / 7.0)
    local valley_score = is_silent_ctx and 1.0 or clamp01((context_valley + 0.5) / 8.0)

    local vr_chest_min = profile.vr_chest_min or 0.22
    local vr_chest_max = profile.vr_chest_max or 0.42
    
    local file_voiced_baseline = file_stats.noise_voiced or 0.0
    local voiced_sub = math.min(0.20, file_voiced_baseline * noise_factor)
    local adjusted_voiced = math.max(0, mean_voiced - voiced_sub)
    
    local voiced_reject = math.max(
      adjusted_voiced,
      clamp01((mean_chest_ratio - vr_chest_min) / (vr_chest_max - vr_chest_min)) *
        clamp01((0.14 - mean_chest_zcr) / 0.08) *
        clamp01((0.88 - mean_air_ratio) / 0.30)
    )
    local spikiness = peak_air_db - mean_air_db
    local sibilance_score = clamp01((mean_air_ratio - (profile.sib_air - 0.08)) / 0.20) *
      clamp01((mean_zcr - (zcr_thresh + 0.02)) / 0.10) *
      clamp01((spikiness - 4.0) / 8.0)
    local esslike_score = clamp01((mean_ess_ratio - 0.16) / 0.20) *
      clamp01((mean_ess_zcr - 0.12) / 0.12) *
      clamp01((spikiness - 2.0) / 10.0)
    local smoothness = 1.0 - clamp01((mean_abs_air_delta - 2.5) / 5.5)
    local context_score = (0.55 * post_attack_score) + (0.25 * pre_gap_score) + (0.20 * valley_score)

    local duration_score
    if dur_ms <= 200 then
      duration_score = clamp01((dur_ms - min_inhale_ms) / 120.0)
    elseif dur_ms <= 350 then
      duration_score = 1.0 - (0.20 * clamp01((dur_ms - 200.0) / 150.0))
    elseif dur_ms <= 900 then
      duration_score = 1.0 - (0.35 * clamp01((dur_ms - 350.0) / 550.0))
    else
      duration_score = 0.35
    end

    local shape_score = clamp01((mid_mean - first_mean + 3.0) / 8.0) * 0.5 +
      clamp01((mid_mean - last_mean + 3.0) / 8.0) * 0.5

    local score = 0.0
    score = score + 1.50 * clamp01((mean_air_ratio - air_thresh) / 0.22)
    score = score + 1.20 * clamp01((mean_zcr - zcr_thresh) / 0.08)
    score = score + 0.70 * clamp01((mean_env_var - (var_thr * 0.65)) / math.max(0.25, var_thr * 0.90))
    score = score + 0.80 * clamp01(((conc_thresh + 0.05) - mean_air_conc) / 0.20)
    score = score + 0.50 * context_score
    score = score + 0.50 * smoothness
    score = score + 0.45 * duration_score
    score = score + 0.35 * shape_score
    score = score - 2.00 * voiced_reject
    score = score - 1.25 * sibilance_score
    score = score - 1.35 * esslike_score
    score = score - 0.70 * clamp01((spikiness - 7.0) / 7.0)
    score = score - 0.60 * clamp01((mean_chest_ratio - (chest_thresh * 0.85)) / 0.18)

    local file_stats_local = compute_file_statistics and compute_file_statistics(features_arrays) or {level_p90=-15.0}
    local word_level_dbg = file_stats_local.level_p90 or -15.0
    
    local rej_dbg = string.format(
      "BREATH_DBG | prof:%d | dur_ms:%d | lvl:%.1f | p90:%.1f | air:%.3f | chest:%.3f | zcr:%.3f | ess:%.3f | voiced:%.3f | conc:%.3f | post:%.2f | pre:%.2f | ctx:%.2f | v_rej:%.2f | esslike:%.2f | sib:%.2f | shape:%.2f | score:%.2f",
      profile_id, dur_ms, mean_level, word_level_dbg, mean_air_ratio, mean_chest_ratio, mean_zcr, mean_ess_ratio, mean_voiced, mean_air_conc, post_attack_score, pre_gap_score, context_score, voiced_reject, esslike_score, sibilance_score, shape_score, score
    )

    local function store_reject(key)
      if #stats.rejected >= max_reject_store then return end
      stats.rejected[#stats.rejected + 1] = {
        start_idx = s,
        end_idx = e,
        reason = key,
        score = score,
        air = mean_air_ratio,
        chest = mean_chest_ratio,
        zcr = mean_zcr,
        ess = mean_ess_ratio,
        voiced = mean_voiced,
        v_rej = voiced_reject,
        post = post_attack_score,
        pre = pre_gap_score,
        ctx = context_score
      }
    end

    local zcr_veto_limit = 0.030
    if profile_id == 1 or profile_id == 4 then zcr_veto_limit = 0.065 end
    if noise_factor > 0 and file_stats.noise_zcr then
        zcr_veto_limit = math.min(zcr_veto_limit, file_stats.noise_zcr * 0.5)
    end
    if mean_zcr < zcr_veto_limit then
        store_reject("voiced")
        debug_reject("voiced", rej_dbg .. " | rej:voiced (zcr)")
        return reject("voiced")
    end

    local ess_ratio_limit = 0.58
    if profile_id == 1 or profile_id == 4 then ess_ratio_limit = 0.65 end
    if noise_factor > 0 and file_stats.noise_air then
        ess_ratio_limit = math.max(ess_ratio_limit, file_stats.noise_air + 0.15)
    end
    if score > 1.8 then
        ess_ratio_limit = ess_ratio_limit + (score - 1.8) * 0.15
    end
    
    if mean_ess_ratio > ess_ratio_limit and mean_zcr > 0.11 then
        store_reject("ess")
        debug_reject("ess", rej_dbg .. " | rej:ess (ratio)")
        return reject("ess")
    end

    local ctx_dur_limit = 90
    local ctx_score_limit = 0.05
    if profile_id == 5 and dur_ms < ctx_dur_limit and context_score < ctx_score_limit then
        store_reject("rap_ctx")
        debug_reject("rap_ctx", rej_dbg .. " | rej:rap_ctx")
        return reject("rap_ctx")
    end
    
    if profile_id == 5 and shape_score < 0.40 then
        -- store_reject("shape")
        -- debug_reject("shape", rej_dbg .. " | rej:shape (not a sausage)")
        -- return reject("shape")
    end
    
    if profile_id == 5 then
        local word_level = file_stats.level_p90 or -15.0
        
        if mean_level > word_level - 9.0 then
            store_reject("rap_loud")
            debug_reject("rap_loud", rej_dbg .. " | rej:rap_loud (too loud, probably a word)")
            return reject("rap_loud")
        end
    end

    local ess_ratio_limit = 0.58
    if mean_ess_ratio > ess_ratio_limit and mean_zcr > 0.11 then
        store_reject("ess")
        debug_reject("ess", rej_dbg .. " | rej:ess (ratio)")
        return reject("ess")
    end

    local v_rej_limit = (profile_id == 1 or profile_id == 4) and 0.45 or 0.38
    if is_silent_ctx then
      v_rej_limit = (profile_id == 1 or profile_id == 4) and 0.42 or 0.35
    end
    if profile_id == 5 then v_rej_limit = 0.30 end -- Stricter limit for Rap

    if score > 1.8 then
        v_rej_limit = v_rej_limit + (score - 1.8) * 0.10
    end
    
    if voiced_reject > v_rej_limit then store_reject("voiced"); debug_reject("voiced", rej_dbg .. " | rej:voiced"); return reject("voiced") end

    local conc_limit = (profile_id == 1 or profile_id == 4) and 0.80 or 0.76
    if mean_air_conc > conc_limit then store_reject("conc"); debug_reject("conc", rej_dbg .. " | rej:conc"); return reject("conc") end

    if sibilance_score > 0.55 and dur_ms < 260 then store_reject("sib"); debug_reject("sib", rej_dbg .. " | rej:sib"); return reject("sib") end
    
    local esslike_limit = (profile_id == 1 or profile_id == 4) and 0.58 or 0.48
    if esslike_score > esslike_limit and dur_ms < 360 then store_reject("ess"); debug_reject("ess", rej_dbg .. " | rej:ess"); return reject("ess") end
    
    if dur_ms < math.max(config.min_seg_ms, 50) and spikiness > 9.0 then return reject("spike") end
    if mean_chest_ratio > math.min(0.70, chest_thresh + 0.12) and mean_voiced > 0.18 then return reject("chest") end
    
    if profile_id ~= 5 and dur_ms < 220 and post_attack_score < 0.18 and pre_gap_score < 0.18 then store_reject("ctx"); debug_reject("ctx", rej_dbg .. " | rej:ctx"); return reject("ctx") end
    
    if dur_ms > 400 and post_attack_score < 0.15 and pre_gap_score < 0.15 then
        store_reject("ctx")
        debug_reject("ctx", rej_dbg .. " | rej:ctx (long glued bleed/word)")
        return reject("ctx")
    end

    local score_thr = 1.55 - (sens * 0.40)
    if profile_id == 5 then
        score_thr = score_thr - 0.20 -- Rap breaths have lower absolute scores
    end
    
    if profile_id ~= 5 and dur_ms > 350 and pre_gap_score < 0.30 then
        score_thr = math.max(score_thr + 0.50, 2.50)
    end
    
    local fast_inhale = (dur_ms <= 180) and (shape_score >= 0.45) and (post_attack_score >= 0.28) and (esslike_score < 0.22)
    local fast_thr = 1.35 - (sens * 0.30)
    if fast_inhale then score_thr = fast_thr end
    if score < score_thr then store_reject("score"); debug_reject("score", rej_dbg .. " | rej:score"); return reject("score") end

    Logger:debug(rej_dbg .. " | status:OK")

    return {
      start_idx = s,
      end_idx = e,
      score = score,
      voiced_reject = voiced_reject,
      sibilance_score = sibilance_score,
      esslike_score = esslike_score
    }
  end

  local local_env = nil
  if config.level_auto then
    local win_frames = math.floor(3000 / config.hop_ms)
    local half_win = math.floor(win_frames / 2)
    local_env = features_arrays.local_env
    
    if not local_env then
        local_env = {}
        local last_valid_env = item_rms > -70 and item_rms or -35.0 
        local step = 5
        local sample_pos = {}
        local sample_val = {}
        local sample_valid = {}
        for k = 1, num_frames, step do
          local l = levels[k]
          local idx = #sample_pos + 1
          sample_pos[idx] = k
          sample_val[idx] = l
          sample_valid[idx] = (l ~= nil) and (l > -68.0)
        end

        local num_samples = #sample_pos
        local left = 1
        local right = 0
        local sum = 0.0
        local cnt = 0

        for i = 1, num_frames do
          local start_i = i - half_win
          local end_i = i + half_win
          if start_i < 1 then start_i = 1 end
          if end_i > num_frames then end_i = num_frames end

          while (right < num_samples) and (sample_pos[right + 1] <= end_i) do
            right = right + 1
            if sample_valid[right] then
              sum = sum + sample_val[right]
              cnt = cnt + 1
            end
          end

          while (left <= right) and (sample_pos[left] < start_i) do
            if sample_valid[left] then
              sum = sum - sample_val[left]
              cnt = cnt - 1
            end
            left = left + 1
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
    
    raw_segments = collect_candidate_segments(levels, env_var, air_dbs, chest_ratios, air_ratios, zcrs, air_concs, local_env)
  else
    -- Manual mode
    raw_segments = collect_candidate_segments(levels, env_var, air_dbs, chest_ratios, air_ratios, zcrs, air_concs, nil)
  end

  local expanded_segments = {}
  local extend_margin_db = 18.0 - 4.0 * sens
  if extend_margin_db < 10.0 then extend_margin_db = 10.0 end

  for _, seg in ipairs(raw_segments) do
    local s, e = seg.start_idx, seg.end_idx
    local sum_lvl, cnt = 0, 0
    for i=s, e do sum_lvl = sum_lvl + levels[i]; cnt = cnt + 1 end
    local seg_mean = sum_lvl / math.max(1, cnt)

    local new_s, new_e = s, e
    
    -- Expand left
    local i = s - 1
    local voiced_consec = 0
    local rms_corr = math.max(0.0, item_rms - (-25.0))
    while i >= 1 do
        local lvl = levels[i]
        if not lvl then break end
        local env = local_env and local_env[i] or -50.0
        local expansion_floor = math.max(-65.0, env - 18.0 - rms_corr)
        
        if lvl < expansion_floor then break end
        
        if voiced_scores[i] and voiced_scores[i] > 0.42 then
            voiced_consec = voiced_consec + 1
            if voiced_consec >= 2 then break end
        else
            voiced_consec = 0
        end
        
        if air_concs[i] and air_concs[i] > 0.82 then break end
        if chest_ratios[i] > (chest_thresh * 1.45) and lvl > -48.0 then break end
        
        new_s = i
        i = i - 1
    end
    
    -- Expand right
    i = e + 1
    voiced_consec = 0
    while i <= num_frames do
        local lvl = levels[i]
        if not lvl then break end
        local env = local_env and local_env[i] or -50.0
        local expansion_floor = math.max(-65.0, env - 18.0 - rms_corr)
        
        if lvl < expansion_floor then break end
        
        if voiced_scores[i] and voiced_scores[i] > 0.42 then
            voiced_consec = voiced_consec + 1
            if voiced_consec >= 2 then break end
        else
            voiced_consec = 0
        end
        
        if air_concs[i] and air_concs[i] > 0.82 then break end
        if chest_ratios[i] > (chest_thresh * 1.45) and lvl > -48.0 then break end
        
        new_e = i
        i = i + 1
    end
    
    table.insert(expanded_segments, { start_idx = new_s, end_idx = new_e })
  end

  local validated_segments = {}
  for _, seg in ipairs(expanded_segments) do
    local valid = validate_segment(seg, local_env)
    if valid then
      validated_segments[#validated_segments + 1] = valid
    end
  end

  for _, seg in ipairs(validated_segments) do
    table.insert(segments, { start_idx = seg.start_idx, end_idx = seg.end_idx, score = seg.score })
  end

  table.sort(segments, function(a, b) return a.start_idx < b.start_idx end)
  local merged_segments = {}
  local merge_gap_frames = math.max(1, math.floor((config.max_gap_ms or 40) / math.max(1, config.hop_ms) + 0.5))
  for _, seg in ipairs(segments) do
    if #merged_segments == 0 then
      merged_segments[#merged_segments + 1] = seg
    else
      local last = merged_segments[#merged_segments]
      if seg.start_idx <= (last.end_idx + merge_gap_frames) then
        if seg.end_idx > last.end_idx then last.end_idx = seg.end_idx end
        if (seg.score or 0.0) > (last.score or 0.0) then
          last.score = seg.score
        end
      else
        merged_segments[#merged_segments + 1] = seg
      end
    end
  end

  local refractory_frames = math.floor(250 / config.hop_ms + 0.5)
  local final_segments = {}
  
  for _, seg in ipairs(merged_segments) do
      if #final_segments == 0 then
          final_segments[#final_segments + 1] = seg
      else
          local last_seg = final_segments[#final_segments]
          if seg.start_idx >= last_seg.end_idx + refractory_frames then
              final_segments[#final_segments + 1] = seg
          else
              if (seg.score or 0) > (last_seg.score or 0) then
                  final_segments[#final_segments] = seg
                  inc_reject("refractory")
              else
                  inc_reject("refractory")
              end
          end
      end
  end
  merged_segments = final_segments

  Logger:debug(string.format(
    "BREATH_STATS | prof:%d | frames:%d | cand:%d | valid:%d | out:%d | thr_air:%.3f | thr_zcr:%.3f | thr_chest:%.3f | rej_bad:%d | rej_dur:%d | rej_voiced:%d | rej_sib:%d | rej_ess:%d | rej_conc:%d | rej_ctx:%d | rej_spike:%d | rej_chest:%d | rej_score:%d",
    profile_id,
    num_frames,
    #raw_segments,
    #validated_segments,
    #merged_segments,
    air_thresh,
    zcr_thresh,
    chest_thresh,
    reject_counts.badseg or 0,
    reject_counts.dur or 0,
    reject_counts.voiced or 0,
    reject_counts.sib or 0,
    reject_counts.ess or 0,
    reject_counts.conc or 0,
    reject_counts.ctx or 0,
    reject_counts.spike or 0,
    reject_counts.chest or 0,
    reject_counts.score or 0
  ))

  return merged_segments, stats
end

return Hunter
