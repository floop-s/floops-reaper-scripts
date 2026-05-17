-- @description Floop Key & BPM Sniffer
-- @version 1.0.0
-- @author Floop-s
-- @license GPL-3.0
-- @about
--   Advanced audio analysis tool for Reaper.
--   Detects the musical Key and tempo (BPM) of selected audio items using Spectral Flux and Chromagram algorithms.
--   Features a dynamic UI that adapts to any Reaper theme.
-- @provides
--   [main] floop-key-bpm-sniffer.lua

-- ===========================================================
-- Dependencies
-- ===========================================================
if not reaper.ImGui_CreateContext then
    reaper.ShowMessageBox("ReaImGui API not found!\nPlease install 'ReaImGui' via ReaPack and restart Reaper.", "Error", 0)
    return
end

-- ===========================================================
-- Configuration
-- ===========================================================
local TITLE = "Floop Key & BPM Sniffer"

local UI_CONST = {
    SPACING_XS = 5,
    SPACING_SM = 10,
    SPACING_MD = 15,
    BUTTON_H = 30,
    ROUNDING = 6,
    FONT_SIZE = 13,
}

-- ===========================================================
-- Theme Engine
-- ===========================================================
local function GenerateDynamicTheme()
    local bg_native = reaper.GetThemeColor("col_main_bg2", 0)
    local text_native = reaper.GetThemeColor("col_main_text2", 0)
    
    if bg_native == -1 then bg_native = reaper.ColorToNative(27, 27, 27) end
    if text_native == -1 then text_native = reaper.ColorToNative(232, 232, 232) end

    local bg_r, bg_g, bg_b = reaper.ColorFromNative(bg_native)
    local txt_r, txt_g, txt_b = reaper.ColorFromNative(text_native)

    local luminance = (0.299 * bg_r + 0.587 * bg_g + 0.114 * bg_b)
    local is_dark = luminance < 128

    local txt_luminance = (0.299 * txt_r + 0.587 * txt_g + 0.114 * txt_b)
    if is_dark and txt_luminance < 180 then
        txt_r, txt_g, txt_b = 210, 212, 220
    elseif not is_dark and txt_luminance > 80 then
        txt_r, txt_g, txt_b = 40, 40, 40
    end

    local function rgba(r, g, b, a)
        return (math.floor(r) << 24) | (math.floor(g) << 16) | (math.floor(b) << 8) | math.floor(a * 255)
    end

    local function mix(r1, g1, b1, r2, g2, b2, t)
        return r1 + (r2 - r1) * t, g1 + (g2 - g1) * t, b1 + (b2 - b1) * t
    end

    local frame_r, frame_g, frame_b = mix(bg_r, bg_g, bg_b, txt_r, txt_g, txt_b, is_dark and 0.05 or 0.10)
    local hover_r, hover_g, hover_b = mix(bg_r, bg_g, bg_b, txt_r, txt_g, txt_b, is_dark and 0.12 or 0.18)
    local active_r, active_g, active_b = mix(bg_r, bg_g, bg_b, txt_r, txt_g, txt_b, is_dark and 0.18 or 0.25)
    local title_r, title_g, title_b = mix(bg_r, bg_g, bg_b, 0, 0, 0, is_dark and 0.2 or 0.05)

    local acc_r, acc_g, acc_b = 41, 140, 206

    local colors = {
        [reaper.ImGui_Col_WindowBg()]          = rgba(bg_r, bg_g, bg_b, 1.0),
        [reaper.ImGui_Col_ChildBg()]           = rgba(frame_r, frame_g, frame_b, 0.2),
        [reaper.ImGui_Col_PopupBg()]           = rgba(bg_r, bg_g, bg_b, 0.95),
        [reaper.ImGui_Col_Text()]              = rgba(txt_r, txt_g, txt_b, 1.0),
        [reaper.ImGui_Col_TextDisabled()]      = rgba(txt_r, txt_g, txt_b, 0.5),
        [reaper.ImGui_Col_TitleBg()]           = rgba(title_r, title_g, title_b, 1.0),
        [reaper.ImGui_Col_TitleBgActive()]     = rgba(title_r, title_g, title_b, 1.0),
        [reaper.ImGui_Col_TitleBgCollapsed()]  = rgba(title_r, title_g, title_b, 0.7),
        [reaper.ImGui_Col_Button()]            = rgba(frame_r, frame_g, frame_b, 1.0),
        [reaper.ImGui_Col_ButtonHovered()]     = rgba(hover_r, hover_g, hover_b, 1.0),
        [reaper.ImGui_Col_ButtonActive()]      = rgba(active_r, active_g, active_b, 1.0),
        [reaper.ImGui_Col_FrameBg()]           = rgba(frame_r, frame_g, frame_b, 1.0),
        [reaper.ImGui_Col_FrameBgHovered()]    = rgba(hover_r, hover_g, hover_b, 1.0),
        [reaper.ImGui_Col_FrameBgActive()]     = rgba(active_r, active_g, active_b, 1.0),
        [reaper.ImGui_Col_SliderGrab()]        = rgba(acc_r, acc_g, acc_b, 0.8),
        [reaper.ImGui_Col_SliderGrabActive()]  = rgba(acc_r, acc_g, acc_b, 1.0),
        [reaper.ImGui_Col_Border()]            = rgba(txt_r, txt_g, txt_b, 0.15),
        [reaper.ImGui_Col_Separator()]         = rgba(txt_r, txt_g, txt_b, 0.15),
        [reaper.ImGui_Col_SeparatorHovered()]  = rgba(txt_r, txt_g, txt_b, 0.3),
        [reaper.ImGui_Col_SeparatorActive()]   = rgba(txt_r, txt_g, txt_b, 0.4),
        [reaper.ImGui_Col_Header()]            = rgba(frame_r, frame_g, frame_b, 1.0),
        [reaper.ImGui_Col_HeaderHovered()]     = rgba(hover_r, hover_g, hover_b, 1.0),
        [reaper.ImGui_Col_HeaderActive()]      = rgba(active_r, active_g, active_b, 1.0),
        [reaper.ImGui_Col_ResizeGrip()]        = rgba(acc_r, acc_g, acc_b, 0.5),
        [reaper.ImGui_Col_ResizeGripHovered()] = rgba(acc_r, acc_g, acc_b, 0.8),
        [reaper.ImGui_Col_ResizeGripActive()]  = rgba(acc_r, acc_g, acc_b, 1.0),
        [reaper.ImGui_Col_CheckMark()]         = rgba(acc_r, acc_g, acc_b, 1.0),
        [reaper.ImGui_Col_PlotHistogram()]     = rgba(239, 142, 39, 1.0),
        [reaper.ImGui_Col_PlotHistogramHovered()] = rgba(239, 142, 39, 1.0),
    }
    
    local special = {
        accent = rgba(acc_r, acc_g, acc_b, 1.0),
        accent_hover = rgba(math.min(255, acc_r + 20), math.min(255, acc_g + 20), math.min(255, acc_b + 20), 1.0),
        accent_active = rgba(math.max(0, acc_r - 20), math.max(0, acc_g - 20), math.max(0, acc_b - 20), 1.0),
        warn   = rgba(239, 142, 39, 1.0),
        error  = rgba(255, 77, 79, 1.0),
        ok     = rgba(38, 226, 68, 1.0),
        text_muted = rgba(txt_r, txt_g, txt_b, 0.6),
        white = rgba(255, 255, 255, 1.0)
    }

    return colors, special
