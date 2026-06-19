-- @noindex
-- @description Floop Hunter Framework - Ess hunter
-- @author Floop-s
-- @license GPL-3.0
local DSP = require("floop_dsp")
local Logger = require("floop_logger")

local Hunter = {}
Hunter.name = "Ess Hunter"

local function clamp01(x)
  if x <= 0.0 then return 0.0 end
  if x >= 1.0 then return 1.0 end
  return x
end

local function calc_entropy_and_flatness(vals)
  local sum = 0.0
  local log_sum = 0.0
  local count = #vals
  if count == 0 then return 0.0, 0.0 end

  for i = 1, count do
    local v = math.max(vals[i] or 0.0, 1e-12)
    sum = sum + v
    log_sum = log_sum + math.log(v)
  end

  local entropy = 0.0
  for i = 1, count do
    local p = math.max(vals[i] or 0.0, 1e-12) / math.max(sum, 1e-12)
    entropy = entropy - (p * math.log(p))
  end
  entropy = entropy / math.log(count)

  local geo = math.exp(log_sum / count)
  local arith = sum / count
  local flatness = geo / math.max(arith, 1e-12)
  return entropy, flatness
end

-- =========================================================================
-- MATRIX DEI PROFILI ACUSTICI (CENTRALIZZATA)
-- =========================================================================
Hunter.Profiles = {
  [1] = { -- FEMALE
    name = "Female",
    hp_freq = 4000,
    c1 = 5500, c2 = 7500, c3 = 9500,
    bias_offset = 0.0,
    zcr_offset = 0.0,
    conc_offset = 0.0,
    tilt_offset = 0.0,
    chest_guard_limit = 0.50
  },
  [2] = { -- MALE
    name = "Male",
    hp_freq = 3000,
    c1 = 4500, c2 = 6500, c3 = 8500,
    bias_offset = 0.0,
    zcr_offset = 0.0,
    conc_offset = 0.0,
    tilt_offset = 0.0,
    chest_guard_limit = 0.55
  },
  [3] = {
    name = "Spoken Male",
    hp_freq = 3000,
    c1 = 4500, c2 = 6500, c3 = 8500,
    bias_offset = -0.05,
    zcr_offset = 0.0,
    conc_offset = 0.0,
    tilt_offset = 0.0,
    chest_guard_limit = 0.60
  },
  [4] = {
    name = "Spoken Female",
    hp_freq = 3000,
    c1 = 4500, c2 = 6500, c3 = 8500,
    bias_offset = -0.05,
    zcr_offset = 0.0,
    conc_offset = 0.0,
    tilt_offset = 0.0,
    chest_guard_limit = 0.60
  },
  [5] = { -- RAP
    name = "Rap",
    hp_freq = 3000,
    c1 = 4500, c2 = 6500, c3 = 8500,
    bias_offset = 0.08,
    zcr_offset = 0.06,
    conc_offset = 0.10,
    tilt_offset = 0.18,
    chest_guard_limit = 0.58
  }
}

Hunter.default_config = {
   source_profile = 2, -- Default su Male
   window_ms = 12,
   hop_ms = 6,
   min_level_db = -45.0,
   zcr_thresh = 0.20,
   delta_on = 0.08,
   delta_off = 0.05,
   min_seg_ms = 25,
   max_gap_ms = 18,
   reduction_db = 4.0,
   pre_ramp_ms = 8,
   post_ramp_ms = 12,
   overwrite = true,
   use_prefx = false,
   sensitivity = 0.0
}

