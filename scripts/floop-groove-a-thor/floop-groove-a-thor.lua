-- @description Floop Groove-A-Thor
-- @version 1.1.0
-- @author Floop-s
-- @license GPL-3.0
-- @about
--   # Floop Groove-A-Thor
--
--   **Groove Extraction and Injection tool for REAPER.**
--
--   Extract the rhythmic feel (timing and velocity) from any Audio or MIDI source and apply it to any target item (Audio or MIDI) with precision.
--
--   **Key Features:**
--   * Groove Extraction from Audio (transients) or MIDI
--   * Groove Injection with adjustable Timing, Velocity, and Grid Attraction
--   * Phase Coherent Mode for multi-track drum phase preservation
--   * Advanced Visualizer with LOCKED (Groove) and LIVE (Selection) modes
--   * Procedural Groove Generator (Swing, Push/Pull, Velocity Curve)
--   * Groove Library with Bank management
--   * Non-destructive workflow with Undo support
--
-- @changelog
--   + Generator: Added Push/Pull offset and hierarchical Velocity Curve.
--   + Injector: Added Phase Coherent Mode for multi-track drum phase preservation.
--   + Extraction: Added 15ms post-transient RMS lookahead for accurate audio velocity.
--   + Extraction: Added Sanity Check warning for Base Grid mismatch.
--   + Visualizer: Extraction preview fully syncs with real-time UI threshold/sensitivity.
--   + Bugfix: Fixed audio loop boundaries shifting when applying groove.
--   + Bugfix: Added Bank deletion via context menu.
-- @provides
--   [main] floop-groove-a-thor.lua

-- ===========================================================
-- Dependencies
-- ===========================================================
if not reaper.ImGui_CreateContext then
    reaper.ShowMessageBox("ReaImGui API not found!\nPlease install 'ReaImGui' via ReaPack and restart Reaper.", "Error",
        0)
    return
end

-- ===========================================================
-- Configuration
-- ===========================================================
local EXT_NS = "Floop Groove-A-Thor"
local TITLE = "Floop Groove-A-Thor"

-- Global Debug Switch
local DEBUG_MODE = false
local VISUALIZER_MAX_LEN_SEC = 30.0

-- UI Constants
local UI_CONST = {
    SPACING_XS = 5,
    SPACING_SM = 10,
    SPACING_MD = 15,
    BUTTON_H = 30,
    ROUNDING = 6,
    FONT_SIZE = 13,
}

-- Grid Definitions
local GRID_DEFS = {
    { label = "1/4",   val = 1.0 },
    { label = "1/4T",  val = 2 / 3 },
    { label = "1/8",   val = 0.5 },
    { label = "1/8D",  val = 0.75 },
    { label = "1/8T",  val = 1 / 3 },
    { label = "1/16",  val = 0.25 },
    { label = "1/16D", val = 0.375 },
    { label = "1/16T", val = 1 / 6 },
    { label = "1/32",  val = 0.125 },
}

-- Swing Generator Grid Definitions
local GEN_GRID_DEFS = {
    { label = "1/8",  val = 0.5 },
    { label = "1/16", val = 0.25 },
    { label = "1/32", val = 0.125 },
}

-- Theme Colors
local THEME_COLORS = {
    [reaper.ImGui_Col_WindowBg()]          = 0x1e1e23FF,
    [reaper.ImGui_Col_ChildBg()]           = 0x1e1e23FF,
    [reaper.ImGui_Col_PopupBg()]           = 0x1e1e23FF,
    [reaper.ImGui_Col_Text()]              = 0xE8E8E8FF,
    [reaper.ImGui_Col_TextDisabled()]      = 0x7A7A7AFF,
    [reaper.ImGui_Col_TitleBg()]           = 0x1a1a20FF,
    [reaper.ImGui_Col_TitleBgActive()]     = 0x26262dFF,
    [reaper.ImGui_Col_TitleBgCollapsed()]  = 0x1a1a20E6,
    [reaper.ImGui_Col_Button()]            = 0x26262dFF,
    [reaper.ImGui_Col_ButtonHovered()]     = 0x33333dFF,
    [reaper.ImGui_Col_ButtonActive()]      = 0x40404cFF,
    [reaper.ImGui_Col_FrameBg()]           = 0x26262dFF,
    [reaper.ImGui_Col_FrameBgHovered()]    = 0x33333dFF,
    [reaper.ImGui_Col_FrameBgActive()]     = 0x40404cFF,
    [reaper.ImGui_Col_SliderGrab()]        = 0x6FB7B2FF,
    [reaper.ImGui_Col_SliderGrabActive()]  = 0x80C7BFFF,
    [reaper.ImGui_Col_Border()]            = 0x2E2E2EFF,
    [reaper.ImGui_Col_Separator()]         = 0x333333FF,
    [reaper.ImGui_Col_SeparatorHovered()]  = 0x474747FF,
    [reaper.ImGui_Col_SeparatorActive()]   = 0x595959FF,
    [reaper.ImGui_Col_Header()]            = 0x26262dFF,
    [reaper.ImGui_Col_HeaderHovered()]     = 0x33333dFF,
    [reaper.ImGui_Col_HeaderActive()]      = 0x40404cFF,
    [reaper.ImGui_Col_ResizeGrip()]        = 0x6FB7B2FF,
    [reaper.ImGui_Col_ResizeGripHovered()] = 0x80C7BFFF,
    [reaper.ImGui_Col_ResizeGripActive()]  = 0x6FB7B2FF,
    [reaper.ImGui_Col_CheckMark()]         = 0x6FB7B2FF,
}

local SPECIAL_COLORS = {
    accent         = 0x6FB7B2FF,
    warn           = 0xC9A24DFF,
    error          = 0xC84C4CFF,
    ok             = 0x22C55EFF,
    custom_element = 0xD9534FFF,
}

-- System & Item Constants
local OS_SEP = package.config:sub(1, 1)
local ITEM_STATE_KEY = "P_EXT:FLOOP_ORIG_STATE"
local ITEM_LEN_KEY = "P_EXT:FLOOP_ORIG_LEN"
local ITEM_POS_KEY = "P_EXT:FLOOP_ORIG_POS"

-- ===========================================================
-- State
-- ===========================================================
local State = {
    ui = {
        ctx = reaper.ImGui_CreateContext(TITLE),
        font = nil,
        open = true,
        scale = 1.0,

        viz_zoom = 1.0,          -- 1.0 = Fit to width
        viz_scroll = 0.0,        -- 0.0-1.0 Normalized scroll position
        viz_locked = false,      -- Toggle: Lock to Groove Source vs Live Selection
        show_help_modal = false, -- Toggle: Show Help Modal
    },
    settings = {
        debug_mode = false,
    },
    runtime = {
        last_update = 0,
        status = { message = "", details = "", kind = "info", time = 0, duration = 3.0 },
        visualizer_data = {} -- Real-time analysis buffer
    }
}

-- ===========================================================
-- Persistence
-- ===========================================================
local function SaveSettings()
    reaper.SetExtState(EXT_NS, "viz_locked", State.ui.viz_locked and "1" or "0", true)
    reaper.SetExtState(EXT_NS, "viz_zoom", tostring(State.ui.viz_zoom), true)
end

local function LoadSettings()
    if reaper.HasExtState(EXT_NS, "viz_locked") then
        State.ui.viz_locked = reaper.GetExtState(EXT_NS, "viz_locked") == "1"
    end
    if reaper.HasExtState(EXT_NS, "viz_zoom") then
        State.ui.viz_zoom = tonumber(reaper.GetExtState(EXT_NS, "viz_zoom")) or 1.0
    end
end

-- Load on startup
LoadSettings()

-- ===========================================================
-- JSON Library
-- ===========================================================
local json = {}
local json_private = {}
function json.encode(val)
    local b = {}
    json_private.encode(b, val)
    return table.concat(b)
end

function json.decode(s)
    local pos = 1
    return json_private.decode(s, pos)
end