end

local THEME_COLORS, SPECIAL_COLORS = GenerateDynamicTheme()

-- ===========================================================
-- State
-- ===========================================================
local State = {
    ui = {
        ctx = reaper.ImGui_CreateContext(TITLE),
        font = nil,
        open = true,
        mini_mode = false,
        full_w = 400,
        full_h = 300,
        need_restore = false,
        dock_id = 0,
        need_dock_update = false,
    },
    analysis = {
        is_analyzing = false,
        progress = 0.0,
        result_key = "Unknown",
        result_confidence = 0.0,
        result_bpm = 0,
        current_item_name = "No Item Selected"
    }
}

-- ===========================================================
-- Core Logic
-- ===========================================================
local function GetSelectedItemInfo()
    local item = reaper.GetSelectedMediaItem(0, 0)
    if not item then return nil, "No Item Selected" end

    local take = reaper.GetActiveTake(item)
    if not take or reaper.TakeIsMIDI(take) then return nil, "No Audio Take" end

    local name = reaper.GetTakeName(take)
    return take, name
end

-- ===========================================================
-- Analysis Algorithms
-- ===========================================================
local PROFILES = {
    major = { 6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88 },
    minor = { 6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17 }
}

local NOTE_NAMES = { "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B" }

local Analysis = {
    take = nil,
    accessor = nil,
    channels = 0,
    samplerate = 0,
    length = 0,
    key_block_size = 16384,
    bpm_block_size = 1024,
    buffer = nil,
    fft_buffer = nil,
    current_pos = 0,
    tuning_deviation_cents = 0,
    chroma_energy = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
    key_accumulator = {},
    key_samples_accumulated = 0,
    energy_history = {},
    history_hop_size = 0,
    total_samples_processed = 0,
    window = nil,
    blocks_processed = 0
}