function Hunter.init(sr, config)
   local profile_id = config.source_profile or 2
   local profile = Hunter.Profiles[profile_id] or Hunter.Profiles[2]
   
   Logger:debug(string.format("ESS_INIT | Profilo:%s | sr:%d", profile.name, sr))

   local hp_freq = profile.hp_freq
   Logger:debug(string.format("ESS_CFG | ess_hp:%d", hp_freq))

   local num_hops = math.max(1, math.floor(config.window_ms / config.hop_ms))
   local hist = { wb = {}, ess = {}, chest = {}, zcr = {}, b1 = {}, b2 = {}, b3 = {}, b4 = {}, b5 = {}, b6 = {} }
   for i = 1, num_hops do
      hist.wb[i] = 0.0
      hist.ess[i] = 0.0
      hist.chest[i] = 0.0
      hist.zcr[i] = 0
      hist.b1[i] = 0.0
      hist.b2[i] = 0.0
      hist.b3[i] = 0.0
      hist.b4[i] = 0.0
      hist.b5[i] = 0.0
      hist.b6[i] = 0.0
   end

   local c1, c2, c3 = profile.c1, profile.c2, profile.c3
   local b4f = math.min(c1 + 1000, sr * 0.45)
   local b5f = math.min(c2 + 1000, sr * 0.45)
   local b6f = math.min(c3 + 1000, sr * 0.45)

   return {
      sr = sr,
      hp_ess1 = DSP.biquad_new(DSP.rbj_highpass(hp_freq, 0.707, sr)),
      hp_ess2 = DSP.biquad_new(DSP.rbj_highpass(hp_freq, 0.707, sr)),
      lp_chest = DSP.biquad_new(DSP.rbj_lowpass((profile_id == 1 or profile_id == 4) and 750 or 400, 0.707, sr)), -- Vowel/plosive guard.
      bp1 = DSP.biquad_new(DSP.rbj_bandpass(c1, 2.0, sr)),
      bp2 = DSP.biquad_new(DSP.rbj_bandpass(c2, 2.0, sr)),
      bp3 = DSP.biquad_new(DSP.rbj_bandpass(c3, 2.0, sr)),
      bp4 = DSP.biquad_new(DSP.rbj_bandpass(b4f, 2.0, sr)),
      bp5 = DSP.biquad_new(DSP.rbj_bandpass(b5f, 2.0, sr)),
      bp6 = DSP.biquad_new(DSP.rbj_bandpass(b6f, 2.0, sr)),
      r_prev1 = 0.0,
      r_prev2 = 0.0,
      num_hops = num_hops,
      hist = hist,
      hist_idx = 1,
      prev_sign = 0
   }
end

