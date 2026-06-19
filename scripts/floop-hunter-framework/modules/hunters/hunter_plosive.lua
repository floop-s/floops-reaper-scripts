-- @noindex
-- @description Floop Hunter Framework - Plosive hunter
-- @author Floop-s
-- @license GPL-3.0
local DSP = require("floop_dsp")
local Logger = require("floop_logger")

local Hunter = {}
Hunter.name = "Plosive Hunter"

-- =========================================================================
-- ACOUSTIC PROFILE MATRIX (CENTRALIZED)
-- =========================================================================
Hunter.Profiles = {
  [1] = { -- FEMALE (Cantato)
    name = "Female",
    low_pass = 130,
    min_low_db = -58.0, 
    transient_thresh = 4.0, -- Raised due to WB delta exceeding LF delta
    silence_margin_db = 10.0,
    refractory_ms = 350,
    env_tau_sec = 0.15,
    max_plosive_ms = 130,
    min_seg_ms = 10,
    delay_ms = 25
  },
  [2] = { -- MALE (Cantato)
    name = "Male",
    low_pass = 110,
    min_low_db = -58.0, 
    transient_thresh = 3.3, 
    silence_margin_db = 10.0,
    refractory_ms = 240,
    env_tau_sec = 0.15,
    max_plosive_ms = 120,
    min_seg_ms = 10,
    delay_ms = 30
  },
  [3] = { -- SPOKEN MALE
    name = "Spoken Male",
    low_pass = 90,
    min_low_db = -50.0,
    transient_thresh = 5.0, 
    silence_margin_db = 8.0,
    refractory_ms = 350,
    env_tau_sec = 0.15,
    max_plosive_ms = 220,
    min_seg_ms = 15,
    delay_ms = 30
  },
  [4] = { -- SPOKEN FEMALE
    name = "Spoken Female",
    low_pass = 120,
    min_low_db = -62.0, 
    transient_thresh = 4.2, 
    silence_margin_db = 8.0,
    refractory_ms = 350,
    env_tau_sec = 0.15,
    max_plosive_ms = 150,
    min_seg_ms = 15,
    delay_ms = 25
  },
  [5] = { -- RAP
    name = "Rap",
    low_pass = 110,
    min_low_db = -50.0, 
    transient_thresh = 6.0, -- High threshold for continuous vocal flow
    silence_margin_db = 8.0,
    refractory_ms = 150,
    env_tau_sec = 0.10,
    max_plosive_ms = 90,
    min_seg_ms = 10,
    delay_ms = 20
  }
}

Hunter.default_config = {
  source_profile = 2, -- Default: Male
  low_pass = 90,
  min_low_db = -55.0,
  transient_thresh = 2.5,
  delay_ms = 30,
  window_ms = 20,
  hop_ms = 5,
  min_seg_ms = 10,
  max_gap_ms = 20,
  pre_ramp_ms = 10,
  post_ramp_ms = 20,
  reduction_db = 6.0
}