local function InitWindow(size)
    Analysis.window = reaper.new_array(size)
    local t = {}
    for i = 0, size - 1 do
        t[i + 1] = 0.5 * (1.0 - math.cos(2.0 * math.pi * i / (size - 1)))
    end
    Analysis.window.copy(t)
end

local function Correlation(data_x, data_y)
    local n = #data_x
    local sum_x, sum_y, sum_xy, sum_sq_x, sum_sq_y = 0, 0, 0, 0, 0

    for i = 1, n do
        sum_x = sum_x + data_x[i]
        sum_y = sum_y + data_y[i]
        sum_xy = sum_xy + (data_x[i] * data_y[i])
        sum_sq_x = sum_sq_x + (data_x[i] ^ 2)
        sum_sq_y = sum_sq_y + (data_y[i] ^ 2)
    end

    local num = (n * sum_xy) - (sum_x * sum_y)
    local var_x = math.max(0, (n * sum_sq_x) - sum_x ^ 2)
    local var_y = math.max(0, (n * sum_sq_y) - sum_y ^ 2)
    local den = math.sqrt(var_x * var_y)

    if den == 0 then return 0 end
    return num / den
end

local function DetectKeyFromChroma(chroma)
    local best_key_idx = -1 
    local best_score = -1.0

    local norm_chroma = {}
    local max_e = 0
    for i = 1, 12 do max_e = math.max(max_e, chroma[i]) end
    
    if max_e > 1e-6 then
        for i = 1, 12 do norm_chroma[i] = chroma[i] / max_e end
    else
        return -1, 0
    end

    for i = 0, 11 do
        local rotated_profile = {}
        for k = 1, 12 do
            local p_idx = (k - i - 1) % 12 + 1
            table.insert(rotated_profile, PROFILES.major[p_idx])
        end
        local score = Correlation(norm_chroma, rotated_profile)
        if score > best_score then
            best_score = score
            best_key_idx = i
        end
    end

    for i = 0, 11 do
        local rotated_profile = {}
        for k = 1, 12 do
            local p_idx = (k - i - 1) % 12 + 1
            table.insert(rotated_profile, PROFILES.minor[p_idx])
        end
        local score = Correlation(norm_chroma, rotated_profile)
        if score > best_score then
            best_score = score
            best_key_idx = i + 12
        end
    end

    return best_key_idx, best_score
end

-- ===========================================================
-- Analysis Engine
-- ===========================================================

local function DetectBPMFromEnergy(energy_envelope, sample_rate, hop_size)
    -- Calculates BPM using Energy Difference and autocorrelation.
    local n = #energy_envelope
    if n < 100 then return 0 end

    -- Computes energy difference from energy envelope.
    local energy_diff = {}
    for i = 1, n do
        if i == 1 then
            energy_diff[i] = 0
        else
            local diff = energy_envelope[i] - energy_envelope[i-1]
            energy_diff[i] = math.max(0, diff)
        end
    end
    
    -- Smooths energy difference to reduce noise artifacts.
    local smoothed_energy_diff = {}
    local window = 3
    for i = 1, n do
        local sum = 0
        local count = 0
        for j = math.max(1, i - window), math.min(n, i + window) do
            sum = sum + energy_diff[j]
            count = count + 1
        end
        smoothed_energy_diff[i] = sum / count
    end

    local min_bpm = 70
    local max_bpm = 180
    local block_time = hop_size / sample_rate
    
    local min_lag = math.floor((60.0 / max_bpm) / block_time)
    local max_lag = math.floor((60.0 / min_bpm) / block_time)
    
    local best_bpm = 0
    local max_corr = 0
    local best_lag = 0
    local corr_array = {}

    -- Evaluates lag candidates via autocorrelation.
    for lag = min_lag, max_lag do
        local sum = 0
        local count = 0
        
        for i = 1, n - lag do
            sum = sum + (smoothed_energy_diff[i] * smoothed_energy_diff[i + lag])
            count = count + 1
        end
                
                if count > 0 then
                    local corr = sum / count
                    
                    local current_bpm = 60.0 / (lag * block_time)
                    local target_bpm = 120.0
                    local distance = math.abs(current_bpm - target_bpm) / 100.0
                    local weight = 1.0 - (distance * 0.15)
                    
                    corr = corr * weight
                    corr_array[lag] = corr

                    if corr > max_corr then
                        max_corr = corr
                        best_lag = lag
                    end
                end
            end
            
            if max_corr < 0.0001 then return 0 end
            
            if best_lag > min_lag and best_lag < max_lag then
                local alpha = corr_array[best_lag - 1] or 0
                local beta = corr_array[best_lag] or 0
                local gamma = corr_array[best_lag + 1] or 0
                
                local p = 0.5 * (alpha - gamma) / (alpha - 2*beta + gamma)
                local fractional_lag = best_lag + p
                best_bpm = 60.0 / (fractional_lag * block_time)
            else
                best_bpm = 60.0 / (best_lag * block_time)
            end
            
            local final_bpm = math.floor(best_bpm + 0.5)
    
    -- Normalizes BPM into standard 70-180 range.
    if final_bpm > 0 and final_bpm < 40 then final_bpm = final_bpm * 2 end
    while final_bpm > 200 do final_bpm = math.floor(final_bpm / 2) end
    
    return final_bpm