function Hunter.process_window(buf, ch, state, result_buf)
   local H_samples = (#buf) / ch
   local hop_wb, hop_ess, hop_chest, hop_zcr = 0.0, 0.0, 0.0, 0
   local hop_b1, hop_b2, hop_b3 = 0.0, 0.0, 0.0
   local hop_b4, hop_b5, hop_b6 = 0.0, 0.0, 0.0
   local prev_sign = state.prev_sign

   for i = 0, H_samples - 1 do
      local mono = 0.0
      for c = 0, ch - 1 do mono = mono + buf[(i * ch) + c + 1] end
      mono = mono / ch
      hop_wb = hop_wb + mono * mono

      local chest = DSP.biquad_process(state.lp_chest, mono)
      hop_chest = hop_chest + chest * chest

      local ess_stage1 = DSP.biquad_process(state.hp_ess1, mono)
      local ess = DSP.biquad_process(state.hp_ess2, ess_stage1)
      hop_ess = hop_ess + ess * ess

      local sign = (ess >= 0) and 1 or -1
      if prev_sign ~= 0 and sign ~= prev_sign then hop_zcr = hop_zcr + 1 end
      prev_sign = sign

      local b1 = DSP.biquad_process(state.bp1, mono)
      local b2 = DSP.biquad_process(state.bp2, mono)
      local b3 = DSP.biquad_process(state.bp3, mono)
      local b4 = DSP.biquad_process(state.bp4, mono)
      local b5 = DSP.biquad_process(state.bp5, mono)
      local b6 = DSP.biquad_process(state.bp6, mono)
      hop_b1 = hop_b1 + b1 * b1
      hop_b2 = hop_b2 + b2 * b2
      hop_b3 = hop_b3 + b3 * b3
      hop_b4 = hop_b4 + b4 * b4
      hop_b5 = hop_b5 + b5 * b5
      hop_b6 = hop_b6 + b6 * b6
   end

   state.prev_sign = prev_sign

   local idx = state.hist_idx
   state.hist.wb[idx] = hop_wb
   state.hist.ess[idx] = hop_ess
   state.hist.chest[idx] = hop_chest
   state.hist.zcr[idx] = hop_zcr
   state.hist.b1[idx] = hop_b1
   state.hist.b2[idx] = hop_b2
   state.hist.b3[idx] = hop_b3
   state.hist.b4[idx] = hop_b4
   state.hist.b5[idx] = hop_b5
   state.hist.b6[idx] = hop_b6

   state.hist_idx = idx + 1
   if state.hist_idx > state.num_hops then state.hist_idx = 1 end

   local sum_sq_wb, sum_sq_ess, sum_sq_chest, total_zcr = 0.0, 0.0, 0.0, 0
   local sum_b1, sum_b2, sum_b3 = 0.0, 0.0, 0.0
   local sum_b4, sum_b5, sum_b6 = 0.0, 0.0, 0.0
   for i = 1, state.num_hops do
      sum_sq_wb = sum_sq_wb + state.hist.wb[i]
      sum_sq_ess = sum_sq_ess + state.hist.ess[i]
      sum_sq_chest = sum_sq_chest + state.hist.chest[i]
      total_zcr = total_zcr + state.hist.zcr[i]
      sum_b1 = sum_b1 + state.hist.b1[i]
      sum_b2 = sum_b2 + state.hist.b2[i]
      sum_b3 = sum_b3 + state.hist.b3[i]
      sum_b4 = sum_b4 + state.hist.b4[i]
      sum_b5 = sum_b5 + state.hist.b5[i]
      sum_b6 = sum_b6 + state.hist.b6[i]
   end

   local N = H_samples * state.num_hops

   local rms_wb = math.sqrt(sum_sq_wb / math.max(1, N))
   local rms_ess = math.sqrt(sum_sq_ess / math.max(1, N))
   local rms_chest = math.sqrt(sum_sq_chest / math.max(1, N))

   local ratio = (rms_ess + 1e-12) / (rms_wb + 1e-12)
   local zcr_norm = total_zcr / math.max(1, (N - 1))
   local level_db = DSP.amp_to_db(rms_wb)
   local chest_ratio = (rms_chest + 1e-12) / (rms_wb + 1e-12)
   local band_vals = { sum_b1, sum_b2, sum_b3, sum_b4, sum_b5, sum_b6 }
   local sum_b = sum_b1 + sum_b2 + sum_b3 + sum_b4 + sum_b5 + sum_b6
   local max_b = 0.0
   for i = 1, #band_vals do
      if band_vals[i] > max_b then max_b = band_vals[i] end
   end
   local hf_conc = max_b / math.max(1e-12, sum_b)
   local hf_tilt = (sum_b4 + sum_b5 + sum_b6) / math.max(1e-12, (sum_b1 + sum_b2 + sum_b3))
   local hf_entropy, hf_flatness = calc_entropy_and_flatness(band_vals)

   if result_buf then
      result_buf.ratio = ratio
      result_buf.zcr = zcr_norm
      result_buf.level = level_db
      result_buf.chest_ratio = chest_ratio
      result_buf.hf_conc = hf_conc
      result_buf.hf_tilt = hf_tilt
      result_buf.hf_entropy = hf_entropy
      result_buf.hf_flatness = hf_flatness
      return result_buf
   else
      return {
         ratio = ratio,
         zcr = zcr_norm,
         level = level_db,
         chest_ratio = chest_ratio,
         hf_conc = hf_conc,
         hf_tilt = hf_tilt,
         hf_entropy = hf_entropy,
         hf_flatness = hf_flatness
      }
   end
end

function Hunter.detect_segments(features, config)
   local levels = features.level
   local ratios = features.ratio
   local zcrs = features.zcr
   local chest_ratios = features.chest_ratio
   local hf_concs = features.hf_conc
   local hf_tilts = features.hf_tilt
   local hf_entropies = features.hf_entropy
   local hf_flatnesses = features.hf_flatness

   if not levels or not ratios or not zcrs or not chest_ratios or not hf_concs or not hf_tilts then return {} end
   if not hf_entropies then hf_entropies = {} end
   if not hf_flatnesses then hf_flatnesses = {} end

   local med_lvl = features.med_lvl
   if not med_lvl then
      med_lvl = DSP.median(levels)
      features.med_lvl = med_lvl
   end

   local item_rms = config.item_rms_db or -20.0
   local min_level_base = config.min_level_db

   if item_rms < -25.0 then
      min_level_base = math.max(-60.0, min_level_base + (item_rms - (-20.0)))
   end

   local min_level_use = math.max(min_level_base, (med_lvl or min_level_base) - 12.0)

   local raw_p75 = features.raw_p75
   if not raw_p75 then
      local valid_ratios = {}
      local filter_level = math.max(-60.0, med_lvl - 12.0)
      for i = 1, #levels do
         if levels[i] > filter_level then
            valid_ratios[#valid_ratios + 1] = ratios[i]
         end
      end
      if #valid_ratios == 0 then valid_ratios = ratios end
      raw_p75 = DSP.percentile(valid_ratios, 0.75)
      features.raw_p75 = raw_p75
   end

   local med_ratio = math.min(raw_p75, 0.75)
   local sens = config.sensitivity or 0.0
   
   local profile_id = config.source_profile or 2
   local profile = Hunter.Profiles[profile_id] or Hunter.Profiles[2]
   
   local bias = (sens * -0.15) + profile.bias_offset

   local thr_on = math.max(0.15, med_ratio + config.delta_on + bias)
   local thr_off = math.max(0.10, med_ratio + config.delta_off + bias)
   
   local conc_thr = 0.52 - (sens * 0.08) + profile.conc_offset
   if conc_thr < 0.38 then conc_thr = 0.38 end
   if conc_thr > 0.65 then conc_thr = 0.65 end
   
   local tilt_thr = 1.20 - (sens * 0.15) + profile.tilt_offset
   if tilt_thr < 0.90 then tilt_thr = 0.90 end
   if tilt_thr > 1.60 then tilt_thr = 1.60 end

   local zcr_thr = config.zcr_thresh + profile.zcr_offset
   if zcr_thr < 0.05 then zcr_thr = 0.05 end
   if zcr_thr > 0.45 then zcr_thr = 0.45 end

   local segments = {}
   local candidates = {}
   local rejected = {}
   local inS = false
   local seg_start_idx = 0
   local gap_run_ms = 0
   local r_prev1, r_prev2 = 0.0, 0.0

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

   local function is_false_positive(start_idx, end_idx)
      local len = end_idx - start_idx
      local duration_ms = len * config.hop_ms
      local sum_ratio, zcr_sum, chest_ratio_sum, sum_conc, sum_tilt, sum_entropy, sum_flat = 0, 0, 0, 0, 0, 0, 0

      for k = start_idx, end_idx do
         sum_ratio = sum_ratio + (ratios[k] or 0)
         zcr_sum = zcr_sum + (zcrs[k] or 0)
         chest_ratio_sum = chest_ratio_sum + (chest_ratios[k] or 0)
         sum_conc = sum_conc + (hf_concs[k] or 0)
         sum_tilt = sum_tilt + (hf_tilts[k] or 0)
         sum_entropy = sum_entropy + (hf_entropies[k] or 0)
         sum_flat = sum_flat + (hf_flatnesses[k] or 0)
      end

      local count = math.max(1, len + 1)
      local avg_ratio = sum_ratio / count
      local avg_zcr = zcr_sum / count
      local avg_chest_ratio = chest_ratio_sum / count
      local avg_conc = sum_conc / count
      local avg_tilt = sum_tilt / count
      local avg_entropy = sum_entropy / count
      local avg_flat = sum_flat / count

      -- Plosive/Vowel Guard
      local chest_guard_limit = profile.chest_guard_limit

      if avg_chest_ratio > chest_guard_limit then return true end
      if avg_zcr < 0.05 then return true end -- Too tonal
      if avg_entropy < 0.42 and avg_flat < 0.45 then return true end
      if avg_conc < conc_thr and avg_tilt < tilt_thr and avg_ratio < (thr_on * 1.1) and duration_ms > 80 then return true end

      return false
   end

   local function validate_segment(seg)
      local s, e = seg.start_idx, seg.end_idx
      local len = (e - s) + 1
      local dur_ms = len * config.hop_ms
      if dur_ms < config.min_seg_ms then return nil end

      local mean_ratio = mean_range(ratios, s, e, 0.0)
      local mean_zcr = mean_range(zcrs, s, e, 0.0)
      local mean_chest = mean_range(chest_ratios, s, e, 0.0)
      local mean_conc = mean_range(hf_concs, s, e, 0.0)
      local mean_tilt = mean_range(hf_tilts, s, e, 0.0)
      local mean_entropy = mean_range(hf_entropies, s, e, 0.0)
      local mean_flat = mean_range(hf_flatnesses, s, e, 0.0)
      local mean_level = mean_range(levels, s, e, -144.0)
      local peak_ratio = 0.0
      local peak_level = -144.0
      local ratio_delta_sum = 0.0
      local prev_ratio = nil

      for i = s, e do
         local rr = ratios[i] or 0.0
         local lvl = levels[i] or -144.0
         if rr > peak_ratio then peak_ratio = rr end
         if lvl > peak_level then peak_level = lvl end
         if prev_ratio ~= nil then
            ratio_delta_sum = ratio_delta_sum + math.abs(rr - prev_ratio)
         end
         prev_ratio = rr
      end

      local third = math.max(1, math.floor(len / 3))
      local first_mean = mean_range(ratios, s, math.min(e, s + third - 1), mean_ratio)
      local last_mean = mean_range(ratios, math.max(s, e - third + 1), e, mean_ratio)
      local mid_s = math.max(s, s + third)
      local mid_e = math.min(e, e - third)
      local mid_mean = mean_range(ratios, mid_s, mid_e, mean_ratio)
      local spikiness = peak_ratio - mean_ratio
      local smoothness = 1.0 - clamp01((ratio_delta_sum / math.max(1, len - 1) - 0.05) / 0.20)
      local shape_score = clamp01((mid_mean - first_mean + 0.04) / 0.14) * 0.5 +
         clamp01((mid_mean - last_mean + 0.04) / 0.14) * 0.5

      local score = 0.0
      score = score + 1.30 * clamp01((mean_ratio - thr_on) / 0.18)
      score = score + 0.90 * clamp01((mean_zcr - zcr_thr) / 0.10)
      score = score + 0.95 * clamp01((mean_conc - (conc_thr - 0.03)) / 0.18)
      score = score + 0.70 * clamp01((mean_tilt - (tilt_thr - 0.10)) / 0.50)
      score = score + 0.75 * clamp01((mean_entropy - 0.48) / 0.28)
      score = score + 0.45 * clamp01((0.55 - mean_flat) / 0.30)
      score = score + 0.30 * smoothness
      score = score + 0.25 * shape_score
      score = score - 1.00 * clamp01((mean_chest - (profile.chest_guard_limit - 0.08)) / 0.18)
      score = score - 0.80 * clamp01((0.42 - mean_entropy) / 0.18)
      score = score - 0.55 * clamp01((mean_flat - 0.62) / 0.20)
      score = score - 0.45 * clamp01((spikiness - 0.22) / 0.30)

      local msg = string.format("ESS_DBG | prof:%d | dur_ms:%d | lvl:%.1f | ratio:%.3f | zcr:%.3f | chest:%.3f | conc:%.3f | tilt:%.3f | ent:%.3f | flat:%.3f | score:%.2f",
         profile_id, dur_ms, mean_level, mean_ratio, mean_zcr, mean_chest, mean_conc, mean_tilt, mean_entropy, mean_flat, score)

      if mean_chest > profile.chest_guard_limit then 
         Logger:debug(msg .. " | rej:chest")
         return nil, "chest" 
      end
      if mean_zcr < math.max(0.05, zcr_thr * 0.85) then 
         Logger:debug(msg .. " | rej:zcr")
         return nil, "zcr" 
      end
      if mean_entropy < 0.38 and mean_flat < 0.42 then 
         Logger:debug(msg .. " | rej:tonal")
         return nil, "tonal" 
      end
      if dur_ms < 18 and peak_ratio < (thr_on * 1.20) then 
         Logger:debug(msg .. " | rej:dur")
         return nil, "dur" 
      end
      if score < 1.45 then 
         Logger:debug(msg .. " | rej:score")
         return nil, "score" 
      end

      Logger:debug(msg .. " | status:OK")

      return {
         start_idx = s,
         end_idx = e,
         score = score
      }, nil
   end

   for i = 1, #levels do
      local ratio = ratios[i]
      local zcr = zcrs[i]
      local lvl = levels[i]
      local conc = hf_concs[i]
      local tilt = hf_tilts[i]

      local r_s = ratio
      if i > 2 then
         r_s = 0.6 * ratio + 0.3 * r_prev1 + 0.1 * r_prev2
      elseif i > 1 then
         r_s = 0.75 * ratio + 0.25 * r_prev1
      end
      r_prev2 = r_prev1
      r_prev1 = ratio

      local is_loud = (lvl > min_level_use)
      local is_sibilant_ratio = (r_s >= thr_on)
      local is_noisy = (zcr >= zcr_thr)
      local entropy = hf_entropies[i] or 0.0
      local flatness = hf_flatnesses[i] or 0.0
      local is_concentrated = (conc >= (conc_thr * 0.92)) or
         (tilt >= (tilt_thr * 0.92)) or
         (entropy >= 0.52) or
         (r_s >= (thr_on * 1.20))

      local pass_on = is_loud and is_sibilant_ratio and is_noisy and (is_concentrated or (lvl > (min_level_use + 6.0)))
      local pass_off = false

      if inS then
         local is_sustained_ratio = (r_s > thr_off)
         local is_sustained_level = (lvl > min_level_use - 6.0)
         if r_s > 0.6 and lvl > min_level_use - 12.0 then is_sustained_level = true end
         pass_off = not (is_sustained_ratio and is_sustained_level)
      else
         pass_off = true
      end

      if pass_on then
         if not inS then
            inS = true
            seg_start_idx = i
         end
         gap_run_ms = 0
      else
         if inS then
            if pass_off then
               gap_run_ms = gap_run_ms + config.hop_ms
               if gap_run_ms >= config.max_gap_ms then
                  inS = false
                  local end_idx = i - math.floor(gap_run_ms / config.hop_ms)
                  if end_idx < seg_start_idx then end_idx = seg_start_idx end

                  local dur_ms = (end_idx - seg_start_idx) * config.hop_ms
                  local min_len = config.min_seg_ms
                  if r_prev1 > 0.5 then min_len = 15 end

                  if dur_ms >= min_len then
                     if not is_false_positive(seg_start_idx, end_idx) then
                        table.insert(candidates, { start_idx = seg_start_idx, end_idx = end_idx })
                     end
                  end
                  gap_run_ms = 0
               end
            else
               gap_run_ms = 0
            end
         end
      end
   end

   if inS then
      local end_idx = #levels
      local dur_ms = (end_idx - seg_start_idx) * config.hop_ms
      if dur_ms >= config.min_seg_ms then
         if not is_false_positive(seg_start_idx, end_idx) then
            table.insert(candidates, { start_idx = seg_start_idx, end_idx = end_idx })
         end
      end
   end

   for _, seg in ipairs(candidates) do
      local valid, rej_reason = validate_segment(seg)
      if valid then
         table.insert(segments, valid)
      else
         if rej_reason then
            table.insert(rejected, { start_idx = seg.start_idx, end_idx = seg.end_idx, reason = rej_reason })
         end
      end
   end

   local stats = { rejected = rejected }
   return segments, stats
end

return Hunter