function Hunter.init(sr, config)
  local profile_id = config.source_profile or 2
  local profile = Hunter.Profiles[profile_id] or Hunter.Profiles[2]
  
  Logger:debug(string.format("PLOSIVE_INIT | Profilo:%s | sr:%d", profile.name, sr))
  
  -- Profile default unless explicitly overridden by UI.
  local lp_freq = profile.low_pass
  if config.low_pass and config.low_pass ~= Hunter.default_config.low_pass then 
      lp_freq = config.low_pass -- Explicit manual override.
  end
  if lp_freq < 40 then lp_freq = 40 end
  
  Logger:debug(string.format("PLOSIVE_CFG | lp:%d | hp:%d", lp_freq, 500))

  return {
    sr = sr,
    lp_filter_1 = DSP.biquad_new(DSP.rbj_lowpass(lp_freq, 0.707, sr)),
    lp_filter_2 = DSP.biquad_new(DSP.rbj_lowpass(lp_freq, 0.707, sr)), -- 4th order cascade
    hp_filter = DSP.biquad_new(DSP.rbj_highpass(500, 0.707, sr)),
    dc_blocker = DSP.biquad_new(DSP.rbj_highpass(20, 0.707, sr))
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
    
    -- Cascade two biquads for a steeper cutoff
    local low_1 = DSP.biquad_process(state.lp_filter_1, mono)
    local low_2 = DSP.biquad_process(state.lp_filter_2, low_1)
    
    hop_low = hop_low + low_2 * low_2
    local alow = math.abs(low_2)
    if alow > hop_peak_low then hop_peak_low = alow end

    local high = DSP.biquad_process(state.hp_filter, mono)
    hop_high = hop_high + high * high
  end

  local invN = 1 / math.max(1, H_samples)
  local rms_wb = math.sqrt(hop_wb * invN)
  local rms_low = math.sqrt(hop_low * invN)
  local rms_high = math.sqrt(hop_high * invN)

  local wb_db = DSP.amp_to_db(rms_wb)
  local low_db = DSP.amp_to_db(rms_low)
  local high_db = DSP.amp_to_db(rms_high)

  local diff_db = low_db - high_db
  local spectral_balance_db = diff_db
  local crest_low = hop_peak_low / math.max(1e-12, rms_low)

  if result_buf then
    result_buf.level = wb_db
    result_buf.low_db = low_db
    result_buf.high_db = high_db
    result_buf.diff_db = diff_db
    result_buf.spectral_balance_db = spectral_balance_db
    result_buf.crest_low = crest_low
    return result_buf
  else
    return {
      level = wb_db,
      low_db = low_db,
      high_db = high_db,
      diff_db = diff_db,
      spectral_balance_db = spectral_balance_db,
      crest_low = crest_low
    }
  end
end

function Hunter.detect_segments(features, config)
  local lows = features.low_db
  local wbs = features.level
  if not lows or not wbs then return {} end

  local segments = {}
  local inS = false
  local seg_start_idx = 0
  local gap_run_ms = 0
  local current_points = {}
  local current_max_delta = 0
  local last_fail_info = nil
  local male_sibilant_veto_until_idx = 0
  
  local profile_id = config.source_profile or 2
  local profile = Hunter.Profiles[profile_id] or Hunter.Profiles[2]
  
  local max_plosive_ms = profile.max_plosive_ms
  local hop_ms = config.hop_ms or 5
  local hop_sec = hop_ms / 1000
  
  -- Fallback to config values if user changed them via UI, else use profile values
  local min_low_db = config.min_low_db or profile.min_low_db
  local burst_db = config.transient_thresh or profile.transient_thresh
  local delay_ms = config.delay_ms or profile.delay_ms
  local delay_frames = math.max(3, math.floor(delay_ms / hop_ms + 0.5))
  
  local env_tau_sec = profile.env_tau_sec
  local rel_a = math.exp(-hop_sec / env_tau_sec)
  -- Slow attack to estimate noise floor (~50ms)
  local att_a = math.exp(-hop_sec / 0.050) 
  
  local max_gap_ms = config.max_gap_ms or 20
  local min_seg_ms = config.min_seg_ms or profile.min_seg_ms or 15
  local male_sibilant_veto_ms = 10
  local male_sibilant_veto_frames = math.max(1, math.floor(male_sibilant_veto_ms / hop_ms + 0.5))

  local ring_size = delay_frames + 1
  local env_ring_wb = {}
  local env_ring_lf = {}
  for i = 1, ring_size do 
      env_ring_wb[i] = 0.0 
      env_ring_lf[i] = 0.0
  end
  local ring_pos = 1
  local env_wb = 0.0
  local env_lf = 0.0

  local lp_dbg = config.low_pass or profile.low_pass
  Logger:debug(string.format("PLOSIVE_DETECT | Profilo:%s | min_low_db:%.1f | burst_db:%.1f | lp:%d | delay_ms:%.1f | delay_frames:%d",
    profile.name, min_low_db, burst_db, math.floor(lp_dbg + 0.5), delay_ms, delay_frames))

  -- ====================================================================
  -- DYNAMIC WIDEBAND NOISE FLOOR TRACKING via Slew Rate
  -- ====================================================================
  local local_noise_wb_db = {}
  -- Estimated Wideband baseline
  local current_noise_wb_db = min_low_db + 6.0
  local noise_up_rate = 40.0 * hop_sec    -- Rises at 40 dB/s (fast tracking)
  local noise_down_rate = 100.0 * hop_sec -- Falls at 100 dB/s
  
  for i = 1, #wbs do
      local val = wbs[i] or -144.0
      if val < current_noise_wb_db then
          current_noise_wb_db = math.max(val, current_noise_wb_db - noise_down_rate)
      else
          current_noise_wb_db = math.min(val, current_noise_wb_db + noise_up_rate)
      end
      local_noise_wb_db[i] = current_noise_wb_db
  end

  for i = 1, #wbs do
    local wb_db = wbs[i] or -144.0
    local wb_amp = DSP.db_to_amp(wb_db)
    local low_db = lows[i] or -144.0
    local low_amp = DSP.db_to_amp(low_db)
    local high_db = features.high_db[i] or -144.0
    local spectral_balance_db = ((features.spectral_balance_db and features.spectral_balance_db[i]) or
      (features.diff_db and features.diff_db[i]) or
      (low_db - high_db))

    -- RING BUFFER WIDEBAND & LF
    env_ring_wb[ring_pos] = env_wb
    env_ring_lf[ring_pos] = env_lf

    ring_pos = ring_pos + 1
    if ring_pos > ring_size then ring_pos = 1 end

    local env_del_wb = env_ring_wb[ring_pos]
    local env_del_lf = env_ring_lf[ring_pos]

    if wb_amp > env_wb then
        env_wb = wb_amp + att_a * (env_wb - wb_amp)
    else
        env_wb = wb_amp + rel_a * (env_wb - wb_amp)
    end

    if low_amp > env_lf then
        env_lf = low_amp + att_a * (env_lf - low_amp)
    else
        env_lf = low_amp + rel_a * (env_lf - low_amp)
    end

    if i <= (delay_frames + 1) then
      goto continue
    end

    local env_del_wb_db = DSP.amp_to_db(env_del_wb)
    local delta_wb = wb_db - env_del_wb_db
    
    local env_del_lf_db = DSP.amp_to_db(env_del_lf)
    local delta_lf = low_db - env_del_lf_db
    
    -- Conservative Male-only sibilance guard. 
    local not_sibilant = true
    if profile_id == 2 then
      local male_sibilant_band = (spectral_balance_db >= -12.6) and (spectral_balance_db <= -10.1)
      local male_sibilant_high = (high_db >= -31.0) and (high_db <= -27.5)
      not_sibilant = not (male_sibilant_band and male_sibilant_high)
    end
    local male_sibilant_veto_active = (profile_id == 2) and not inS and (i <= male_sibilant_veto_until_idx)
    -- LF energy gate
    local has_lf = (low_db > min_low_db) and (delta_lf >= (burst_db * 0.3))

    local pass_on = false
    if not inS then
      -- PRE-BURST SILENCE THRESHOLD based on dynamic noise floor
      local dyn_noise_wb_db = math.max(min_low_db + 6.0, local_noise_wb_db[i])
      local silence_floor_wb_db = dyn_noise_wb_db + (profile.silence_margin_db or 8.0)
      local is_pre_silent = (env_del_wb_db < silence_floor_wb_db)
      
      -- Optional WB upper bound
      local max_burst_low_db = profile.max_burst_low_db
      local is_burst_level = max_burst_low_db and (low_db < max_burst_low_db) or true

      -- Wideband trigger logic
      pass_on = has_lf and (delta_wb >= burst_db) and not_sibilant and not male_sibilant_veto_active and is_burst_level
    else
        -- Hold logic
        pass_on = has_lf and (delta_wb >= math.min(1.0, burst_db * 0.3))
    end

    if not pass_on and not inS and (low_db > min_low_db) and delta_wb >= 2.0 then
        local fail_reason = ""
        if delta_wb < burst_db then fail_reason = "delta_wb_low"
        elseif not has_lf then fail_reason = "no_lf_burst"
        elseif not not_sibilant then fail_reason = "is_sibilant"
        elseif male_sibilant_veto_active then fail_reason = "sibilant_veto"
        elseif not is_pre_silent then fail_reason = "not_pre_silent"
        elseif not is_burst_level then fail_reason = "burst_too_loud"
        end
        if fail_reason ~= "" then
            Logger:debug(string.format("PLOSIVE_FAIL | i:%d | ms:%.1f | reason:%s | wb_db:%.1f | low_db:%.1f | high_db:%.1f | spec_bal:%.1f | delta_wb:%.1f(req:%.1f) | delta_lf:%.1f",
                i, i * hop_ms, fail_reason, wb_db, low_db, high_db, spectral_balance_db, delta_wb, burst_db, delta_lf))
            if fail_reason == "is_sibilant" then
              male_sibilant_veto_until_idx = math.max(male_sibilant_veto_until_idx, i + male_sibilant_veto_frames)
            end
            last_fail_info = {
              idx = i,
              reason = fail_reason,
              low_db = low_db,
              high_db = high_db,
              spectral_balance_db = spectral_balance_db,
              wb_db = wb_db,
              env_del_wb_db = env_del_wb_db,
              delta_wb = delta_wb,
              delta_lf = delta_lf
            }
        end
    elseif not inS then
        last_fail_info = nil
    end

    if pass_on then
      if not inS then
        local backtracked = false
        if last_fail_info and last_fail_info.idx == (i - 1) then
          local fail_reason = last_fail_info.reason
          local eligible_reason = (fail_reason == "delta_wb_low") or (fail_reason == "no_lf_burst")
          local borderline_wb = last_fail_info.delta_wb >= math.max(2.0, burst_db * 0.80)
          local borderline_lf = last_fail_info.delta_lf >= math.max(0.0, burst_db * 0.15)
          if eligible_reason and borderline_wb and borderline_lf then
            backtracked = true
            seg_start_idx = last_fail_info.idx
            current_points = {}
            local prev_strength = last_fail_info.delta_wb - burst_db
            if prev_strength < 0 then prev_strength = 0 end
            local prev_target_hz = 30 + (prev_strength * 12)
            if prev_target_hz > 180 then prev_target_hz = 180 end
            table.insert(current_points, { offset_sec = 0.0, val = prev_target_hz })
            current_max_delta = math.max(delta_wb, last_fail_info.delta_wb)
            Logger:debug(string.format("PLOSIVE_BACKTRACK | from:%d | to:%d | reason:%s | prev_delta_wb:%.1f | prev_delta_lf:%.1f",
              i, seg_start_idx, fail_reason, last_fail_info.delta_wb, last_fail_info.delta_lf))
          end
        end

        inS = true
        if not backtracked then
          seg_start_idx = i
          current_points = {}
          current_max_delta = delta_wb
        end
        gap_run_ms = 0
        Logger:debug(string.format("PLOSIVE_ON | i:%d | wb_db:%.1f | low_db:%.1f | high_db:%.1f | spec_bal:%.1f | env_wb:%.1f | delta_wb:%.1f | delta_lf:%.1f", i, wb_db, low_db, high_db, spectral_balance_db, env_del_wb_db, delta_wb, delta_lf))
        last_fail_info = nil
      else
        gap_run_ms = 0
        current_max_delta = math.max(current_max_delta, delta_wb)
      end

      local strength = delta_wb - burst_db
      if strength < 0 then strength = 0 end
      local target_hz = 30 + (strength * 12)
      if target_hz > 180 then target_hz = 180 end

      table.insert(current_points, { offset_sec = (i - seg_start_idx) * hop_sec, val = target_hz })
    else
      if inS then
        gap_run_ms = gap_run_ms + hop_ms
        if gap_run_ms >= max_gap_ms then
          local end_idx = i - math.floor(gap_run_ms / hop_ms)
          if end_idx < seg_start_idx then end_idx = seg_start_idx end

          local dur_ms = ((end_idx - seg_start_idx) + 1) * hop_ms
          if dur_ms >= min_seg_ms and dur_ms <= max_plosive_ms then
            table.insert(segments, { start_idx = seg_start_idx, end_idx = end_idx, points = current_points, max_delta = current_max_delta })
            local last_high_db = features.high_db[end_idx] or -144.0
            local last_spectral_balance_db = ((features.spectral_balance_db and features.spectral_balance_db[end_idx]) or
              (features.diff_db and features.diff_db[end_idx]) or
              -144.0)
            Logger:debug(string.format("PLOSIVE_OFF | s:%d | e:%d | dur_ms:%d | high_db:%.1f | spec_bal:%.1f", seg_start_idx, end_idx, dur_ms, last_high_db, last_spectral_balance_db))
          else
            local last_high_db = features.high_db[end_idx] or -144.0
            local last_spectral_balance_db = ((features.spectral_balance_db and features.spectral_balance_db[end_idx]) or
              (features.diff_db and features.diff_db[end_idx]) or
              -144.0)
            Logger:debug(string.format("PLOSIVE_DROP | s:%d | e:%d | dur_ms:%d | high_db:%.1f | spec_bal:%.1f", seg_start_idx, end_idx, dur_ms, last_high_db, last_spectral_balance_db))
          end
          inS = false
          gap_run_ms = 0
        end
      end
    end

    ::continue::
  end
  
  if inS then
    local end_idx = #lows
    local dur_ms = ((end_idx - seg_start_idx) + 1) * hop_ms
    if dur_ms >= min_seg_ms and dur_ms <= max_plosive_ms then
      table.insert(segments, { start_idx = seg_start_idx, end_idx = end_idx, points = current_points, max_delta = current_max_delta })
      local last_high_db = features.high_db[end_idx] or -144.0
      local last_spectral_balance_db = ((features.spectral_balance_db and features.spectral_balance_db[end_idx]) or
        (features.diff_db and features.diff_db[end_idx]) or
        -144.0)
      Logger:debug(string.format("PLOSIVE_OFF | s:%d | e:%d | dur_ms:%d | high_db:%.1f | spec_bal:%.1f", seg_start_idx, end_idx, dur_ms, last_high_db, last_spectral_balance_db))
    else
        local last_high_db = features.high_db[end_idx] or -144.0
        local last_spectral_balance_db = ((features.spectral_balance_db and features.spectral_balance_db[end_idx]) or
          (features.diff_db and features.diff_db[end_idx]) or
          -144.0)
        Logger:debug(string.format("PLOSIVE_DROP | s:%d | e:%d | dur_ms:%d | high_db:%.1f | spec_bal:%.1f", seg_start_idx, end_idx, dur_ms, last_high_db, last_spectral_balance_db))
      end
  end

  -- ====================================================================
  -- MARKER-ORIENTED CLUSTER FILTER
  -- Safely merges micro-bounces without destroying HPF segment points
  -- ====================================================================
  local clean_segments = {}
  local cluster_window_ms = 80

  for i = 1, #segments do
    local current = segments[i]
    if #clean_segments == 0 then
      table.insert(clean_segments, current)
    else
      local last = clean_segments[#clean_segments]
      local distance_ms = (current.start_idx - last.start_idx) * hop_ms
      
      if distance_ms < cluster_window_ms then
        last.end_idx = math.max(last.end_idx, current.end_idx)
        last.max_delta = math.max(last.max_delta or 0, current.max_delta or 0)
        
        if current.points then
          for _, pt in ipairs(current.points) do
             local adjusted_offset = ((current.start_idx - last.start_idx) * hop_sec) + pt.offset_sec
             table.insert(last.points, { offset_sec = adjusted_offset, val = pt.val })
          end
        end
        Logger:debug(string.format("PLOSIVE_CLUSTER | Merged %d into %d", current.start_idx, last.start_idx))
      else
        table.insert(clean_segments, current)
      end
    end
  end

  -- ====================================================================
  -- INTER-PLOSIVE REFRACTORY PERIOD
  -- Eliminates false positive clusters based on distance and strength
  -- ====================================================================
  local refractory_ms = profile.refractory_ms or 350
  local final_segments = {}

  for i = 1, #clean_segments do
    local current = clean_segments[i]
    if #final_segments == 0 then
      table.insert(final_segments, current)
    else
      local last = final_segments[#final_segments]
      local dist_ms = (current.start_idx - last.start_idx) * hop_ms
      
      if dist_ms < refractory_ms then
        if (current.max_delta or 0) > (last.max_delta or 0) then
          final_segments[#final_segments] = current
          Logger:debug(string.format("PLOSIVE_REFRACTORY | Replaced i:%d with stronger i:%d (dist:%.1fms)", 
            last.start_idx, current.start_idx, dist_ms))
        else
          Logger:debug(string.format("PLOSIVE_REFRACTORY | Dropped i:%d (dist:%.1fms < %.1fms)", 
            current.start_idx, dist_ms, refractory_ms))
        end
      else
        table.insert(final_segments, current)
      end
    end
  end

  return final_segments, {
    min_low_db = min_low_db,
    burst_db = burst_db,
    delay_ms = delay_ms,
    delay_frames = delay_frames
  }
end

return Hunter