end

local function GetKeyName(idx)
    -- Converts key index to formatted string label.
    if not idx or idx < 0 then return "Unknown" end
    if idx < 12 then
        return NOTE_NAMES[idx + 1] .. " Major"
    else
        return NOTE_NAMES[(idx - 12) + 1] .. " Minor"
    end
end

local function InitAnalysis(take)
    -- Prevents memory leaks by destroying previous accessor if analysis was interrupted.
    if Analysis.accessor then
        reaper.DestroyAudioAccessor(Analysis.accessor)
        Analysis.accessor = nil
    end

    -- Initializes audio accessor and dual-buffer state for analysis.
    Analysis.take = take
    Analysis.accessor = reaper.CreateTakeAudioAccessor(take)
    local src = reaper.GetMediaItemTake_Source(take)
    Analysis.samplerate = reaper.GetMediaSourceSampleRate(src)
    if Analysis.samplerate == 0 then Analysis.samplerate = 44100 end
    Analysis.channels = reaper.GetMediaSourceNumChannels(src)
    Analysis.length = reaper.GetMediaItemInfo_Value(reaper.GetMediaItemTake_Item(take), "D_LENGTH")

    -- Dynamically calculates FFT block size based on sample rate to maintain consistent frequency resolution.
    -- Targets a resolution of ~2.7 Hz (16384 @ 44.1kHz).
    local target_resolution = 44100 / 16384
    local dynamic_block_size = math.floor(Analysis.samplerate / target_resolution)
    
    -- Ensures block size is a power of 2 for FFT efficiency.
    local pow2 = 1
    while pow2 < dynamic_block_size do pow2 = pow2 * 2 end
    Analysis.key_block_size = pow2

    local start_offset = math.min(2.0, Analysis.length * 0.1)
    Analysis.current_pos = start_offset

    Analysis.blocks_processed = 0

    for i = 1, 12 do Analysis.chroma_energy[i] = 0 end
    
    Analysis.key_accumulator = {}
    Analysis.key_samples_accumulated = 0
    
    Analysis.energy_history = {}
    Analysis.history_hop_size = Analysis.bpm_block_size

    InitWindow(Analysis.key_block_size)

    Analysis.buffer = reaper.new_array(Analysis.bpm_block_size * Analysis.channels)
    Analysis.fft_buffer = reaper.new_array(Analysis.key_block_size * 2) 

    Analysis.tuning_deviation_cents = 0

    State.analysis.is_analyzing = true
    State.analysis.progress = 0.0
    State.analysis.result_key = "Analyzing..."
    State.analysis.result_confidence = 0.0
    State.analysis.result_bpm = 0
end

local function StopAnalysis()
    if State.analysis.is_analyzing then
        State.analysis.is_analyzing = false
        State.analysis.progress = 0.0
        State.analysis.result_key = "Interrupted"
        State.analysis.result_confidence = 0.0
        State.analysis.result_bpm = 0
        
        if Analysis.accessor then
            reaper.DestroyAudioAccessor(Analysis.accessor)
            Analysis.accessor = nil
        end
    end
end