function json_private.encode(b, val)
    local t = type(val)
    if t == "table" then
        local is_list = true
        local n = 0
        for k, v in pairs(val) do
            n = n + 1
            if type(k) ~= "number" or k < 1 or k ~= math.floor(k) then is_list = false end
        end
        if is_list then -- Validate sequential integer indexing
            for i = 1, n do
                if val[i] == nil then
                    is_list = false
                    break
                end
            end
        end

        if is_list then
            b[#b + 1] = "["
            for i = 1, #val do
                if i > 1 then b[#b + 1] = "," end
                json_private.encode(b, val[i])
            end
            b[#b + 1] = "]"
        else
            b[#b + 1] = "{"
            local first = true
            for k, v in pairs(val) do
                if not first then b[#b + 1] = "," end
                first = false
                json_private.encode(b, tostring(k))
                b[#b + 1] = ":"
                json_private.encode(b, v)
            end
            b[#b + 1] = "}"
        end
    elseif t == "string" then
        b[#b + 1] = string.format("%q", val)
    elseif t == "number" or t == "boolean" then
        b[#b + 1] = tostring(val)
    else
        b[#b + 1] = "null"
    end
end

function json_private.skip_white(s, pos)
    while true do
        local c = string.sub(s, pos, pos)
        if c == "" or (c ~= " " and c ~= "\t" and c ~= "\r" and c ~= "\n") then break end
        pos = pos + 1
    end
    return pos
end

function json_private.decode(s, pos)
    pos = json_private.skip_white(s, pos)
    local c = string.sub(s, pos, pos)
    if c == "{" then
        local obj = {}
        pos = pos + 1
        while true do
            pos = json_private.skip_white(s, pos)
            local ch = string.sub(s, pos, pos)
            if ch == "" then return nil, pos end
            if ch == "}" then return obj, pos + 1 end
            local key, next_pos = json_private.decode(s, pos)
            pos = next_pos
            pos = json_private.skip_white(s, pos)
            if string.sub(s, pos, pos) ~= ":" then return nil, pos end -- Error
            pos = pos + 1
            local val, next_pos2 = json_private.decode(s, pos)
            pos = next_pos2
            obj[key] = val
            pos = json_private.skip_white(s, pos)
            local sep = string.sub(s, pos, pos)
            if sep == "," then
                pos = pos + 1
            elseif sep ~= "}" then
                return nil, pos
            end
        end
    elseif c == "[" then
        local arr = {}
        pos = pos + 1
        while true do
            pos = json_private.skip_white(s, pos)
            local ch = string.sub(s, pos, pos)
            if ch == "" then return nil, pos end
            if ch == "]" then return arr, pos + 1 end
            local val, next_pos = json_private.decode(s, pos)
            pos = next_pos
            if val == nil then return nil, pos end
            table.insert(arr, val)
            pos = json_private.skip_white(s, pos)
            local sep = string.sub(s, pos, pos)
            if sep == "," then
                pos = pos + 1
            elseif sep ~= "]" then
                return nil, pos
            end
        end
    elseif c == "\"" then
        local start = pos + 1
        local i = start
        while true do
            local ch = string.sub(s, i, i)
            if ch == "\"" and string.sub(s, i - 1, i - 1) ~= "\\" then break end
            if ch == "" then return nil, pos end
            i = i + 1
        end
        local str = string.sub(s, start, i - 1)
        str = str:gsub('\\"', '"'):gsub('\\\\', '\\'):gsub('\\n', '\n')
        return str, i + 1
    else
        local start = pos
        while true do
            local ch = string.sub(s, pos, pos)
            if ch == "" or ch == "," or ch == "}" or ch == "]" or ch == " " or ch == "\n" then break end
            pos = pos + 1
        end
        local sub = string.sub(s, start, pos - 1)
        if sub == "true" then return true, pos end
        if sub == "false" then return false, pos end
        if sub == "null" then return nil, pos end
        return tonumber(sub), pos
    end
end

-- ===========================================================
-- Utilities
-- ===========================================================
local Logger = {
    level = 1, -- 0=DEBUG, 1=INFO, 2=WARN, 3=ERROR
}

function Logger:log(lvl_name, msg)
    local levels = { DEBUG = 0, INFO = 1, WARN = 2, ERROR = 3 }
    local lvl = levels[lvl_name] or 1

    if DEBUG_MODE then
        local colors = { DEBUG = "xd", INFO = "i", WARN = "!", ERROR = "!!" }
        reaper.ShowConsoleMsg(string.format("[%s] %s\n", lvl_name, msg))
    end
end

function Logger:info(msg) self:log("INFO", msg) end

function Logger:warn(msg) self:log("WARN", msg) end

function Logger:error(msg) self:log("ERROR", msg) end

function Logger:debug(msg) self:log("DEBUG", msg) end

local function dbg(msg)
    Logger:debug(msg)
end

local function summarizeFailureDetails(reason_counts, max_parts)
    local rows = {}
    for reason, count in pairs(reason_counts or {}) do
        rows[#rows + 1] = { reason = tostring(reason), count = count }
    end
    if #rows == 0 then return "" end
    table.sort(rows, function(a, b)
        if a.count == b.count then
            return a.reason < b.reason
        end
        return a.count > b.count
    end)
    local parts = {}
    local limit = math.min(max_parts or 2, #rows)
    for i = 1, limit do
        parts[#parts + 1] = string.format("%s x%d", rows[i].reason, rows[i].count)
    end
    return table.concat(parts, " | ")
end

local function statusSet(msg, kind, duration, details)
    State.runtime.status.message = msg
    State.runtime.status.details = details or ""
    State.runtime.status.kind = kind or "info"
    State.runtime.status.time = reaper.time_precise()
    State.runtime.status.duration = duration or 3.0

    if kind == "error" then
        Logger:error(msg)
    elseif kind == "warn" then
        Logger:warn(msg)
    else
        Logger:info(msg)
    end
end


local function ClearDebugMarkers()
    local _, num_markers, num_regions = reaper.CountProjectMarkers(0)
    local count = num_markers + num_regions
    for i = count - 1, 0, -1 do
        local ok, isrgn, _, _, name, idx_num = reaper.EnumProjectMarkers(i)
        if ok and name and name:match("^G_REF_") then
            reaper.DeleteProjectMarker(0, idx_num, isrgn)
        end
    end
end

local function uiScale(n)
    local s = State.ui.scale or 1.0
    return math.floor(n * s)
end

local function applyThemeBase()
    local count_vars = 0
    reaper.ImGui_PushStyleVar(State.ui.ctx, reaper.ImGui_StyleVar_FrameRounding(), uiScale(UI_CONST.ROUNDING))
    reaper.ImGui_PushStyleVar(State.ui.ctx, reaper.ImGui_StyleVar_WindowRounding(), uiScale(8))
    reaper.ImGui_PushStyleVar(State.ui.ctx, reaper.ImGui_StyleVar_WindowPadding(), uiScale(10), uiScale(10))
    reaper.ImGui_PushStyleVar(State.ui.ctx, reaper.ImGui_StyleVar_ItemSpacing(), uiScale(8), uiScale(8))
    count_vars = 4
    local count_colors = 0
    for id, color in pairs(THEME_COLORS) do
        reaper.ImGui_PushStyleColor(State.ui.ctx, id, color)
        count_colors = count_colors + 1
    end
    return count_colors, count_vars
end

local function endTheme(count_colors, count_vars)
    if count_colors > 0 then reaper.ImGui_PopStyleColor(State.ui.ctx, count_colors) end
    if count_vars > 0 then reaper.ImGui_PopStyleVar(State.ui.ctx, count_vars) end
end


-- ===========================================================
-- Groove Cache (Non-Destructive)
-- ===========================================================
local GrooveCache = {
    data = {}
}

local function hashInit()
    return 2166136261
end

local function hashAddInt(h, n)
    local v = math.floor(tonumber(n) or 0)
    h = (h ~ v) % 4294967296
    h = (h * 16777619) % 4294967296
    return h
end

local function hashAddFloat(h, n, scale)
    local s = scale or 100000
    local v = math.floor(((tonumber(n) or 0) * s) + 0.5)
    return hashAddInt(h, v)
end

local function buildTakeSignature(take)
    local item = reaper.GetMediaItemTake_Item(take)
    if not item then return nil end

    local is_midi = reaper.TakeIsMIDI(take)
    local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local item_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    local start_offs = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
    local play_rate = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
    local h = hashInit()

    h = hashAddInt(h, is_midi and 1 or 2)
    h = hashAddFloat(h, item_pos, 1000000)
    h = hashAddFloat(h, item_len, 1000000)
    h = hashAddFloat(h, start_offs, 1000000)
    h = hashAddFloat(h, play_rate, 1000000)

    local count = 0
    if is_midi then
        local _, note_count = reaper.MIDI_CountEvts(take)
        count = note_count or 0
        h = hashAddInt(h, count)
        for i = 0, count - 1 do
            local rv, _, muted, startppq, endppq, chan, pitch, vel = reaper.MIDI_GetNote(take, i)
            if rv then
                h = hashAddFloat(h, startppq, 10)
                h = hashAddFloat(h, endppq, 10)
                h = hashAddInt(h, chan)
                h = hashAddInt(h, pitch)
                h = hashAddInt(h, vel)
                h = hashAddInt(h, muted and 1 or 0)
            end
        end
    else
        local marker_count = reaper.GetTakeNumStretchMarkers(take) or 0
        count = marker_count
        h = hashAddInt(h, count)
        for i = 0, count - 1 do
            local rv, pos, src_pos = reaper.GetTakeStretchMarker(take, i)
            if rv then
                h = hashAddFloat(h, pos, 1000000)
                h = hashAddFloat(h, src_pos, 1000000)
            end
        end
    end

    return {
        kind = is_midi and "MIDI" or "AUDIO",
        count = count,
        hash = h
    }
end

function GrooveCache:getTakeGUID(take)
    local _, guid = reaper.GetSetMediaItemTakeInfo_String(take, "GUID", "", false)
    return guid
end

function GrooveCache:clear(take)
    local guid = self:getTakeGUID(take)
    self.data[guid] = nil
end

function GrooveCache:clearAll()
    self.data = {}
    statusSet("Groove Cache Cleared", "warn")
end

function GrooveCache:ensure(take)
    local guid = self:getTakeGUID(take)
    local valid = false
    if self.data[guid] then
        local cached = self.data[guid]
        local current_sig = buildTakeSignature(take)
        if current_sig and cached.signature then
            if current_sig.kind == cached.signature.kind and
                current_sig.count == cached.signature.count and
                current_sig.hash == cached.signature.hash then
                valid = true
            end
        end
    end

    if not valid then
        self:snapshot(take, guid)
    end
    return self.data[guid]
end

function GrooveCache:snapshot(take, guid)
    local item = reaper.GetMediaItemTake_Item(take)
    local item_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local start_qn = reaper.TimeMap2_timeToQN(0, item_start)
    local signature = buildTakeSignature(take)

    local entry = {
        count = 0,
        events = {},
        signature = signature
    }

    if reaper.TakeIsMIDI(take) then
        local _, note_count = reaper.MIDI_CountEvts(take)
        entry.count = note_count
        for i = 0, note_count - 1 do
            local _, sel, muted, startppq, endppq, chan, pitch, vel = reaper.MIDI_GetNote(take, i)
            local note_qn = reaper.MIDI_GetProjQNFromPPQPos(take, startppq)
            local end_qn = reaper.MIDI_GetProjQNFromPPQPos(take, endppq)
            table.insert(entry.events, {
                idx = i,
                orig_qn = note_qn,
                orig_len = end_qn - note_qn,
                orig_vel = vel,
                pitch = pitch,
                chan = chan,
                sel = sel,
                muted = muted
            })
        end
    else
        local count = reaper.GetTakeNumStretchMarkers(take)
        entry.count = count
        for i = 0, count - 1 do
            local _, pos, src_pos = reaper.GetTakeStretchMarker(take, i)
            local abs_time = item_start + pos
            local marker_qn = reaper.TimeMap2_timeToQN(0, abs_time)
            table.insert(entry.events, {
                idx = i,
                orig_qn = marker_qn,
                src_pos = src_pos,
                orig_time_offset = pos
            })
        end
    end
    self.data[guid] = entry
end

-- ===========================================================
-- Time Domain Helper
-- ===========================================================
local TimeContext = {}
TimeContext.__index = TimeContext

function TimeContext.new(item, take)
    local self = setmetatable({}, TimeContext)
    self.item = item
    self.take = take
    self.item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    self.start_offs = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
    self.play_rate = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
    return self
end

function TimeContext:getVirtualStartTime()
    if self.play_rate == 0 then return self.item_pos end -- Safety
    return self.item_pos - (self.start_offs / self.play_rate)
end

function TimeContext:getVirtualStartQN()
    local v_start = self:getVirtualStartTime()
    return reaper.TimeMap2_timeToQN(0, v_start)
end

-- ===========================================================
-- Groove Core Logic
-- ===========================================================
local GrooveCore = {
    pool = {},
    banks = {},         -- list of folder names
    current_bank = nil, -- current folder name (nil = root)

    current_groove_index = nil,
    selected_indices = {},
    last_clicked_index = nil,

    extraction = {
        sensitivity = 0.5,
        threshold_db = -30.0,
        grid_base = 0.25,
        velocity_min = 10,
        hpf_hz = 0.0,
        lpf_hz = 0.0,
    },

    application = {
        global_intensity = 1.0,
        timing_amount = 1.0,
        velocity_amount = 1.0,
        quantize_amount = 0.0,
        window_ms = 50,
        target_grid = 0, -- 0=All, 0.5=1/8, 0.25=1/16, etc.

        audio_max_db = 6.0,
        audio_pre_ms = 15,
        audio_post_ms = 50,
        audio_shape = 5,
        audio_apply_volume = false,
    }
}

local function getRelativeOffset(pos_qns, grid_qns)
    local perfect_grid_pos = math.floor(pos_qns / grid_qns + 0.5) * grid_qns
    return pos_qns - perfect_grid_pos
end

local function GetClosestGridQuantized(pos_qn, division)
    return math.floor(pos_qn / division + 0.5) * division
end

local function GetHeuristicGridPos(pos_qn, base_division)
    local straight_div = base_division
    local triplet_div = base_division * (2/3)
    
    local pos_straight = math.floor(pos_qn / straight_div + 0.5) * straight_div
    local dist_straight = math.abs(pos_qn - pos_straight)
    
    local pos_triplet = math.floor(pos_qn / triplet_div + 0.5) * triplet_div
    local dist_triplet = math.abs(pos_qn - pos_triplet)
    
    if dist_triplet < (dist_straight * 0.9) then
        return pos_triplet, pos_qn - pos_triplet
    else
        return pos_straight, pos_qn - pos_straight
    end
end

function GrooveCore:addGroove(groove, no_select)
    table.insert(self.pool, groove)
    if not no_select then
        self.current_groove_index = #self.pool
        self.selected_indices = { [self.current_groove_index] = true }
        self.last_clicked_index = self.current_groove_index
    end
end

function GrooveCore:deleteSelectedGrooves()
    local to_delete = {}
    for i, _ in pairs(self.selected_indices) do
        table.insert(to_delete, i)
    end
    table.sort(to_delete, function(a, b) return a > b end)

    local count = 0
    local path = self:getGroovePath()
    local path_ok = path ~= nil
    for _, idx in ipairs(to_delete) do
        local groove = self.pool[idx]
        if groove then
            if path_ok then
                local filename = groove.name:gsub("[^%w%-_%s]", "") .. ".gat"
                local fullpath = path .. filename
                local ok_rm, rm_err = os.remove(fullpath)
                if not ok_rm then
                    Logger:warn("deleteSelectedGrooves: failed to remove file: " ..
                        tostring(fullpath) .. " (" .. tostring(rm_err) .. ")")
                end
            end
            table.remove(self.pool, idx)
            count = count + 1
        end
    end

    self.selected_indices = {}
    self.current_groove_index = nil
    self.last_clicked_index = nil
    if count > 0 then
        if not path_ok then
            statusSet("Deleted grooves from pool, but could not remove files on disk.", "warn")
        else
            statusSet("Deleted " .. count .. " grooves", "warn")
        end
    end
end

function GrooveCore:renameGroove(index, new_name)
    local groove = self.pool[index]
    if not groove then return false, "Invalid groove" end

    new_name = new_name:match("^%s*(.-)%s*$")
    if new_name == "" then return false, "Name cannot be empty" end
    if new_name == groove.name then return true end

    local safe_new_name = new_name:gsub("[^%w%-_%s]", "")
    if safe_new_name == "" then return false, "Invalid characters in name" end

    local path = self:getGroovePath()
    if not path then
        Logger:error("renameGroove failed: script path not found")
        return false, "Script path not found"
    end
    local new_filename = safe_new_name .. ".gat"
    local old_filename = groove.name:gsub("[^%w%-_%s]", "") .. ".gat"

    if new_filename ~= old_filename and reaper.file_exists(path .. new_filename) then
        return false, "Groove with this name already exists"
    end

    local old_fullpath = path .. old_filename
    local ok_rm, rm_err = os.remove(old_fullpath)
    if not ok_rm then
        Logger:warn("renameGroove: failed to remove old file: " ..
            tostring(old_fullpath) .. " (" .. tostring(rm_err) .. ")")
    end

    groove.name = new_name
    local saved, err = self:saveGrooveToDisk(groove)
    if not saved then return false, "Failed to save: " .. (err or "unknown") end

    return true
end

function GrooveCore:importAndAnalyzeFile(filepath)
    if not filepath then return end
    local ext = filepath:match("%.([^%.]+)$")
    if ext then ext = ext:lower() end
    if ext == "gat" then
        local ok, err = self:loadGrooveFile(filepath)
        if ok then
            statusSet("Groove loaded: " .. filepath:match("([^/\\]+)$"), "ok")
        else
            statusSet("Groove import failed: " .. (err or "unknown"), "error")
        end
        return
    end

    reaper.PreventUIRefresh(1)
    reaper.InsertTrackAtIndex(reaper.CountTracks(0), false)
    local tr = reaper.GetTrack(0, reaper.CountTracks(0) - 1)
    local item = reaper.AddMediaItemToTrack(tr)
    local take = reaper.AddTakeToMediaItem(item)
    local src = reaper.PCM_Source_CreateFromFile(filepath)
    if not src then
        reaper.DeleteTrack(tr)
        reaper.PreventUIRefresh(-1)
        statusSet("Failed to load source", "error")
        return
    end
    reaper.SetMediaItemTake_Source(take, src)
    local src_len, is_qn = reaper.GetMediaSourceLength(src)
    local len_sec = 4.0
    if is_qn then len_sec = reaper.TimeMap2_QNToTime(0, src_len) else len_sec = src_len end
    reaper.SetMediaItemInfo_Value(item, "D_LENGTH", len_sec)

    local g, err = self:analyzeSelection(item)
    reaper.DeleteTrack(tr)
    reaper.PreventUIRefresh(-1)
    if g then
        self:addGroove(g)
        statusSet("Imported: " .. g.name, "ok")
    else
        statusSet("Import failed: " .. (err or "unknown"), "error")
    end
end

function GrooveCore:getCurrentGroove()
    if not self.current_groove_index then return nil end
    return self.pool[self.current_groove_index]
end

function GrooveCore:detectTransients(take, max_len)
    local item = reaper.GetMediaItemTake_Item(take)
    local item_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local item_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    
    local analyze_len = item_len
    if max_len and analyze_len > max_len then analyze_len = max_len end

    local transients = {}
    local accessor = reaper.CreateTakeAudioAccessor(take)
    local src = reaper.GetMediaItemTake_Source(take)
    local samplerate = reaper.GetMediaSourceSampleRate(src)
    if samplerate == 0 then samplerate = 44100 end
    local channels = reaper.GetMediaSourceNumChannels(src)
    local buffer_size = 4096
    local buffer = reaper.new_array(buffer_size * channels)

    local bpm = reaper.TimeMap2_GetDividedBpmAtTime(0, item_start)
    local lockout_qn = 0.0625 -- 1/64 note
    local lockout_sec = (60 / bpm) * lockout_qn
    local lockout_samples = math.floor(lockout_sec * samplerate)

    local rms_window_size = 1024
    local current_rms = 0.001
    local env_fast = 0.0
    local prev_env_fast = 0.0
    
    -- Map sensitivity (0.0-1.0) to threshold multiplier (3.5-1.3) to prevent saturation.
    local sensitivity_mult = 3.5 - ((self.extraction.sensitivity or 0.5) * 2.2)

    local threshold_db = self.extraction.threshold_db or -30.0
    local threshold_lin = 10 ^ (threshold_db / 20)

    local total_samples = math.floor(analyze_len * samplerate)
    local sample_pos = 0
    local last_transient_sample = -lockout_samples * 2

    local hpf_fc = (self.extraction.hpf_hz or 0.0)
    local lpf_fc = (self.extraction.lpf_hz or 0.0)
    local hpf_a = 0.0
    local lpf_a = 0.0
    if hpf_fc > 0.0 then
        local x = math.exp(-2.0 * math.pi * hpf_fc / samplerate)
        hpf_a = x
    end
    if lpf_fc > 0.0 then
        local x = math.exp(-2.0 * math.pi * lpf_fc / samplerate)
        lpf_a = x
    end
    local hpf_z = {}
    local lpf_z = {}
    for c = 1, channels do
        hpf_z[c] = 0.0
        lpf_z[c] = 0.0
    end

    while sample_pos < total_samples do
        local chunk_size = math.min(buffer_size, total_samples - sample_pos)
        if chunk_size <= 0 then break end

        local rv = reaper.GetAudioAccessorSamples(accessor, samplerate, channels, sample_pos / samplerate, chunk_size,
            buffer)
        if not rv then break end

        local i = 1
        while i <= chunk_size do
            local abs_val = 0
            for c = 1, channels do
                local val = buffer[(i - 1) * channels + c] or 0.0

                if hpf_fc > 0.0 then
                    local z = hpf_z[c]
                    local lpf_comp = (1.0 - hpf_a) * val + hpf_a * z
                    hpf_z[c] = lpf_comp
                    val = val - lpf_comp
                end
                if lpf_fc > 0.0 then
                    local z = lpf_z[c]
                    z = lpf_a * z + (1.0 - lpf_a) * val
                    lpf_z[c] = z
                    val = z
                end

                abs_val = abs_val + math.abs(val)
            end
            abs_val = abs_val / channels

            if abs_val > env_fast then
                env_fast = abs_val
            else
                env_fast = env_fast * 0.999
            end

            current_rms = (current_rms * 0.9999) + (abs_val * 0.0001)

            local dynamic_thresh = math.max(threshold_lin, current_rms * sensitivity_mult)

            if env_fast > dynamic_thresh and prev_env_fast <= dynamic_thresh then
                local current_abs_sample = sample_pos + i
                if current_abs_sample > last_transient_sample + lockout_samples then
                    local time_in_item = current_abs_sample / samplerate
                    local abs_time = item_start + time_in_item
                    table.insert(transients, { time = abs_time, val = env_fast })
                    last_transient_sample = current_abs_sample
                end
            end
            prev_env_fast = env_fast
            i = i + 1
        end
        sample_pos = sample_pos + chunk_size
    end

    -- Second pass: Post-transient RMS calculation for accurate velocity
    local window_ms = 15.0 -- 15ms lookahead window
    local window_samples = math.floor((window_ms / 1000.0) * samplerate)
    local rms_buffer = reaper.new_array(window_samples * channels)
    local max_rms = 0.0

    for _, t in ipairs(transients) do
        local time_in_item = t.time - item_start
        local rv = reaper.GetAudioAccessorSamples(accessor, samplerate, channels, time_in_item, window_samples, rms_buffer)
        
        local hit_rms = 0.0
        if rv and rv > 0 then
            local sum_sq = 0.0
            local count = rv * channels
            for i = 1, count do
                local s = rms_buffer[i]
                sum_sq = sum_sq + (s * s)
            end
            hit_rms = math.sqrt(sum_sq / count)
        else
            hit_rms = t.val
        end
        
        t.val = hit_rms
        if hit_rms > max_rms then max_rms = hit_rms end
    end

    if max_rms > 0 then
        for _, t in ipairs(transients) do
            t.val = t.val / max_rms
        end
    end

    reaper.DestroyAudioAccessor(accessor)
    return transients
end

function GrooveCore:analyzeSelection(target_item)
    local item = target_item or reaper.GetSelectedMediaItem(0, 0)
    if not item then return nil, "No item selected" end
    local take = reaper.GetActiveTake(item)
    if not take then return nil, "No active take" end

    local groove = {
        name = reaper.GetTakeName(take) .. " Groove",
        grid_base = self.extraction.grid_base,
        points = {},
        source_type = "UNKNOWN",
        length_beats = 0
    }

    local item_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local item_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")

    if item_len > VISUALIZER_MAX_LEN_SEC then
        return nil, "Selected item exceeds allowed loop length for extraction"
    end

    local start_qn = reaper.TimeMap2_timeToQN(0, item_start)
    local end_qn = reaper.TimeMap2_timeToQN(0, item_start + item_len)
    groove.length_beats = end_qn - start_qn

    if reaper.TakeIsMIDI(take) then
        groove.source_type = "MIDI"
        local _, note_count = reaper.MIDI_CountEvts(take)
        for i = 0, note_count - 1 do
            local _, _, _, startppq, _, chan, pitch, vel = reaper.MIDI_GetNote(take, i)
            local note_qn = reaper.MIDI_GetProjQNFromPPQPos(take, startppq)
            local pos_qn_rel = note_qn - start_qn
            local grid_pos, offset = GetHeuristicGridPos(pos_qn_rel, groove.grid_base)
            table.insert(groove.points, {
                pos_qn = grid_pos,
                offset = offset,
                velocity = vel / 127,
                vel_delta = vel - 100,
                raw_vel = vel,
                pitch = pitch,
                chan = chan
            })
        end
    else
        groove.source_type = "AUDIO"
        local num_markers = reaper.GetTakeNumStretchMarkers(take)
        if num_markers > 0 then
            for i = 0, num_markers - 1 do
                local _, pos, src_pos = reaper.GetTakeStretchMarker(take, i)
                local abs_time = item_start + pos
                local marker_qn = reaper.TimeMap2_timeToQN(0, abs_time)
                local pos_qn_rel = marker_qn - start_qn
                local grid_pos, offset = GetHeuristicGridPos(pos_qn_rel, groove.grid_base)
                table.insert(groove.points, {
                    pos_qn = grid_pos,
                    offset = offset,
                    velocity = 1.0,
                    vel_delta = 0,
                    raw_vel = 100
                })
            end
        else
            local transients = self:detectTransients(take)
            for _, t in ipairs(transients) do
                local marker_qn = reaper.TimeMap2_timeToQN(0, t.time)
                local pos_qn_rel = marker_qn - start_qn
                local grid_pos, offset = GetHeuristicGridPos(pos_qn_rel, groove.grid_base)
                local val_lin = math.max(0.000001, t.val)
                local db = 20 * math.log(val_lin, 10)
                local raw_vel = math.floor(127 * (1 + (db / 60)))
                raw_vel = math.max(1, math.min(127, raw_vel))
                local vel_delta = raw_vel - 100
                table.insert(groove.points, {
                    pos_qn = grid_pos,
                    offset = offset,
                    velocity = raw_vel / 127,
                    vel_delta = vel_delta,
                    raw_vel = raw_vel
                })
            end
        end
    end

    if #groove.points == 0 then return nil, "No notes/transients found." end

    local total_abs_offset = 0
    for _, p in ipairs(groove.points) do
        total_abs_offset = total_abs_offset + math.abs(p.offset)
    end
    local avg_offset = total_abs_offset / #groove.points
    if avg_offset > (groove.grid_base * 0.25) then
        statusSet("Warning: Large timing offsets detected. Verify Base Grid matches audio (e.g. Triplets).", "warn")
    end

    return groove, "Success"
end

function GrooveCore:generateSwingGroove(grid_base, swing_percent, push_pull, dynamics, preview_only)
    local grid_name = "16"
    for _, g in ipairs(GEN_GRID_DEFS) do
        if math.abs(grid_base - g.val) < 0.001 then
            grid_name = string.gsub(g.label, "1/", "")
            break
        end
    end
    
    local name = string.format("Swing %s %.0f%%", grid_name, swing_percent * 100)
    if preview_only then name = "PREVIEW: " .. name end

    push_pull = push_pull or 0.0
    dynamics = dynamics or 0.0

    local groove = {
        name = name,
        grid_base = grid_base,
        points = {},
        source_type = "GENERATED",
        length_beats = 4.0
    }
    local num_steps = math.floor(groove.length_beats / grid_base + 0.5)
    
    local function is_close_to_grid(p, div)
        local nearest = math.floor(p / div + 0.5) * div
        return math.abs(p - nearest) < 0.001
    end

    for index = 0, num_steps - 1 do
        local pos = index * grid_base
        local offset = 0
        
        -- Apply swing offset (off-beats only).
        if index % 2 == 1 then offset = grid_base * (2 * swing_percent - 1) end
        
        -- Apply global push/pull offset.
        offset = offset + (grid_base * push_pull)

        -- Calculate hierarchical velocity.
        local vel = 1.0
        if dynamics > 0 then
            if is_close_to_grid(pos, 1.0) then
                vel = 1.0 -- Downbeat.
            elseif is_close_to_grid(pos, 0.5) then
                vel = 1.0 - dynamics * 0.2 -- 8th note
            elseif is_close_to_grid(pos, 0.25) then
                vel = 1.0 - dynamics * 0.4 -- 16th note
            elseif is_close_to_grid(pos, 0.125) then
                vel = 1.0 - dynamics * 0.6 -- 32nd note
            else
                vel = 1.0 - dynamics * 0.5 -- Subdivisions.
            end
        end

        table.insert(groove.points, {
            pos_qn = pos,
            offset = offset,
            velocity = vel,
            vel_delta = 0,
            raw_vel = math.floor(vel * 127 + 0.5)
        })
    end

    if not preview_only then
        self:addGroove(groove)
        self:saveGrooveToDisk(groove)
    end
    return groove
end

function GrooveCore:getScriptPath()
    local info = debug.getinfo(1, "S")
    local src = info and info.source or ""
    local path = src:match("@?(.*[\\/])")
    if not path or path == "" then
        Logger:error("Unable to determine script path from debug info: " .. tostring(src))
        return nil
    end
    return path
end

function GrooveCore:getGroovePath()
    local base = self:getScriptPath()
    if not base then return nil end
    local root = base .. "Grooves" .. OS_SEP
    if self.current_bank then
        return root .. self.current_bank .. OS_SEP
    end
    return root
end

function GrooveCore:getGrooveRootPath()
    local base = self:getScriptPath()
    if not base then return nil end
    return base .. "Grooves" .. OS_SEP
end

function GrooveCore:refreshBanks()
    local root = self:getGrooveRootPath()
    if not root then return end

    self.banks = {}
    local i = 0
    while true do
        local subdir = reaper.EnumerateSubdirectories(root, i)
        if not subdir then break end
        if subdir ~= "." and subdir ~= ".." then
            table.insert(self.banks, subdir)
        end
        i = i + 1
    end
    table.sort(self.banks)
end

function GrooveCore:createBank(name)
    local root = self:getGrooveRootPath()
    if not root then return false, "No script path" end

    local safe_name = name:gsub("[^%w%-_%s]", "")
    if safe_name == "" then return false, "Invalid name" end

    local new_dir = root .. safe_name
    reaper.RecursiveCreateDirectory(new_dir, 0)

    self:refreshBanks()
    self.current_bank = safe_name
    self.pool = {} -- Switch to empty new bank
    return true
end

function GrooveCore:deleteBank(name)
    local root = self:getGrooveRootPath()
    if not root then return false, "No script path" end

    if not name or name == "" then return false, "Invalid name" end
    if name:find("[/\\]") then return false, "Invalid name" end

    local dir_to_remove = root .. name

    local ok
    if OS_SEP == "\\" then
        ok = os.execute('cmd /C rmdir /S /Q "' .. dir_to_remove .. '"')
    else
        ok = os.execute('rm -rf "' .. dir_to_remove .. '"')
    end
    if ok ~= true and ok ~= 0 then return false, "No such file or directory" end

    if self.current_bank == name then
        self.current_bank = nil
        self.pool = {}
        self.selected_indices = {}
        self.current_groove_index = nil
        self.last_clicked_index = nil
    end

    self:refreshBanks()
    return true
end

function GrooveCore:moveGroove(index, target_bank)
    local groove = self.pool[index]
    if not groove then return false, "Invalid groove" end

    local source_path = self:getGroovePath()
    if not source_path then return false, "No source path" end

    local filename = groove.name:gsub("[^%w%-_%s]", "") .. ".gat"
    local source_file = source_path .. filename

    local root = self:getGrooveRootPath()
    local target_path
    if target_bank then
        target_path = root .. target_bank .. OS_SEP
    else
        target_path = root
    end

    local target_file = target_path .. filename

    local f_check = io.open(target_file, "r")
    if f_check then
        f_check:close()
        return false, "File exists in target"
    end

    local ok, err = os.rename(source_file, target_file)
    if not ok then
        local f_in = io.open(source_file, "rb")
        if not f_in then return false, "Cannot read source" end
        local content = f_in:read("*a")
        f_in:close()

        local f_out = io.open(target_file, "wb")
        if not f_out then return false, "Cannot write target" end
        f_out:write(content)
        f_out:close()

        os.remove(source_file)
    end

    return true
end

function GrooveCore:saveGrooveToDisk(groove)
    local path = self:getGroovePath()
    if not path then
        statusSet("Cannot determine script path. Saving grooves is disabled.", "error")
        Logger:error("saveGrooveToDisk failed: script path not found")
        return false, "Script path not found"
    end
    reaper.RecursiveCreateDirectory(path, 0)
    local filename = groove.name:gsub("[^%w%-_%s]", "") .. ".gat"
    local fullpath = path .. filename
    local f, err = io.open(fullpath, "w")
    if not f then
        Logger:error("saveGrooveToDisk failed: cannot open file: " .. tostring(fullpath) .. " (" .. tostring(err) .. ")")
        return false, "Cannot open file"
    end

    local export_data = {
        version = "1.1.0",
        created_at = os.time(),
        name = groove.name,
        source_type = groove.source_type,
        length_beats = groove.length_beats,
        grid_base = groove.grid_base or 0.25,
        points = {}
    }

    for _, p in ipairs(groove.points) do
        table.insert(export_data.points, {
            pos = p.pos_qn,
            offs = p.offset,
            vel = p.velocity or 0,
            v_delta = p.vel_delta or 0,
            raw = p.raw_vel or 100,
            pitch = p.pitch or -1
        })
    end

    local ok_enc, str = pcall(json.encode, export_data)
    if not ok_enc or not str then
        Logger:error("saveGrooveToDisk failed: JSON encode error for groove " .. tostring(groove.name))
        f:close()
        return false, "JSON encode failed"
    end
    local ok_write, write_err = f:write(str)
    if not ok_write then
        Logger:error("saveGrooveToDisk failed: write error for file: " ..
            tostring(fullpath) .. " (" .. tostring(write_err) .. ")")
        f:close()
        return false, "Write failed"
    end
    f:close()
    Logger:info("Saved groove to disk: " .. tostring(fullpath))
    return true
end

function GrooveCore:loadGroovesFromDisk()
    local path = self:getGroovePath()
    if not path then
        statusSet("Cannot determine script path. Groove auto-load is disabled.", "error")
        Logger:error("loadGroovesFromDisk aborted: script path not found")
        return
    end

    self:refreshBanks()

    self.pool = {}
    local loaded, failed = 0, 0
    local i = 0
    while true do
        local file = reaper.EnumerateFiles(path, i)
        if not file then break end
        if file:match("%.gat$") then
            local ok, err = self:loadGrooveFile(path .. file, true)
            if ok then
                loaded = loaded + 1
            else
                failed = failed + 1
                Logger:error("Failed to load groove file '" .. tostring(file) .. "': " .. tostring(err))
            end
        end
        i = i + 1
    end

    self.selected_indices = {}
    self.current_groove_index = nil

    if loaded > 0 then
        Logger:info("Loaded " .. loaded .. " groove(s) from " .. (self.current_bank or "Root"))
    end
end

function GrooveCore:loadGrooveFile(filepath, no_select)
    local f, err = io.open(filepath, "rb")
    if not f then
        Logger:error("loadGrooveFile failed: cannot open file: " .. tostring(filepath) .. " (" .. tostring(err) .. ")")
        if not no_select then
            statusSet("Failed to open groove file", "error")
        end
        return false, "Cannot open file"
    end
    local size = f:seek("end")
    if not size then
        Logger:error("loadGrooveFile failed: cannot determine file size for " .. tostring(filepath))
        f:close()
        if not no_select then
            statusSet("Failed to read groove file (size error)", "error")
        end
        return false, "Size error"
    end
    if size > 1024 * 1024 then
        Logger:error("loadGrooveFile aborted: file too large (" .. tostring(size) .. " bytes): " .. tostring(filepath))
        f:close()
        if not no_select then
            statusSet("Groove file too large (corrupted?)", "error")
        end
        return false, "File too large"
    end
    f:seek("set", 0)
    local content = f:read("*all")
    f:close()

    if not content or content == "" then
        Logger:error("loadGrooveFile failed: empty file: " .. tostring(filepath))
        if not no_select then
            statusSet("Groove file is empty", "error")
        end
        return false, "Empty file"
    end

    local groove = { points = {} }

    local first_char = content:match("^%s*(.)")

    if first_char == "{" then
        local ok_dec, data = pcall(json.decode, content)
        if not ok_dec or not data then
            Logger:error("Failed to decode JSON groove: " .. tostring(filepath))
            if not no_select then
                statusSet("Failed to read groove file (JSON error)", "error")
            end
            return false, "JSON decode failed"
        end
        groove.name = data.name
        groove.source_type = data.source_type
        groove.length_beats = tonumber(data.length_beats)
        groove.grid_base = tonumber(data.grid_base)

        if data.points then
            for _, p in ipairs(data.points) do
                table.insert(groove.points, {
                    pos_qn = tonumber(p.pos),
                    offset = tonumber(p.offs),
                    velocity = tonumber(p.vel),
                    vel_delta = tonumber(p.v_delta),
                    raw_vel = tonumber(p.raw),
                    pitch = tonumber(p.pitch)
                })
            end
        end
        Logger:info("Loaded JSON groove: " .. (groove.name or "???"))
    else
        Logger:info("Loading legacy groove: " .. filepath)
        for line in content:gmatch("[^\r\n]+") do
            local k, v = line:match("^(%w+):(.*)$")
            if k == "name" then
                groove.name = v
            elseif k == "source" then
                groove.source_type = v
            elseif k == "len" then
                groove.length_beats = tonumber(v)
            elseif k == "grid" then
                groove.grid_base = tonumber(v)
            elseif k == "p" then
                local parts = {}
                for part in v:gmatch("[^,]+") do parts[#parts + 1] = part end
                local g_pos, o = tonumber(parts[1]), tonumber(parts[2])
                if g_pos and o then
                    table.insert(groove.points, {
                        pos_qn = g_pos,
                        offset = o,
                        velocity = tonumber(parts[3]),
                        vel_delta = tonumber(parts[4]),
                        raw_vel = tonumber(parts[5]) or 100,
                        pitch = tonumber(parts[6])
                    })
                end
            end
        end
    end

    if not groove.grid_base then groove.grid_base = 0.25 end
    if not groove.name then
        Logger:error("loadGrooveFile failed: missing groove name in file " .. tostring(filepath))
        if not no_select then
            statusSet("Groove file is invalid (no name)", "error")
        end
        return false, "Invalid groove file"
    end
    self:addGroove(groove, no_select)
    return true, nil
end

function GrooveCore:saveOriginalState(item)
    if not item then return end

    local has_backup, backup_chunk = reaper.GetSetMediaItemInfo_String(item, ITEM_STATE_KEY, "", false)
    if has_backup and backup_chunk and backup_chunk ~= "" then return end

    local ok_chunk, chunk = reaper.GetItemStateChunk(item, "", false)
    if not ok_chunk or not chunk or chunk == "" then
        statusSet("Backup failed: cannot read item state", "error")
        return
    end

    chunk = chunk:gsub("GUID %{.-%}\n", "")

    reaper.GetSetMediaItemInfo_String(item, ITEM_STATE_KEY, chunk, true)

    local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    reaper.GetSetMediaItemInfo_String(item, ITEM_LEN_KEY, tostring(len), true)
    reaper.GetSetMediaItemInfo_String(item, ITEM_POS_KEY, tostring(pos), true)
end

function GrooveCore:restoreOriginalState(item)
    if not item then return false, "No item" end

    ClearDebugMarkers()

    local ok, chunk = reaper.GetSetMediaItemInfo_String(item, ITEM_STATE_KEY, "", false)
    if not ok or chunk == "" then return false, "No backup found" end

    local set_ok = reaper.SetItemStateChunk(item, chunk, false)
    if not set_ok then return false, "Chunk restore failed" end

    reaper.UpdateItemInProject(item)
    reaper.UpdateArrange()
    return true, "Restored"
end

function GrooveCore:restoreOriginalSelection()
    local selected_count = reaper.CountSelectedMediaItems(0)
    if selected_count == 0 then return nil, "No items selected" end

    ClearDebugMarkers()

    local success_count = 0
    local failed_count = 0
    local first_error = nil
    local fail_reasons = {}

    for i = 0, selected_count - 1 do
        local item = reaper.GetSelectedMediaItem(0, i)
        if item then
            local ok, chunk = reaper.GetSetMediaItemInfo_String(item, ITEM_STATE_KEY, "", false)
            if ok and chunk and chunk ~= "" then
                local set_ok = reaper.SetItemStateChunk(item, chunk, false)
                if set_ok then
                    reaper.UpdateItemInProject(item)
                    success_count = success_count + 1
                else
                    failed_count = failed_count + 1
                    local reason = "Chunk restore failed"
                    fail_reasons[reason] = (fail_reasons[reason] or 0) + 1
                    if not first_error then first_error = reason end
                end
            else
                failed_count = failed_count + 1
                local reason = "No backup found"
                fail_reasons[reason] = (fail_reasons[reason] or 0) + 1
                if not first_error then first_error = reason end
            end
        else
            failed_count = failed_count + 1
            local reason = "Invalid selected item"
            fail_reasons[reason] = (fail_reasons[reason] or 0) + 1
            if not first_error then first_error = reason end
        end
    end

    reaper.UpdateArrange()
    local details = summarizeFailureDetails(fail_reasons, 2)

    if success_count == 0 then
        return nil, first_error or "Restore failed on all selected items", failed_count, details
    end
    if failed_count > 0 then
        return true, string.format("Restored %d item(s), %d failed", success_count, failed_count), failed_count, details
    end
    return true, string.format("Restored %d item(s)", success_count), 0, ""
end

function GrooveCore:_findBestMatch(groove, target_qn_abs, pitch, item_pos, start_qn)
    if DEBUG_MODE then
        local rel_qn = target_qn_abs - start_qn
        dbg(string.format("getGroovePoint: TargetAbsQN: %.3f | RelQN: %.3f | Pitch: %s",
            target_qn_abs, rel_qn, tostring(pitch)))
    end

    local loop_pos = (target_qn_abs - start_qn) % groove.length_beats
    local min_dist = 1000000
    local best_point = nil
    local best_match_abs_qn = nil

    local window_qn = math.max(0.25, (groove.grid_base or 0.25) * 0.66)
    if self.application.window_ms then
        local bpm = reaper.TimeMap2_GetDividedBpmAtTime(0, item_pos)
        window_qn = (self.application.window_ms / 1000) * (bpm / 60)
    end

    local target_grid = self.application.target_grid
    local vel_min = self.extraction.velocity_min or 0

    for _, gp in ipairs(groove.points) do
        local allowed = true

        if groove.source_type == "MIDI" and (gp.raw_vel or 100) < vel_min then
            allowed = false
        end

        if target_grid > 0 then
            local dist_to_grid = math.abs(gp.pos_qn % target_grid)
            if dist_to_grid > 0.01 and math.abs(dist_to_grid - target_grid) > 0.01 then
                allowed = false
            end
        end

        if allowed and (pitch == -1 or gp.pitch == nil or gp.pitch == -1 or gp.pitch == pitch) then
            local dist = math.abs(gp.pos_qn - loop_pos)
            local dist_wrap = math.abs((gp.pos_qn - groove.length_beats) - loop_pos)
            local dist_wrap2 = math.abs((gp.pos_qn + groove.length_beats) - loop_pos)
            local real_dist = math.min(dist, dist_wrap, dist_wrap2)

            if real_dist < min_dist then
                min_dist = real_dist
                best_point = gp

                local cycle_start = start_qn +
                    math.floor((target_qn_abs - start_qn) / groove.length_beats) * groove.length_beats
                local match_qn = cycle_start + gp.pos_qn

                if dist_wrap < dist and dist_wrap < dist_wrap2 then
                    match_qn = match_qn - groove.length_beats
                elseif dist_wrap2 < dist and dist_wrap2 < dist_wrap then
                    match_qn = match_qn + groove.length_beats
                end
                best_match_abs_qn = match_qn
            end
        end
    end

    if best_point and min_dist <= window_qn then return best_point, best_match_abs_qn end
    return nil, nil
end

function GrooveCore:_applyToMIDI(take, groove, start_qn, item_pos)
    local cache = GrooveCache:ensure(take)
    if not cache or cache.count == 0 then return nil, "Analysis failed or empty" end

    local new_events = {}
    local vel_min = self.extraction.velocity_min or 0

    for _, evt in ipairs(cache.events) do
        if evt.orig_vel < vel_min then
            table.insert(new_events, {
                idx = evt.idx,
                new_start_qn = evt.orig_qn,
                len_qn = evt.orig_len,
                new_vel = evt.orig_vel,
                pitch = evt.pitch,
                chan = evt.chan,
                sel = evt.sel,
                muted = evt.muted
            })
        else
            local gp = self:_findBestMatch(groove, evt.orig_qn, evt.pitch, item_pos, start_qn)

            local final_qn = evt.orig_qn
            local new_vel = evt.orig_vel

            if gp then
                local rel_qn = evt.orig_qn - start_qn
                local closest_grid_rel, _ = GetHeuristicGridPos(rel_qn, groove.grid_base)
                local target_grid_abs = start_qn + closest_grid_rel

                local q_qn = evt.orig_qn + (target_grid_abs - evt.orig_qn) * self.application.quantize_amount
                local groove_offset = gp.offset * self.application.timing_amount * self.application.global_intensity
                final_qn = q_qn + groove_offset

                if self.application.velocity_amount > 0 then
                    local target_vel = gp.raw_vel or 100
                    if gp.velocity then target_vel = math.floor(gp.velocity * 127) end
                    local strength = self.application.velocity_amount * self.application.global_intensity
                    new_vel = evt.orig_vel + (target_vel - evt.orig_vel) * strength
                    new_vel = math.max(1, math.min(127, math.floor(new_vel)))
                end
            end

            table.insert(new_events, {
                idx = evt.idx,
                new_start_qn = final_qn,
                len_qn = evt.orig_len,
                new_vel = new_vel,
                pitch = evt.pitch,
                chan = evt.chan,
                sel = evt.sel,
                muted = evt.muted
            })
        end
    end

    local groups = {}
    for _, evt in ipairs(new_events) do
        local key = tostring(evt.chan) .. ":" .. tostring(evt.pitch)
        if not groups[key] then groups[key] = {} end
        table.insert(groups[key], evt)
    end

    for _, group in pairs(groups) do
        table.sort(group, function(a, b) return a.new_start_qn < b.new_start_qn end)
        for i = 1, #group - 1 do
            local curr = group[i]
            local next = group[i + 1]
            local curr_end = curr.new_start_qn + curr.len_qn
            if curr_end > next.new_start_qn then
                curr.len_qn = math.max(0.01, next.new_start_qn - curr.new_start_qn - 0.001)
            end
        end
    end

    for i, evt in ipairs(new_events) do
        local new_ppq = reaper.MIDI_GetPPQPosFromProjQN(take, evt.new_start_qn)
        local end_qn = evt.new_start_qn + evt.len_qn
        local end_ppq = reaper.MIDI_GetPPQPosFromProjQN(take, end_qn)

        reaper.MIDI_SetNote(take, evt.idx, evt.sel, evt.muted, new_ppq, end_ppq, evt.chan, evt.pitch, evt.new_vel, true)
    end
    reaper.MIDI_Sort(take)
    return true
end

local function findBestStretchModeID()
    local i = 0
    local algo_candidates = {}

    while true do
        local retval, str = reaper.EnumPitchShiftModes(i)
        if not retval then break end

        if str then
            if str:find("3%.3%.3 Pro") then
                algo_candidates.elastique = i
            elseif str:find("Rubber Band") or str:find("RubberBand") then
                algo_candidates.rubberband = i
            end
        end
        i = i + 1
    end

    local selected_idx = nil
    local selected_submode = 0
    local algo_name = ""

    if algo_candidates.elastique then
        selected_idx = algo_candidates.elastique
        algo_name = "Elastique 3.3.3 Pro"
        local j = 0
        while true do
            local retval, sub_str = reaper.EnumPitchShiftSubModes(selected_idx, j)
            if not retval then break end
            if sub_str and sub_str:find("Synchronized") then
                selected_submode = j
                algo_name = algo_name .. " (Synchronized)"
                break
            end
            j = j + 1
        end
    elseif algo_candidates.rubberband then
        selected_idx = algo_candidates.rubberband
        algo_name = "Rubber Band"
        local j = 0
        local best_rb_sub = 0
        local best_rb_name = "Default"

        while true do
            local retval, sub_str = reaper.EnumPitchShiftSubModes(selected_idx, j)
            if not retval then break end

            if sub_str then
                if sub_str:find("Transient") then
                    best_rb_sub = j
                    best_rb_name = "Transient Optimized"
                    break
                elseif sub_str:find("Balanced") and best_rb_name ~= "Transient Optimized" then
                    best_rb_sub = j
                    best_rb_name = "Balanced"
                end
            end
            j = j + 1
        end
        selected_submode = best_rb_sub
        algo_name = algo_name .. " (" .. best_rb_name .. ")"
    end

    if selected_idx then
        return (selected_idx << 16) | selected_submode, algo_name
    end

    return nil, "None"
end

function GrooveCore:setPitchModeChunk(item, take, mode_id, submode_flags)
    local take_idx = -1
    for i = 0, reaper.CountTakes(item) - 1 do
        if reaper.GetTake(item, i) == take then
            take_idx = i
            break
        end
    end

    if take_idx == -1 then return false end

    local retval, chunk = reaper.GetItemStateChunk(item, "", false)
    if not retval then return false end

    local count = 0
    local new_chunk = chunk:gsub("(PLAYRATE %S+ %S+ %S+) (%S+)", function(prefix, current_mode)
        local result = prefix .. " " .. current_mode
        if count == take_idx then
            result = prefix .. " " .. string.format("%d", mode_id)
        end
        count = count + 1
        return result
    end)

    if new_chunk ~= chunk then
        reaper.SetItemStateChunk(item, new_chunk, false)
        return true
    end
    return false
end

function GrooveCore:getEffectiveSourceLength(take)
    local src = reaper.GetMediaItemTake_Source(take)
    local retval, offs, len, rev = reaper.PCM_Source_GetSectionInfo(src)
    if retval and len > 0 then
        return len
    end
    local src_len, is_qn = reaper.GetMediaSourceLength(src)
    if not is_qn and src_len > 0 then
        return src_len
    end
    return nil
end

function GrooveCore:_applyToAudio(take, item, groove, start_qn, item_pos, item_len, start_offs, play_rate, master_audio_info)
    local pitch_mode, algo_name = findBestStretchModeID()

    if pitch_mode then
        reaper.SetMediaItemTakeInfo_Value(take, "B_PPITCH", 1)

        reaper.SetMediaItemTakeInfo_Value(take, "I_PITCHMODE", pitch_mode)

        local stretch_flags = 1

        if algo_name:find("Synchronized") or algo_name:find("Transient") then
            stretch_flags = 4
        end

        local current_flags = reaper.GetMediaItemTakeInfo_Value(take, "I_STRETCHFLAGS")
        local new_flags = (current_flags & ~7) | stretch_flags

        reaper.SetMediaItemTakeInfo_Value(take, "I_STRETCHFLAGS", new_flags)

        self:setPitchModeChunk(item, take, pitch_mode)

        reaper.UpdateItemInProject(item)

        if DEBUG_MODE then
            local verify_mode  = reaper.GetMediaItemTakeInfo_Value(take, "I_PITCHMODE")
            local verify_flags = reaper.GetMediaItemTakeInfo_Value(take, "I_STRETCHFLAGS")

            local v_algo       = (verify_mode >> 16) & 0xFFFF
            local v_sub        = verify_mode & 0xFFFF

            dbg(string.format("Set Algo: %s (Val: %d) | Verified: %d | Flags: %d",
                algo_name, pitch_mode, verify_mode, verify_flags))
        end
    else
        if DEBUG_MODE then dbg("Warning: Optimal stretch algorithm not found!") end
    end

    -- [PLAYRATE NORMALIZATION]
    -- Force item playrate to 1.0 and bake multiplier into stretch markers.
    local baked_play_rate = 1.0
    if math.abs(play_rate - 1.0) > 0.0001 then
        baked_play_rate = play_rate
        reaper.SetMediaItemTakeInfo_Value(take, "D_PLAYRATE", 1.0)
        reaper.SetMediaItemInfo_Value(item, "D_LENGTH", item_len) -- Preserve visual length
        
        -- Scale existing marker src_pos to match baked rate.
        local existing_markers = reaper.GetTakeNumStretchMarkers(take)
        for i = 0, existing_markers - 1 do
            local idx, pos, src_pos = reaper.GetTakeStretchMarker(take, i)
            reaper.SetTakeStretchMarker(take, idx, pos, src_pos * baked_play_rate)
        end
        
        if DEBUG_MODE then
            dbg(string.format("[NORMALIZATION] Forced D_PLAYRATE to 1.0. Baking multiplier: %.4f", baked_play_rate))
        end
    end

    local actual_src_len = self:getEffectiveSourceLength(take)

    local num_markers = reaper.GetTakeNumStretchMarkers(take)
    if num_markers == 0 then
        if master_audio_info and master_audio_info.markers then
            -- Clone markers from Master item.
            for _, m in ipairs(master_audio_info.markers) do
                local pos_in_item = m.abs_time - item_pos
                if pos_in_item > 0 and pos_in_item < item_len then
                    local src_pos = start_offs + (pos_in_item * baked_play_rate)
                    reaper.SetTakeStretchMarker(take, -1, pos_in_item, src_pos)
                end
            end
        else
            local transients = self:detectTransients(take)
            for _, t in ipairs(transients) do
                local pos_in_item = t.time - item_pos
                -- Apply baked rate to source position.
                local src_pos = start_offs + (pos_in_item * baked_play_rate)
                reaper.SetTakeStretchMarker(take, -1, pos_in_item, src_pos)
            end
        end
        
        if actual_src_len then
            if DEBUG_MODE then
                dbg(string.format("[LOOP BOUNDARIES] actual_src_len: %.4f | start_offs: %.4f | baked_rate: %.4f", actual_src_len, start_offs, baked_play_rate))
            end
            local first_loop_src = actual_src_len - (start_offs % actual_src_len)
            if math.abs(first_loop_src - actual_src_len) < 0.001 then first_loop_src = 0 end
            
            local t = first_loop_src / baked_play_rate
            while t < item_len - 0.010 do
                if t > 0.010 then
                    -- Insert safe boundary markers before loop points.
                    local safe_t = t - 0.005
                    local boundary_src = start_offs + (safe_t * baked_play_rate)
                    if DEBUG_MODE then
                        dbg(string.format("  -> Adding safe loop boundary marker at pos: %.4f, src: %.4f", safe_t, boundary_src))
                    end
                    reaper.SetTakeStretchMarker(take, -1, safe_t, boundary_src)
                end
                t = t + (actual_src_len / baked_play_rate)
            end
        end

        GrooveCache:clear(take)
    end

    -- Insert start/end markers with offset to maintain loop stability.
    local has_start_marker = false
    local has_end_marker = false
    num_markers = reaper.GetTakeNumStretchMarkers(take)

    if num_markers > 0 then
        local _, first_pos, _ = reaper.GetTakeStretchMarker(take, 0)
        if first_pos <= 0.010 then has_start_marker = true end

        local _, last_pos, _ = reaper.GetTakeStretchMarker(take, num_markers - 1)
        if last_pos >= item_len - 0.010 then has_end_marker = true end
    end

    local markers_updated = false
    if not has_start_marker then
        reaper.SetTakeStretchMarker(take, -1, 0.005, start_offs + (0.005 * baked_play_rate))
        markers_updated = true
        if DEBUG_MODE then dbg("  -> Adding safe start marker at pos 0.005") end
    end

    if not has_end_marker then
        local end_pos = item_len - 0.005
        if end_pos > 0.010 then
            local end_src_pos = start_offs + (end_pos * baked_play_rate)
            if num_markers > 0 then
                local _, last_pos, last_src = reaper.GetTakeStretchMarker(take, num_markers - 1)
                if last_pos < end_pos then
                    end_src_pos = last_src + (end_pos - last_pos) * baked_play_rate
                end
            end
            reaper.SetTakeStretchMarker(take, -1, end_pos, end_src_pos)
            markers_updated = true
            if DEBUG_MODE then dbg(string.format("  -> Adding safe end marker at pos %.4f, src %.4f", end_pos, end_src_pos)) end
        end
    end

    if markers_updated then
        reaper.UpdateItemInProject(item)
        GrooveCache:clear(take)
    end

    local env = nil
    local env_mode, scaled_unity

    if self.application.audio_apply_volume then
        env = reaper.GetTakeEnvelopeByName(take, "Volume")
        if not env then
            -- Cache item selection state.
            local sel_items = {}
            for i = 0, reaper.CountSelectedMediaItems(0) - 1 do
                sel_items[#sel_items+1] = reaper.GetSelectedMediaItem(0, i)
            end
            
            reaper.Main_OnCommand(40289, 0) -- Unselect all items.
            reaper.SetMediaItemSelected(item, true)
            reaper.Main_OnCommand(40693, 0) -- Toggle take volume envelope.
            
            -- Restore selection
            reaper.Main_OnCommand(40289, 0)
            for _, sel_item in ipairs(sel_items) do
                reaper.SetMediaItemSelected(sel_item, true)
            end
            
            env = reaper.GetTakeEnvelopeByName(take, "Volume")
        end

        if env then
        env_mode = reaper.GetEnvelopeScalingMode(env)
        scaled_unity = reaper.ScaleToEnvelopeMode(env_mode, 1.0)

        local source_start = start_offs
        local source_end = start_offs + (item_len * baked_play_rate)
        reaper.DeleteEnvelopePointRange(env, source_start - 0.1, source_end + 0.1)
        reaper.InsertEnvelopePoint(env, source_start, scaled_unity, 0, 0, false, true)
        reaper.InsertEnvelopePoint(env, source_end, scaled_unity, 0, 0, false, true)
    end
    end

    if DEBUG_MODE then
        dbg("--- AUDIO GROOVE APPLICATION START ---")
        dbg(string.format("ItemPos: %.3fs | ItemLen: %.3fs", item_pos, item_len))
        dbg(string.format("TakeOffset: %.3fs | BakedRate: %.3f", start_offs, baked_play_rate))
    end

    num_markers = reaper.GetTakeNumStretchMarkers(take)
    local markers = {}

    if DEBUG_MODE then
        dbg("Stretch Markers Before Apply:")
    end

    for i = 0, num_markers - 1 do
        local idx, pos, src_pos = reaper.GetTakeStretchMarker(take, i)
        if idx ~= -1 then
            if DEBUG_MODE then
                dbg(string.format("  [%d] pos: %.4f, src: %.4f", i, pos, src_pos))
            end
            table.insert(markers, {
                index = i,
                orig_pos = pos,
                src_pos = src_pos
            })
        end
    end

    local last_query_qn = -1
    local last_delta = 0
    local last_abs_time = -100

    if DEBUG_MODE then ClearDebugMarkers() end

    local marker_idx_offset = 0
    local last_new_pos = -0.001
    
    local out_info = { markers = {} }

    for i, m in ipairs(markers) do
        local current_abs_time = item_pos + m.orig_pos
        local abs_qn = reaper.TimeMap2_timeToQN(0, current_abs_time)

        local grid_division = self.application.target_grid
        if grid_division <= 0 then grid_division = groove.grid_base or 0.125 end

        local query_qn, _ = GetHeuristicGridPos(abs_qn, grid_division)

        local delta = 0
        local is_grouped = false
        local gp = nil
        local target_abs_time = 0

        local bpm = reaper.TimeMap2_GetDividedBpmAtTime(0, current_abs_time)
        local lockout_qn = 1 / 64
        local lockout_sec = (60 / bpm) * lockout_qn

        local time_dist = math.abs(current_abs_time - last_abs_time)

        -- Preserve pinned edge markers and loop boundaries.
        local is_pinned = false
        if m.orig_pos < 0.030 or math.abs(m.orig_pos - item_len) < 0.030 then
            is_pinned = true
        end
        if not is_pinned and actual_src_len then
            local src_rem = m.src_pos % actual_src_len
            if src_rem < 0.030 or src_rem > actual_src_len - 0.030 then
                is_pinned = true
            end
        end

        if is_pinned then
            delta = 0
            is_grouped = true
            gp = nil
            last_query_qn = query_qn
            last_delta = 0
            if DEBUG_MODE then dbg(string.format("  -> Marker %d PINNED (delta=0)", m.index)) end
        elseif master_audio_info and master_audio_info.markers then
            local closest_m = nil
            local min_dist = 9999
            for _, mm in ipairs(master_audio_info.markers) do
                local dist = math.abs(mm.abs_time - current_abs_time)
                if dist < min_dist then
                    min_dist = dist
                    closest_m = mm
                end
            end
            
            if closest_m and min_dist < 0.050 then
                delta = closest_m.delta
                is_grouped = false
                if closest_m.gp_velocity then
                    gp = { velocity = closest_m.gp_velocity }
                end
            else
                delta = 0
                is_grouped = true
            end
        elseif math.abs(query_qn - last_query_qn) < 0.001 and time_dist < lockout_sec then
            delta = last_delta
            is_grouped = true
            if DEBUG_MODE then
                dbg(string.format("  -> Grouped with prev (Dist: %.4fs < %.4fs)", time_dist, lockout_sec))
            end
        else
            local found_gp, target_abs_qn = self:_findBestMatch(groove, query_qn, -1, item_pos, start_qn)
            gp = found_gp

            if gp and target_abs_qn then
                local vel_min = self.extraction.velocity_min or 0
                local is_valid_source = true
                if groove.source_type == "MIDI" and (gp.raw_vel or 100) < vel_min then
                    is_valid_source = false
                end

                if is_valid_source then
                    local target_groove_qn = target_abs_qn + (gp.offset or 0)
                    target_abs_time = reaper.TimeMap2_QNToTime(0, target_groove_qn)

                    delta = target_abs_time - current_abs_time

                    last_query_qn = query_qn
                    last_delta = delta
                end
            end
        end

        last_abs_time = current_abs_time
        
        table.insert(out_info.markers, {
            abs_time = current_abs_time,
            delta = delta,
            gp_velocity = gp and gp.velocity or nil
        })

        local vel_factor = 0

        if (gp or is_grouped) then
            if DEBUG_MODE then
                local group_tag = is_grouped and "[GROUP] " or ""
                local offs_val = (gp and gp.offset) or (is_grouped and "Linked") or 0
                dbg(string.format("%sMarker %d | Moved: %.2f ms | Grid QN: %.3f | Offs: %s",
                    group_tag, m.index, delta * 1000, query_qn, tostring(offs_val)))

                if not is_grouped and target_abs_time > 0 then
                    reaper.AddProjectMarker(0, false, target_abs_time, 0, "G_REF_" .. m.index, -1, 0xFF0000)
                end
            end

            local strength = self.application.timing_amount * self.application.global_intensity
            local new_pos = m.orig_pos + (delta * strength)


            if not is_grouped or delta ~= 0 then
                local min_pos = last_new_pos + 0.001
                local max_pos = item_len - 0.001

                if i < #markers then
                    max_pos = markers[i + 1].orig_pos - 0.001
                end

                -- Clamp marker positions to avoid item boundaries.
                if new_pos < 0.010 then new_pos = 0.010 end
                if new_pos > item_len - 0.010 then new_pos = item_len - 0.010 end
                
                if actual_src_len then
                    -- Calculate next loop boundary.
                    local current_src_offset = start_offs + (m.orig_pos * baked_play_rate)
                    local loops_passed = math.floor(current_src_offset / actual_src_len)
                    local next_loop_src = (loops_passed + 1) * actual_src_len
                    local next_loop_pos = (next_loop_src - start_offs) / baked_play_rate
                    
                    if next_loop_pos < item_len and next_loop_pos > new_pos then
                        if new_pos > next_loop_pos - 0.010 then new_pos = next_loop_pos - 0.010 end
                    end
                end

                if new_pos < min_pos then new_pos = min_pos end
                if new_pos > max_pos then new_pos = max_pos end
            end

            reaper.SetTakeStretchMarker(take, m.index + marker_idx_offset, new_pos, m.src_pos)
            last_new_pos = new_pos

            if not is_grouped then
                local protect_time = 0.040

                local next_marker_pos = item_len
                if i < #markers then
                    next_marker_pos = markers[i + 1].orig_pos
                end

                local dist_orig = next_marker_pos - m.orig_pos
                if protect_time > dist_orig * 0.4 then
                    protect_time = dist_orig * 0.4
                end

                local available_space = next_marker_pos - new_pos
                if protect_time > available_space - 0.001 then
                    protect_time = available_space - 0.001
                end

                if protect_time > 0.002 then
                    local anchor_src = m.src_pos + (protect_time * baked_play_rate)
                    local anchor_pos = new_pos + protect_time
                    reaper.SetTakeStretchMarker(take, -1, anchor_pos, anchor_src)
                    marker_idx_offset = marker_idx_offset + 1
                    last_new_pos = anchor_pos
                end
            end

            if gp then
                vel_factor = (gp.velocity or 0.78) - 0.78

                if env and self.application.velocity_amount > 0 and vel_factor ~= 0 then
                    local intensity = self.application.velocity_amount * self.application.global_intensity
                    local gain_db = (vel_factor * 2) * self.application.audio_max_db * intensity
                    local amp = 10 ^ (gain_db / 20)
                    local scaled_amp = reaper.ScaleToEnvelopeMode(env_mode, amp)

                    local env_time_center = start_offs + (new_pos * baked_play_rate)

                    local pre_s = self.application.audio_pre_ms / 1000
                    local post_s = self.application.audio_post_ms / 1000
                    local shape = self.application.audio_shape or 2

                    reaper.InsertEnvelopePoint(env, env_time_center - pre_s, scaled_unity, shape, 0, false, true)
                    reaper.InsertEnvelopePoint(env, env_time_center, scaled_amp, shape, 0, false, true)
                    reaper.InsertEnvelopePoint(env, env_time_center + post_s, scaled_unity, shape, 0, false, true)
                end
            end
        end
    end

    if env then reaper.Envelope_SortPoints(env) end
    reaper.UpdateItemInProject(item)
    reaper.UpdateArrange()
    return true, nil, out_info
end

function GrooveCore:applyGroove()
    local groove = self:getCurrentGroove()
    if not groove then return nil, "No groove selected" end

    local selected_count = reaper.CountSelectedMediaItems(0)
    if selected_count == 0 then return nil, "No items selected" end

    if not groove.length_beats or groove.length_beats <= 0 then
        groove.length_beats = 4.0
        statusSet("Warning: Groove length invalid, defaulting to 4.0", "warn")
    end

    local success_count = 0
    local failed_count = 0
    local first_error = nil
    local fail_reasons = {}

    local masters = {} -- Map of time segments to master_audio_infos.

    for i = 0, selected_count - 1 do
        local item = reaper.GetSelectedMediaItem(0, i)
        if item then
            self:saveOriginalState(item)

            local take = reaper.GetActiveTake(item)
            if not take then
                failed_count = failed_count + 1
                local reason = "No active take"
                fail_reasons[reason] = (fail_reasons[reason] or 0) + 1
                if not first_error then first_error = reason end
            else
                local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
                local item_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
                local t_ctx = TimeContext.new(item, take)
                local virtual_start_time = t_ctx:getVirtualStartTime()
                local start_qn = t_ctx:getVirtualStartQN()

                local current_master = nil
                if self.application.phase_coherent then
                    for _, m in ipairs(masters) do
                        local overlap = math.max(0, math.min(item_pos + item_len, m.item_pos + m.item_len) - math.max(item_pos, m.item_pos))
                        if overlap > 0.050 then -- at least 50ms overlap
                            current_master = m
                            break
                        end
                    end
                end

                local ok_apply, err_apply, out_info
                if reaper.TakeIsMIDI(take) then
                    ok_apply, err_apply = self:_applyToMIDI(take, groove, start_qn, item_pos)
                else
                    local start_offs = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
                    local play_rate = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
                    ok_apply, err_apply, out_info = self:_applyToAudio(take, item, groove, start_qn, item_pos, item_len, start_offs,
                        play_rate, current_master)
                        
                    if ok_apply and self.application.phase_coherent and not current_master and out_info then
                        out_info.item_pos = item_pos
                        out_info.item_len = item_len
                        table.insert(masters, out_info)
                    end
                end

                if ok_apply then
                    success_count = success_count + 1
                else
                    failed_count = failed_count + 1
                    local reason = err_apply or "Apply failed"
                    fail_reasons[reason] = (fail_reasons[reason] or 0) + 1
                    if not first_error then first_error = reason end
                end
            end
        else
            failed_count = failed_count + 1
            local reason = "Invalid selected item"
            fail_reasons[reason] = (fail_reasons[reason] or 0) + 1
            if not first_error then first_error = reason end
        end
    end
    local details = summarizeFailureDetails(fail_reasons, 2)

    if success_count == 0 then
        return nil, first_error or "Apply failed on all selected items", failed_count, details
    end
    if failed_count > 0 then
        return true, string.format("Groove applied to %d item(s), %d failed", success_count, failed_count), failed_count,
            details
    end
    return true, string.format("Groove applied to %d item(s)", success_count), 0, ""
end

-- ===========================================================
-- MAIN UI COMPONENTS
-- ===========================================================
local function DrawHelpModal()
    if State.ui.open_help_requested then
        reaper.ImGui_OpenPopup(State.ui.ctx, "Help Guide")
        State.ui.open_help_requested = false
        State.ui.show_help_modal = true
    end

    if State.ui.show_help_modal then
        local ctx = State.ui.ctx
        local modalW, modalH = 750, 650
        reaper.ImGui_SetNextWindowSize(ctx, modalW, modalH, reaper.ImGui_Cond_Always())

        local winX, winY = reaper.ImGui_GetWindowPos(ctx)
        local winW, winH = reaper.ImGui_GetWindowSize(ctx)
        if winX and winY and winW and winH then
            local posX = winX + (winW - modalW) * 0.5
            local posY = winY + (winH - modalH) * 0.5
            reaper.ImGui_SetNextWindowPos(ctx, posX, posY, reaper.ImGui_Cond_Appearing())
        else
            local center = { reaper.ImGui_Viewport_GetCenter(reaper.ImGui_GetMainViewport(ctx)) }
            reaper.ImGui_SetNextWindowPos(ctx, center[1], center[2], reaper.ImGui_Cond_Appearing(), 0.5, 0.5)
        end

        local flags = reaper.ImGui_WindowFlags_NoResize() | reaper.ImGui_WindowFlags_NoMove() |
            reaper.ImGui_WindowFlags_NoScrollbar()
        if reaper.ImGui_BeginPopupModal(ctx, 'Help Guide', true, flags) then
            reaper.ImGui_Text(ctx, 'Floop Groove-A-Thor - User Guide')
            reaper.ImGui_Separator(ctx)
            reaper.ImGui_Spacing(ctx)

            if reaper.ImGui_BeginChild(ctx, "HelpContent", 0, -40) then
                reaper.ImGui_Text(ctx, 'OVERVIEW')
                reaper.ImGui_TextWrapped(ctx,
                    'This script allows you to extract groove (timing and velocity) from audio or MIDI items and apply it to any target item (Audio or MIDI). It features a non-destructive workflow with visual feedback.')
                reaper.ImGui_Spacing(ctx)
                reaper.ImGui_Separator(ctx)
                reaper.ImGui_Spacing(ctx)

                reaper.ImGui_Text(ctx, 'GROOVE EXTRACTION')
                reaper.ImGui_BulletText(ctx, 'Source Selection: Select an audio item (drums/percussion) or MIDI item.')
                reaper.ImGui_BulletText(ctx,
                    'Extract: Click "Extract from Sel". On success, visualizer switches to LOCKED mode automatically.')
                reaper.ImGui_BulletText(ctx,
                    string.format('Length Guard: Extraction is limited to short loops (max %.0f seconds).',
                        VISUALIZER_MAX_LEN_SEC))
                reaper.ImGui_BulletText(ctx,
                    'Transient Detection: The script automatically detects transients (Audio) or note starts (MIDI).')
                reaper.ImGui_BulletText(ctx, 'Groove Pool: The extracted pattern is saved to the groove pool.')
                reaper.ImGui_Spacing(ctx)

                reaper.ImGui_Text(ctx, 'GROOVE POOL & BANKS')
                reaper.ImGui_BulletText(ctx, 'Groove List: Click a groove to select it (highlighted in blue).')
                reaper.ImGui_BulletText(ctx,
                    'Banks (Folders): Organize grooves into banks using the dropdown menu above the list.')
                reaper.ImGui_BulletText(ctx, 'Create Bank: Click the "+" button to create a new bank.')
                reaper.ImGui_BulletText(ctx,
                    'Navigation: Use [..] (Up) to go back to the root folder, or click a bank name to enter it.')
                reaper.ImGui_BulletText(ctx,
                    'Context Menu: Right-click a groove to Rename, Delete, or Move to another Bank.')
                reaper.ImGui_Spacing(ctx)

                reaper.ImGui_Text(ctx, 'GROOVE APPLICATION')
                reaper.ImGui_BulletText(ctx,
                    'Target Selection: Select the target items you want to quantize (Audio or MIDI).')
                reaper.ImGui_BulletText(ctx,
                    'Timing Strength: Controls how strongly the timing matches the groove (0% to 100%).')
                reaper.ImGui_BulletText(ctx,
                    'Velocity Strength: Scales the velocity of MIDI notes or Audio Envelopes to match the groove dynamics.')
                reaper.ImGui_BulletText(ctx,
                    'Grid Attraction: Pre-quantizes items to the selected Grid before applying groove offset.')
                reaper.ImGui_BulletText(ctx,
                    'Match Window: Max time distance (ms) to link source notes to grid/groove points.')
                reaper.ImGui_BulletText(ctx,
                    'Target Filter: Apply groove only to notes near specific grid lines (e.g., 1/4 for kicks only).')
                reaper.ImGui_BulletText(ctx,
                    'Phase Coherent Mode: When applying to multi-track audio, uses the first selected item as the Master to preserve phase.')
                reaper.ImGui_BulletText(ctx,
                    'Audio Velocity Settings: Create volume envelopes dynamically shaped around transients.')
                reaper.ImGui_BulletText(ctx,
                    'Apply: Click "Apply Groove" to process all selected target items. This action is undoable.')
                reaper.ImGui_Spacing(ctx)

                reaper.ImGui_Text(ctx, 'VISUALIZER')
                reaper.ImGui_BulletText(ctx, 'Modes:')
                reaper.ImGui_Indent(ctx)
                reaper.ImGui_BulletText(ctx, 'LIVE (Selection): Shows the waveform/notes of the currently selected item.')
                reaper.ImGui_BulletText(ctx,
                    'LOCKED (Groove): Shows the stored pattern of the selected groove from the pool.')
                reaper.ImGui_Unindent(ctx)
                reaper.ImGui_BulletText(ctx,
                    'LP Override: When LP is enabled, visualizer shows synthetic generator preview.')
                reaper.ImGui_BulletText(ctx, 'Navigation: Wheel = Zoom, Right-Click Drag = Scroll.')
                reaper.ImGui_BulletText(ctx,
                    'Feedback: Green lines = Transients/Notes. Blue lines = Active Groove Pattern.')
                reaper.ImGui_Spacing(ctx)

                reaper.ImGui_Text(ctx, 'GROOVE GENERATOR')
                reaper.ImGui_BulletText(ctx, 'Procedural Grooves: Create perfect swing patterns without audio analysis.')
                reaper.ImGui_BulletText(ctx, 'Grid: Select the base resolution (e.g., 1/16).')
                reaper.ImGui_BulletText(ctx, 'Swing: Adjust the swing amount (50% = straight, 66% = triplet feel).')
                reaper.ImGui_BulletText(ctx, 'Push/Pull: Shift the entire groove ahead of or behind the exact beat.')
                reaper.ImGui_BulletText(ctx, 'Velocity Curve: Apply hierarchical musical dynamics (accents on downbeats).')
                reaper.ImGui_BulletText(ctx, 'Shortcuts: Right-click sliders to reset to defaults.')
                reaper.ImGui_BulletText(ctx,
                    'LP: Real-time preview of synthetic groove. It is independent from the selected groove.')
                reaper.ImGui_BulletText(ctx, 'Generate: Adds the generated pattern to the Groove Pool.')
                reaper.ImGui_Spacing(ctx)

                reaper.ImGui_Text(ctx, 'MANAGEMENT & ADVANCED')
                reaper.ImGui_BulletText(ctx, 'Rename: Double-click a groove name or use the context menu.')
                reaper.ImGui_BulletText(ctx,
                    'Multi-Select: Ctrl+Click (Cmd+Click) to select multiple grooves for deletion.')
                reaper.ImGui_BulletText(ctx,
                    'Reset Cache: Force re-analysis if you manually edited stretch markers or item bounds.')
                reaper.ImGui_BulletText(ctx, 'Files: Grooves are saved as .gat files in the script directory.')

                reaper.ImGui_EndChild(ctx)
            end

            reaper.ImGui_Separator(ctx)

            local availWidth = reaper.ImGui_GetContentRegionAvail(ctx)
            local buttonWidth = 100
            reaper.ImGui_SetCursorPosX(ctx, (availWidth - buttonWidth) * 0.5)
            if reaper.ImGui_Button(ctx, 'Close', buttonWidth, 30) then
                State.ui.show_help_modal = false
                reaper.ImGui_CloseCurrentPopup(ctx)
            end

            reaper.ImGui_EndPopup(ctx)
        else
            State.ui.show_help_modal = false
        end
    end
end



local function DrawMainToolbar()
    local ctx = State.ui.ctx
    local full_w = reaper.ImGui_GetContentRegionAvail(ctx)
    local child_h = uiScale(35)

    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ChildBg(), 0x00000000)

    if reaper.ImGui_BeginChild(ctx, "MainToolbar", full_w, child_h, 0) then
        local btn_h = uiScale(24)
        local pad_y = (child_h - btn_h) * 0.5
        reaper.ImGui_SetCursorPosY(ctx, pad_y)

        local has_selection = reaper.GetSelectedMediaItem(0, 0) ~= nil
        local has_groove = GrooveCore:getCurrentGroove() ~= nil


        reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FramePadding(), 10, 0)

        if reaper.ImGui_Button(ctx, "Extract from Sel", 0, btn_h) then
            if has_selection then
                local g, err = GrooveCore:analyzeSelection()
                if g then
                    GrooveCore:addGroove(g)
                    State.ui.viz_locked = true
                    State.ui.viz_force_groove_view = true
                    statusSet("Extracted groove: " .. g.name, "ok")
                else
                    statusSet("Extraction failed: " .. (err or "unknown"), "error")
                end
            else
                statusSet("No item selected for extraction", "warn")
            end
        end

        reaper.ImGui_SameLine(ctx)

        if reaper.ImGui_Button(ctx, "Reset Cache", 0, btn_h) then
            GrooveCache:clearAll()
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Force clear analysis cache.\nUse this if you manually edited markers/notes.")
        end

        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_Button(ctx, "Help", 0, btn_h) then
            State.ui.open_help_requested = true
        end

        reaper.ImGui_PopStyleVar(ctx) -- Pop FramePadding

        reaper.ImGui_EndChild(ctx)
    end

    reaper.ImGui_PopStyleColor(ctx)

    reaper.ImGui_Separator(ctx)
end

local VizCache = {
    id = nil,
    peaks = {},
    w = 0,
    len = 0,
    pos = 0,
    dirty = true
}

local PreviewCache = {
    id = nil,
    candidates = {}
}

local function UpdatePreviewCache(take)
    local item = reaper.GetMediaItemTake_Item(take)
    local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local _, guid = reaper.GetSetMediaItemTakeInfo_String(take, "GUID", "", false)
    
    local ext = GrooveCore.extraction
    local id = string.format("%s_%.3f_%.3f_%.2f_%.2f_%.0f_%.0f", 
        guid, len, pos, ext.threshold_db or -30, ext.sensitivity or 0.5, ext.hpf_hz or 0, ext.lpf_hz or 0)

    if PreviewCache.id == id then return end

    PreviewCache.id = id
    PreviewCache.candidates = {}

    -- Limit extraction preview to 30.0s to prevent UI thread blocking.
    local transients = GrooveCore:detectTransients(take, 30.0)
    
    for _, t in ipairs(transients) do
        local time_in_item = t.time - pos
        table.insert(PreviewCache.candidates, { t = time_in_item, v = t.val })
    end
end

local function UpdateMidiPreviewCache(take)
    local item = reaper.GetMediaItemTake_Item(take)
    local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    local _, guid = reaper.GetSetMediaItemTakeInfo_String(take, "GUID", "", false)
    local id = guid .. "_" .. len

    if VizCache.id == id then return end -- Already cached

    VizCache.id = id
    VizCache.len = len
    VizCache.pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    VizCache.name = reaper.GetTakeName(take)
    VizCache.peaks = {} -- No audio peaks
    VizCache.is_midi = true

    VizCache.midi_points = {}
    VizCache.midi_min_pitch = 127
    VizCache.midi_max_pitch = 0

    local _, note_count = reaper.MIDI_CountEvts(take)
    if not note_count or note_count == 0 then return end

    local loop_source = reaper.GetMediaItemTake_Source(take)
    local loop_len_qn = reaper.GetMediaSourceLength(loop_source)
    if loop_len_qn <= 0 then
        loop_len_qn = reaper.TimeMap2_timeToQN(0, len)
    end
    VizCache.midi_loop_len = loop_len_qn

    for i = 0, note_count - 1 do
        local rv, selected, muted, startppq, endppq, chan, pitch, vel = reaper.MIDI_GetNote(take, i)
        if rv and not muted then
            local start_qn = reaper.MIDI_GetProjQNFromPPQPos(take, startppq)
            local item_start_qn = reaper.TimeMap2_timeToQN(0, VizCache.pos)
            local rel_qn = start_qn - item_start_qn

            if pitch < VizCache.midi_min_pitch then VizCache.midi_min_pitch = pitch end
            if pitch > VizCache.midi_max_pitch then VizCache.midi_max_pitch = pitch end

            table.insert(VizCache.midi_points, { pos = rel_qn, vel = vel, pitch = pitch })
        end
    end

    table.sort(VizCache.midi_points, function(a, b) return a.pos < b.pos end)
end

local function UpdateVizCache(item, take, w, view_start, view_len)
    local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    if not w or w < 1 or len <= 0 then return end
    w = math.floor(w + 0.5)

    view_start = view_start or 0
    view_len = view_len or len

    local _, guid = reaper.GetSetMediaItemTakeInfo_String(take, "GUID", "", false)
    local id = guid .. "_" .. len .. "_" .. pos .. "_" .. view_start .. "_" .. view_len .. "_" .. w

    if VizCache.id == id then
        return
    end

    VizCache.id = id
    VizCache.w = w
    VizCache.len = len
    VizCache.pos = pos
    VizCache.take = take -- Store take for locked mode
    VizCache.name = reaper.GetTakeName(take)
    VizCache.view_start = view_start
    VizCache.view_len = view_len

    if reaper.TakeIsMIDI(take) then
        VizCache.is_midi = true
        VizCache.peaks = {}
        UpdateMidiPreviewCache(take)
    else
        VizCache.is_midi = false
        VizCache.midi_points = {}
        VizCache.peaks = {}

        local acc = reaper.CreateTakeAudioAccessor(take)
        local src = reaper.GetMediaItemTake_Source(take)
        local sr = reaper.GetMediaSourceSampleRate(src)
        if sr == 0 then sr = 44100 end

        local samples_per_pixel = math.floor((view_len * sr) / w)
        local block_size = 256
        if block_size > samples_per_pixel then block_size = samples_per_pixel end
        if block_size < 1 then block_size = 1 end
        if block_size > 1024 then block_size = 1024 end

        local buf = reaper.new_array(block_size)
        local dt = view_len / w
        for i = 0, w - 1 do
            local t = view_start + (i * dt)
            if t >= 0 and t <= len then
                reaper.GetAudioAccessorSamples(acc, sr, 1, t, block_size, buf)
                local t_tbl = buf.table()
                local max_v = 0
                for _, v in ipairs(t_tbl) do
                    local abs_v = math.abs(v)
                    if abs_v > max_v then max_v = abs_v end
                end
                VizCache.peaks[i + 1] = max_v
            else
                VizCache.peaks[i + 1] = 0
            end
        end

        reaper.DestroyAudioAccessor(acc)
    end
end

local function DrawVisualizer(w, h)
    local draw_list = reaper.ImGui_GetWindowDrawList(State.ui.ctx)
    local p_x, p_y = reaper.ImGui_GetCursorScreenPos(State.ui.ctx)

    reaper.ImGui_DrawList_AddRectFilled(draw_list, p_x, p_y, p_x + w, p_y + h, 0x1a1a20FF, uiScale(4))

    local grid_col = 0xFFFFFF08
    local num_grid_lines = 8
    for i = 1, num_grid_lines do
        local x = p_x + (i / (num_grid_lines + 1)) * w
        reaper.ImGui_DrawList_AddLine(draw_list, x, p_y, x, p_y + h, grid_col, 1.0)
    end

    if reaper.ImGui_IsMouseHoveringRect(State.ui.ctx, p_x, p_y, p_x + w, p_y + h) and reaper.ImGui_IsWindowHovered(State.ui.ctx, reaper.ImGui_HoveredFlags_None()) then
        local wheel = reaper.ImGui_GetMouseWheel(State.ui.ctx)
        if wheel ~= 0 then
            if reaper.ImGui_IsKeyDown(State.ui.ctx, reaper.ImGui_Mod_Shift()) then
                if State.ui.viz_zoom > 1.0 then
                    State.ui.viz_scroll = State.ui.viz_scroll - (wheel * 0.05 / math.log(State.ui.viz_zoom + 1))

                    if State.ui.viz_scroll < 0.0 then State.ui.viz_scroll = 0.0 end
                    if State.ui.viz_scroll > 1.0 then State.ui.viz_scroll = 1.0 end
                end
            else
                local zoom_inc = wheel * 0.2 * State.ui.viz_zoom
                State.ui.viz_zoom = State.ui.viz_zoom + zoom_inc
                if State.ui.viz_zoom < 1.0 then State.ui.viz_zoom = 1.0 end
                if State.ui.viz_zoom > 50.0 then State.ui.viz_zoom = 50.0 end
            end
        end
    end



    local item = reaper.GetSelectedMediaItem(0, 0)
    local has_selection = item ~= nil

    if has_selection then
        local take = reaper.GetActiveTake(item)
        if take then
            local _, guid = reaper.GetSetMediaItemTakeInfo_String(take, "GUID", "", false)
            if State.ui.last_selection_guid ~= guid then
                State.ui.viz_force_groove_view = false
                State.ui.last_selection_guid = guid
                if DEBUG_MODE then reaper.ShowConsoleMsg("[Visualizer] Timeline Selection Changed -> Resetting View\n") end
            end
        end
    elseif State.ui.last_selection_guid ~= "NONE" then
        State.ui.viz_force_groove_view = false
        State.ui.last_selection_guid = "NONE"
    end

    local target_take = nil
    local current_groove = GrooveCore:getCurrentGroove()
    if not State.runtime.gen_preview then
        if State.ui.viz_locked then
            if (not current_groove) and VizCache.take and reaper.ValidatePtr(VizCache.take, "MediaItem_Take*") then
                target_take = VizCache.take
            end
        elseif has_selection and not State.ui.viz_force_groove_view then
            target_take = reaper.GetActiveTake(item)
        end
    end

    local view_start = 0
    local view_len = 0
    local viz_block_reason = nil

    if target_take then
        local t_item = reaper.GetMediaItemTake_Item(target_take)
        local t_len = reaper.GetMediaItemInfo_Value(t_item, "D_LENGTH")

        if not State.ui.viz_locked and t_len > VISUALIZER_MAX_LEN_SEC then
            viz_block_reason =
            "Selected item exceeds the allowed loop length.\nSelect a shorter loop or enable LOCKED mode."
        end

        if not viz_block_reason then
            view_len = t_len / State.ui.viz_zoom
            local max_scroll_start = t_len - view_len
            view_start = State.ui.viz_scroll * max_scroll_start
            if view_start < 0 then view_start = 0 end

            if not reaper.TakeIsMIDI(target_take) then
                UpdateVizCache(t_item, target_take, w, view_start, view_len)
                UpdatePreviewCache(target_take)
            else
                UpdateMidiPreviewCache(target_take)
                VizCache.len = t_len
                VizCache.view_start = view_start
                VizCache.view_len = view_len
            end
        end
    end

    local is_viz_blocked = viz_block_reason ~= nil
    local has_viz_data = target_take and not is_viz_blocked and VizCache.peaks and #VizCache.peaks > 0 and
        VizCache.len > 0
    local has_midi_data = target_take and not is_viz_blocked and VizCache.is_midi and VizCache.midi_points and
        #VizCache.midi_points > 0

    local function MapTimeToX(t)
        return p_x + ((t - (VizCache.view_start or 0)) / (VizCache.view_len or VizCache.len)) * w
    end

    reaper.ImGui_PushClipRect(State.ui.ctx, p_x, p_y, p_x + w, p_y + h, true)

    if is_viz_blocked then
        local title = "Visualizer paused"
        local subtitle = "Selected item exceeds allowed loop length"
        local tw, th = reaper.ImGui_CalcTextSize(State.ui.ctx, title)
        local sw, sh = reaper.ImGui_CalcTextSize(State.ui.ctx, subtitle)
        reaper.ImGui_SetCursorScreenPos(State.ui.ctx, p_x + (w - tw) * 0.5, p_y + (h - th) * 0.45)
        reaper.ImGui_TextDisabled(State.ui.ctx, title)
        reaper.ImGui_SetCursorScreenPos(State.ui.ctx, p_x + (w - sw) * 0.5, p_y + (h - sh) * 0.58)
        reaper.ImGui_TextDisabled(State.ui.ctx, subtitle)
        if reaper.ImGui_IsMouseHoveringRect(State.ui.ctx, p_x, p_y, p_x + w, p_y + h) then
            reaper.ImGui_SetTooltip(State.ui.ctx, viz_block_reason)
        end
    elseif has_viz_data then
        local thresh_db = GrooveCore.extraction.threshold_db or -30
        local thresh_lin = 10 ^ (thresh_db / 20)

        local col_norm = 0xDDDDDDFF -- Light Grey for waveform
        local col_high = 0xFFFFFFAA
        local col_thresh = 0xFF2222FF
        local col_preview = 0x00FF00AA -- Green for groove markers

        local base_y = p_y + h
        local scale_x = w / (VizCache.w or w)

        local fill_col = (col_norm & 0xFFFFFF00) | 0x66

        for i = 1, #VizCache.peaks do
            local v = VizCache.peaks[i]
            local x = p_x + (i - 1) * scale_x
            local h_bar = v * h
            if h_bar > h then h_bar = h end

            if h_bar > 1 then
                reaper.ImGui_DrawList_AddLine(draw_list, x, base_y, x, base_y - h_bar, fill_col, 1.0)
            end
        end

        local points = {}
        for i = 1, #VizCache.peaks do
            local v = VizCache.peaks[i]
            local x = p_x + (i - 1) * scale_x
            local h_bar = v * h
            if h_bar > h then h_bar = h end

            points[#points + 1] = x
            points[#points + 1] = base_y - h_bar
        end

        if #points > 0 then
            local points_arr = reaper.new_array(points)
            reaper.ImGui_DrawList_AddPolyline(draw_list, points_arr, col_norm, 0, 1.5)
        end

        local y_thresh = base_y - (thresh_lin * h)
        if y_thresh < p_y then y_thresh = p_y end
        if y_thresh > base_y then y_thresh = base_y end

        reaper.ImGui_DrawList_AddLine(draw_list, p_x, y_thresh, p_x + w, y_thresh, col_thresh, 1.5)

        local last_t = -1
        local lockout = 0.050

        local v_start = VizCache.view_start or 0
        local v_end = v_start + (VizCache.view_len or VizCache.len)

        for _, cand in ipairs(PreviewCache.candidates) do
            if cand.t >= v_start and cand.t <= v_end then
                -- PreviewCache candidates are pre-validated by detectTransients.
                local x = MapTimeToX(cand.t)
                reaper.ImGui_DrawList_AddLine(draw_list, x, p_y, x, p_y + h, col_preview, 1.5)
            end
        end

        if reaper.ImGui_IsMouseHoveringRect(State.ui.ctx, p_x, p_y, p_x + w, p_y + h) then
            local name = VizCache.name or "Unknown"
            local mode = State.ui.viz_locked and "[LOCKED] " or "[LIVE] "
            reaper.ImGui_SetTooltip(State.ui.ctx, mode .. "Analyzing: " .. name)
        end
    elseif has_midi_data then
        local loop_len_qn = VizCache.midi_loop_len

        if not loop_len_qn or loop_len_qn <= 0 then
            loop_len_qn = reaper.TimeMap2_timeToQN(0, VizCache.len)
        end
        if loop_len_qn <= 0 then loop_len_qn = 4 end

        local min_p = VizCache.midi_min_pitch or 0
        local max_p = VizCache.midi_max_pitch or 127
        if max_p <= min_p then min_p, max_p = 0, 127 end
        local p_range = max_p - min_p + 5

        local grid_base = GrooveCore.extraction.grid_base or 0.25
        local vel_min = GrooveCore.extraction.velocity_min or 10

        local item_start_qn = reaper.TimeMap2_timeToQN(0, VizCache.pos)
        local v_start = VizCache.view_start or 0
        local v_end = v_start + (VizCache.view_len or VizCache.len)

        local qn_per_sec = loop_len_qn / VizCache.len
        local qn_view_start = v_start * qn_per_sec
        local qn_view_end = v_end * qn_per_sec

        for _, p in ipairs(VizCache.midi_points) do
            if p.pos >= qn_view_start and p.pos <= qn_view_end then
                local rel_pos_in_view = p.pos - qn_view_start
                local view_len_qn = qn_view_end - qn_view_start

                local x = p_x + (rel_pos_in_view / view_len_qn) * w

                local perfect_pos = math.floor(p.pos / grid_base + 0.5) * grid_base

                local note_idx = p.pitch - min_p + 2
                local y_norm = note_idx / p_range
                local note_h = math.max(2, h / p_range * 0.8)
                local note_y = p_y + h - (y_norm * h)

                local color = 0x8888FFAA
                if p.vel < vel_min then color = 0x88888855 end

                reaper.ImGui_DrawList_AddRectFilled(draw_list, x, note_y, x + uiScale(4), note_y + note_h, color)
            end
        end
    else
        local g = GrooveCore:getCurrentGroove()

        if State.runtime.gen_preview then
            g = GrooveCore:generateSwingGroove(State.runtime.gen_grid_val or 0.25, State.runtime.gen_swing or 0.57, State.runtime.gen_push_pull, State.runtime.gen_dynamics, true)
        end

        if g then
            if g.source_type == "MIDI" then
                local loop_len = g.length_beats
                if loop_len <= 0 then loop_len = 4 end

                local min_p, max_p = 127, 0
                for _, p in ipairs(g.points) do
                    if p.pitch then
                        if p.pitch < min_p then min_p = p.pitch end
                        if p.pitch > max_p then max_p = p.pitch end
                    end
                end
                if max_p < min_p then min_p, max_p = 36, 60 end
                local p_range = max_p - min_p + 5
                if p_range < 5 then p_range = 12 end

                for _, p in ipairs(g.points) do
                    local actual_pos = p.pos_qn + p.offset
                    local x_actual = (actual_pos % loop_len) / loop_len * w
                    local x_grid = (p.pos_qn % loop_len) / loop_len * w

                    local pitch = p.pitch or 60
                    local note_idx = pitch - min_p + 2
                    local y_norm = note_idx / p_range
                    local note_h = math.max(2, h / p_range * 0.8)
                    local note_y = p_y + h - (y_norm * h)

                    if math.abs(x_actual - x_grid) > 1 then
                        reaper.ImGui_DrawList_AddLine(draw_list, p_x + x_grid, p_y, p_x + x_grid, p_y + h, 0xFFFFFF22,
                            1.0)
                    end

                    local col = SPECIAL_COLORS.accent
                    local raw_vel = p.raw_vel or 100

                    local vel_min = GrooveCore.extraction.velocity_min or 0
                    if raw_vel < vel_min then
                        col = 0x77777740
                    else
                        local alpha = 0.4 + (raw_vel / 127) * 0.6
                        col = (col & 0xFFFFFF00) | math.floor(alpha * 255)
                    end

                    local note_w = math.max(3, w / 64)
                    if not (min_p == 36 and max_p == 60) and p_range > 0 then
                        reaper.ImGui_DrawList_AddRectFilled(draw_list, p_x + x_actual, note_y, p_x + x_actual + note_w,
                            note_y + note_h, col, 1.0)
                    else
                        reaper.ImGui_DrawList_AddRectFilled(draw_list, p_x + x_actual, p_y + h / 2 - 2,
                            p_x + x_actual + note_w, p_y + h / 2 + 2, col, 1.0)
                    end
                end
            else
                local loop_len = g.length_beats
                if loop_len <= 0 then loop_len = 4 end

                for _, p in ipairs(g.points) do
                    local pos_qn = p.pos_qn

                    local x = (pos_qn % loop_len) / loop_len * w
                    reaper.ImGui_DrawList_AddLine(draw_list, p_x + x, p_y, p_x + x, p_y + h, 0xFFFFFF33, 1)

                    local target_grid = GrooveCore.application.target_grid
                    local allowed = true
                    if target_grid > 0 then
                        local dist_to_grid = math.abs(p.pos_qn % target_grid)
                        if dist_to_grid > 0.01 and math.abs(dist_to_grid - target_grid) > 0.01 then allowed = false end
                    end

                    if allowed then
                        local offset_px = p.offset * (w / loop_len) * GrooveCore.application.timing_amount *
                            GrooveCore.application.global_intensity
                        local visual_x = x + offset_px

                        local color = SPECIAL_COLORS.accent
                        -- For generated grooves, visualize velocity dynamically
                        local vel_alpha = math.floor((p.velocity or 1.0) * 255)
                        if g.source_type == "GENERATED" then
                            color = (SPECIAL_COLORS.accent & 0xFFFFFF00) | vel_alpha
                        end

                        if (p.vel_delta or 0) > 20 then color = SPECIAL_COLORS.warn end
                        if (p.vel_delta or 0) < -20 then color = 0x55AAAAFF end

                        reaper.ImGui_DrawList_AddLine(draw_list, p_x + visual_x, p_y + uiScale(10), p_x + visual_x,
                            p_y + h - uiScale(10), color, uiScale(2))
                        local radius = uiScale(3)
                        if g.source_type == "GENERATED" then
                            radius = radius * (p.velocity or 1.0)
                        elseif p.vel_delta then
                            radius = math.max(uiScale(1.5),
                                math.min(uiScale(8), radius + (p.vel_delta / 25)))
                        end
                        reaper.ImGui_DrawList_AddCircleFilled(draw_list, p_x + visual_x, p_y + h / 2, radius, color)
                    else
                        reaper.ImGui_DrawList_AddCircle(draw_list, p_x + x, p_y + h / 2, uiScale(2), 0xFFFFFF40)
                    end
                end
            end
        else
            local txt = "Select Item"

            if State.ui.viz_locked then
                txt = "Groove Locked (Select Donor)"
            end

            local txt_w, txt_h = reaper.ImGui_CalcTextSize(State.ui.ctx, txt)
            reaper.ImGui_SetCursorScreenPos(State.ui.ctx, p_x + (w - txt_w) / 2, p_y + (h - txt_h) / 2)
            reaper.ImGui_TextDisabled(State.ui.ctx, txt)
        end
    end

    reaper.ImGui_PopClipRect(State.ui.ctx)

    reaper.ImGui_SetCursorScreenPos(State.ui.ctx, p_x, p_y)

    if reaper.ImGui_SetNextItemAllowOverlap then
        reaper.ImGui_SetNextItemAllowOverlap(State.ui.ctx)
    end

    reaper.ImGui_InvisibleButton(State.ui.ctx, "viz_drop_target", w, h)
    if reaper.ImGui_BeginDragDropTarget(State.ui.ctx) then
        local rv, count = reaper.ImGui_AcceptDragDropPayloadFiles(State.ui.ctx)
        if rv then
            local ok, filename = reaper.ImGui_GetDragDropPayloadFile(State.ui.ctx, 0)
            if ok and filename then GrooveCore:importAndAnalyzeFile(filename) end
        end
        reaper.ImGui_EndDragDropTarget(State.ui.ctx)
    end

    reaper.ImGui_DrawList_AddRectFilled(draw_list, p_x, p_y, p_x + w, p_y + h, 0x00000000)

    local ref_grid = GrooveCore.application.target_grid or 0
    if ref_grid > 0 then
        local loop_len_for_grid = 4
        if State.ui.viz_locked and GrooveCore:getCurrentGroove() then
            loop_len_for_grid = GrooveCore:getCurrentGroove().length_beats
        elseif VizCache.len > 0 then
            loop_len_for_grid = VizCache.len
        end

        if loop_len_for_grid > 0 then
            local grid_count = math.floor(loop_len_for_grid / ref_grid)
            for i = 0, grid_count do
                local qn_pos = i * ref_grid
                if qn_pos <= loop_len_for_grid then
                    local x_grid = (qn_pos % loop_len_for_grid) / loop_len_for_grid * w
                    reaper.ImGui_DrawList_AddLine(draw_list, p_x + x_grid, p_y, p_x + x_grid, p_y + h, 0xFFFFFF15, 1.0)
                end
            end
        end
    end

    reaper.ImGui_DrawList_AddRect(draw_list, p_x, p_y, p_x + w, p_y + h, 0xFFFFFF1A)

    reaper.ImGui_SetCursorScreenPos(State.ui.ctx, p_x + uiScale(5), p_y + uiScale(5))
    local lock_icon = State.ui.viz_locked and "LOCKED (Groove)" or "LIVE (Selection)"
    local btn_col = State.ui.viz_locked and 0xCC4444AA or 0x44CC44AA
    reaper.ImGui_PushStyleColor(State.ui.ctx, reaper.ImGui_Col_Button(), btn_col)
    if reaper.ImGui_Button(State.ui.ctx, lock_icon) then
        State.ui.viz_locked = not State.ui.viz_locked
        if State.ui.viz_locked and State.ui.viz_force_groove_view then
            VizCache.take = nil
            VizCache.id = nil
        end
    end
    reaper.ImGui_PopStyleColor(State.ui.ctx)

    if State.ui.viz_zoom > 1.0 then
        reaper.ImGui_SameLine(State.ui.ctx)
        reaper.ImGui_Text(State.ui.ctx, string.format("Zoom: %.1fx", State.ui.viz_zoom))
        if reaper.ImGui_IsItemClicked(State.ui.ctx) then State.ui.viz_zoom = 1.0 end
    end

    if reaper.ImGui_IsItemHovered(State.ui.ctx) then
        reaper.ImGui_SetTooltip(State.ui.ctx,
            "Visualizer Mode:\nLOCKED: Shows Groove Source (Donor)\nLIVE: Shows Selected Item\n\nControls:\nWheel: Zoom\nShift+Wheel: Scroll")
    end

    reaper.ImGui_SetCursorScreenPos(State.ui.ctx, p_x, p_y + h + uiScale(5))
end

local function SliderWithReset(label, v, v_min, v_max, format, default_val)
    local rv, new_v = reaper.ImGui_SliderDouble(State.ui.ctx, label, v, v_min, v_max, format)
    if reaper.ImGui_IsItemHovered(State.ui.ctx) and reaper.ImGui_IsMouseClicked(State.ui.ctx, reaper.ImGui_MouseButton_Right()) then
        return true, default_val
    end
    return rv, new_v
end

local function DrawGeneratorPanel()
    reaper.ImGui_Spacing(State.ui.ctx)
    reaper.ImGui_TextDisabled(State.ui.ctx, "GENERATOR")
    reaper.ImGui_Separator(State.ui.ctx)

    if not State.runtime.gen_grid_val then State.runtime.gen_grid_val = 0.25 end

    local current_gen_label = "1/16"
    for _, g in ipairs(GEN_GRID_DEFS) do
        if math.abs(State.runtime.gen_grid_val - g.val) < 0.001 then
            current_gen_label = g.label
            break
        end
    end

    if reaper.ImGui_BeginCombo(State.ui.ctx, "Grid##gen", current_gen_label) then
        for _, g in ipairs(GEN_GRID_DEFS) do
            local is_selected = (current_gen_label == g.label)
            if reaper.ImGui_Selectable(State.ui.ctx, g.label, is_selected) then
                State.runtime.gen_grid_val = g.val
            end
        end
        reaper.ImGui_EndCombo(State.ui.ctx)
    end

    if not State.runtime.gen_swing then State.runtime.gen_swing = 0.57 end
    local swing_int = math.floor(State.runtime.gen_swing * 100 + 0.5)
    local rv, new_swing_int = reaper.ImGui_SliderInt(State.ui.ctx, "Swing ##gen", swing_int, 50, 75, "%d%%")
    if rv then State.runtime.gen_swing = new_swing_int / 100 end
    if reaper.ImGui_IsItemHovered(State.ui.ctx) and reaper.ImGui_IsMouseClicked(State.ui.ctx, reaper.ImGui_MouseButton_Right()) then
        State.runtime.gen_swing = 0.57
        rv = true
    end

    if not State.runtime.gen_push_pull then State.runtime.gen_push_pull = 0.0 end
    local pp_int = math.floor(State.runtime.gen_push_pull * 100 + 0.5)
    local rv_pp, new_pp_int = reaper.ImGui_SliderInt(State.ui.ctx, "Push/Pull ##gen", pp_int, -25, 25, "%d%%")
    if rv_pp then State.runtime.gen_push_pull = new_pp_int / 100 end
    if reaper.ImGui_IsItemHovered(State.ui.ctx) and reaper.ImGui_IsMouseClicked(State.ui.ctx, reaper.ImGui_MouseButton_Right()) then
        State.runtime.gen_push_pull = 0.0
    end

    if not State.runtime.gen_dynamics then State.runtime.gen_dynamics = 0.0 end
    local dyn_int = math.floor(State.runtime.gen_dynamics * 100 + 0.5)
    local rv_dyn, new_dyn_int = reaper.ImGui_SliderInt(State.ui.ctx, "Velocity Curve ##gen", dyn_int, 0, 100, "%d%%")
    if rv_dyn then State.runtime.gen_dynamics = new_dyn_int / 100 end
    if reaper.ImGui_IsItemHovered(State.ui.ctx) and reaper.ImGui_IsMouseClicked(State.ui.ctx, reaper.ImGui_MouseButton_Right()) then
        State.runtime.gen_dynamics = 0.0
    end

    if reaper.ImGui_Button(State.ui.ctx, "Generate Swing") then
        GrooveCore:generateSwingGroove(State.runtime.gen_grid_val, State.runtime.gen_swing, State.runtime.gen_push_pull, State.runtime.gen_dynamics)
        statusSet("Generated Swing Groove", "ok")
    end
    reaper.ImGui_SameLine(State.ui.ctx)
    rv, State.runtime.gen_preview = reaper.ImGui_Checkbox(State.ui.ctx, "LP", State.runtime.gen_preview)
    if reaper.ImGui_IsItemHovered(State.ui.ctx) then
        reaper.ImGui_SetTooltip(State.ui.ctx,
            "Preview synthetic swing in real-time before generating.\nThis preview is independent from the selected groove.")
    end
end

local function DrawGroovePoolPanel()
    reaper.ImGui_TableNextColumn(State.ui.ctx)
    reaper.ImGui_TextDisabled(State.ui.ctx, "GROOVE POOL")
    reaper.ImGui_Separator(State.ui.ctx)

    local current_bank_label = GrooveCore.current_bank or "(Root)"
    reaper.ImGui_SetNextItemWidth(State.ui.ctx, uiScale(120))
    if reaper.ImGui_BeginCombo(State.ui.ctx, "##bank_combo", current_bank_label) then
        if reaper.ImGui_Selectable(State.ui.ctx, "(Root)", GrooveCore.current_bank == nil) then
            GrooveCore.current_bank = nil
            GrooveCore:loadGroovesFromDisk()
        end

        GrooveCore:refreshBanks()

        for _, b in ipairs(GrooveCore.banks) do
            local is_sel = (GrooveCore.current_bank == b)
            if reaper.ImGui_Selectable(State.ui.ctx, b, is_sel) then
                GrooveCore.current_bank = b
                GrooveCore:loadGroovesFromDisk()
            end
        end
        reaper.ImGui_EndCombo(State.ui.ctx)
    end

    reaper.ImGui_SameLine(State.ui.ctx)
    if reaper.ImGui_Button(State.ui.ctx, "+") then
        State.ui.rename_buffer = ""
        reaper.ImGui_OpenPopup(State.ui.ctx, "New Bank")
    end
    if reaper.ImGui_IsItemHovered(State.ui.ctx) then
        reaper.ImGui_SetTooltip(State.ui.ctx, "Create new Bank folder")
    end
    


    local center = { reaper.ImGui_Viewport_GetCenter(reaper.ImGui_GetMainViewport(State.ui.ctx)) }
    reaper.ImGui_SetNextWindowPos(State.ui.ctx, center[1], center[2], reaper.ImGui_Cond_Appearing(), 0.5, 0.5)
    if reaper.ImGui_BeginPopupModal(State.ui.ctx, "New Bank", true, reaper.ImGui_WindowFlags_AlwaysAutoResize()) then
        reaper.ImGui_Text(State.ui.ctx, "Enter Bank Name:")
        if reaper.ImGui_IsWindowAppearing(State.ui.ctx) then
            reaper.ImGui_SetKeyboardFocusHere(State.ui.ctx)
        end

        local _changed
        _changed, State.ui.rename_buffer = reaper.ImGui_InputText(State.ui.ctx, "##new_bank_input",
            State.ui.rename_buffer)

        local enter_pressed = reaper.ImGui_IsKeyPressed(State.ui.ctx, reaper.ImGui_Key_Enter())

        if reaper.ImGui_Button(State.ui.ctx, "Create", 120) or enter_pressed then
            local name = State.ui.rename_buffer
            local ok, err = GrooveCore:createBank(name)
            if ok then
                statusSet("Bank created: " .. name, "ok")
                reaper.ImGui_CloseCurrentPopup(State.ui.ctx)
            else
                statusSet("Failed: " .. (err or "unknown"), "error")
            end
        end
        reaper.ImGui_SameLine(State.ui.ctx)
        if reaper.ImGui_Button(State.ui.ctx, "Cancel", 120) then
            reaper.ImGui_CloseCurrentPopup(State.ui.ctx)
        end
        reaper.ImGui_EndPopup(State.ui.ctx)
    end

    if reaper.ImGui_BeginListBox(State.ui.ctx, "##pool_list", -1.19209290e-07, uiScale(180)) then
        if GrooveCore.current_bank then
            if reaper.ImGui_Selectable(State.ui.ctx, "[..]  (Up)", false) then
                GrooveCore.current_bank = nil
                GrooveCore:loadGroovesFromDisk()
            end
        else
            for _, b in ipairs(GrooveCore.banks) do
                if reaper.ImGui_Selectable(State.ui.ctx, "[+]  " .. b, false) then
                    GrooveCore.current_bank = b
                    GrooveCore:loadGroovesFromDisk()
                end
                
                if reaper.ImGui_BeginPopupContextItem(State.ui.ctx) then
                    if reaper.ImGui_MenuItem(State.ui.ctx, "Delete Bank") then
                        State.runtime.pending_bank_delete = b
                        if GrooveCore.current_bank == b then
                            GrooveCore.current_bank = nil
                            GrooveCore.pool = {}
                            GrooveCore.selected_indices = {}
                            GrooveCore.current_groove_index = nil
                            GrooveCore.last_clicked_index = nil
                        end
                        for idx = #GrooveCore.banks, 1, -1 do
                            if GrooveCore.banks[idx] == b then
                                table.remove(GrooveCore.banks, idx)
                                break
                            end
                        end
                        statusSet("Deleting bank: " .. tostring(b), "info")
                    end
                    reaper.ImGui_EndPopup(State.ui.ctx)
                end
            end
        end

        for i, g in ipairs(GrooveCore.pool) do
            local is_selected = GrooveCore.selected_indices[i] == true
            local is_active = (i == GrooveCore.current_groove_index)
            local display_name = g.name
            if is_active then
                display_name = "▶ " .. display_name
            else
                display_name = "   " .. display_name
            end
            if reaper.ImGui_Selectable(State.ui.ctx, display_name .. "##" .. i, is_selected) then
                local ctrl = reaper.ImGui_IsKeyDown(State.ui.ctx, reaper.ImGui_Mod_Ctrl())
                local shift = reaper.ImGui_IsKeyDown(State.ui.ctx, reaper.ImGui_Mod_Shift())

                if shift and GrooveCore.last_clicked_index then
                    local start_idx = GrooveCore.last_clicked_index
                    local end_idx = i
                    if start_idx > end_idx then start_idx, end_idx = end_idx, start_idx end

                    if not ctrl then GrooveCore.selected_indices = {} end
                    for k = start_idx, end_idx do GrooveCore.selected_indices[k] = true end
                elseif ctrl then
                    if GrooveCore.selected_indices[i] then
                        GrooveCore.selected_indices[i] = nil
                    else
                        GrooveCore.selected_indices[i] = true
                    end
                else
                    GrooveCore.selected_indices = { [i] = true }
                end

                GrooveCore.current_groove_index = i
                GrooveCore.last_clicked_index = i

                State.ui.viz_force_groove_view = true

                local item = reaper.GetSelectedMediaItem(0, 0)
                if item then
                    local take = reaper.GetActiveTake(item)
                    if take then
                        local _, guid = reaper.GetSetMediaItemTakeInfo_String(take, "GUID", "", false)
                        State.ui.last_selection_guid = guid
                    else
                        State.ui.last_selection_guid = "NONE"
                    end
                else
                    State.ui.last_selection_guid = "NONE"
                end
            end
            if reaper.ImGui_IsItemHovered(State.ui.ctx) then
                reaper.ImGui_SetTooltip(State.ui.ctx, g.name)
            end

            if reaper.ImGui_BeginPopupContextItem(State.ui.ctx) then
                if reaper.ImGui_MenuItem(State.ui.ctx, "Rename") then
                    State.ui.rename_buffer = g.name
                    State.ui.rename_modal_open = true
                    GrooveCore.current_groove_index = i
                    State.ui.open_rename_popup_request = true
                end

                if reaper.ImGui_BeginMenu(State.ui.ctx, "Move to Bank") then
                    if GrooveCore.current_bank ~= nil then
                        if reaper.ImGui_MenuItem(State.ui.ctx, "(Root)") then
                            local ok, err = GrooveCore:moveGroove(i, nil)
                            if ok then
                                GrooveCore:loadGroovesFromDisk()
                            else
                                statusSet("Move failed: " .. (err or "unknown"), "error")
                            end
                        end
                    end

                    for _, b in ipairs(GrooveCore.banks) do
                        if b ~= GrooveCore.current_bank then
                            if reaper.ImGui_MenuItem(State.ui.ctx, b) then
                                local ok, err = GrooveCore:moveGroove(i, b)
                                if ok then
                                    GrooveCore:loadGroovesFromDisk()
                                else
                                    statusSet("Move failed: " .. (err or "unknown"), "error")
                                end
                            end
                        end
                    end
                    reaper.ImGui_EndMenu(State.ui.ctx)
                end

                if reaper.ImGui_MenuItem(State.ui.ctx, "Delete") then
                    GrooveCore.selected_indices = { [i] = true }
                    GrooveCore.current_groove_index = i
                    GrooveCore:deleteSelectedGrooves()
                end
                reaper.ImGui_EndPopup(State.ui.ctx)
            end
        end
        reaper.ImGui_EndListBox(State.ui.ctx)
    end

    if State.ui.open_rename_popup_request then
        reaper.ImGui_OpenPopup(State.ui.ctx, "Rename Groove")
        State.ui.open_rename_popup_request = false
    end

    local has_groove = GrooveCore:getCurrentGroove() ~= nil
    local has_selection = false
    for _ in pairs(GrooveCore.selected_indices) do
        has_selection = true
        break
    end

    if not has_groove then reaper.ImGui_BeginDisabled(State.ui.ctx) end

    if reaper.ImGui_Button(State.ui.ctx, "Save", -1) then
        local g = GrooveCore:getCurrentGroove()
        if g and GrooveCore:saveGrooveToDisk(g) then
            statusSet("Saved " .. g.name, "ok")
        else
            statusSet("Save failed", "error")
        end
    end

    if reaper.ImGui_Button(State.ui.ctx, "Rename", -1) then
        local g = GrooveCore:getCurrentGroove()
        if g then
            State.ui.rename_buffer = g.name
            reaper.ImGui_OpenPopup(State.ui.ctx, "Rename Groove")
        end
    end

    local center = { reaper.ImGui_Viewport_GetCenter(reaper.ImGui_GetMainViewport(State.ui.ctx)) }
    reaper.ImGui_SetNextWindowPos(State.ui.ctx, center[1], center[2], reaper.ImGui_Cond_Appearing(), 0.5, 0.5)
    if reaper.ImGui_BeginPopupModal(State.ui.ctx, "Rename Groove", true, reaper.ImGui_WindowFlags_AlwaysAutoResize()) then
        reaper.ImGui_Text(State.ui.ctx, "Enter new name:")
        if reaper.ImGui_IsWindowAppearing(State.ui.ctx) then
            reaper.ImGui_SetKeyboardFocusHere(State.ui.ctx)
        end
        local _changed
        _changed, State.ui.rename_buffer = reaper.ImGui_InputText(
            State.ui.ctx,
            "##rename_input",
            State.ui.rename_buffer
        )
        local enter_pressed = reaper.ImGui_IsKeyPressed(State.ui.ctx, reaper.ImGui_Key_Enter())

        if reaper.ImGui_Button(State.ui.ctx, "OK", 120) or enter_pressed then
            local idx = GrooveCore.current_groove_index
            local requested = State.ui.rename_buffer or ""
            local success, err = GrooveCore:renameGroove(idx, requested)
            if success then
                local g2 = GrooveCore.pool[idx]
                local renamed = g2 and g2.name or State.ui.rename_buffer
                statusSet("Renamed to " .. renamed, "ok")
                reaper.ImGui_CloseCurrentPopup(State.ui.ctx)
            else
                statusSet("Rename failed: " .. (err or "unknown"), "error")
            end
        end

        reaper.ImGui_SameLine(State.ui.ctx)
        if reaper.ImGui_Button(State.ui.ctx, "Cancel", 120) then
            reaper.ImGui_CloseCurrentPopup(State.ui.ctx)
        end

        reaper.ImGui_EndPopup(State.ui.ctx)
    end

    if not has_groove then reaper.ImGui_EndDisabled(State.ui.ctx) end

    if not has_selection then reaper.ImGui_BeginDisabled(State.ui.ctx) end
    if reaper.ImGui_Button(State.ui.ctx, "Delete", -1) then
        GrooveCore:deleteSelectedGrooves()
    end
    if not has_selection then reaper.ImGui_EndDisabled(State.ui.ctx) end

    DrawGeneratorPanel()
end

local function DrawExtractionSettingsSection(current_groove)
    local is_live = (VizCache.id ~= nil) and (not State.ui.viz_locked)
    local show_settings = false
    local is_midi_source = false
    local settings_title = "EXTRACTION SETTINGS"

    if current_groove and not is_live then
        show_settings = true
        is_midi_source = (current_groove.source_type == "MIDI")
        settings_title = "EXTRACTION SETTINGS (Groove: " .. current_groove.name .. ")"
    elseif is_live then
        show_settings = true
        is_midi_source = VizCache.is_midi
        settings_title = "EXTRACTION SETTINGS (Live)"
    end

    if not show_settings then return end

    reaper.ImGui_TextDisabled(State.ui.ctx, settings_title)
    reaper.ImGui_Separator(State.ui.ctx)

    local is_midi = is_midi_source
    local grid_label = is_midi and "Ref Grid (Filter)" or "Base Grid"

    local current_grid_label = "1/16"
    for _, g in ipairs(GRID_DEFS) do
        if math.abs(GrooveCore.extraction.grid_base - g.val) < 0.001 then
            current_grid_label = g.label
            break
        end
    end

    if reaper.ImGui_BeginCombo(State.ui.ctx, grid_label, current_grid_label) then
        for _, g in ipairs(GRID_DEFS) do
            local is_selected = (current_grid_label == g.label)
            if reaper.ImGui_Selectable(State.ui.ctx, g.label, is_selected) then
                GrooveCore.extraction.grid_base = g.val
            end
        end
        reaper.ImGui_EndCombo(State.ui.ctx)
    end
    if is_midi and reaper.ImGui_IsItemHovered(State.ui.ctx) then
        reaper.ImGui_SetTooltip(State.ui.ctx,
            "Reference Grid: Notes too far from this grid (>20%) will be marked as 'Dirty' (Red).")
    end

    local rv
    if is_midi then
        local v_int = math.floor(GrooveCore.extraction.velocity_min or 10)
        rv, v_int = reaper.ImGui_SliderInt(State.ui.ctx, "Min Velocity", v_int, 0, 127, "%d")
        if rv then GrooveCore.extraction.velocity_min = v_int end
        if reaper.ImGui_IsItemHovered(State.ui.ctx) then
            reaper.ImGui_SetTooltip(State.ui.ctx,
                "Ghost Notes: Notes with velocity below this value will be excluded (Gray).")
        end
    else
        rv, GrooveCore.extraction.threshold_db = SliderWithReset("Threshold (dB)",
            GrooveCore.extraction.threshold_db or -30.0, -60.0, 0.0, "%.1f dB", -30.0)

        rv, GrooveCore.extraction.sensitivity = SliderWithReset("Sensitivity",
            GrooveCore.extraction.sensitivity or 0.5, 0.0, 1.0, "%.2f", 0.5)
        if reaper.ImGui_IsItemHovered(State.ui.ctx) then
            reaper.ImGui_SetTooltip(State.ui.ctx,
                "Adjusts dynamic threshold relative to RMS. Higher = more sensitive.")
        end

        local hpf = GrooveCore.extraction.hpf_hz or 0.0
        local lpf = GrooveCore.extraction.lpf_hz or 0.0

        local hpf_idx = 1
        local hpf_labels = { "Off", "60 Hz", "90 Hz", "150 Hz", "300 Hz", "500 Hz" }
        local hpf_vals = { 0.0, 60.0, 90.0, 150.0, 300.0, 500.0 }
        for i, v in ipairs(hpf_vals) do
            if math.abs(hpf - v) < 1e-3 then
                hpf_idx = i
                break
            end
        end
        if reaper.ImGui_BeginCombo(State.ui.ctx, "HPF", hpf_labels[hpf_idx]) then
            for i, label in ipairs(hpf_labels) do
                local sel = (i == hpf_idx)
                if reaper.ImGui_Selectable(State.ui.ctx, label, sel) then
                    GrooveCore.extraction.hpf_hz = hpf_vals[i]
                end
            end
            reaper.ImGui_EndCombo(State.ui.ctx)
        end
        if reaper.ImGui_IsItemHovered(State.ui.ctx) then
            reaper.ImGui_SetTooltip(State.ui.ctx, "High-pass the detector to reduce kick/low bleed and focus mids/highs.")
        end

        local lpf_idx = 1
        local lpf_labels = { "Off", "2 kHz", "4 kHz", "6 kHz", "8 kHz" }
        local lpf_vals = { 0.0, 2000.0, 4000.0, 6000.0, 8000.0 }
        for i, v in ipairs(lpf_vals) do
            if math.abs(lpf - v) < 1e-3 then
                lpf_idx = i
                break
            end
        end
        if reaper.ImGui_BeginCombo(State.ui.ctx, "LPF", lpf_labels[lpf_idx]) then
            for i, label in ipairs(lpf_labels) do
                local sel = (i == lpf_idx)
                if reaper.ImGui_Selectable(State.ui.ctx, label, sel) then
                    GrooveCore.extraction.lpf_hz = lpf_vals[i]
                end
            end
            reaper.ImGui_EndCombo(State.ui.ctx)
        end
        if reaper.ImGui_IsItemHovered(State.ui.ctx) then
            reaper.ImGui_SetTooltip(State.ui.ctx,
                "Low-pass the detector to reduce hats/highs and focus low-mid transients.")
        end
    end

    reaper.ImGui_Spacing(State.ui.ctx)
end

local function GetSelectionBackupState()
    local selected_count = reaper.CountSelectedMediaItems(0)
    local backup_count = 0
    local warning_count = 0

    if selected_count > 0 then
        for si = 0, selected_count - 1 do
            local sel_item = reaper.GetSelectedMediaItem(0, si)
            if sel_item then
                local _, chunk = reaper.GetSetMediaItemInfo_String(sel_item, ITEM_STATE_KEY, "", false)
                if chunk and chunk ~= "" then
                    backup_count = backup_count + 1
                    local _, orig_len_str = reaper.GetSetMediaItemInfo_String(sel_item, ITEM_LEN_KEY, "", false)
                    local _, orig_pos_str = reaper.GetSetMediaItemInfo_String(sel_item, ITEM_POS_KEY, "", false)
                    local cur_len = reaper.GetMediaItemInfo_Value(sel_item, "D_LENGTH")
                    local cur_pos = reaper.GetMediaItemInfo_Value(sel_item, "D_POSITION")
                    if math.abs(cur_len - (tonumber(orig_len_str) or 0)) > 0.0001 or
                        math.abs(cur_pos - (tonumber(orig_pos_str) or 0)) > 0.0001 then
                        warning_count = warning_count + 1
                    end
                end
            end
        end
    end

    return {
        selected_count = selected_count,
        backup_count = backup_count,
        warning_count = warning_count,
        has_backup = backup_count > 0,
        warning = warning_count > 0
    }
end

local function DrawApplyAndRestoreButtons(current_groove, backup_state)
    local right_padding = uiScale(15)
    local spacing = uiScale(5)
    local avail_w = reaper.ImGui_GetContentRegionAvail(State.ui.ctx) - right_padding
    local reset_w = uiScale(90)
    local apply_w = avail_w - reset_w - spacing
    local btn_h = uiScale(30)

    local col_normal = 0x26262dFF
    local col_hover = 0x5AA09BFF
    local col_active = 0x4A8580FF

    reaper.ImGui_PushStyleColor(State.ui.ctx, reaper.ImGui_Col_Button(), col_normal)
    reaper.ImGui_PushStyleColor(State.ui.ctx, reaper.ImGui_Col_ButtonHovered(), col_hover)
    reaper.ImGui_PushStyleColor(State.ui.ctx, reaper.ImGui_Col_ButtonActive(), col_active)

    local apply_disabled = not current_groove
    if apply_disabled then
        reaper.ImGui_BeginDisabled(State.ui.ctx)
    end

    if reaper.ImGui_Button(State.ui.ctx, "APPLY GROOVE", apply_w, btn_h) then
        statusSet("Applying groove...", "info")

        local g_name = current_groove and current_groove.name or "Groove"

        reaper.Undo_BeginBlock()
        local ok, msg, failed, details = GrooveCore:applyGroove()
        if ok then
            if failed and failed > 0 then
                statusSet(msg or "Groove applied with partial failures", "warn", nil, details)
            else
                statusSet(msg or "Groove Applied!", "ok", nil, details)
            end
            reaper.Undo_EndBlock("Apply Groove: " .. g_name, -1)
        else
            statusSet("Error: " .. (msg or "unknown"), "error", nil, details)
            reaper.Undo_EndBlock("Apply Groove (Failed)", -1)
        end
    end

    if apply_disabled then
        reaper.ImGui_EndDisabled(State.ui.ctx)
    end

    reaper.ImGui_PopStyleColor(State.ui.ctx, 3)
    reaper.ImGui_SameLine(State.ui.ctx)

    local disabled_mode = false
    local fallback_disabled = false

    if not backup_state.has_backup then
        if reaper.ImGui_BeginDisabled then
            reaper.ImGui_BeginDisabled(State.ui.ctx)
            disabled_mode = true
        else
            fallback_disabled = true
            reaper.ImGui_PushStyleColor(State.ui.ctx, reaper.ImGui_Col_Button(), 0x33333355)
            reaper.ImGui_PushStyleColor(State.ui.ctx, reaper.ImGui_Col_Text(), 0xAAAAAA55)
        end
    end

    local pushed_cols = 0
    if backup_state.warning then
        reaper.ImGui_PushStyleColor(State.ui.ctx, reaper.ImGui_Col_Button(), SPECIAL_COLORS.warn)
        reaper.ImGui_PushStyleColor(State.ui.ctx, reaper.ImGui_Col_ButtonHovered(),
            SPECIAL_COLORS.warn + 0x11111100)
        reaper.ImGui_PushStyleColor(State.ui.ctx, reaper.ImGui_Col_ButtonActive(),
            SPECIAL_COLORS.warn + 0x22222200)
        pushed_cols = 3
    end

    if reaper.ImGui_Button(State.ui.ctx, "ORIGINAL", reset_w, btn_h) then
        if backup_state.has_backup then
            reaper.Undo_BeginBlock()
            local ok, msg, failed, details = GrooveCore:restoreOriginalSelection()
            if ok then
                if failed and failed > 0 then
                    statusSet(msg or "Restore completed with partial failures", "warn", nil, details)
                else
                    statusSet(msg or "Restored Original State", "ok", nil, details)
                end
                reaper.Undo_EndBlock("Restore Original Item State(s)", -1)
            else
                statusSet("Restore Failed: " .. (msg or "unknown"), "error", nil, details)
                reaper.Undo_EndBlock("Restore Original Item State(s) (Failed)", -1)
            end
        end
    end

    if pushed_cols > 0 then
        reaper.ImGui_PopStyleColor(State.ui.ctx, pushed_cols)
    end

    if not backup_state.has_backup then
        if disabled_mode then
            reaper.ImGui_EndDisabled(State.ui.ctx)
        elseif fallback_disabled then
            reaper.ImGui_PopStyleColor(State.ui.ctx, 2)
        end
    else
        if reaper.ImGui_IsItemHovered(State.ui.ctx) then
            if not backup_state.has_backup then
                reaper.ImGui_SetTooltip(State.ui.ctx,
                    "No backup found on selected items.\nApply Groove first to create ORIGINAL snapshots.")
            elseif backup_state.warning then
                reaper.ImGui_SetTooltip(State.ui.ctx,
                    string.format(
                        "WARNING: %d item(s) changed length/position.\nORIGINAL will revert backed-up items to original bounds.\nBackups found on %d/%d selected item(s).",
                        backup_state.warning_count, backup_state.backup_count, backup_state.selected_count))
            elseif backup_state.backup_count < backup_state.selected_count then
                reaper.ImGui_SetTooltip(State.ui.ctx,
                    string.format(
                        "Backups found on %d/%d selected item(s).\nOnly backed-up items will be restored.",
                        backup_state.backup_count, backup_state.selected_count))
            else
                reaper.ImGui_SetTooltip(State.ui.ctx,
                    string.format("Restore original state for %d selected item(s)", backup_state.selected_count))
            end
        end
    end
end

local function DrawInjectorSection(current_groove)
    local backup_state = GetSelectionBackupState()
    local has_groove = current_groove ~= nil

    if not has_groove then
        reaper.ImGui_BeginDisabled(State.ui.ctx)
    end

    reaper.ImGui_TextDisabled(State.ui.ctx, "INJECTOR")
    reaper.ImGui_Separator(State.ui.ctx)

    if has_groove then
        reaper.ImGui_Text(State.ui.ctx, "Selected: " .. current_groove.name)
    else
        reaper.ImGui_Text(State.ui.ctx, "Selected: (None)")
    end

    local v_int
    local rv

    v_int = math.floor(GrooveCore.application.global_intensity * 100 + 0.5)
    rv, v_int = reaper.ImGui_SliderInt(State.ui.ctx, "Global Intensity", v_int, 0, 100, "%d%%")
    if rv then GrooveCore.application.global_intensity = v_int / 100 end
    if reaper.ImGui_IsItemHovered(State.ui.ctx) and reaper.ImGui_IsMouseClicked(State.ui.ctx, reaper.ImGui_MouseButton_Right()) then
        GrooveCore.application.global_intensity = 1.0
        rv = true
    end

    v_int = math.floor(GrooveCore.application.timing_amount * 100 + 0.5)
    rv, v_int = reaper.ImGui_SliderInt(State.ui.ctx, "Timing Strength", v_int, 0, 100, "%d%%")
    if rv then GrooveCore.application.timing_amount = v_int / 100 end
    if reaper.ImGui_IsItemHovered(State.ui.ctx) and reaper.ImGui_IsMouseClicked(State.ui.ctx, reaper.ImGui_MouseButton_Right()) then
        GrooveCore.application.timing_amount = 1.0
        rv = true
    end

    v_int = math.floor(GrooveCore.application.velocity_amount * 100 + 0.5)
    rv, v_int = reaper.ImGui_SliderInt(State.ui.ctx, "Velocity Strength", v_int, 0, 100, "%d%%")
    if rv then GrooveCore.application.velocity_amount = v_int / 100 end
    if reaper.ImGui_IsItemHovered(State.ui.ctx) and reaper.ImGui_IsMouseClicked(State.ui.ctx, reaper.ImGui_MouseButton_Right()) then
        GrooveCore.application.velocity_amount = 1.0
        rv = true
    end

    v_int = math.floor(GrooveCore.application.quantize_amount * 100 + 0.5)
    rv, v_int = reaper.ImGui_SliderInt(State.ui.ctx, "Grid Attraction", v_int, 0, 100, "%d%%")
    if rv then GrooveCore.application.quantize_amount = v_int / 100 end
    if reaper.ImGui_IsItemHovered(State.ui.ctx) and reaper.ImGui_IsMouseClicked(State.ui.ctx, reaper.ImGui_MouseButton_Right()) then
        GrooveCore.application.quantize_amount = 0.0
        rv = true
    end
    local window_ms_int = math.floor((GrooveCore.application.window_ms or 50) + 0.5)
    rv, window_ms_int = reaper.ImGui_SliderInt(State.ui.ctx, "Match Window (ms)", window_ms_int, 5, 200, "%d ms")
    if rv then GrooveCore.application.window_ms = window_ms_int end
    if reaper.ImGui_IsItemHovered(State.ui.ctx) and reaper.ImGui_IsMouseClicked(State.ui.ctx, reaper.ImGui_MouseButton_Right()) then
        GrooveCore.application.window_ms = 50
        rv = true
    end

    rv, GrooveCore.application.phase_coherent = reaper.ImGui_Checkbox(State.ui.ctx,
        "Phase Coherent Mode", GrooveCore.application.phase_coherent)
    if reaper.ImGui_IsItemHovered(State.ui.ctx) then
        reaper.ImGui_SetTooltip(State.ui.ctx,
            "When applying to multiple audio items, uses the first selected item as the Master Guide. All other items will receive identical timing shifts to preserve phase.")
    end

    reaper.ImGui_Spacing(State.ui.ctx)

    local current_filter_label = "All"
    if GrooveCore.application.target_grid > 0 then
        for _, g in ipairs(GRID_DEFS) do
            if math.abs(GrooveCore.application.target_grid - g.val) < 0.001 then
                current_filter_label = g.label
                break
            end
        end
    end

    if reaper.ImGui_BeginCombo(State.ui.ctx, "Target Filter", current_filter_label) then
        if reaper.ImGui_Selectable(State.ui.ctx, "All", current_filter_label == "All") then
            GrooveCore.application.target_grid = 0
        end
        for _, g in ipairs(GRID_DEFS) do
            local is_selected = (current_filter_label == g.label)
            if reaper.ImGui_Selectable(State.ui.ctx, g.label, is_selected) then
                GrooveCore.application.target_grid = g.val
            end
        end
        reaper.ImGui_EndCombo(State.ui.ctx)
    end
    if reaper.ImGui_IsItemHovered(State.ui.ctx) then
        reaper.ImGui_SetTooltip(State.ui.ctx, "Only apply groove points that match this grid division.")
    end

    reaper.ImGui_Spacing(State.ui.ctx)

    reaper.ImGui_TextDisabled(State.ui.ctx, "AUDIO VELOCITY SETTINGS")
    reaper.ImGui_Separator(State.ui.ctx)

    rv, GrooveCore.application.audio_apply_volume = reaper.ImGui_Checkbox(State.ui.ctx,
        "Apply Velocity to Volume", GrooveCore.application.audio_apply_volume)
    if reaper.ImGui_IsItemHovered(State.ui.ctx) then
        reaper.ImGui_SetTooltip(State.ui.ctx,
            "Enable to apply groove velocity changes to audio volume envelope. Creates envelope if missing.")
    end
    rv, GrooveCore.application.audio_max_db = SliderWithReset("Max Gain (dB)",
        GrooveCore.application.audio_max_db, 0.0, 24.0, "%.1f dB", 6.0)
    rv, GrooveCore.application.audio_pre_ms = SliderWithReset("Attack (ms)", GrooveCore.application.audio_pre_ms,
        0.0, 100.0, "%.0f ms", 15.0)
    rv, GrooveCore.application.audio_post_ms = SliderWithReset("Release (ms)",
        GrooveCore.application.audio_post_ms, 0.0, 200.0, "%.0f ms", 50.0)

    local shapes = { "Linear", "Square", "Slow Start/End", "Fast Start", "Fast End", "Bezier" }
    local current_shape = (GrooveCore.application.audio_shape or 2)
    if reaper.ImGui_BeginCombo(State.ui.ctx, "Env Shape", shapes[current_shape + 1] or "Slow Start/End") then
        for i, s in ipairs(shapes) do
            local is_selected = (current_shape == i - 1)
            if reaper.ImGui_Selectable(State.ui.ctx, s, is_selected) then
                GrooveCore.application.audio_shape = i - 1
            end
        end
        reaper.ImGui_EndCombo(State.ui.ctx)
    end

    if not has_groove then
        reaper.ImGui_EndDisabled(State.ui.ctx)
    end

    reaper.ImGui_Spacing(State.ui.ctx)

    DrawApplyAndRestoreButtons(current_groove, backup_state)
end

local function DrawInspectorPanel()
    reaper.ImGui_TableNextColumn(State.ui.ctx)
    local current_groove = GrooveCore:getCurrentGroove()
    DrawExtractionSettingsSection(current_groove)
    DrawInjectorSection(current_groove)
end

local function DrawContent()
    local viz_label
    local current_groove = GrooveCore:getCurrentGroove()
    if State.runtime.gen_preview then
        viz_label = "Visualizer: LP Generator Preview (synthetic)"
    elseif State.ui.viz_locked then
        if current_groove then
            viz_label = "Visualizer: Groove '" .. current_groove.name .. "'"
        else
            viz_label = "Visualizer: Groove (no groove selected)"
        end
    elseif State.ui.viz_force_groove_view and current_groove then
        viz_label = "Visualizer: Groove Preview '" .. current_groove.name .. "'"
    else
        viz_label = "Visualizer: Live Selection"
    end
    reaper.ImGui_TextDisabled(State.ui.ctx, viz_label)
    reaper.ImGui_Spacing(State.ui.ctx)

    local avail_w, _ = reaper.ImGui_GetContentRegionAvail(State.ui.ctx)
    local line_h = reaper.ImGui_GetTextLineHeight(State.ui.ctx)
    DrawVisualizer(avail_w, uiScale(100) + line_h)
    reaper.ImGui_Spacing(State.ui.ctx)

    if reaper.ImGui_BeginTable(State.ui.ctx, "MainLayout", 2, reaper.ImGui_TableFlags_Resizable()) then
        reaper.ImGui_TableSetupColumn(State.ui.ctx, "Inspector", reaper.ImGui_TableColumnFlags_None())
        reaper.ImGui_TableSetupColumn(State.ui.ctx, "Groove Pool", reaper.ImGui_TableColumnFlags_WidthFixed(),
            uiScale(150))

        DrawInspectorPanel()

        DrawGroovePoolPanel()

        reaper.ImGui_EndTable(State.ui.ctx)
    end
end

local function DrawStatusBar()
    local s = State.runtime.status
    local msg = ""
    local details = ""
    local color = reaper.ImGui_GetStyleColor(State.ui.ctx, reaper.ImGui_Col_Text())

    if s and s.message ~= "" then
        if reaper.time_precise() <= s.time + s.duration then
            msg = s.message
            details = s.details or ""
            if s.kind == "error" then color = SPECIAL_COLORS.error end
            if s.kind == "warn" then color = SPECIAL_COLORS.warn end
            if s.kind == "ok" then color = SPECIAL_COLORS.ok end
        else
            s.message = ""
            s.details = ""
        end
    end

    reaper.ImGui_Separator(State.ui.ctx)

    if msg ~= "" then
        reaper.ImGui_PushStyleColor(State.ui.ctx, reaper.ImGui_Col_Text(), color)
        reaper.ImGui_Text(State.ui.ctx, msg)
        reaper.ImGui_PopStyleColor(State.ui.ctx)
        if details ~= "" then
            reaper.ImGui_TextDisabled(State.ui.ctx, details)
        end
    else
        reaper.ImGui_Dummy(State.ui.ctx, 0, reaper.ImGui_GetTextLineHeight(State.ui.ctx))
    end
end

local function CreateUIFont()
    -- Map 'sans-serif' to OS default UI font.
    return reaper.ImGui_CreateFont("sans-serif", UI_CONST.FONT_SIZE)
end

local function Loop()
    if not State.ui.font then
        State.ui.font = CreateUIFont()
        reaper.ImGui_Attach(State.ui.ctx, State.ui.font)
    end

    if State.runtime.pending_bank_delete then
        local name = State.runtime.pending_bank_delete
        State.runtime.pending_bank_delete = nil
        local ok, err = GrooveCore:deleteBank(name)
        GrooveCore:loadGroovesFromDisk()
        if ok then
            statusSet("Bank deleted: " .. tostring(name), "ok")
        else
            statusSet("Failed to delete bank: " .. tostring(err or "unknown"), "error")
        end
    end

    local window_flags = 0
    if reaper.ImGui_ConfigVar_Flags then window_flags = window_flags | reaper.ImGui_WindowFlags_NoCollapse() end

    reaper.ImGui_SetNextWindowSize(State.ui.ctx, uiScale(600), uiScale(750), reaper.ImGui_Cond_FirstUseEver())

    local c_col, c_var = applyThemeBase()
    local visible, open = reaper.ImGui_Begin(State.ui.ctx, TITLE, true, window_flags)
    if visible then
        DrawMainToolbar()
        DrawContent()
        DrawStatusBar()
        DrawHelpModal()
        reaper.ImGui_End(State.ui.ctx)
    end
    endTheme(c_col, c_var)
    if not open then
        State.ui.open = false
        SaveSettings()
    end
    if State.ui.open then reaper.defer(Loop) end
end

local function Init()
    local dbg = reaper.GetExtState(EXT_NS, "debug_mode")
    if dbg == "1" then State.settings.debug_mode = true end

    -- Sync global DEBUG_MODE
    if DEBUG_MODE then State.settings.debug_mode = true end
    if State.settings.debug_mode then DEBUG_MODE = true end

    GrooveCore:loadGroovesFromDisk()
    reaper.defer(Loop)
end

Init()