local function StepAnalysis()
    if not State.analysis.is_analyzing then return end

    -- Limits processing time per frame to maintain UI responsiveness and prevent stuttering.
    local start_time = reaper.time_precise()
    local max_time_per_frame = 0.012 

    while (reaper.time_precise() - start_time) < max_time_per_frame do
        if Analysis.current_pos >= Analysis.length then
            State.analysis.is_analyzing = false
            State.analysis.progress = 1.0

            local winner_idx, conf = DetectKeyFromChroma(Analysis.chroma_energy)
            State.analysis.result_key = GetKeyName(winner_idx)
            State.analysis.result_confidence = conf
            
            State.analysis.result_bpm = DetectBPMFromEnergy(Analysis.energy_history, Analysis.samplerate, Analysis.history_hop_size)

            reaper.DestroyAudioAccessor(Analysis.accessor)
            Analysis.accessor = nil
            return
        end

        local ret = reaper.GetAudioAccessorSamples(
            Analysis.accessor,
            Analysis.samplerate,
            Analysis.channels,
            Analysis.current_pos,
            Analysis.bpm_block_size,
            Analysis.buffer
        )

        if ret > 0 then
            local t_buf = Analysis.buffer.table()
            local block_energy = 0
            
            -- Processes small blocks for BPM timing and accumulates for Key FFT.
            for i = 1, Analysis.bpm_block_size do
                local mono_sample = 0
                for c = 0, Analysis.channels - 1 do
                    local buf_idx = (i-1)*Analysis.channels + c + 1
                    mono_sample = mono_sample + (t_buf[buf_idx] or 0)
                end
                mono_sample = mono_sample / Analysis.channels
                
                block_energy = block_energy + math.abs(mono_sample)
                
                Analysis.key_samples_accumulated = Analysis.key_samples_accumulated + 1
                Analysis.key_accumulator[Analysis.key_samples_accumulated] = mono_sample
            end
            
            table.insert(Analysis.energy_history, block_energy)
            
            if Analysis.key_samples_accumulated >= Analysis.key_block_size then
                -- Performs FFT when key block accumulator is full.
                Analysis.fft_buffer.clear()
                local t_fft = {} 
                local t_win = Analysis.window.table()
                
                for i = 1, Analysis.key_block_size do
                    t_fft[2*i - 1] = Analysis.key_accumulator[i] * (t_win[i] or 0) -- Real part
                    t_fft[2*i]     = 0                                             -- Imaginary part
                end
                
                Analysis.fft_buffer.copy(t_fft)
                Analysis.fft_buffer.fft(Analysis.key_block_size, true)
                
                local t_bins = Analysis.fft_buffer.table()
                local magnitudes = {}
                local num_bins = (Analysis.key_block_size / 2) - 1
                
                for k = 1, num_bins do
                    local re = t_bins[2*k + 1] or 0
                    local im = t_bins[2*k + 2] or 0
                    magnitudes[k] = math.sqrt(math.sqrt(re*re + im*im))
                end
                
                for k = 2, num_bins - 1 do
                    local mag = magnitudes[k]
                    
                    if mag > 0.001 and mag > magnitudes[k-1] and mag > magnitudes[k+1] then
                        local alpha = magnitudes[k-1]
                        local beta = mag
                        local gamma = magnitudes[k+1]
                        local p = 0.5 * (alpha - gamma) / (alpha - 2*beta + gamma)
                        local freq = (k + p) * Analysis.samplerate / Analysis.key_block_size

                        if freq > 60 and freq < 1000 then
                            local midi_exact = 12 * (math.log(freq / 440.0) / math.log(2)) + 69
                            local note_closest = math.floor(midi_exact + 0.5)
                            local cents_deviation = (midi_exact - note_closest) * 100
                            
                            local update_weight = math.min(0.05, mag * 0.005)
                            Analysis.tuning_deviation_cents = Analysis.tuning_deviation_cents * (1 - update_weight) + cents_deviation * update_weight

                            local adjusted_midi = midi_exact - (Analysis.tuning_deviation_cents / 100)
                            
                            local note_exact = adjusted_midi % 12
                            local note_idx = math.floor(note_exact) + 1 
                            local fraction = note_exact - math.floor(note_exact)
                            local next_idx = (note_idx % 12) + 1
                            
                            local weight = 1.0
                            if freq > 500 then
                                 weight = 1.0 - ((freq - 500) / 500) * 0.8
                            end
                            
                            local sharpness = 2.0
                            local weight_current = (1.0 - fraction) ^ sharpness
                            local weight_next = fraction ^ sharpness
                            local total_weight = weight_current + weight_next
                            
                            Analysis.chroma_energy[note_idx] = Analysis.chroma_energy[note_idx] + (mag * (weight_current / total_weight) * weight)
                            Analysis.chroma_energy[next_idx] = Analysis.chroma_energy[next_idx] + (mag * (weight_next / total_weight) * weight)
                        end
                    end
                end

                local half_size = Analysis.key_block_size / 2
                for i = 1, half_size do
                    Analysis.key_accumulator[i] = Analysis.key_accumulator[i + half_size]
                end
                Analysis.key_samples_accumulated = half_size
            end

            Analysis.blocks_processed = Analysis.blocks_processed + 1
        end

        Analysis.current_pos = Analysis.current_pos + (Analysis.bpm_block_size / Analysis.samplerate)
        State.analysis.progress = Analysis.current_pos / Analysis.length
    end
end

local function StartAnalysis()
    -- Initiates analysis for the currently selected media item.
    local take, name = GetSelectedItemInfo()
    if not take then return end

    State.analysis.current_item_name = name
    InitAnalysis(take)
end

-- ===========================================================
-- UI Logic
-- ===========================================================
local function PushTheme()
    -- Applies dynamic theme colors and styling variables.
    for col, val in pairs(THEME_COLORS) do
        reaper.ImGui_PushStyleColor(State.ui.ctx, col, val)
    end
    reaper.ImGui_PushStyleVar(State.ui.ctx, reaper.ImGui_StyleVar_WindowRounding(), UI_CONST.ROUNDING)
    reaper.ImGui_PushStyleVar(State.ui.ctx, reaper.ImGui_StyleVar_FrameRounding(), UI_CONST.ROUNDING)
end

local function PopTheme()
    -- Dynamically counts and pops pushed theme colors.
    local count = 0
    for _ in pairs(THEME_COLORS) do count = count + 1 end
    reaper.ImGui_PopStyleColor(State.ui.ctx, count)
    reaper.ImGui_PopStyleVar(State.ui.ctx, 2)
end

local function DrawUI()
    PushTheme()
    reaper.ImGui_PushFont(State.ui.ctx, State.ui.font, UI_CONST.FONT_SIZE)

    -- Configures window flags based on current mode.
    local flags = 0
    if State.ui.mini_mode then
        flags = reaper.ImGui_WindowFlags_NoTitleBar() | reaper.ImGui_WindowFlags_AlwaysAutoResize() | reaper.ImGui_WindowFlags_NoCollapse()
    else
        flags = reaper.ImGui_WindowFlags_NoCollapse()
    end

    -- Updates docking state before window creation.
    if State.ui.need_dock_update then
        if State.ui.mini_mode then
            reaper.ImGui_SetNextWindowDockID(State.ui.ctx, State.ui.dock_id)
        else
            reaper.ImGui_SetNextWindowDockID(State.ui.ctx, 0)
        end
        State.ui.need_dock_update = false
    end

    if not State.ui.mini_mode then
        if State.ui.need_restore then
            reaper.ImGui_SetNextWindowSize(State.ui.ctx, State.ui.full_w, State.ui.full_h)
            
            -- Centers window on active viewport upon restoration.
            local viewport = reaper.ImGui_GetMainViewport(State.ui.ctx)
            local work_pos_x, work_pos_y = reaper.ImGui_Viewport_GetWorkPos(viewport)
            local work_size_w, work_size_h = reaper.ImGui_Viewport_GetWorkSize(viewport)
            
            local center_x = work_pos_x + (work_size_w - State.ui.full_w) * 0.5
            local center_y = work_pos_y + (work_size_h - State.ui.full_h) * 0.5
            reaper.ImGui_SetNextWindowPos(State.ui.ctx, center_x, center_y)
            
            State.ui.need_restore = false
        else
            reaper.ImGui_SetNextWindowSize(State.ui.ctx, 450, 350, reaper.ImGui_Cond_FirstUseEver())
        end
    end

    -- Initializes UI window context.
    local visible, open = reaper.ImGui_Begin(State.ui.ctx, TITLE, true, flags)
    State.ui.open = open

    if visible then
        if State.ui.mini_mode then
            -- ==========================================
            -- MINI MODE LAYOUT
            -- ==========================================
            local current_dock = reaper.ImGui_GetWindowDockID(State.ui.ctx)
            if current_dock ~= 0 then State.ui.dock_id = current_dock end

            -- Uses text symbols to prevent OS emoji color overrides.
            if reaper.ImGui_Button(State.ui.ctx, " + ", 0, 0) then
                State.ui.mini_mode = false
                State.ui.need_restore = true
                State.ui.need_dock_update = true
            end
            if reaper.ImGui_IsItemHovered(State.ui.ctx) then 
                reaper.ImGui_SetTooltip(State.ui.ctx, "Full Mode") 
            end
            
            reaper.ImGui_SameLine(State.ui.ctx)
            if State.analysis.is_analyzing then
                reaper.ImGui_PushStyleColor(State.ui.ctx, reaper.ImGui_Col_Button(), SPECIAL_COLORS.warn)
                reaper.ImGui_PushStyleColor(State.ui.ctx, reaper.ImGui_Col_ButtonHovered(), SPECIAL_COLORS.warn)
                reaper.ImGui_PushStyleColor(State.ui.ctx, reaper.ImGui_Col_ButtonActive(), SPECIAL_COLORS.warn)
                if reaper.ImGui_Button(State.ui.ctx, "Stop", 0, 0) then
                    StopAnalysis()
                end
                reaper.ImGui_PopStyleColor(State.ui.ctx, 3)
            else
                if reaper.ImGui_Button(State.ui.ctx, "Analyze", 0, 0) then
                    StartAnalysis()
                end
            end
            
            reaper.ImGui_SameLine(State.ui.ctx)
            reaper.ImGui_Text(State.ui.ctx, "Key:")
            reaper.ImGui_SameLine(State.ui.ctx)
            
            local key_text = State.analysis.result_key
            if State.analysis.is_analyzing then 
                reaper.ImGui_TextColored(State.ui.ctx, SPECIAL_COLORS.warn, "Analyzing...")
            else
                reaper.ImGui_TextColored(State.ui.ctx, SPECIAL_COLORS.ok, key_text)
                if State.analysis.result_bpm > 0 then
                    reaper.ImGui_SameLine(State.ui.ctx)
                    reaper.ImGui_Text(State.ui.ctx, "|")
                    reaper.ImGui_SameLine(State.ui.ctx)
                    reaper.ImGui_Text(State.ui.ctx, "BPM:")
                    reaper.ImGui_SameLine(State.ui.ctx)
                    reaper.ImGui_TextColored(State.ui.ctx, SPECIAL_COLORS.ok, tostring(State.analysis.result_bpm))
                end
            end

        else
            -- ==========================================
            -- FULL MODE LAYOUT
            -- ==========================================
           
        
            if reaper.ImGui_Button(State.ui.ctx, " - ", 0, 0) then
                State.ui.full_w, State.ui.full_h = reaper.ImGui_GetWindowSize(State.ui.ctx)
                State.ui.mini_mode = true
                State.ui.need_dock_update = true
            end
            if reaper.ImGui_IsItemHovered(State.ui.ctx) then 
                reaper.ImGui_SetTooltip(State.ui.ctx, "Mini Mode") 
            end
            
            reaper.ImGui_SameLine(State.ui.ctx)
            reaper.ImGui_Text(State.ui.ctx, "Selected Item:")
            reaper.ImGui_SameLine(State.ui.ctx)
            
            -- Truncates item name dynamically 
            local avail_w = reaper.ImGui_GetContentRegionAvail(State.ui.ctx)
            local item_name = State.analysis.current_item_name
            local text_w, _ = reaper.ImGui_CalcTextSize(State.ui.ctx, item_name)
            
            if text_w > avail_w and string.len(item_name) > 5 then
                
                local len = string.len(item_name)
                while len > 5 do
                    local truncated = string.sub(item_name, 1, len) .. "..."
                    text_w, _ = reaper.ImGui_CalcTextSize(State.ui.ctx, truncated)
                    if text_w <= avail_w then
                        item_name = truncated
                        break
                    end
                    len = len - 1
                end
            end
            
            reaper.ImGui_TextColored(State.ui.ctx, SPECIAL_COLORS.white, item_name)

            reaper.ImGui_Separator(State.ui.ctx)
            reaper.ImGui_Spacing(State.ui.ctx)

            -- Renders primary analysis controls.
            if State.analysis.is_analyzing then
                reaper.ImGui_PushStyleColor(State.ui.ctx, reaper.ImGui_Col_Button(), SPECIAL_COLORS.warn)
                reaper.ImGui_PushStyleColor(State.ui.ctx, reaper.ImGui_Col_ButtonHovered(), SPECIAL_COLORS.warn)
                reaper.ImGui_PushStyleColor(State.ui.ctx, reaper.ImGui_Col_ButtonActive(), SPECIAL_COLORS.warn)
                
                if reaper.ImGui_Button(State.ui.ctx, "Stop Analysis", -1, UI_CONST.BUTTON_H) then
                    StopAnalysis()
                end
                
                reaper.ImGui_PopStyleColor(State.ui.ctx, 3)
            else
                -- Applies accent styling exclusively to main action button.
                reaper.ImGui_PushStyleColor(State.ui.ctx, reaper.ImGui_Col_Button(), SPECIAL_COLORS.accent)
                reaper.ImGui_PushStyleColor(State.ui.ctx, reaper.ImGui_Col_ButtonHovered(), SPECIAL_COLORS.accent_hover)
                reaper.ImGui_PushStyleColor(State.ui.ctx, reaper.ImGui_Col_ButtonActive(), SPECIAL_COLORS.accent_active)
                
                if reaper.ImGui_Button(State.ui.ctx, "Analyze Key", -1, UI_CONST.BUTTON_H) then
                    StartAnalysis()
                end
                
                reaper.ImGui_PopStyleColor(State.ui.ctx, 3)
            end

            reaper.ImGui_Spacing(State.ui.ctx)

            -- Renders analysis progress state.
            if State.analysis.is_analyzing then
                reaper.ImGui_ProgressBar(State.ui.ctx, State.analysis.progress, -1, 0,
                    string.format("Analyzing... %.0f%%", State.analysis.progress * 100))
            else
                -- Renders analysis results and confidence.
                if State.analysis.result_key ~= "Unknown" and State.analysis.result_key ~= "---" then
                    reaper.ImGui_Text(State.ui.ctx, "Estimated Key:")
                    reaper.ImGui_TextColored(State.ui.ctx, SPECIAL_COLORS.ok, State.analysis.result_key)
                    reaper.ImGui_TextDisabled(State.ui.ctx,
                        string.format("Confidence: %.1f%%", State.analysis.result_confidence * 100))

                    if State.analysis.result_bpm > 0 then
                        -- Wraps BPM display based on available horizontal width.
                        if avail_w > 300 then
                            reaper.ImGui_SameLine(State.ui.ctx, avail_w - 150)
                        end
                        reaper.ImGui_Text(State.ui.ctx, "Estimated BPM:")
                        reaper.ImGui_SameLine(State.ui.ctx)
                        reaper.ImGui_TextColored(State.ui.ctx, SPECIAL_COLORS.ok, tostring(State.analysis.result_bpm))
                    end

                    reaper.ImGui_Spacing(State.ui.ctx)
                    reaper.ImGui_Text(State.ui.ctx, "Chroma Profile:")

                    -- Renders dynamic chroma profile chart.
                    local draw_list = reaper.ImGui_GetWindowDrawList(State.ui.ctx)
                    local cur_x, cur_y = reaper.ImGui_GetCursorScreenPos(State.ui.ctx)
                    
                   
                    local avail_w, avail_h = reaper.ImGui_GetContentRegionAvail(State.ui.ctx)
                    local chart_h = math.max(100, avail_h - 20) 

                    reaper.ImGui_Dummy(State.ui.ctx, avail_w, chart_h)

                  
                    local max_val = 0
                    local dominant_idx = 1
                    for i = 1, 12 do 
                        if Analysis.chroma_energy[i] > max_val then
                            max_val = Analysis.chroma_energy[i]
                            dominant_idx = i
                        end
                    end

                
                    local spacing = 2
                    local total_spacing = spacing * 11
                    local bar_w = math.max(10, (avail_w - total_spacing) / 12)
                    
                  
                    local total_chart_w = (bar_w * 12) + total_spacing
                    local offset_x = math.max(0, (avail_w - total_chart_w) / 2)

                    for i = 1, 12 do
                        local val = Analysis.chroma_energy[i] or 0
                        local norm_val = (max_val > 0) and (val / max_val) or 0
                        
                      
                        local min_h = 15
                        local bar_h = math.max(min_h, norm_val * chart_h)

                        local x1 = cur_x + offset_x + (i - 1) * (bar_w + spacing)
                        local y1 = cur_y + chart_h - bar_h
                        local x2 = x1 + bar_w
                        local y2 = cur_y + chart_h

                      
                        local col = SPECIAL_COLORS.accent
                        if i == dominant_idx or norm_val > 0.9 then
                            col = SPECIAL_COLORS.ok
                        end
                        
                        local border_col = (0 << 24) | (0 << 16) | (0 << 8) | 255 

                      
                        reaper.ImGui_DrawList_AddRectFilled(draw_list, x1, y1, x2, y2, col)

                        -- Renders note label with text shadow for readability.
                        local text_w, text_h = reaper.ImGui_CalcTextSize(State.ui.ctx, NOTE_NAMES[i])
                        local text_x = x1 + (bar_w - text_w) / 2
                        local text_y = y2 - text_h - 4
                        local text_col = (255 << 24) | (255 << 16) | (255 << 8) | 255 
                        
                        reaper.ImGui_DrawList_AddText(draw_list, text_x + 1, text_y + 1, border_col, NOTE_NAMES[i])
                        reaper.ImGui_DrawList_AddText(draw_list, text_x, text_y, text_col, NOTE_NAMES[i])
                    end
                end
            end
        end
        
        -- Ends window 
        local ok, err = pcall(reaper.ImGui_End, State.ui.ctx)
        if not ok then
            -- Silent fail for safe docking transitions
        end
    end

    reaper.ImGui_PopFont(State.ui.ctx)
    PopTheme()
end

-- ===========================================================
-- Cleanup & Safety
-- ===========================================================
local function CleanUp()
    -- Prevents memory leaks by destroying pending audio accessors when script exits
    if Analysis.accessor then
        reaper.DestroyAudioAccessor(Analysis.accessor)
        Analysis.accessor = nil
    end
end
reaper.atexit(CleanUp)

-- ===========================================================
-- Main Loop
-- ===========================================================
local function Main()
    if not State.ui.open then return end

    StepAnalysis()
    DrawUI()

    reaper.defer(Main)
end

-- ===========================================================
-- Init
-- ===========================================================
local function Init()
    State.ui.font = reaper.ImGui_CreateFont('sans-serif', UI_CONST.FONT_SIZE)
    reaper.ImGui_Attach(State.ui.ctx, State.ui.font)

    local _, name = GetSelectedItemInfo()
    if name then State.analysis.current_item_name = name end

    reaper.defer(Main)
end

Init()
