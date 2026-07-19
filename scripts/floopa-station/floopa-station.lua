-- Floopa Station
-- @description Floopa Station: five-track live looping station.
-- @version 1.1.3
-- @author Floop-s
-- @license GPL-3.0
-- @changelog
--   - Fixed MCP track color synchronization bug.
-- @about
--   Five-track live looping station for REAPER.
--
--   Designed for live performance with automated track setup,
--   smart auto-looping, and hands-free control. 
--
--   Requires:
--   - ReaImGui (ReaTeam Extensions repository), v0.10.2 or newer
--   - SWS Extension (ReaTeam Extensions repository)
--   Keywords: looper, live performance, recording, workflow.
-- @provides
--   [main] floopa-station.lua
--   modules/midi-map.lua




-- === REQUIREMENTS ==========================================
-- Dependencies and environment requirements
-- ===========================================================
if not reaper.ImGui_CreateContext then
    reaper.ShowMessageBox("ReaImGui API not found!\nPlease install 'ReaImGui' via ReaPack and restart Reaper.", "Error", 0)
    return
end

-- Dev wrapper extensions for HUD (placed after local defs)
if _G.__FLOOPA_NO_GUI__ then
    _G.__FLOOPA_DEV = _G.__FLOOPA_DEV or {}
    function _G.__FLOOPA_DEV.statusSet(msg, kind, duration)
        if statusSet then statusSet(msg, kind, duration) end
    end
    function _G.__FLOOPA_DEV.updateStatusHUD()
        if updateStatusHUD then updateStatusHUD() end
    end
    function _G.__FLOOPA_DEV.getStatus()
        local s = (State and State.status) or {}
        return { message = s.message, kind = s.kind, duration = s.duration, t = s.t }
    end
end

-- Developer-only helpers (headless mode)
if _G.__FLOOPA_NO_GUI__ then
    _G.__FLOOPA_DEV = _G.__FLOOPA_DEV or {}
    -- Allow tests to configure micro-fades without UI
    function _G.__FLOOPA_DEV.setLoopMicroFades(enabled, durationMs, shape)
        if State and State.loop and State.loop.microFades then
            State.loop.microFades.enabled = not not enabled
            if type(durationMs) == 'number' then
                State.loop.microFades.durationMs = math.max(0, math.floor(durationMs))
            end
            if type(shape) == 'string' then
                State.loop.microFades.shape = shape
            end
        end
    end
end
-- Developer-only exposures for headless test harness
local drawStatusBar

local getFloopaTracks


local function renderStatusBar()
    if not (State and State.ui and State.ui.ctx) then return end
    
    if drawStatusBar then drawStatusBar() end
  
    reaper.ImGui_Separator(State.ui.ctx)
    reaper.ImGui_Text(State.ui.ctx, "System active. Make sure your MIDI device has 'All' inputs enabled in Preferences > MIDI Devices to receive MIDI.")
    reaper.ImGui_Dummy(State.ui.ctx, 0, uiScale(6))
end



if not reaper.SNM_GetIntConfigVar or not reaper.SNM_SetIntConfigVar then
    reaper.ShowMessageBox("SWS extension not found!\nPlease install 'SWS Extension' via ReaPack and restart REAPER.", "Error", 0)
    return
end

-- === STATE =================================================
-- Central state management
-- ===========================================================
local State = {
    -- UI Context
    ui = {
        ctx = reaper.ImGui_CreateContext("Floopa-Station"),
        sans_serif = reaper.ImGui_CreateFont("sans-serif", 13),
        show_modal = false
    },
    
    -- Transport and Loop Settings
    transport = {
        bpmLast = reaper.Master_GetTempo(),
        actions = {1, 2, 4, 8, 16},
        selectedAction = nil,
        beatsPerMeasure = 4,
        tempDisableAutoPunch = false
    },



    -- User Input
    input = {
        bpm = tostring(reaper.Master_GetTempo()),
        measure = "",
        lastKeyTime = {},
        lastKeyTimeTag = {},
        keyCooldown = 0.18, -- 180 ms
        perActionCooldown = {}, 
    },
    
    -- Setup and Dependencies
    setup = {
        tracksCreated = false,
        floopaSetupDone = false,
        commandId = reaper.NamedCommandLookup("_SWS_SETMONMEDIA"),
        userSettings = {}
    },

   
    mappings = {
        data = {}, 
        actions = {
            { id = 'setup_revert',  label = 'Setup/Revert Floopa' },
            { id = 'play_pause',    label = 'Play/Pause' },
            { id = 'record_toggle', label = 'Record Toggle' },
            { id = 'metronome',     label = 'Toggle Metronome' },
            { id = 'toggle_click',  label = 'Toggle Click Track' },
            { id = 'select_trk',    label = 'Select Track 1..5' },
            { id = 'mute_trk',      label = 'Mute Selected Track' },
            { id = 'fx_trk',        label = 'Effects Selected Track' },
            { id = 'rev_trk',       label = 'Reverse Selected Track' },
            { id = 'toggle_input',  label = 'Toggle Input (Audio/MIDI)' },
            { id = 'pitch_up',      label = 'Transpose +12' },
            { id = 'pitch_down',    label = 'Transpose -12' },
            { id = 'undo_all',      label = 'Undo All Lanes' },
            { id = 'undo_lane',     label = 'Undo Lane' },
           
        },
        learn_action = nil, 
        manual_input = {}
    },
    
    -- Beat Counter
    beatCounter = {
        enabled = false,
        lastUpdate = 0,
        updateInterval = 0.05, -- Update every 50ms for smoothness
        accent = nil,
        border = nil,
        muted  = nil,
        bg     = nil,
        rounding = 6           
    },

    -- Loop Progress Bar
    progressBar = {
        enabled = true,
        height = 20,
        rounding = 6,
        fg = 0x55FF55FF,      
        bg = nil,             
        text = nil,           
        rateLimited = true,   -- enable rate-limited smoothing in enhanced renderer
        vmaxFracPerSec = 2.0  -- max fraction change per second 
    },

    -- Rec button palette and animation 
    recButton = {
        duration = 0.30, -- seconds
        normal = {0.8117647, 0.0588235, 0.2823529, 1.0}, -- #CF0F48
        hover  = {0.6901961, 0.0627451, 0.2470588, 1.0}, -- #B0103F
        active = {1.0, 0.0, 0.0, 1.0},                    -- #FF0000
        current = {0.8117647, 0.0588235, 0.2823529, 1.0}, 
        from = {0.8117647, 0.0588235, 0.2823529, 1.0},
        to = {0.8117647, 0.0588235, 0.2823529, 1.0},
        start = 0,
        last_hovered = false
    },

    -- Stop button palette 
    stopButton = {
        duration = 0.30, -- seconds
        normal = {0.1333333, 0.6901961, 0.2980392, 1.0}, -- #55FF55
        hover  = {0.1098039, 0.6039216, 0.2588235, 1.0}, -- #22B04C
        active = {0.2666667, 0.8, 0.2666667, 1.0}, 
        current = {0.1333333, 0.6901961, 0.2980392, 1.0}, 
        from = {0.1333333, 0.6901961, 0.2980392, 1.0},
        to = {0.1333333, 0.6901961, 0.2980392, 1.0},
        start = 0,
        last_hovered = false
    },

    -- Auto Loop Length settings
    loop = {
        autoEnabled = false,
        locked = false,
        quantize = 'measure', 
        tolerance = 0.12,     -- seconds tolerance for rounding
        startPos = nil,       
        detectEpsilon = 0.05, -- seconds, window tolerance when matching recorded items
        rounding = 'smart', 
        startAlign = 'measure', -- measure | exact (start position alignment)
        -- Micro-fades configuration
        microFades = {
            enabled = false,
            durationMs = 5,
            shape = 'linear',
        },
        -- Epsilon mode 
        epsilonMode = 'dynamic',     -- dynamic | strict
        strictEpsilonMs = 50,        -- used when epsilonMode = 'strict' 
    },

    -- Track group border theming and animation
    trackBorder = {
        duration = 0.30, -- seconds
        -- Theme mode: dark | light
        theme = "dark",
        themes = {
            dark = { 
                normal   = {0.40, 0.40, 0.40, 1.00}, 
                hover    = {0.65, 0.65, 0.65, 1.00}, 
                active   = {0.95, 0.80, 0.20, 1.00}, 
                selected = {0.10, 0.70, 0.95, 1.00}, 
                play     = {0.10, 0.70, 0.95, 1.00}, 
                muted    = {0.55, 0.55, 0.55, 1.00}, 
                armed    = {0.95, 0.15, 0.15, 1.00}   
            },
            light = {
                normal   = {0.40, 0.40, 0.40, 1.00},
                hover    = {0.20, 0.20, 0.20, 1.00},
                active   = {0.00, 0.50, 0.90, 1.00},
                selected = {0.00, 0.45, 0.80, 1.00},
                play     = {0.00, 0.55, 1.00, 1.00}, 
                muted    = {0.60, 0.60, 0.60, 1.00},
                armed    = {1.00, 0.25, 0.25, 1.00}  
            }
        },
        -- Per-track animation state
        anim = {
           
        }
    },

    -- Non-modal status/notifications
    status = {
        message = "",
        kind = "info",    
        t = 0,
        duration = 3.0
    },
    
    -- Track States
    tracks = {
        muteStates = {false, false, false, false, false},
        volumes = {},
        created = false
    },
    
    
    -- Count-in
    countIn = {
        executed = false,
        enabled = false
    }
}

-- Enable Docking if available
if reaper.ImGui_ConfigVar_Flags and reaper.ImGui_ConfigFlags_DockingEnable then
    local flags = reaper.ImGui_ConfigVar_Flags()
    local current_flags = reaper.ImGui_GetConfigVar(State.ui.ctx, flags)
    reaper.ImGui_SetConfigVar(State.ui.ctx, flags, current_flags | reaper.ImGui_ConfigFlags_DockingEnable())
end

-- === THEME =================================================
-- Theme colors - centralized color palette
-- ===========================================================

local THEME_COLORS = {
    [reaper.ImGui_Col_WindowBg()]         = 0x1E1E1EFF,  
    [reaper.ImGui_Col_TitleBg()]          = 0x444444FF,  
    [reaper.ImGui_Col_TitleBgActive()]    = 0x484848FF,  
    [reaper.ImGui_Col_Button()]           = 0x4444CCFF,  
    [reaper.ImGui_Col_ButtonHovered()]    = 0x6666FFFF,  
    [reaper.ImGui_Col_ButtonActive()]     = 0x222299FF,  
    [reaper.ImGui_Col_FrameBg()]          = 0x333333FF,  
    [reaper.ImGui_Col_FrameBgHovered()]   = 0x555555FF,  
    [reaper.ImGui_Col_FrameBgActive()]    = 0x777777FF,  
    [reaper.ImGui_Col_Text()]             = 0xFFFFFFFF,  
    [reaper.ImGui_Col_TextDisabled()]     = 0xAAAAAAFF,  
    [reaper.ImGui_Col_Border()]           = 0x4444CCFF,  
    [reaper.ImGui_Col_Separator()]        = 0x444444FF,  
    [reaper.ImGui_Col_CheckMark()]        = 0x6666FFFF,  
    [reaper.ImGui_Col_SliderGrab()]       = 0x6666FFFF,  
    [reaper.ImGui_Col_SliderGrabActive()] = 0x4444CCFF,  
    [reaper.ImGui_Col_Header()]           = 0x333333FF,  
    [reaper.ImGui_Col_HeaderHovered()]    = 0x555555FF,  
    [reaper.ImGui_Col_HeaderActive()]     = 0x777777FF,  
    [reaper.ImGui_Col_ResizeGrip()]       = 0x4444CCFF,  
    [reaper.ImGui_Col_ResizeGripHovered()] = 0x6666FFFF, 
    [reaper.ImGui_Col_ResizeGripActive()]  = 0x222299FF, 
}

-- Special colors for specific UI elements
local SPECIAL_COLORS = {
    red_button = 0xFF0000FF,      
    cyan_text = 0x66CCFFFF,       
    beat_counter_border = 0x4444CCFF, 
    track_highlight_bg = 0xCF0F48CC, 
    track_bg = 0x333333FF,        
    accent = 0x6666FFFF,          
    muted_text = 0xAAAAAAFF,      
    -- StatusBar specific 
    status_bg = 0x333333FF,
    status_ok_text = 0x66FF66FF,
    status_warn_text = 0xFFCC66FF,
    status_error_text = 0xFF6666FF,
}

-- REAPER Track color scheme for Floopa tracks (ensure custom color flag)
local FLOOPA_TRACK_COLOR_BASE     = (reaper.ColorToNative(68, 68, 204) | 0x1000000)
local FLOOPA_TRACK_COLOR_SELECTED = (reaper.ColorToNative(159, 6, 45)  | 0x1000000)

-- UI constants 
local UI_CONST = {
    GROUP_W = 160,
    BUTTON_W = 160, BUTTON_H = 30,
    SMALL_BUTTON_W = 75, SMALL_BUTTON_H = 30,
    SLIDER_W = 60,
    SLIDER_H = 150,
    SPACING_XS = 5,
    SPACING_SM = 10,
    SPACING_MD = 15,
    LABEL_PAD_X = 6,
    LABEL_PAD_Y = 2,
    BUTTON_ROUNDING = 5,
}

-- Aliases for common button sizes
UI_CONST.BTN_W = UI_CONST.BUTTON_W
UI_CONST.BTN_H = UI_CONST.BUTTON_H
UI_CONST.SMALL_BTN_W = UI_CONST.SMALL_BUTTON_W

local function uiScale(n)
    local s = (State and State.ui and State.ui.scale) or 1.0
    if s < 0.5 then s = 0.5 end
    if s > 2.0 then s = 2.0 end
    return math.floor(n * s)
end

-- Apply theme base function - sets up styles and base colors
local function applyThemeBase()
    -- Style variables (scaled)
    local s = (State and State.ui and State.ui.scale) or 1.0
    reaper.ImGui_PushStyleVar(State.ui.ctx, reaper.ImGui_StyleVar_FrameRounding(), uiScale(6))
    reaper.ImGui_PushStyleVar(State.ui.ctx, reaper.ImGui_StyleVar_WindowRounding(), uiScale(8))
    reaper.ImGui_PushStyleVar(State.ui.ctx, reaper.ImGui_StyleVar_WindowPadding(), uiScale(10), uiScale(10))
    reaper.ImGui_PushStyleVar(State.ui.ctx, reaper.ImGui_StyleVar_FramePadding(), uiScale(8), uiScale(6))
    reaper.ImGui_PushStyleVar(State.ui.ctx, reaper.ImGui_StyleVar_ItemSpacing(), uiScale(8), uiScale(8))
    
    -- Optional: center button text 
    local style_var_count = 5
    if reaper.ImGui_StyleVar_ButtonTextAlign then
        reaper.ImGui_PushStyleVar(State.ui.ctx, reaper.ImGui_StyleVar_ButtonTextAlign(), 0.5, 0.5)
        style_var_count = style_var_count + 1
    end

    -- Optional GrabRounding 
    if reaper.ImGui_StyleVar_GrabRounding then
        reaper.ImGui_PushStyleVar(State.ui.ctx, reaper.ImGui_StyleVar_GrabRounding(), uiScale(6))
        style_var_count = style_var_count + 1
    end
    
    -- Apply all theme colors
    local color_count = 0
    for color_id, color_value in pairs(THEME_COLORS) do
        reaper.ImGui_PushStyleColor(State.ui.ctx, color_id, color_value)
        color_count = color_count + 1
    end
    
    return color_count, style_var_count
end


local function end_theme(color_count, style_var_count)
  
    if color_count and color_count > 0 then
        reaper.ImGui_PopStyleColor(State.ui.ctx, color_count)
    end
    
    
    if style_var_count and style_var_count > 0 then
        
        local success, error_msg = pcall(function()
            reaper.ImGui_PopStyleVar(State.ui.ctx, style_var_count)
        end)
        if not success then
        
            
            for i = 1, style_var_count do
                local single_success = pcall(function()
                    reaper.ImGui_PopStyleVar(State.ui.ctx, 1)
                end)
                if not single_success then
       
                    break
                end
            end
        end
    end
end





-- === STYLE HELPERS =========================================
-- Helpers for colors, style variables, and scoped blocks
-- ===========================================================
local function with_colors(pairs, render_fn)
    local ctx = State and State.ui and State.ui.ctx
    if not ctx then return render_fn() end
    local count = 0
    for i = 1, #pairs do
        local id = pairs[i][1]
        local color = pairs[i][2]
        reaper.ImGui_PushStyleColor(ctx, id, color)
        count = count + 1
    end
    local ok, err = pcall(render_fn)
    local popped = pcall(function() reaper.ImGui_PopStyleColor(ctx, count) end)
    if not popped then
        for i = 1, count do pcall(function() reaper.ImGui_PopStyleColor(ctx, 1) end) end
    end
    if not ok then
        if statusSet then
            statusSet("UI render error: " .. tostring(err), "error", 2.0)
        else
            reaper.ShowMessageBox("UI render error: " .. tostring(err), "Floopa Station", 0)
        end
    end
end

local function with_vars(vars, render_fn)
    local ctx = State and State.ui and State.ui.ctx
    if not ctx then return render_fn() end
    local count = 0
    for i = 1, #vars do
        local var = vars[i][1]
        local a = vars[i][2]
        local b = vars[i][3]
        if b ~= nil then
            reaper.ImGui_PushStyleVar(ctx, var, a, b)
        else
            reaper.ImGui_PushStyleVar(ctx, var, a)
        end
        count = count + 1
    end
    local ok, err = pcall(render_fn)
    local popped = pcall(function() reaper.ImGui_PopStyleVar(ctx, count) end)
    if not popped then
        for i = 1, count do pcall(function() reaper.ImGui_PopStyleVar(ctx, 1) end) end
    end
    if not ok then
        if statusSet then
            statusSet("UI render error: " .. tostring(err), "error", 2.0)
        else
            reaper.ShowMessageBox("UI render error: " .. tostring(err), "Floopa Station", 0)
        end
    end
end

local function centerCursorForWidth(ctx, width)
    local availW = reaper.ImGui_GetContentRegionAvail(ctx)
    if not availW or availW <= 0 then return end
    local curX = reaper.ImGui_GetCursorPosX(ctx)
    local offset = (availW - width) * 0.5
    if offset and offset > 0 then
        reaper.ImGui_SetCursorPosX(ctx, curX + offset)
    end
end

local function rowSpacing()
    return UI_CONST and (UI_CONST.SPACING_SM or UI_CONST.SPACING_XS) or uiScale(10)
end

-- Unified style/color pusher 
local function with_style(styles, colors, render_fn)
    local ctx = State and State.ui and State.ui.ctx
    if not ctx then return render_fn() end
    local style_count = 0
    local color_count = 0
    if styles and #styles > 0 then
        for i = 1, #styles do
            local var = styles[i][1]
            local a = styles[i][2]
            local b = styles[i][3]
            if b ~= nil then
                reaper.ImGui_PushStyleVar(ctx, var, a, b)
            else
                reaper.ImGui_PushStyleVar(ctx, var, a)
            end
            style_count = style_count + 1
        end
    end
    if colors and #colors > 0 then
        for i = 1, #colors do
            reaper.ImGui_PushStyleColor(ctx, colors[i][1], colors[i][2])
            color_count = color_count + 1
        end
    end
    local ok, err = pcall(render_fn)
    if color_count > 0 then pcall(function() reaper.ImGui_PopStyleColor(ctx, color_count) end) end
    if style_count > 0 then pcall(function() reaper.ImGui_PopStyleVar(ctx, style_count) end) end
    if not ok then error(err) end
end


local function ensureCtx()
    return (State and State.ui and State.ui.ctx) or nil
end

local function get_special_color(name)
    return SPECIAL_COLORS[name] or 0xFFFFFFFF
end

reaper.ImGui_Attach(State.ui.ctx, State.ui.sans_serif)
if State.setup.commandId == 0 then
    State.setup.commandId = nil 
end

-- Compatibility wrapper for reaper.ImGui_PushFont
local function PushFontCompat(ctx, font, size)
    local ok = pcall(function() reaper.ImGui_PushFont(ctx, font, size) end)
    if not ok then
        reaper.ImGui_PushFont(ctx, font)
    end
end


local EXT_NS = "Floopa" 

local function extGet(key)

-- === PERSISTENCE ===========================================
-- ExtState utilities
-- ===========================================================

    if reaper.GetProjExtState then
        local ok, projVal = reaper.GetProjExtState(0, EXT_NS, key)
        if ok == 1 and projVal ~= "" then return projVal end
    end
   
    local v = reaper.GetExtState(EXT_NS, key)
    return (v ~= "" and v) or nil
end

local function extSet(key, value)
    local val = value or ""

    if reaper.SetProjExtState then
        reaper.SetProjExtState(0, EXT_NS, key, val)
    end

    reaper.SetExtState(EXT_NS, key, val, true)
end

-- Quick startup sanity check: logs basic invariants to console
local function sanityCheckOnStartup()
    -- Silent by default: only logs if ExtState 'debug_ui' == '1'
    local dbg = extGet('debug_ui')
    if dbg ~= '1' then return end
    if not reaper or not reaper.ShowConsoleMsg then return end
    local issues = {}
    -- UI_CONST aliases should exist and be numbers
    local bw = UI_CONST and UI_CONST.BTN_W or nil
    local bh = UI_CONST and UI_CONST.BTN_H or nil
    if type(bw) ~= 'number' or type(bh) ~= 'number' then
        issues[#issues+1] = 'UI_CONST aliases missing or invalid'
    end
    -- TrackBorder light theme 
    local tb = State and State.trackBorder
    local light = tb and tb.themes and tb.themes.light
    local required = {'normal','hover','active','selected','play','muted','armed'}
    if type(light) ~= 'table' then
        issues[#issues+1] = 'trackBorder.themes.light non-table'
    else
        for i=1,#required do
            local k = required[i]
            if type(light[k]) ~= 'table' or #light[k] < 4 then
                issues[#issues+1] = 'trackBorder.light missing channel '..k
                break
            end
        end
    end
    if #issues > 0 then
        reaper.ShowConsoleMsg('[Sanity] ' .. table.concat(issues, '; ') .. '\n')
    else
        reaper.ShowConsoleMsg('[Sanity] OK\n')
    end
end


local formatTime


-- === KEY MAPPING HELPERS ===================================
-- Key input utilities: conversion, parsing, and single-press detection
-- ===========================================================
local function keyFromAscii(n)
    if type(n) ~= 'number' then return nil end
    if n == 32 then return reaper.ImGui_Key_Space() end
    if n == 13 then return reaper.ImGui_Key_Enter() end
    if n == 9 then return reaper.ImGui_Key_Tab() end
    if n == 27 then return reaper.ImGui_Key_Escape() end
    if n >= 48 and n <= 57 then 
        local ch = string.char(n)
        local fn = reaper["ImGui_Key_" .. ch]
        return fn and fn() or nil
    end
    if n >= 65 and n <= 90 then 
        local ch = string.char(n)
        local fn = reaper["ImGui_Key_" .. ch]
        return fn and fn() or nil
    end
    if n >= 97 and n <= 122 then 
        local ch = string.char(n-32)
        local fn = reaper["ImGui_Key_" .. ch]
        return fn and fn() or nil
    end
    return nil
end

local function keyFromLabel(s)
    if not s then return nil end
    s = tostring(s)
    s = s:gsub("^%s+", ""):gsub("%s+$", "")

    if s:find("[,%s]") then
        s = s:match("^([^,%s]+)")
        if not s then return nil end
    end
    local u = s:upper()
    if #u == 1 and u:match("[A-Z0-9]") then
        local fn = reaper["ImGui_Key_" .. u]
        return fn and fn() or nil
    end
    if u:match("^F%d+$") then
        local n = tonumber(u:sub(2))
        if n and n >= 1 and n <= 12 then
            local fn = reaper["ImGui_Key_F" .. n]
            return fn and fn() or nil
        end
    end
    local aliases = {
        SPACE = reaper.ImGui_Key_Space,
        SPAZIO = reaper.ImGui_Key_Space,
        ENTER = reaper.ImGui_Key_Enter,
        RETURN = reaper.ImGui_Key_Enter,
        TAB = reaper.ImGui_Key_Tab,
        ESC = reaper.ImGui_Key_Escape,
        ESCAPE = reaper.ImGui_Key_Escape,
        LEFT = reaper.ImGui_Key_LeftArrow,
        RIGHT = reaper.ImGui_Key_RightArrow,
        UP = reaper.ImGui_Key_UpArrow,
        DOWN = reaper.ImGui_Key_DownArrow,
        DELETE = reaper.ImGui_Key_Delete,
        DEL = reaper.ImGui_Key_Delete,
    }
    local fn = aliases[u]
    return fn and fn() or nil
end

local function parseKeyInput(val)
    if val == nil then return nil end
 
    if type(val) == 'string' then
        local s = tostring(val)
        
        local byLabel = keyFromLabel(s)
        if byLabel then return byLabel end
       
        local num = tonumber(s)
        if num then return keyFromAscii(num) end
        return nil
    elseif type(val) == 'number' then
       
        if val >= 0 and val <= 255 then
            local fromAscii = keyFromAscii(val)
            if fromAscii then return fromAscii end
        end
       
        return val
    end
    return nil
end

local function keyPressedOnce(key)
    -- process keys only when Floopa window is focused to avoid conflicts
    if not (State and State.ui and State.ui.ctx) then return false end
    if reaper.ImGui_IsWindowFocused and not reaper.ImGui_IsWindowFocused(State.ui.ctx) then
        return false
    end
   
    local nk
    if type(key) == 'number' then
        nk = keyFromAscii(key)
        if not nk then
            
            nk = key
        end
    elseif type(key) == 'string' then
        nk = parseKeyInput(key)
    end
    if type(nk) ~= 'number' then return false end
    local now = reaper.time_precise()
    if reaper.ImGui_IsKeyPressed(State.ui.ctx, nk) then
        local last = State.input.lastKeyTime[nk] or 0
        if now - last > State.input.keyCooldown then
            State.input.lastKeyTime[nk] = now
            return true
        end
    end
    return false
end


-- === STATUS & HUD ==========================================
-- Non-modal status messages and HUD info bar
-- ===========================================================
local function statusSet(msg, kind, duration)
    State.status.message = msg or ""
    State.status.kind = kind or "info"
    State.status.t = reaper.time_precise()
    if duration and type(duration) == "number" then State.status.duration = duration end
end

local function drawStatusBar()
    if not (State and State.ui and State.ui.ctx) then return end
    local msg = State.status.message
    if not msg or msg == "" then return end
    local elapsed = reaper.time_precise() - (State.status.t or 0)
    if elapsed > (State.status.duration or 3.0) then return end

    local bg = get_special_color("status_bg")
    local col = get_special_color("muted_text")
    if State.status.kind == "ok" then
        col = get_special_color("status_ok_text")
    elseif State.status.kind == "warn" then
        col = get_special_color("status_warn_text")
    elseif State.status.kind == "error" then
        col = get_special_color("status_error_text")
    end

    with_style(
        {{reaper.ImGui_StyleVar_FramePadding(), 8, 6}},
        {
            {reaper.ImGui_Col_FrameBg(), bg},
            {reaper.ImGui_Col_Border(), get_special_color("beat_counter_border")},
            {reaper.ImGui_Col_Text(), col},
        },
        function()
            if reaper.ImGui_BeginChild(State.ui.ctx, "StatusBar", -1, uiScale(32), reaper.ImGui_ChildFlags_Borders()) then
                reaper.ImGui_Text(State.ui.ctx, msg)
                reaper.ImGui_EndChild(State.ui.ctx)
            end
        end
    )
end


local function updateStatusHUD()
    local enabled = (extGet("hud_enable") == "1")
    if not enabled then return end
    if not State.perf then State.perf = {} end
    local now = reaper.time_precise()
    local interval = State.perf.hudInterval or 0.8
    local last = State.perf.lastHudUpdate or 0
    if (now - last) < interval then return end
    local playstate = reaper.GetPlayState()
    local isPlaying = (playstate & 1) == 1 or (playstate & 4) == 4
    local pos = isPlaying and reaper.GetPlayPosition() or reaper.GetCursorPosition()
    local metro = (reaper.GetToggleCommandState(40364) == 1)
    local click = hasClickTrack and hasClickTrack() or false
    local hud = string.format("[Metro:%s] [Click:%s]  %s", metro and "ON" or "OFF", click and "ON" or "OFF", format_mm_ss(pos))
    local nowMsg = State.status.message or ""
    local nowKind = State.status.kind or "info"
    local elapsed = reaper.time_precise() - (State.status.t or 0)
    local active = (nowMsg ~= "" and elapsed <= (State.status.duration or 3.0))
    
    if active then return end
    statusSet(hud, "info", 0.5)
    State.perf.lastHudUpdate = now
end


local function notifyInfo(message, duration)
    statusSet(message or "", "info", duration or 2.5)
end



local function toggleTransportPlayStop()
    local ps = reaper.GetPlayState()
    local isPlayingOrRecording = ((ps & 1) == 1) or ((ps & 4) == 4)
    if isPlayingOrRecording then
        reaper.Main_OnCommand(1016, 0) 
    else
        if reaper.OnPlayButton then
            reaper.OnPlayButton() 
        else
            reaper.CSurf_OnPlay() 
        end
    end
end


-- === TRANSPORT & PROGRESS ==================================
-- Timing utilities, smoothing, and transport state helpers
-- ===========================================================
local function format_mm_ss(seconds)
    if not seconds or seconds < 0 then seconds = 0 end
    local m = math.floor(seconds / 60)
    local s = math.floor(seconds % 60)
    return string.format("%02d:%02d", m, s)
end


function computeSmoothingAlpha(dt)
    if not dt or dt < 0 then dt = 0 end
    local a = dt * 0.5
    if a < 0.08 then a = 0.08 end
    if a > 0.35 then a = 0.35 end
    return a
end

function applySmoothing(prev, current, alpha)
    prev = prev or 0
    current = current or 0
    alpha = alpha or 0
    local val = prev + alpha * (current - prev)
    if val < 0 then val = 0 end
    if val > 1 then val = 1 end
    return val
end


local function getMetronomeState()
    return reaper.GetToggleCommandState(40364) == 1
end


local function hasClickTrack()
    local numTracks = reaper.CountTracks(0)
    for i = 0, numTracks - 1 do
        local t = reaper.GetTrack(0, i)
        local ok, name = reaper.GetSetMediaTrackInfo_String(t, "P_NAME", "", false)
        if ok and (name == "Floopa Click Track" or name == "Click Track") then return true end
    end
    return false
end

function getLoopProgress()
    local start_t, end_t = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
    local len = end_t - start_t
    if not start_t or not end_t or len <= 0 then
        return { valid=false, fraction=0, elapsed=0, remaining=0, length=0, start=0, stop=0 }
    end

    local playstate = reaper.GetPlayState()
    local isPlaying = (playstate & 1) == 1 or (playstate & 4) == 4
    local pos = isPlaying and reaper.GetPlayPosition() or reaper.GetCursorPosition()

    local rel = pos - start_t
    if rel < 0 then rel = 0 end
    if rel > len then rel = rel % len end
  
    local end_eps = (State.progressBar and State.progressBar.endEpsilonSec) or 0.01 -- 10 ms
    if (len - rel) >= 0 and (len - rel) < end_eps then
        rel = len
    end
    local frac = len > 0 and (rel / len) or 0
    local remaining = len - rel
    return { valid=true, fraction=math.max(0, math.min(1, frac)), elapsed=rel, remaining=remaining, length=len, start=start_t, stop=end_t, playing=isPlaying }
end



-- === LOOP PROGRESS BAR =====================================
-- Loop progress bar 
-- ===========================================================
function drawLoopProgressBarEnhanced()
    if not State.ui or not State.ui.ctx then return end
    if not State.progressBar or not State.progressBar.enabled then return end

    local p = getLoopProgress()
    local avail = reaper.ImGui_GetContentRegionAvail(State.ui.ctx)
    local w = math.max(200, avail)
    local h = uiScale(State.progressBar.height or 10)
    local rounding = State.progressBar.rounding or 2
    local fg = State.progressBar.fg or get_special_color("accent")
    local bg = State.progressBar.bg or THEME_COLORS[reaper.ImGui_Col_FrameBg()]

    with_vars({{reaper.ImGui_StyleVar_FrameRounding(), rounding}} , function()
    local color = fg
    
    with_colors({
        {reaper.ImGui_Col_PlotHistogram(), color},
        {reaper.ImGui_Col_FrameBg(), bg},
    }, function()

    -- Progress bar animation
    local frac = (p.valid and p.fraction) or 0
    local now = reaper.time_precise()
    local lastTs = State.progressBar and State.progressBar._lastTs or now
    local dt = now - lastTs
    if not dt or dt < 0 then dt = 0 end
    local dispPrev = State.progressBar and State.progressBar._dispFrac
    if dispPrev == nil then dispPrev = frac end
    local frac_smooth
    if State.progressBar and State.progressBar.rateLimited then
        local delta = frac - dispPrev
        if delta <= 0 then
          
            frac_smooth = frac
        else
            -- vmax dinamico:
            local targetSpeed = (p and p.valid and p.length and p.length > 0) and (1.0 / p.length) or 0.0
            local vmaxBase = State.progressBar.vmaxFracPerSec or 2.0
            local vmax = math.max(vmaxBase, targetSpeed * 1.10)
            local max_step = vmax * dt
            if delta <= max_step then
                frac_smooth = frac
            else
                frac_smooth = dispPrev + max_step
            end
        end
    else
        
        frac_smooth = frac
    end
    
    if p and p.valid then
        local eps_dyn = (dt and dt > 0) and (dt * 0.75) or 0
        if p.remaining and p.remaining <= eps_dyn then
            frac_smooth = 1.0
        end
    end
    if State.progressBar then
        State.progressBar._lastTs = now
        State.progressBar._dispFrac = frac_smooth
    end
    if frac_smooth < 0 then frac_smooth = 0 elseif frac_smooth > 1 then frac_smooth = 1 end

    
    local label = ""
    if State.progressBar and State.progressBar.detail == true and p and p.valid then
        local bpm = reaper.Master_GetTempo()
        if bpm <= 0 then bpm = 120 end
        local num, den = getCurrentTimeSig()
        local spb = 60 / bpm
        local beats_per_bar = num * (4 / den)
        local bars = (p.length / spb) / beats_per_bar
        label = string.format("Loop %.1fs • %.2f bars", p.length, bars)
    end

    reaper.ImGui_ProgressBar(State.ui.ctx, frac_smooth, w, h, label)
    end)
    end)
end

-- Beat counter UI

local function getCurrentTimeSig()
    local proj = 0
    local playPos = reaper.GetPlayPosition()
    local function getTimeSigAt(time)
        if reaper.TimeMap2_getTimeSigAtTime then
            return reaper.TimeMap2_getTimeSigAtTime(proj, time)
        end
        if reaper.TimeMap2_GetTimeSigAtTime then
            return reaper.TimeMap2_GetTimeSigAtTime(proj, time)
        end
        if reaper.TimeMap_GetTimeSigAtTime then
            return reaper.TimeMap_GetTimeSigAtTime(proj, time)
        end
        return nil
    end
    local ok, num, den = pcall(getTimeSigAt, playPos)
    if ok and num and den then
        return num, den
    else
        return State.transport.beatsPerMeasure, 4
    end
end

local function getCurrentBeatPosition()
    local proj = 0
    local playPos = reaper.GetPlayPosition()
    local qn = 0
    if reaper.TimeMap2_timeToQN then
        qn = reaper.TimeMap2_timeToQN(proj, playPos)
    else
        local ok, a, b = pcall(reaper.TimeMap2_timeToBeats, proj, playPos)
        if ok then
            qn = (type(b) == 'number') and b or ((type(a) == 'number') and a or 0)
        end
    end
    local num, den = getCurrentTimeSig()
    local measureQN = num * (4 / den)
    local posQNInMeasure = (qn % measureQN)
    local beatInMeasureDen = posQNInMeasure / (4 / den)
    local currentBeat = math.floor(beatInMeasureDen) + 1
    if currentBeat < 1 then currentBeat = 1 end
    if currentBeat > num then currentBeat = num end
    return currentBeat, num, den
end

-- === BEAT COUNTER ==========================================
-- Beat counter visualization and controls
-- ===========================================================
local function drawBeatCounter()
    if not (State and State.ui and State.ui.ctx) then return end
    if not State.beatCounter.enabled then return end

    local currentBeat, num, den = getCurrentBeatPosition()

    local accent = State.beatCounter.accent or THEME_COLORS[reaper.ImGui_Col_CheckMark()]
    local border = State.beatCounter.border or THEME_COLORS[reaper.ImGui_Col_Border()]
    local muted = State.beatCounter.muted  or THEME_COLORS[reaper.ImGui_Col_TextDisabled()]

    with_colors({
        {reaper.ImGui_Col_FrameBg(), THEME_COLORS[reaper.ImGui_Col_FrameBg()]},
        {reaper.ImGui_Col_Border(),  border},
    }, function()
        with_vars({
            {reaper.ImGui_StyleVar_FramePadding(),      9, 6},
            {reaper.ImGui_StyleVar_WindowRounding(),   State.beatCounter.rounding or 6},
            {reaper.ImGui_StyleVar_ScrollbarSize(),    0},
        }, function()

    local childW = -1
    local childH = uiScale(34)
    if reaper.ImGui_BeginChild(State.ui.ctx, "BeatCounter", childW, childH, reaper.ImGui_ChildFlags_Borders()) then
        local frameH = reaper.ImGui_GetFrameHeight(State.ui.ctx)
        local baseY = math.floor((childH - frameH) * 0.5)
        reaper.ImGui_SetCursorPosY(State.ui.ctx, baseY)

        reaper.ImGui_AlignTextToFramePadding(State.ui.ctx)
        reaper.ImGui_Text(State.ui.ctx, string.format("%d/%d:", num, den))
        reaper.ImGui_SameLine(State.ui.ctx)
        reaper.ImGui_AlignTextToFramePadding(State.ui.ctx)
        reaper.ImGui_Text(State.ui.ctx, "Beats:")
        reaper.ImGui_SameLine(State.ui.ctx)

        for i = 1, num do
            if i > 1 then reaper.ImGui_SameLine(State.ui.ctx) end
            if i == currentBeat then
                with_colors({
                    {reaper.ImGui_Col_Button(),        accent},
                    {reaper.ImGui_Col_ButtonHovered(), accent},
                    {reaper.ImGui_Col_ButtonActive(),  accent},
                    {reaper.ImGui_Col_Text(),          THEME_COLORS[reaper.ImGui_Col_Text()]},
                }, function()
                    with_vars({
                        {reaper.ImGui_StyleVar_FrameRounding(), State.beatCounter.rounding or 6}
                    }, function()
                        reaper.ImGui_Button(State.ui.ctx, tostring(i))
                    end)
                end)
            else
                reaper.ImGui_AlignTextToFramePadding(State.ui.ctx)
                with_colors({
                    {reaper.ImGui_Col_Text(), muted}
                }, function()
                    reaper.ImGui_Text(State.ui.ctx, tostring(i))
                end)
            end
        end
        reaper.ImGui_EndChild(State.ui.ctx)
    end
        end)
    end)
end

local function drawBeatCounterSection()
    if not (State and State.ui and State.ui.ctx) then return end
    reaper.ImGui_SameLine(State.ui.ctx, nil, uiScale(10))
    local toggledBC = reaper.ImGui_Checkbox(State.ui.ctx, "Beat Counter", State.beatCounter.enabled)
    if toggledBC then
        State.beatCounter.enabled = not State.beatCounter.enabled
    end
    if State.beatCounter.enabled then
        reaper.ImGui_Dummy(State.ui.ctx, 0, uiScale(6))
        drawBeatCounter()
    end
end


local goToMeasure, setBPM, setLoop, saveLoopAutoSettings, clearAllFloopa
local setupFloopa, revertFloopa
local renderMainControls, renderBeatCounter

-- Helper: Get list of Floopa tracks (1..5)
-- Defined here to be accessible by cleanEmptyItems
local function getFloopaTracks()
    local list = {}
    local numTracks = reaper.CountTracks(0)
    for i = 0, numTracks - 1 do
        local t = reaper.GetTrack(0, i)
        local ok, name = reaper.GetSetMediaTrackInfo_String(t, "P_NAME", "", false)
        if ok and name then
            local n = name:match("^Floopa (%d+)$")
            if n then
                table.insert(list, { track = t, num = tonumber(n) })
            end
        end
    end
    table.sort(list, function(a,b) return a.num < b.num end)
    return list
end

-- Prunes empty items from Floopa tracks and removes unused lanes.
-- Criteria: MIDI with 0 events, or Audio below -50dB threshold.
local function cleanEmptyItems()
    reaper.Undo_BeginBlock()
    local count = 0
    local threshold_db = -50
    
    local function getAudioPeak(item)
        -- Prefer SWS API for performance
        if reaper.NF_GetMediaItemMaxPeak then
            return reaper.NF_GetMediaItemMaxPeak(item)
        end
        
        -- Fallback: Native sample analysis via Audio Accessor
        local take = reaper.GetActiveTake(item)
        if not take then return -150 end
        
        local accessor = reaper.CreateTakeAudioAccessor(take)
        if not accessor then return -150 end
        
        local src = reaper.GetMediaItemTake_Source(take)
        local num_channels = reaper.GetMediaSourceNumChannels(src)
        local rate = reaper.GetMediaSourceSampleRate(src)
        if rate == 0 then rate = 44100 end
        
        local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
        local start_offs = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
        
        -- Sample subset of points to maintain UI responsiveness
        local points = 100 
        local step = math.max(0.01, len / points)
        
        local buffer = reaper.new_array(num_channels * 2)
        local max_val = 0
        
        for t = 0, len, step do
            reaper.GetAudioAccessorSamples(accessor, rate, num_channels, t + start_offs, 1, buffer)
            local samples = buffer.table()
            for _, s in ipairs(samples) do
                local abs_s = math.abs(s)
                if abs_s > max_val then max_val = abs_s end
            end
            if max_val > 0.5 then break end -- Early exit on high signal
        end
        
        reaper.DestroyAudioAccessor(accessor)
        
        if max_val == 0 then return -150 end
        return 20 * math.log(max_val, 10)
    end

    local floopa_tracks = getFloopaTracks()
    local tracks_cleaned = {} 

    for _, tdata in ipairs(floopa_tracks) do
        local track = tdata.track
        if track then
            local item_count = reaper.CountTrackMediaItems(track)
            local track_cleaned_something = false
            
            -- Iterate backwards to safely delete items
            for j = item_count - 1, 0, -1 do
                local item = reaper.GetTrackMediaItem(track, j)
                if item then
                    local take = reaper.GetActiveTake(item)
                    if take then
                        local should_delete = false
                        if reaper.TakeIsMIDI(take) then
                            local _, notecnt = reaper.MIDI_CountEvts(take)
                            if notecnt == 0 then should_delete = true end
                        else
                            local peak_db = getAudioPeak(item)
                            if peak_db < threshold_db then should_delete = true end
                        end

                        if should_delete then
                            reaper.DeleteTrackMediaItem(track, item)
                            count = count + 1
                            track_cleaned_something = true
                        end
                    end
                end
            end
            
            if track_cleaned_something then
                table.insert(tracks_cleaned, track)
            end
        end
    end
    
    -- Prune empty lanes on affected tracks
    if #tracks_cleaned > 0 then
        reaper.Main_OnCommand(40297, 0) -- Unselect all
        for _, tr in ipairs(tracks_cleaned) do
            reaper.SetTrackSelected(tr, true)
        end
        reaper.Main_OnCommand(42689, 0) -- Track lanes: Delete empty lanes
        reaper.Main_OnCommand(40297, 0) -- Restore unselected state
    end

    reaper.UpdateArrange()
    reaper.Undo_EndBlock("Clean Empty Floopa Items", -1)
    
    if count > 0 then
        notifyInfo(string.format("Cleaned %d empty items (< %d dB) & lanes", count, threshold_db))
    else
        notifyInfo(string.format("No empty items found (Threshold: %d dB)", threshold_db))
    end
end

-- === TRANSPORT CONTROLS ==================================
-- Measure, BPM, Go To, Play/Stop, and Clear
-- ===========================================================
local function drawTransportControls()
    if not (State and State.ui and State.ui.ctx) then return end
    reaper.ImGui_Dummy(State.ui.ctx, 0, uiScale(5))

    reaper.ImGui_AlignTextToFramePadding(State.ui.ctx)
    reaper.ImGui_Text(State.ui.ctx, "Measure:")
    reaper.ImGui_SameLine(State.ui.ctx)
    reaper.ImGui_SetNextItemWidth(State.ui.ctx, uiScale(100))
    with_vars({
        {reaper.ImGui_StyleVar_FramePadding(), 5, 7},
        {reaper.ImGui_StyleVar_FrameRounding(), UI_CONST.BUTTON_ROUNDING},
    }, function()
        local changed, new_measure_input = reaper.ImGui_InputText(State.ui.ctx, "##measure_input", State.input.measure, reaper.ImGui_InputTextFlags_CharsDecimal())
        if changed then State.input.measure = new_measure_input end
    end)
    reaper.ImGui_SameLine(State.ui.ctx)
    with_vars({
        {reaper.ImGui_StyleVar_FrameRounding(), UI_CONST.BUTTON_ROUNDING}
    }, function()
        if reaper.ImGui_Button(State.ui.ctx, "GO TO", uiScale(100), uiScale(28)) then goToMeasure() end
    end)
    reaper.ImGui_SameLine(State.ui.ctx)

    reaper.ImGui_AlignTextToFramePadding(State.ui.ctx)
    reaper.ImGui_Text(State.ui.ctx, "BPM:")
    reaper.ImGui_SameLine(State.ui.ctx)
    reaper.ImGui_SetNextItemWidth(State.ui.ctx, uiScale(100))
    with_vars({
        {reaper.ImGui_StyleVar_FramePadding(), 5, 7},
        {reaper.ImGui_StyleVar_FrameRounding(), UI_CONST.BUTTON_ROUNDING},
    }, function()
        local changed_bpm, new_bpm_input = reaper.ImGui_InputText(State.ui.ctx, "##bpm_input", State.input.bpm, reaper.ImGui_InputTextFlags_CharsDecimal())
        if changed_bpm then State.input.bpm = new_bpm_input end
    end)
    reaper.ImGui_SameLine(State.ui.ctx)
    with_vars({
        {reaper.ImGui_StyleVar_FrameRounding(), UI_CONST.BUTTON_ROUNDING}
    }, function()
        if reaper.ImGui_Button(State.ui.ctx, "SET", uiScale(100), uiScale(28)) then setBPM() end
    end)
    reaper.ImGui_SameLine(State.ui.ctx)

    reaper.ImGui_AlignTextToFramePadding(State.ui.ctx)
    reaper.ImGui_Text(State.ui.ctx, "Loop Length:")
    reaper.ImGui_SameLine(State.ui.ctx)
    reaper.ImGui_SetNextItemWidth(State.ui.ctx, uiScale(100))
    with_vars({
        {reaper.ImGui_StyleVar_FramePadding(), 5, 7},
        {reaper.ImGui_StyleVar_FrameRounding(), UI_CONST.BUTTON_ROUNDING},
    }, function()
    local preview = (State.transport.selectedAction and tostring(State.transport.actions[State.transport.selectedAction])) or "--"
    if reaper.ImGui_BeginCombo(State.ui.ctx, "##loop_length", preview) then
        -- Always offer "--" to clear loop selection
        if reaper.ImGui_Selectable(State.ui.ctx, "--", State.transport.selectedAction == nil) then
            State.transport.selectedAction = nil
            if clearLoopSelection then clearLoopSelection() end
        end
        for i, action in ipairs(State.transport.actions) do
            if reaper.ImGui_Selectable(State.ui.ctx, tostring(action), State.transport.selectedAction == i) then
                State.transport.selectedAction = i
                setLoop(State.transport.actions[State.transport.selectedAction])
            end
        end
        reaper.ImGui_EndCombo(State.ui.ctx)
    end
    end)

    -- Clean Button
    reaper.ImGui_SameLine(State.ui.ctx)
    with_vars({
        {reaper.ImGui_StyleVar_FrameRounding(), UI_CONST.BUTTON_ROUNDING}
    }, function()
        if reaper.ImGui_Button(State.ui.ctx, "Clean", uiScale(60), uiScale(28)) then
             cleanEmptyItems()
        end
    end)
    if reaper.ImGui_IsItemHovered(State.ui.ctx) then
        reaper.ImGui_SetTooltip(State.ui.ctx, "Remove empty items (MIDI with 0 notes, Audio < -50dB)")
    end

    reaper.ImGui_Dummy(State.ui.ctx, 0, uiScale(15))

    local toggledAuto = reaper.ImGui_Checkbox(State.ui.ctx, "Auto Loop", State.loop.autoEnabled)
    if toggledAuto then
        State.loop.autoEnabled = not State.loop.autoEnabled
        saveLoopAutoSettings()
        if State.loop.autoEnabled then
            State.loop.locked = false
            State.loop.startPos = nil
        end
    end

    reaper.ImGui_SameLine(State.ui.ctx, nil, uiScale(10))
    reaper.ImGui_SetNextItemWidth(State.ui.ctx, uiScale(160))
    if not State.loop.autoEnabled then reaper.ImGui_BeginDisabled(State.ui.ctx) end
    local alignOptions = "Measure\0Exact\0"
    local currentAlign = (State.loop.startAlign == 'measure') and 0 or 1
    local changed_align, newAlign = reaper.ImGui_Combo(State.ui.ctx, "Start##align", currentAlign, alignOptions)
    if changed_align and State.loop.autoEnabled then
        State.loop.startAlign = (newAlign == 0) and 'measure' or 'exact'
        saveLoopAutoSettings()
        local msg = (State.loop.startAlign == 'measure') and "Auto-loop: measure-aligned start" or "Auto-loop: exact timing start"
        statusSet(msg, "info", 1.5)
    end

    reaper.ImGui_SameLine(State.ui.ctx, nil, uiScale(10))
    reaper.ImGui_SetNextItemWidth(State.ui.ctx, uiScale(160))
    local roundingOptions = "Smart\0Nearest\0Forward\0"
    local currentRounding = 0
    if State.loop.rounding == 'nearest' then currentRounding = 1
    elseif State.loop.rounding == 'forward' then currentRounding = 2 end
    local roundingChanged, newRounding = reaper.ImGui_Combo(State.ui.ctx, "End##rounding", currentRounding, roundingOptions)
    if roundingChanged and State.loop.autoEnabled then
        if newRounding == 0 then State.loop.rounding = 'smart'
        elseif newRounding == 1 then State.loop.rounding = 'nearest'
        else State.loop.rounding = 'forward' end
        local msg2 = "Auto-loop end: " .. State.loop.rounding .. " rounding"
        statusSet(msg2, "info", 1.5)
    end
    if not State.loop.autoEnabled then reaper.ImGui_EndDisabled(State.ui.ctx) end

    -- Auto Fades toggle 
    reaper.ImGui_SameLine(State.ui.ctx, nil, uiScale(10))
    local toggledMF = reaper.ImGui_Checkbox(State.ui.ctx, "Auto Fades", State.loop.microFades.enabled)
    if toggledMF then
        State.loop.microFades.enabled = not State.loop.microFades.enabled
        saveLoopAutoSettings()
        statusSet(State.loop.microFades.enabled and "Micro-fades: ON" or "Micro-fades: OFF", "info", 1.5)
    end

    -- Count-In 
    State.metronome = State.metronome or { countInMode = false, snapshot = {} }
    reaper.ImGui_SameLine(State.ui.ctx, nil, uiScale(15))
    local ciChanged, ciNew = reaper.ImGui_Checkbox(State.ui.ctx, "Count-In", State.metronome.countInMode)
    if ciChanged then
        if ciNew then enableCountInMode() else disableCountInMode() end
    end

    reaper.ImGui_Dummy(State.ui.ctx, 0, uiScale(15))

    local metronomeState = reaper.GetToggleCommandState(40364) == 1
    local metronomeButtonText = metronomeState and "Metronome ON" or "Metronome OFF"
    reaper.ImGui_PushStyleVar(State.ui.ctx, reaper.ImGui_StyleVar_FrameRounding(), uiScale(5))
    if reaper.ImGui_Button(State.ui.ctx, metronomeButtonText, uiScale(120), uiScale(30)) then
        reaper.Main_OnCommand(40364, 0)
    end
    reaper.ImGui_PopStyleVar(State.ui.ctx)
    reaper.ImGui_SameLine(State.ui.ctx, nil, uiScale(10))

    -- Detect click track by name 
    local function findClickTrack()
        local numTracks = reaper.CountTracks(0)
        for i = 0, numTracks - 1 do
            local t = reaper.GetTrack(0, i)
            local ok, name = reaper.GetSetMediaTrackInfo_String(t, "P_NAME", "", false)
            if ok and (name == "Floopa Click Track" or name == "Click Track") then return t, i end
        end
        return nil, nil
    end
    local ct, _ = findClickTrack()
    local hasClickTrack = ct ~= nil
    local buttonText = hasClickTrack and "Remove Click" or "Create Click"
    with_vars({
        {reaper.ImGui_StyleVar_FrameRounding(), UI_CONST.BUTTON_ROUNDING}
    }, function()
        if reaper.ImGui_Button(State.ui.ctx, buttonText, uiScale(120), uiScale(30)) then
            if toggleClickTrackPreservingSelection then
                toggleClickTrackPreservingSelection()
            else
                notifyInfo("Click Track action not available (initializing)", 2.0)
            end
        end
    end)
    reaper.ImGui_SameLine(State.ui.ctx, nil, uiScale(30))

    -- Count-In checkbox ON
    do
        State.metronome = State.metronome or { countInMode = false, snapshot = {} }
        reaper.ImGui_SameLine(State.ui.ctx, nil, uiScale(10))
        local changed, newVal = false, State.metronome.countInMode -- moved near Auto Fades
        if changed then
            if newVal then enableCountInMode() else disableCountInMode() end
        end
    end

    local isRecording = reaper.GetToggleCommandState(1013) == 1
    local now = reaper.time_precise()
    if State.recButton.start == 0 then State.recButton.start = now end

    local function lerp(a, b, u) return (a or 0) + ((b or 0) - (a or 0)) * (u or 0) end
    local elapsed = now - (State.recButton.start or 0)
    local u = elapsed / (State.recButton.duration or 0.30)
    if u > 1.0 then u = 1.0 end
    local cur = State.recButton.current
    local from = State.recButton.from
    local to = State.recButton.to
    cur[1] = lerp(from[1], to[1], u)
    cur[2] = lerp(from[2], to[2], u)
    cur[3] = lerp(from[3], to[3], u)
    cur[4] = lerp(from[4], to[4], u)

    local cur_u32 = reaper.ImGui_ColorConvertDouble4ToU32(cur[1], cur[2], cur[3], cur[4])
    local active_u32 = reaper.ImGui_ColorConvertDouble4ToU32(State.recButton.active[1], State.recButton.active[2], State.recButton.active[3], State.recButton.active[4])

    with_colors({
        {reaper.ImGui_Col_Button(),          cur_u32},
        {reaper.ImGui_Col_ButtonHovered(),   cur_u32},
        {reaper.ImGui_Col_ButtonActive(),    active_u32},
        {reaper.ImGui_Col_Text(),            THEME_COLORS[reaper.ImGui_Col_Text()]},
    }, function()
        with_vars({
            {reaper.ImGui_StyleVar_FrameRounding(), UI_CONST.BUTTON_ROUNDING}
        }, function()
            local recIcon = isRecording and "⬤" or "◯"
            local recText = isRecording and (recIcon .. " Rec On") or (recIcon .. " Rec Off")
            local clicked = reaper.ImGui_Button(State.ui.ctx, recText, uiScale(180), uiScale(30))
            if clicked then
                reaper.Main_OnCommand(1013, 0)
            end
        end)
    end)

    local hovered = reaper.ImGui_IsItemHovered(State.ui.ctx)
    if hovered then
        reaper.ImGui_SetMouseCursor(State.ui.ctx, reaper.ImGui_MouseCursor_Hand())
    end
    State.recButton.last_hovered = hovered


    local target = State.recButton.normal
    if isRecording then
        target = State.recButton.active
    elseif hovered then
        target = State.recButton.hover
    end

    local function neq(a, b)
        return (math.abs(a[1]-b[1]) > 1e-6) or (math.abs(a[2]-b[2]) > 1e-6) or (math.abs(a[3]-b[3]) > 1e-6) or (math.abs(a[4]-b[4]) > 1e-6)
    end
    if neq(State.recButton.to, target) then
        State.recButton.from = {cur[1], cur[2], cur[3], cur[4]}
        State.recButton.to = {target[1], target[2], target[3], target[4]}
        State.recButton.start = now
    end

    reaper.ImGui_SameLine(State.ui.ctx, nil, uiScale(10))

    local stop_hovered = false
    local stop_x, stop_y = reaper.ImGui_GetCursorScreenPos(State.ui.ctx)
    local stop_w, stop_h = 100, 30
    local mouse_x, mouse_y = reaper.ImGui_GetMousePos(State.ui.ctx)
    if mouse_x >= stop_x and mouse_x <= stop_x + stop_w and mouse_y >= stop_y and mouse_y <= stop_y + stop_h then
        stop_hovered = true
        reaper.ImGui_SetMouseCursor(State.ui.ctx, reaper.ImGui_MouseCursor_Hand())
    end

    if stop_hovered ~= State.stopButton.last_hovered then
        State.stopButton.last_hovered = stop_hovered
        State.stopButton.from = {State.stopButton.current[1], State.stopButton.current[2], State.stopButton.current[3], State.stopButton.current[4]}
        State.stopButton.to = stop_hovered and State.stopButton.hover or State.stopButton.normal
        State.stopButton.start = reaper.time_precise()
    end

    local stop_t = math.min(1.0, (reaper.time_precise() - State.stopButton.start) / State.stopButton.duration)
    local function lerp2(a, b, t) return a + (b - a) * t end
    State.stopButton.current = {
        lerp2(State.stopButton.from[1], State.stopButton.to[1], stop_t),
        lerp2(State.stopButton.from[2], State.stopButton.to[2], stop_t),
        lerp2(State.stopButton.from[3], State.stopButton.to[3], stop_t),
        lerp2(State.stopButton.from[4], State.stopButton.to[4], stop_t)
    }

    local stop_color = reaper.ImGui_ColorConvertDouble4ToU32(State.stopButton.current[1], State.stopButton.current[2], State.stopButton.current[3], State.stopButton.current[4])
    local stop_active = reaper.ImGui_ColorConvertDouble4ToU32(State.stopButton.active[1], State.stopButton.active[2], State.stopButton.active[3], State.stopButton.active[4])
    with_colors({
        {reaper.ImGui_Col_Button(),          stop_color},
        {reaper.ImGui_Col_ButtonHovered(),   stop_color},
        {reaper.ImGui_Col_ButtonActive(),    stop_active},
        {reaper.ImGui_Col_Text(),            THEME_COLORS[reaper.ImGui_Col_Text()]},
    }, function()
        with_vars({
            {reaper.ImGui_StyleVar_FrameRounding(), UI_CONST.BUTTON_ROUNDING}
        }, function()
            local ps2 = reaper.GetPlayState()
            local isPlayingOrRecording2 = ((ps2 & 1) == 1) or ((ps2 & 4) == 4)
            local btnLabel = isPlayingOrRecording2 and "Stop" or "Play"
            local icon = isPlayingOrRecording2 and "⏹" or "▶"
            local btnText = icon .. " " .. btnLabel
            if reaper.ImGui_Button(State.ui.ctx, btnText, uiScale(100), uiScale(30)) then
                toggleTransportPlayStop()
            end
        end)
    end)
    
    reaper.ImGui_SameLine(State.ui.ctx, nil, uiScale(10))
    do
        
        local function hasAnyFloopaTracks()
            local n = reaper.CountTracks(0)
            for i = 0, n - 1 do
                local t = reaper.GetTrack(0, i)
                local ok, name = reaper.GetSetMediaTrackInfo_String(t, "P_NAME", "", false)
                if ok and name then
                    local s = tostring(name):gsub("^%s+", ""):gsub("%s+$", "")
                    if s:match("^Floopa %d+$") then return true end
                end
            end
            return false
        end
        local canClear = hasAnyFloopaTracks()
        if not canClear then reaper.ImGui_BeginDisabled(State.ui.ctx) end
        with_vars({
            {reaper.ImGui_StyleVar_FrameRounding(), UI_CONST.BUTTON_ROUNDING}
        }, function()
            local clicked = reaper.ImGui_Button(State.ui.ctx, "Clear All", uiScale(120), uiScale(30))
            if clicked and canClear then
                clearAllFloopa()
            end
        end)
        if not canClear then reaper.ImGui_EndDisabled(State.ui.ctx) end
    end


    drawBeatCounterSection()
    reaper.ImGui_Dummy(State.ui.ctx, 0, uiScale(6))
end



local function commandExists(cmd)
    if reaper.CF_GetCommandText then
        local name = reaper.CF_GetCommandText(0, cmd)
        return name and name ~= ""
    end
   
    return true
end


local getFloopaTracks_original_location_removed

-- Map fade shape string to REAPER shape code 
local function mapFadeShapeToCode(shape)
    if shape == 'linear' then return 0 end
    if shape == 'exponential' then return 3 end
    if shape == 'logarithmic' then return 4 end
    return 0
end

-- Compute epsilon for recorded item overlap detection 
-- dynamic: derive from median item length across Floopa tracks within the window
-- strict: use configured strictEpsilonMs
local function computeEpsilon(startTime, endTime)
    local mode = State.loop.epsilonMode or 'dynamic'
    if mode == 'strict' then
        local ms = State.loop.strictEpsilonMs or 20
        return (ms or 0) / 1000.0
    end
    -- dynamic mode
    local tracks = getFloopaTracks()
    local lens = {}
    for _, e in ipairs(tracks) do
        local tr = e.track
        local cnt = reaper.CountTrackMediaItems(tr)
        for i = 0, cnt - 1 do
            local it = reaper.GetTrackMediaItem(tr, i)
            if it then
                local pos = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
                local len = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
                if type(pos) == 'number' and type(len) == 'number' then
                    local itEnd = pos + len
                    if (itEnd > startTime) and (pos < endTime) then
                        table.insert(lens, math.max(0.0, len))
                    end
                end
            end
        end
    end
    local eps = State.loop.detectEpsilon or 0.05
    if #lens == 0 then return eps end
    table.sort(lens)
    local mid = lens[math.floor((#lens + 1) / 2)] or eps
    
    local dyn = math.max(0.01, math.min(0.05, (mid or 0) * 0.02))
    return dyn
end

-- Align loop boundaries to nearest item starts/ends within a threshold (seconds)

local function alignLoopToNearestItemBoundaries(startSel, endSel, threshold)
    local bestStart = startSel
    local bestEnd = endSel
    local thresholdStart = threshold
    local thresholdEnd = threshold
    local tracks = getFloopaTracks()
    
    for _, e in ipairs(tracks) do
        local tr = e.track
        local cnt = reaper.CountTrackMediaItems(tr)
        for i = 0, cnt - 1 do
            local it = reaper.GetTrackMediaItem(tr, i)
            if it then
                local pos = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
                local len = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
                if type(pos) == 'number' and type(len) == 'number' then
                    local itEnd = pos + len
                    
                    -- Check start alignment
                    local dStart = math.abs(pos - startSel)
                    if dStart <= thresholdStart then
                        bestStart = pos
                        thresholdStart = dStart
                    end
                    
                    -- Check end alignment
                    local dEnd = math.abs(itEnd - endSel)
                    if dEnd <= thresholdEnd then
                        bestEnd = itEnd
                        thresholdEnd = dEnd
                    end
                end
            end
        end
    end
    
    if bestEnd <= bestStart then return startSel, endSel end
    return bestStart, bestEnd
end

-- Apply micro-fades using State
function applyMicroFadesConfigured(startTime, endTime)
    if not startTime or not endTime or endTime <= startTime then return end
    local cfg = State.loop.microFades or { enabled = true, durationMs = 5, shape = 'linear' }
    if not cfg.enabled then return end
    local ms = tonumber(cfg.durationMs) or 5
    ms = math.max(0, math.min(500, ms))
    ms = math.floor((ms + 5) / 10) * 10
    local fadeLen = ms / 1000.0
    local shapeCode = mapFadeShapeToCode(cfg.shape)
    local tracks = getFloopaTracks()
    local doWrap = not _G.__FLOOPA_NO_GUI__
    if doWrap then reaper.Undo_BeginBlock() end
    if doWrap then reaper.PreventUIRefresh(1) end
    for _, e in ipairs(tracks) do
        local tr = e.track
        local cnt = reaper.CountTrackMediaItems(tr)
        for i = 0, cnt - 1 do
            local it = reaper.GetTrackMediaItem(tr, i)
            if it then
                local pos = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
                local len = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
                if type(pos) == 'number' and type(len) == 'number' then
                    local itEnd = pos + len
                    if (itEnd > startTime) and (pos < endTime) then
                        -- Apply configured fade length exactly, regardless of current defaults
                        reaper.SetMediaItemInfo_Value(it, "D_FADEINLEN", fadeLen)
                        reaper.SetMediaItemInfo_Value(it, "D_FADEOUTLEN", fadeLen)
                        -- Clear any auto-fade to avoid overrides by project defaults
                        reaper.SetMediaItemInfo_Value(it, "D_FADEINLEN_AUTO", -1)
                        reaper.SetMediaItemInfo_Value(it, "D_FADEOUTLEN_AUTO", -1)
                        reaper.SetMediaItemInfo_Value(it, "C_FADEINSHAPE", shapeCode)
                        reaper.SetMediaItemInfo_Value(it, "C_FADEOUTSHAPE", shapeCode)
                        reaper.UpdateItemInProject(it)
                        if _G.__FLOOPA_NO_GUI__ then
                            local fin = reaper.GetMediaItemInfo_Value(it, "D_FADEINLEN") or 0
                            local fout = reaper.GetMediaItemInfo_Value(it, "D_FADEOUTLEN") or 0
                            if math.abs(fin - fadeLen) > 0.0001 or math.abs(fout - fadeLen) > 0.0001 then
                                reaper.SetMediaItemInfo_Value(it, "D_FADEINLEN", fadeLen)
                                reaper.SetMediaItemInfo_Value(it, "D_FADEOUTLEN", fadeLen)
                                reaper.UpdateItemInProject(it)
                            end
                        end
                    end
                end
            end
        end
    end
    if doWrap then reaper.PreventUIRefresh(-1) end
    reaper.UpdateArrange()
    if doWrap then reaper.Undo_EndBlock("Floopa: apply configurable micro-fades", -1) end
end

local function keyPressedOnceTagged(key, tag)
    
    local nk
    if type(key) == 'number' then
        nk = keyFromAscii(key) or key
    elseif type(key) == 'string' then
        nk = parseKeyInput(key)
    end
    if type(nk) ~= 'number' then return false end
    local now = reaper.time_precise()
    if reaper.ImGui_IsKeyPressed(State.ui.ctx, nk) then
        local lastMap = State.input.lastKeyTimeTag
        local last = lastMap[tag or nk] or 0
        local cd
        if tag and State.input.perActionCooldown[tag] and State.input.perActionCooldown[tag] > 0 then
            cd = State.input.perActionCooldown[tag]
        else
            cd = State.input.keyCooldown
        end
        if now - last > cd then
            lastMap[tag or nk] = now
            return true
        end
    end
    return false
end


-- ===== MAPPING FUNCTIONS =====
local function saveMappings()
    for _, a in ipairs(State.mappings.actions) do
        local k = State.mappings.data[a.id]
        if type(k) == 'table' then
            local parts = {}
            for _, v in ipairs(k) do parts[#parts+1] = tostring(v) end
            -- Persist to project (fallback to global via extSet)
            extSet("mapping_" .. a.id, table.concat(parts, ","))
        elseif type(k) == 'number' then
            extSet("mapping_" .. a.id, tostring(k))
        else
            extSet("mapping_" .. a.id, "")
        end
    end
end

local function loadMappings()
    for _, a in ipairs(State.mappings.actions) do
        local v = extGet("mapping_" .. a.id) or ""
        if v and v ~= "" then
            if v:find(",") then
                local list = {}
                for token in v:gmatch("[^,]+") do
                    local nk = parseKeyInput(token)
                    if type(nk) == 'number' then table.insert(list, nk) end
                end
                if #list == 1 then
                    State.mappings.data[a.id] = list[1]
                else
                    State.mappings.data[a.id] = list
                end
            else
                local num = tonumber(v)
                local named = parseKeyInput(num ~= nil and num or v)
                State.mappings.data[a.id] = named
            end
        else
            State.mappings.data[a.id] = nil
        end
    end
    
    saveMappings()
end

local function saveCooldowns()
    for _, a in ipairs(State.mappings.actions) do
        local tag = "mapping_" .. a.id
        local cd = State.input.perActionCooldown[tag]
        if cd and cd > 0 then
            -- Persist to project, fallback handled by extSet
            extSet("mapping_cooldown_" .. a.id, tostring(cd))
        else
            extSet("mapping_cooldown_" .. a.id, "")
        end
    end
end

local function loadCooldowns()
    for _, a in ipairs(State.mappings.actions) do
        local tag = "mapping_" .. a.id
        local v = extGet("mapping_cooldown_" .. a.id) or ""
        local num = tonumber(v)
        if num and num >= 0 then
            State.input.perActionCooldown[tag] = num
        else
            -- default to global cooldown
            State.input.perActionCooldown[tag] = State.input.keyCooldown
        end
    end
end


loadMappings()
loadCooldowns()


if State.mappings and State.mappings.data then
    if State.mappings.data.select_trk ~= nil then
        State.mappings.data.select_trk = nil
        
        extSet("mapping_select_trk", "")
        saveMappings()
    end
end

-- Load Auto Loop settings 
local function loadLoopAutoSettings()
    local v = extGet("loop_auto_enabled")
    if v == "1" then State.loop.autoEnabled = true else State.loop.autoEnabled = false end
    local q = extGet("loop_quantize")
    if q == "beat" or q == "measure" then State.loop.quantize = q end
    local a = extGet("loop_start_align")
    if a == "exact" or a == "measure" then State.loop.startAlign = a end
    -- Micro-fades config 
    local mf_en = extGet("loop_microfades_enabled")
    if mf_en == "0" then State.loop.microFades.enabled = false else State.loop.microFades.enabled = true end
    local mf_ms = tonumber(extGet("loop_microfades_ms") or "")
    if mf_ms then
        
        mf_ms = math.max(0, math.min(500, mf_ms))
        mf_ms = math.floor((mf_ms + 5) / 10) * 10
        State.loop.microFades.durationMs = mf_ms
    end
    local mf_shape = extGet("loop_microfades_shape")
    if mf_shape == "linear" or mf_shape == "exponential" or mf_shape == "logarithmic" then
        State.loop.microFades.shape = mf_shape
    end
    
    local em = extGet("loop_epsilon_mode")
    if em == "strict" or em == "dynamic" then State.loop.epsilonMode = em end
    local se_ms = tonumber(extGet("loop_epsilon_strict_ms") or "")
    if se_ms then
        se_ms = math.max(0, math.min(500, se_ms))
        State.loop.strictEpsilonMs = se_ms
    end
end

saveLoopAutoSettings = function()
    extSet("loop_auto_enabled", State.loop.autoEnabled and "1" or "0")
    extSet("loop_quantize", State.loop.quantize or "measure")
    extSet("loop_start_align", State.loop.startAlign or "measure")
    
    extSet("loop_microfades_enabled", State.loop.microFades.enabled and "1" or "0")
    extSet("loop_microfades_ms", tostring(State.loop.microFades.durationMs or 5))
    extSet("loop_microfades_shape", State.loop.microFades.shape or "linear")
   
    extSet("loop_epsilon_mode", State.loop.epsilonMode or "dynamic")
    extSet("loop_epsilon_strict_ms", tostring(State.loop.strictEpsilonMs or 50))
end

loadLoopAutoSettings()

-- Force Auto-Loop disabled at startup so the user explicitly opts in
State.loop.autoEnabled = false
-- Force Auto-Fades disabled at startup; 
State.loop.microFades.enabled = false

-- Seed default metronome 
if not State.mappings.data.metronome then
    State.mappings.data.metronome = reaper.ImGui_Key_T()
    saveMappings()
end

-- Default mapping
    if not State.mappings.data.record_toggle then
        State.mappings.data.record_toggle = reaper.ImGui_Key_R()
    end
    if not State.mappings.data.play_pause then
        State.mappings.data.play_pause = reaper.ImGui_Key_Space()
    end
    -- Default mapping: set Toggle Click=C if unset
    if not State.mappings.data.toggle_click then
        State.mappings.data.toggle_click = reaper.ImGui_Key_C()
    end
    -- Default mapping: set Toggle Input=I if unset
    if not State.mappings.data.toggle_input then
        State.mappings.data.toggle_input = reaper.ImGui_Key_I()
    end
    -- Default mapping: Transpose +12 = Z, Transpose -12 = X
    if not State.mappings.data.pitch_up then
        State.mappings.data.pitch_up = reaper.ImGui_Key_Z()
    end
    if not State.mappings.data.pitch_down then
        State.mappings.data.pitch_down = reaper.ImGui_Key_X()
    end
    -- Default mapping: set Mute Selected Track=M if unset
    if not State.mappings.data.mute_trk then
        State.mappings.data.mute_trk = reaper.ImGui_Key_M()
    end
    -- Default mapping: set FX Track=F if unset
    if not State.mappings.data.fx_trk then
        State.mappings.data.fx_trk = reaper.ImGui_Key_F()
    end
    -- Default mapping: set Reverse Selected Track=S if unset
    if not State.mappings.data.rev_trk then
        State.mappings.data.rev_trk = reaper.ImGui_Key_S()
    end
    -- Default mapping: set Undo Lane=Backspace if unset
    if not State.mappings.data.undo_lane then
        State.mappings.data.undo_lane = reaper.ImGui_Key_Backspace()
    end
    -- Default mapping: set Undo All Lanes=Del if unset
    if not State.mappings.data.undo_all then
        State.mappings.data.undo_all = reaper.ImGui_Key_Delete()
    end
    saveMappings()

-- Mapping helpers (key names and UI)
local function getKeyName(code)
    if not code then return "None" end
    if not State.mappings._keyNameMap then
        local m = {}
        -- Letters A-Z
        for i = 65, 90 do
            local ch = string.char(i)
            local fn = reaper["ImGui_Key_"..ch]
            if fn then m[fn()] = ch end
        end
        -- Digits 0-9
        for i = 0, 9 do
            local fn = reaper["ImGui_Key_"..i]
            if fn then m[fn()] = tostring(i) end
        end
        -- Common controls
        m[reaper.ImGui_Key_Space()] = "Space"
        m[reaper.ImGui_Key_Enter()] = "Enter"
        m[reaper.ImGui_Key_Tab()] = "Tab"
        m[reaper.ImGui_Key_Escape()] = "Esc"
        m[reaper.ImGui_Key_Backspace()] = "Backspace"
        m[reaper.ImGui_Key_Delete()] = "Del"
        
        for i = 1, 12 do
            local fn = reaper["ImGui_Key_F"..i]
            if fn then m[fn()] = "F"..i end
        end
        State.mappings._keyNameMap = m
    end
    return State.mappings._keyNameMap[code] or tostring(code)
end



local function setMapping(actionId, code)
    -- Fully lock mappings for setup/revert and track selection
    if actionId == 'setup_revert' or actionId == 'select_trk' then
        State.mappings.feedback = { msg = "This mapping is fixed and cannot be modified.", ts = reaper.time_precise(), kind = "error", target_id = actionId }
        return false
    end
    -- Centralized check for reserved track shortcut keys
    local function getReservedKeys()
        if State.mappings._reservedKeys then return State.mappings._reservedKeys end
        local r = {}
       
        r[reaper.ImGui_Key_K()] = true
        r[reaper.ImGui_Key_L()] = true
        
        for i = 1, 5 do
            local fn = reaper["ImGui_Key_"..i]
            if fn then r[fn()] = true end
        end
        State.mappings._reservedKeys = r
        return r
    end
    local function isReserved(code, action)
        local r = getReservedKeys()
        return code and r[code] == true
    end

    if type(code) == 'number' then
        local lbl = actionId
        for _, a in ipairs(State.mappings.actions) do if a.id == actionId then lbl = a.label end end
        if isReserved(code, actionId) then
            State.mappings.feedback = { msg = "Refused: " .. lbl .. " conflicts with track shortcuts (" .. getKeyName(code) .. ")", ts = reaper.time_precise(), kind = "error", target_id = actionId }
            return false
        end
        -- Prevent duplicate assignment
        local usedById = nil
        for aid, val in pairs(State.mappings.data) do
            if aid ~= actionId then
                if type(val) == 'number' and val == code then
                    usedById = aid
                    break
                elseif type(val) == 'table' then
                    for _, v in ipairs(val) do if v == code then usedById = aid; break end end
                    if usedById then break end
                end
            end
        end
        if usedById then
            local usedLbl = usedById
            for _, a in ipairs(State.mappings.actions) do if a.id == usedById then usedLbl = a.label end end
            State.mappings.feedback = { msg = "Refused: " .. getKeyName(code) .. " is already assigned to " .. tostring(usedLbl), ts = reaper.time_precise(), kind = "error", target_id = actionId, conflict_id = usedById }
            return false
        end
        State.mappings.data[actionId] = code
        saveMappings()
        State.mappings.feedback = { msg = "Saved: " .. lbl .. " = " .. getKeyName(code), ts = reaper.time_precise(), kind = "ok", target_id = actionId }
        return true
    end
    return false
end



-- ===== SETUP CONFIGURATION LOGIC =====


local function splitCSV(str)
    local t = {}
    if not str or str == "" then return t end
    for s in string.gmatch(str, '([^,]+)') do
        table.insert(t, s)
    end
    return t
end

local function joinCSV(list)
    return table.concat(list, ",")
end

local function findTrackByGUID(guid)
    local t = nil
    if reaper.BR_GetMediaTrackByGUID then
        t = reaper.BR_GetMediaTrackByGUID(0, guid)
    end
    if not t then
        local num = reaper.CountTracks(0)
        for i = 0, num - 1 do
            local tr = reaper.GetTrack(0, i)
            local g = reaper.GetTrackGUID(tr)
            if g == guid then
                t = tr
                break
            end
        end
    end
    return t
end

local function ensureFloopaTracksIdempotent()
    local createdGuids = {}
    local numTracks = reaper.CountTracks(0)
    local existing = {}
    local usedNums = {}
    
    -- First pass: identify valid Floopa tracks
    for i = 0, numTracks - 1 do
        local t = reaper.GetTrack(0, i)
        local ok, name = reaper.GetSetMediaTrackInfo_String(t, "P_NAME", "", false)
        if ok and name then
            local n = name:match("^Floopa (%d+)$")
            if n then
                n = tonumber(n)
                if n >= 1 and n <= 5 then
                    if not usedNums[n] then
                        existing[#existing+1] = {track = t, index = i, num = n}
                        usedNums[n] = true
                    end
                end
            end
        end
    end
    table.sort(existing, function(a,b) return a.num < b.num end)

    -- Check if we have exactly 1..5
    local allFound = true
    for n = 1, 5 do
        if not usedNums[n] then allFound = false break end
    end

    if allFound then
        return createdGuids
    end

    -- Move any existing Floopa tracks to top preserving order
    if #existing > 0 and reaper.ReorderSelectedTracks then
        
        reaper.Main_OnCommand(40297, 0)
        for _, e in ipairs(existing) do
            reaper.SetTrackSelected(e.track, true)
        end
        reaper.ReorderSelectedTracks(0, 0)
       
        reaper.Main_OnCommand(40297, 0)
        
        for _, e in ipairs(existing) do
            reaper.SetTrackColor(e.track, FLOOPA_TRACK_COLOR_BASE)
        end
    end

    local missingCount = 5 - #existing
    
    local missingNums = {}
    for n = 1, 5 do
        if not usedNums[n] then table.insert(missingNums, n) end
    end

    -- Insert required number of tracks
    for i = 1, missingCount do
        local insertIndex = i - 1 + #existing
        reaper.InsertTrackAtIndex(insertIndex, true)
        local t = reaper.GetTrack(0, insertIndex)
        if t then
            local num = missingNums[i] or (i + #existing)
            reaper.GetSetMediaTrackInfo_String(t, "P_NAME", "Floopa " .. tostring(num), true)
            
            reaper.SetTrackColor(t, FLOOPA_TRACK_COLOR_BASE)
            table.insert(createdGuids, reaper.GetTrackGUID(t))
        end
    end

    

    reaper.UpdateArrange()
    return createdGuids
end

function getFloopaTracks_deprecated()
    -- This function is kept for compatibility if needed, but the main one is defined above
    return getFloopaTracks()
end


local function isAutoRecArmEnabledOnAtLeastOneFloopaTrack()
    local flist = getFloopaTracks()
    for _, e in ipairs(flist) do
        if e.num >= 1 and e.num <= 5 then
            local v = reaper.GetMediaTrackInfo_Value(e.track, "B_AUTO_RECARM")
            if v == 1 then return true end
        end
    end
    return false
end
-- Persistence and application: automatic record‑arm when track selected
local function getPersistedAutoRecArm()
    local v = extGet("auto_recarm")
    if v == "0" then return false end
    if v == "1" then return true end
    return true -- default: enabled
end

local function setPersistedAutoRecArm(enabled)
    extSet("auto_recarm", enabled and "1" or "0")
end

local function applyAutoRecArmToFloopaTracks(enabled)
    local flist = getFloopaTracks()
    for _, e in ipairs(flist) do
        if e.num >= 1 and e.num <= 5 then
            reaper.SetMediaTrackInfo_Value(e.track, "B_AUTO_RECARM", enabled and 1 or 0)
        end
    end
end

-- === METRONOME / COUNT-IN SNAPSHOT & HANDLERS ==============================
local function getToggle(cmdId)
    local ok = reaper.GetToggleCommandState(cmdId)
    return ok == 1
end

local function runNamedCmd(name)
    local id = reaper.NamedCommandLookup(name)
    if id and id ~= 0 then reaper.Main_OnCommand(id, 0) end
end

local function setToggle(cmdId, wantOn)
    local isOn = getToggle(cmdId)
    if wantOn and not isOn then reaper.Main_OnCommand(cmdId, 0) end
    if (not wantOn) and isOn then reaper.Main_OnCommand(cmdId, 0) end
end

local function saveMetronomeSnapshot()
    State.metronome = State.metronome or { countInMode = false, snapshot = {} }
    State.metronome.snapshot = {
        enableMetronome = getToggle(40364),
        preroll = reaper.SNM_GetIntConfigVar("preroll", 0),
        projmetroen = reaper.SNM_GetIntConfigVar("projmetroen", 0),
        projmetrocountin = reaper.SNM_GetDoubleConfigVar and reaper.SNM_GetDoubleConfigVar("projmetrocountin", 0.0) or 0.0,
        metronome_flags = reaper.SNM_GetIntConfigVar("metronome_flags", 0)
    }
end

local function restoreMetronomeSnapshot()
    if not (State.metronome and State.metronome.snapshot) then return end
    local s = State.metronome.snapshot
    setToggle(40364, s.enableMetronome)
    reaper.SNM_SetIntConfigVar("preroll", s.preroll or 0)
    reaper.SNM_SetIntConfigVar("projmetroen", s.projmetroen or 0)
    if reaper.SNM_SetDoubleConfigVar and (s.projmetrocountin ~= nil) then
        reaper.SNM_SetDoubleConfigVar("projmetrocountin", s.projmetrocountin)
    end
    reaper.SNM_SetIntConfigVar("metronome_flags", s.metronome_flags or 0)
end

-- Count-In Mode: conservative implementation
-- - Disables metronome during playback/record by turning off global metronome
-- - Forces no pre-roll via config var
-- - Preserves full snapshot for restoration
function enableCountInMode()
    -- Metronome ON; ensure count-in for recording ON; disable metronome during recording
    -- Fallback to native toggle in case SWS command lookup fails
    setToggle(40364, true)            -- ensure global metronome ON
    runNamedCmd("_SWS_METRONON")     -- optional if SWS is available
    runNamedCmd("_SWS_AWCOUNTRECON") -- ensure count-in before recording is enabled
    runNamedCmd("_SWS_AWCOUNTPLAYOFF") -- keep count-in off for playback
    -- count-in measures safeguard (default 2)
    if reaper.SNM_SetDoubleConfigVar then
        local cm = reaper.SNM_GetDoubleConfigVar and reaper.SNM_GetDoubleConfigVar("projmetrocountin", 0.0) or 0.0
        if not cm or cm <= 0 then reaper.SNM_SetDoubleConfigVar("projmetrocountin", 2.0) end
    end
    runNamedCmd("_SWS_AWMRECOFF")    -- disable metronome during recording so we only hear the count-in
    extSet("count_in_mode", "1")
    State.metronome.countInMode = true
end

function disableCountInMode()
    -- Metronome OFF; enable metronome during recording for normal operation
    setToggle(40364, false)           -- ensure global metronome OFF
    runNamedCmd("_SWS_METROOFF")
    runNamedCmd("_SWS_AWMRECON")
    extSet("count_in_mode", "0")
    State.metronome.countInMode = false
end

-- Function to save current settings state
local function saveUserSettings()
   
    local recordModeCmd = nil
    if reaper.GetToggleCommandState(40252) == 1 then recordModeCmd = 40252
    elseif reaper.GetToggleCommandState(40076) == 1 then recordModeCmd = 40076 end

    State.setup.userSettings = {
        recordModeCmd = recordModeCmd,
        repeatState = reaper.GetToggleCommandState(1068),
        offsetMedia = reaper.GetToggleCommandState(40507),
        loopPoints = reaper.GetToggleCommandState(40621),
        addLanes = reaper.GetToggleCommandState(41329),
        trimBehind = reaper.GetToggleCommandState(43151),
        prerollPlay = reaper.GetToggleCommandState(41818),
        prerollRec = reaper.GetToggleCommandState(41819),
        monitorTrack = State.setup.commandId and reaper.GetToggleCommandState(State.setup.commandId) or nil,
        bpm = reaper.Master_GetTempo(),
        recaddatloop = reaper.SNM_GetIntConfigVar("recaddatloop", 0), 
        autoRecArmByGuid = (function()
            local map = {}
            local nt = reaper.CountTracks(0)
            for i = 0, nt - 1 do
                local tr = reaper.GetTrack(0, i)
                if tr then
                    local g = reaper.GetTrackGUID(tr)
                    local v = reaper.GetMediaTrackInfo_Value(tr, "B_AUTO_RECARM")
                    map[g] = v
                end
            end
            return map
        end)()
    }
end

-- Function to restore saved settings
revertFloopa = function()
    if not State.setup.floopaSetupDone then return end 
    
    if State.setup.userSettings.recordModeCmd then
        local cmd = State.setup.userSettings.recordModeCmd
        local cur40252 = reaper.GetToggleCommandState(40252)
        local cur40076 = reaper.GetToggleCommandState(40076)
        if cmd == 40252 and cur40252 ~= 1 then reaper.Main_OnCommand(40252, 0) end
        if cmd == 40076 and cur40076 ~= 1 then reaper.Main_OnCommand(40076, 0) end
    end

    -- Restore other toggles ensuring state matches
    local function restoreToggle(cmdId, savedState)
       
        if not cmdId or (savedState ~= 0 and savedState ~= 1) then return end
        local cur = reaper.GetToggleCommandState(cmdId)
        if cur ~= savedState then
            reaper.Main_OnCommand(cmdId, 0)
        end
    end

    restoreToggle(1068, State.setup.userSettings.repeatState)
    restoreToggle(40507, State.setup.userSettings.offsetMedia)
    restoreToggle(40621, State.setup.userSettings.loopPoints)
    restoreToggle(41329, State.setup.userSettings.addLanes)
    restoreToggle(43151, State.setup.userSettings.trimBehind)
    restoreToggle(41818, State.setup.userSettings.prerollPlay)
    restoreToggle(41819, State.setup.userSettings.prerollRec)
    if State.setup.commandId and State.setup.userSettings.monitorTrack ~= nil then
        restoreToggle(State.setup.commandId, State.setup.userSettings.monitorTrack)
    end

    if State.setup.userSettings.bpm then
        reaper.SetCurrentBPM(0, State.setup.userSettings.bpm, true)
    end

    -- Restore loop recording preferences
    if State.setup.userSettings.recaddatloop then
        reaper.SNM_SetIntConfigVar("recaddatloop", State.setup.userSettings.recaddatloop)
    end

    -- Remove only tracks created by setup using ExtState
    local createdCSV = extGet("created_guids")
    if createdCSV and createdCSV ~= "" then
        local guids = splitCSV(createdCSV)
        if #guids > 0 then
            local deleted_guids = {}
            local kept_guids = {}
            reaper.Undo_BeginBlock()
            reaper.PreventUIRefresh(1)
            for _, g in ipairs(guids) do
                local tr = findTrackByGUID(g)
                if tr then
                    local itemCount = reaper.CountTrackMediaItems(tr)
                    if itemCount == 0 then
                        reaper.DeleteTrack(tr)
                        table.insert(deleted_guids, g)
                    else
                        table.insert(kept_guids, g) 
                    end
                else
                   
                end
            end
            reaper.PreventUIRefresh(-1)
            reaper.Undo_EndBlock("Floopa: revert - safe remove empty setup-created tracks", -1)
            reaper.UpdateArrange()
            -- Update ExtState with what remains and a brief log
            extSet("created_guids", joinCSV(kept_guids))
            extSet("change_log", string.format("deleted=%d; kept_with_items=%d", #deleted_guids, #kept_guids))
        end
    end

    -- Remove track midi if present
    local function deleteControlTrack()
        local guid = nil
        if reaper.GetProjExtState then
            local ok, val = reaper.GetProjExtState(0, "FLOOPA_MIDI", "MidiControlTrackGUID")
            if ok == 1 and val ~= "" then guid = val end
        end

        local foundTr = nil
        local proj = 0
        local total = reaper.CountTracks(proj)

        if guid then
             for i = 0, total - 1 do
                local tr = reaper.GetTrack(proj, i)
                if reaper.GetTrackGUID(tr) == guid then
                    foundTr = tr
                    break
                end
             end
        end

        if not foundTr then
             for i = 0, total - 1 do
                local tr = reaper.GetTrack(proj, i)
                local _, name = reaper.GetSetMediaTrackInfo_String(tr, 'P_NAME', '', false)
                if name == 'Floopa MIDI Control' then
                    foundTr = tr
                    break
                end
             end
        end

        if foundTr then
            reaper.Undo_BeginBlock()
            reaper.DeleteTrack(foundTr)
            reaper.Undo_EndBlock('Floopa: remove MIDI Control track on revert', -1)
            reaper.UpdateArrange()
        end
    end
    deleteControlTrack()

    extSet("active", "0")

  
    restoreMetronomeSnapshot()
end


-- Function to configure initial setup
setupFloopa = function()
    saveUserSettings()
    
    saveMetronomeSnapshot()
    State.setup.floopaSetupDone = true 
    
    -- Safety: clear any pre-existing time selection and loop points
    State.transport.selectedAction = nil
    if clearLoopSelection then
        clearLoopSelection()
    else
        reaper.Main_OnCommand(40020, 0)
        reaper.UpdateArrange(); reaper.UpdateTimeline()
    end
    
    -- Set new loop recording preferences
    local recaddatloop = reaper.SNM_GetIntConfigVar("recaddatloop", 0)
    recaddatloop = recaddatloop | 1  
    recaddatloop = recaddatloop | 4  
    recaddatloop = recaddatloop | 8  
    reaper.SNM_SetIntConfigVar("recaddatloop", recaddatloop)
    
    -- Execute initial actions only if not already set
   local initialCommands = {
        {id = 40507, state = reaper.GetToggleCommandState(40507)},
        {id = 40621, state = reaper.GetToggleCommandState(40621)},
        {id = 40076, state = reaper.GetToggleCommandState(40076)},
        {id = 41329, state = reaper.GetToggleCommandState(41329)},
        {id = 1068, state = reaper.GetToggleCommandState(1068)},
        {id = 43151, state = reaper.GetToggleCommandState(43151)}
    }
    for _, cmd in ipairs(initialCommands) do
        if cmd.state == 0 then
            reaper.Main_OnCommand(cmd.id, 0)
        end
    end

   
    do
        local function runNamed(name)
            local id = reaper.NamedCommandLookup(name)
            if id and id ~= 0 then reaper.Main_OnCommand(id, 0) end
        end

        -- Pre‑roll OFF su play e record
        local pr_play = reaper.GetToggleCommandState(41818)
        if pr_play == 1 then reaper.Main_OnCommand(41818, 0) end
        local pr_rec = reaper.GetToggleCommandState(41819)
        if pr_rec == 1 then reaper.Main_OnCommand(41819, 0) end

        -- Metronome: OFF in playback, ON in recording
        runNamed("_SWS_AWMPLAYOFF")
        runNamed("_SWS_AWMRECON")

        -- Count‑in: OFF su playback, ON su recording
        runNamed("_SWS_AWCOUNTPLAYOFF")
        runNamed("_SWS_AWCOUNTRECON")

        -- Misure di count‑in: 2
        if reaper.SNM_SetDoubleConfigVar then
            reaper.SNM_SetDoubleConfigVar("projmetrocountin", 2.0)
        end

     
        runNamed("_SWS_METRONON")
    end
    
 
   local created = ensureFloopaTracksIdempotent()
   if #created > 0 then
       State.tracks.created = true
   else
       State.tracks.created = true
   end
   extSet("active", "1")
   extSet("created_guids", joinCSV(created))
   extSet("change_log", (#created > 0) and ("created=" .. tostring(#created)) or "created=0")

    
    do
        local flist_color = getFloopaTracks()
        for _, e in ipairs(flist_color) do
            reaper.SetTrackColor(e.track, FLOOPA_TRACK_COLOR_BASE)
        end
        reaper.UpdateArrange()
    end
    
    -- Select and arm only Floopa tracks 1..5 
    reaper.Main_OnCommand(40297, 0)
    local flist = getFloopaTracks()
    for _, e in ipairs(flist) do
        if e.num >= 1 and e.num <= 5 then
            reaper.SetTrackSelected(e.track, true)
            reaper.SetMediaTrackInfo_Value(e.track, "I_RECARM", 1)
            if State.setup.commandId then
                reaper.Main_OnCommand(State.setup.commandId, 0)
            end
        end
    end
    
    -- Execute actions on selected tracks (only Floopa 1..5 are selected)
    local trackCommands = {40740, 42063, 42047, 42431, 43099, 43100}
    for _, cmd in ipairs(trackCommands) do
        reaper.Main_OnCommand(cmd, 0)
    end
    
   
    local autoRecEnabled = getPersistedAutoRecArm()
    applyAutoRecArmToFloopaTracks(autoRecEnabled)
    setPersistedAutoRecArm(autoRecEnabled)

    -- Safeguard: restore original auto-recarm for non-Floopa tracks
    do
        local flist2 = getFloopaTracks()
        local floopaSet = {}
        for _, e in ipairs(flist2) do
            local g = reaper.GetTrackGUID(e.track)
            floopaSet[g] = true
        end
        local nt = reaper.CountTracks(0)
        for i = 0, nt - 1 do
            local tr = reaper.GetTrack(0, i)
            if tr then
                local g = reaper.GetTrackGUID(tr)
                if not floopaSet[g] then
                    local orig = State.setup.userSettings and State.setup.userSettings.autoRecArmByGuid and State.setup.userSettings.autoRecArmByGuid[g]
                    if orig ~= nil then
                        reaper.SetMediaTrackInfo_Value(tr, "B_AUTO_RECARM", orig)
                    end
                end
            end
        end
    end

    -- Deselect all tracks
    reaper.Main_OnCommand(40297, 0)
end



-- Function to set loop length
-- Helper: compute time (seconds) by advancing measures from startTime.
local function timeAfterMeasures(startTime, measures)
    local proj = 0
    local curTime = startTime
    local remaining = measures

    local startQN = nil
    if reaper.TimeMap2_timeToQN then
        startQN = reaper.TimeMap2_timeToQN(proj, startTime)
    else
        -- attempt to extract a QN-like value from TimeMap2_timeToBeats
        local ok, a, b = pcall(reaper.TimeMap2_timeToBeats, proj, startTime)
        if ok then
            
            if type(b) == 'number' then startQN = b
            elseif type(a) == 'number' then startQN = a
            end
        end
    end
    if not startQN or type(startQN) ~= 'number' then startQN = 0 end
    local curQN = startQN
    -- Helper to fetch time signature at position 
    local function getTimeSigAt(time)
        if reaper.TimeMap2_getTimeSigAtTime then
            return reaper.TimeMap2_getTimeSigAtTime(proj, time)
        end
        if reaper.TimeMap2_GetTimeSigAtTime then
            return reaper.TimeMap2_GetTimeSigAtTime(proj, time)
        end
        if reaper.TimeMap_GetTimeSigAtTime then
            return reaper.TimeMap_GetTimeSigAtTime(proj, time)
        end
        return nil
    end

    while remaining > 0 do
        -- Try to get the numerator/denominator of the time signature at the current position
        local num, den
        local ok, a, b = pcall(getTimeSigAt, curTime)
        if ok and a and b then
            num = a
            den = b
        else
            -- fallback if API doesn't exist or doesn't return values: use beatsPerMeasure/4
            num = State.transport.beatsPerMeasure
            den = 4
        end

        -- QN per measure: num * (4 / den)
        local qnPerMeasure = num * (4 / den)
        local nextQN = curQN + qnPerMeasure
        local nextTime = reaper.TimeMap2_QNToTime(proj, nextQN)
        if not nextTime or type(nextTime) ~= 'number' then
            -- as a last resort try to compute via beats->time
            nextTime = reaper.TimeMap2_QNToTime(proj, curQN + qnPerMeasure)
        end
        if not nextTime or type(nextTime) ~= 'number' then break end
        curTime = nextTime
        curQN = nextQN
        remaining = remaining - 1
    end
    return curTime
end

-- Quantize position to the nearest measure boundary
local function quantizeToNearestMeasure(pos)
    if not pos or pos < 0 then return 0 end
    local proj = 0
    
    -- Convert position to quarter notes
    local posQN = nil
    if reaper.TimeMap2_timeToQN then
        posQN = reaper.TimeMap2_timeToQN(proj, pos)
    else
        local ok, a, b = pcall(reaper.TimeMap2_timeToBeats, proj, pos)
        if ok then
            posQN = (type(b) == 'number') and b or ((type(a) == 'number') and a or 0)
        end
    end
    if not posQN or type(posQN) ~= 'number' then return pos end
    
    -- Get time signature at this position
    local function getTimeSigAt(time)
        if reaper.TimeMap2_getTimeSigAtTime then
            return reaper.TimeMap2_getTimeSigAtTime(proj, time)
        end
        if reaper.TimeMap2_GetTimeSigAtTime then
            return reaper.TimeMap2_GetTimeSigAtTime(proj, time)
        end
        if reaper.TimeMap_GetTimeSigAtTime then
            return reaper.TimeMap_GetTimeSigAtTime(proj, time)
        end
        return nil
    end
    
    local num, den
    local ok, a, b = pcall(getTimeSigAt, pos)
    if ok and a and b then
        num = a
        den = b
    else
        num = State.transport.beatsPerMeasure
        den = 4
    end
    
    -- Calculate measure length in quarter notes
    local qnPerMeasure = num * (4 / den)
    
    -- Find the measure boundary
    local measureIndex = math.floor(posQN / qnPerMeasure)
    local measureStartQN = measureIndex * qnPerMeasure
    local measureEndQN = (measureIndex + 1) * qnPerMeasure
    
    -- Choose nearest boundary
    local distToStart = math.abs(posQN - measureStartQN)
    local distToEnd = math.abs(posQN - measureEndQN)
    
    local targetQN = (distToStart <= distToEnd) and measureStartQN or measureEndQN
    
    
    local targetTime = reaper.TimeMap2_QNToTime(proj, targetQN)
    return (targetTime and type(targetTime) == 'number') and targetTime or pos
end

setLoop = function(measures)
    local timeSelStart = reaper.GetCursorPosition()
    local timeSelEnd = timeAfterMeasures(timeSelStart, measures)
    if timeSelEnd and timeSelEnd > timeSelStart then
        reaper.GetSet_LoopTimeRange(true, false, timeSelStart, timeSelEnd, false)
        
        local function ensureLoopPlaybackReady()
            if reaper.GetToggleCommandState(1068) ~= 1 then
                reaper.Main_OnCommand(1068, 0) -- Repeat ON
            end
            if reaper.GetToggleCommandState(40621) ~= 1 then
                reaper.Main_OnCommand(40621, 0) -- Link loop points to time selection
            end
        end
        ensureLoopPlaybackReady()
        reaper.SetEditCurPos(timeSelStart, false, false)
        reaper.UpdateArrange()
        reaper.UpdateTimeline()
        statusSet(string.format("Loop set: %d measure(s)", measures or 0), "ok")
    else
        reaper.ShowMessageBox("Unable to set loop length for the requested measures.", "Error", 0)
        statusSet("Failed to set loop.", "error")
    end
end

-- Clear loop/time selection completely
function clearLoopSelection()
    -- Use REAPER action to remove time selection AND loop points
    reaper.Main_OnCommand(40020, 0) -- Time selection: Remove (unselect) time selection and loop points
    reaper.UpdateArrange()
    reaper.UpdateTimeline()
    statusSet("Loop length: no selection", "ok", 1.8)
end

-- Detect if a manual time selection is set
local function hasManualLoopSelection()
    local s, e = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
    return (s and e) and (e - s) > 0.0001
end

-- Quantize end to the next measure boundary forward from startPos
local function quantizeEndToMeasureForward(startPos, endPos)
    if not startPos or not endPos or endPos <= startPos then return nil end
    local tol = State.loop.tolerance or 0.12
    local k = 1
    local nextTime = timeAfterMeasures(startPos, k)
    
    while nextTime and (nextTime + tol) < endPos do
        k = k + 1
        
        if k > 256 then break end
        nextTime = timeAfterMeasures(startPos, k)
    end
    if not nextTime or nextTime <= startPos then return nil end
    return nextTime, k
end

-- Quantize end to the nearest measure boundary from startPos
local function quantizeEndToMeasureNearest(startPos, endPos)
    if not startPos or not endPos or endPos <= startPos then return nil end
    local tol = State.loop.tolerance or 0.12
    local k = 1
    local cur = timeAfterMeasures(startPos, k)
    if not cur then return nil end
    while cur and cur < endPos do
        k = k + 1
        if k > 256 then break end
        cur = timeAfterMeasures(startPos, k)
    end
    if not cur then return nil end
    local prev = timeAfterMeasures(startPos, math.max(0, k-1)) or startPos
   
    local dPrev = math.abs(endPos - prev)
    local dNext = math.abs(cur - endPos)
    local boundary = (dPrev + tol <= dNext) and prev or cur
    local measures = (boundary == prev) and (k-1) or k
    if not boundary or boundary <= startPos then return nil end
    return boundary, measures
end

-- Smart quantize: if you exceed 1/4 of a measure, go to next measure
local function quantizeEndToMeasureSmart(startPos, endPos)
    if not startPos or not endPos or endPos <= startPos then return nil end
    local tol = State.loop.tolerance or 0.12
    local k = 1
    local cur = timeAfterMeasures(startPos, k)
    if not cur then return nil end
    while cur and cur < endPos do
        k = k + 1
        if k > 256 then break end
        cur = timeAfterMeasures(startPos, k)
    end
    if not cur then return nil end
    local prev = timeAfterMeasures(startPos, math.max(0, k-1)) or startPos
    
   
    local measureLength = cur - prev
    local overshoot = endPos - prev
    local overshootRatio = overshoot / measureLength
    
  
    local boundary, measures
    if overshootRatio > 0.25 then
        boundary = cur
        measures = k
    else
        -- Standard nearest logic
        local dPrev = math.abs(endPos - prev)
        local dNext = math.abs(cur - endPos)
        boundary = (dPrev + tol <= dNext) and prev or cur
        measures = (boundary == prev) and (k-1) or k
    end
    
    if not boundary or boundary <= startPos then return nil end
    return boundary, measures
end

local function debugAutoLoop(msg) end

-- Logic to capture first take and set auto loop
local function autoLoopPoll()
    if not State.loop.autoEnabled then return end
    
    local manual = hasManualLoopSelection()
    if manual ~= State.loop._lastManualFlag then
        if manual then
            debugAutoLoop("manual selection present (autoloop continues)")
        else
            debugAutoLoop("manual selection cleared")
        end
        State.loop._lastManualFlag = manual
    end

    

    local ps = reaper.GetPlayState()
    local isRec = (ps & 4) == 4
    local wasRec = (State.transport.prevPlayState or 0) & 4 == 4

    

    -- Transition to recording: capture start 
    if (not wasRec) and isRec then
        if reaper.ClearConsole then reaper.ClearConsole() end
        local rawPos = reaper.GetPlayPosition()
        if State.loop.startAlign == 'measure' then
            State.loop.startPos = quantizeToNearestMeasure(rawPos)
        else
            State.loop.startPos = rawPos
        end
        debugAutoLoop(string.format("enter rec rawPos=%.3f align=%s startPos=%.3f", rawPos or -1, State.loop.startAlign or "", State.loop.startPos or -1))
        local autoPunchActive = reaper.GetToggleCommandState(40076) == 1
        if autoPunchActive and (not hasManualLoopSelection()) then
            reaper.Main_OnCommand(40252, 0) -- Record mode: normal
            State.transport.tempDisableAutoPunch = true
            debugAutoLoop("auto punch disabled temporarily")
        end
        local s, e = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
        if (not hasManualLoopSelection()) and s and e and (e - s) > 0.0001 then
            debugAutoLoop(string.format("clearing existing non-manual selection start=%.3f end=%.3f", s or -1, e or -1))
            reaper.GetSet_LoopTimeRange(true, false, 0, 0, false)
        end
        
    end

    if wasRec and (not isRec) and State.loop.startPos then
       
        local endPos = reaper.GetPlayPosition()
        local startSel = State.loop.startPos
        local endSel = endPos
        debugAutoLoop(string.format("exit rec startSel=%.3f endSel=%.3f", startSel or -1, endSel or -1))
        local searchEnd = endPos
        if not searchEnd or searchEnd <= startSel then
            searchEnd = startSel + 3600.0
            debugAutoLoop(string.format("endPos<=startSel, widening searchEnd to %.3f", searchEnd))
        end
        local flist = getFloopaTracks()
        local minStart = math.huge
        local maxEnd = 0
  
        local eps = computeEpsilon(startSel, endPos)
        for _, e in ipairs(flist) do
            local tr = e.track
            local cnt = reaper.CountTrackMediaItems(tr)
            for i = 0, cnt - 1 do
                local it = reaper.GetTrackMediaItem(tr, i)
                if it then
                    local pos = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
                    local len = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
                    if type(pos) == 'number' and type(len) == 'number' then
                        local itEnd = pos + len
                       
                        if (itEnd > (startSel - eps)) and (pos < (searchEnd + eps)) then
                            if pos < minStart then minStart = pos end
                            if itEnd > maxEnd then maxEnd = itEnd end
                        end
                    end
                end
            end
        end
        local haveItems = (maxEnd > 0 and minStart < math.huge)
        local baseStart = startSel
        local baseEnd = endSel
        if haveItems then
            baseStart = minStart
            baseEnd = maxEnd
        end
        debugAutoLoop(string.format("items window haveItems=%s minStart=%.3f maxEnd=%.3f eps=%.4f", tostring(haveItems), minStart or -1, maxEnd or -1, eps or -1))
        local qEnd, measures
        if State.loop.rounding == 'nearest' then
            qEnd, measures = quantizeEndToMeasureNearest(baseStart, baseEnd)
        elseif State.loop.rounding == 'smart' then
            qEnd, measures = quantizeEndToMeasureSmart(baseStart, baseEnd)
        else
            qEnd, measures = quantizeEndToMeasureForward(baseStart, baseEnd)
        end
        debugAutoLoop(string.format("quantize mode=%s baseStart=%.3f baseEnd=%.3f qEnd=%s measures=%s", State.loop.rounding or "", baseStart or -1, baseEnd or -1, qEnd and string.format("%.3f", qEnd) or "nil", tostring(measures)))
        if (not qEnd) or (qEnd <= baseStart) then
            qEnd = baseEnd
            if not measures or measures < 1 then
                measures = 1
            end
            debugAutoLoop(string.format("fallback qEnd=%.3f measures=%s", qEnd or -1, tostring(measures)))
        end
        if qEnd and baseStart and qEnd > baseStart then

            local cfg = State.loop.microFades or { durationMs = 5 }
            local fadeLen = math.max(0, math.min(500, tonumber(cfg.durationMs) or 5)) / 1000.0
            local threshold = math.max(eps or 0.05, fadeLen)
            baseStart, qEnd = alignLoopToNearestItemBoundaries(baseStart, qEnd, threshold)
            reaper.GetSet_LoopTimeRange(true, false, baseStart, qEnd, false)
            local s2, e2 = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
            debugAutoLoop(string.format("loop range set start=%.3f end=%.3f", s2 or -1, e2 or -1))
           
            if reaper.GetToggleCommandState(1068) ~= 1 then
                reaper.Main_OnCommand(1068, 0) -- Repeat ON
            end
            if reaper.GetToggleCommandState(40621) ~= 1 then
                reaper.Main_OnCommand(40621, 0) -- Link loop points to time selection
            end
           
            
            applyMicroFadesConfigured(startSel, qEnd)
            reaper.UpdateArrange()
            reaper.UpdateTimeline()
            -- Ensure playhead respects the newly created loop selection
            local playState = reaper.GetPlayState()
            local playing = (playState & 1) == 1
            local pos = reaper.GetPlayPosition()
            if playing and (pos < baseStart or pos > qEnd) then
                debugAutoLoop(string.format("playhead outside loop pos=%.3f, restarting at %.3f", pos or -1, baseStart or -1))
                reaper.OnStopButton()
                reaper.SetEditCurPos(baseStart, true, false)
                reaper.OnPlayButton()
            else
                reaper.SetEditCurPos(baseStart, true, false)
                debugAutoLoop(string.format("cursor moved to loop start %.3f", baseStart or -1))
            end
            State.loop.locked = true
            statusSet(string.format("Auto loop set: %d measure(s)", measures or 1), "ok", 2.5)
        else
            debugAutoLoop("no valid loop window, nothing applied")
        end
        State.loop.startPos = nil
        -- Restore auto-punch if it was temporarily disabled
        if State.transport.tempDisableAutoPunch then
            reaper.Main_OnCommand(40076, 0) 
            State.transport.tempDisableAutoPunch = false
            debugAutoLoop("auto punch restored")
        end
    end
end

-- Function to go to measure
goToMeasure = function()
    local measure = tonumber(State.input.measure)
    if measure then
       
        local time = timeAfterMeasures(0, math.max(0, measure - 1))
        if time and type(time) == 'number' then
            reaper.SetEditCurPos2(0, time, false, false)
            statusSet(string.format("Jumped to measure %d", measure), "ok")
        else
            reaper.ShowMessageBox("Invalid measure number.", "Error", 0)
            statusSet("Invalid measure number.", "error")
        end
    else
        reaper.ShowMessageBox("Please enter a valid measure number.", "Error", 0)
    end
end

-- Function to set BPM
setBPM = function()
    local new_bpm = tonumber(State.input.bpm)
    if new_bpm and new_bpm > 0 then
        reaper.SetCurrentBPM(0, new_bpm, true)
        State.transport.bpmLast = new_bpm
    end
end





-- Function to select a track
local function selectTrack(trackIndex)
  local track = reaper.GetTrack(0, trackIndex)
  if track then
    reaper.SetOnlyTrackSelected(track)
    
    local list = getFloopaTracks()
    for _, e in ipairs(list) do
      reaper.SetTrackColor(e.track, FLOOPA_TRACK_COLOR_BASE)
    end
    reaper.SetTrackColor(track, FLOOPA_TRACK_COLOR_SELECTED)
    reaper.UpdateArrange()
    reaper.TrackList_AdjustWindows(false)
  else
    reaper.ShowMessageBox("Track not found.", "Error", 0)
  end
end


-- MIDI Map bridge: consume commands from external MIDI Map via ExtState
local MIDI_NS = "FLOOPA_MIDI"
-- Initialize to current time to avoid consuming stale commands on startup
local midi_last_ts = reaper.time_precise()
-- Per‑command cooldown to evitare doppi trigger ravvicinati da MIDI
local midi_last_cmd_ts = {}
local MIDI_CMD_COOLDOWN = { record_toggle = 1.5 }


-- Function to set track mute
local function toggleTrackMute(trackIndex)
    local track = reaper.GetTrack(0, trackIndex)
    if track then
        local muteState = reaper.GetMediaTrackInfo_Value(track, "B_MUTE")
        local newState = muteState == 0 and 1 or 0
        reaper.SetMediaTrackInfo_Value(track, "B_MUTE", newState)
        statusSet(string.format("Track %d %s", trackIndex + 1, newState == 1 and "muted" or "unmuted"), "info", 1.8)
    else
        statusSet("Track not found.", "error")
    end
end

-- Function to set track MIDI input
local function setTrackInputMIDI(trackIndex)
    local track = reaper.GetTrack(0, trackIndex)
    if track then
        reaper.SetMediaTrackInfo_Value(track, "I_RECINPUT", 4096 + 0x7E0) -- MIDI: All Inputs, All Channels
    end
end

-- Function to set track audio input
local function setTrackInputAudio(trackIndex)
    local track = reaper.GetTrack(0, trackIndex)
    if track then
        -- Set to Audio: Mono input 1 (more predictable than an undefined "All Inputs")
        reaper.SetMediaTrackInfo_Value(track, "I_RECINPUT", 0)
    end
end

-- Function to change a track's input
local function toggleTrackInput(trackIndex)
    local track = reaper.GetTrack(0, trackIndex)
    if track then
        local inputType = reaper.GetMediaTrackInfo_Value(track, "I_RECINPUT")
        if inputType >= 4096 then
            setTrackInputAudio(trackIndex)
            extSet("track_input_" .. trackIndex, "audio")
            statusSet(string.format("Track %d input: Audio (mono 1)", trackIndex + 1), "info", 1.5)
        else
            setTrackInputMIDI(trackIndex)
            extSet("track_input_" .. trackIndex, "midi")
            statusSet(string.format("Track %d input: MIDI", trackIndex + 1), "info", 1.5)
        end
    else
        statusSet("Track not found.", "error")
    end
end

-- Variables for track mute state
local trackMuteStates = {false, false, false, false, false}

-- Function to run selection script and toggle reverse
local function toggleReverse(trackIndex)
    reaper.Undo_BeginBlock()
    reaper.PreventUIRefresh(1)
    
    local selItems = {}
    local numItems = reaper.CountMediaItems(0)
    for i = 0, numItems - 1 do
        local it = reaper.GetMediaItem(0, i)
        if it and reaper.IsMediaItemSelected(it) then
            table.insert(selItems, it)
        end
    end

    -- Get the specified track and select its items
    local track = reaper.GetTrack(0, trackIndex)
    if track then
        local item_count = reaper.CountTrackMediaItems(track)
        for i = 0, item_count - 1 do
            local item = reaper.GetTrackMediaItem(track, i)
            if item then
                reaper.SetMediaItemSelected(item, true)
            end
        end
    end

    reaper.PreventUIRefresh(-1)
    reaper.UpdateArrange()
    reaper.Undo_EndBlock("Toggle Reverse on track", -1)

    -- Perform Toggle Reverse action 
    if not commandExists(41051) then
        notifyInfo("Reverse command not available.")
    else
        reaper.Main_OnCommand(41051, 0)
    end

    -- Restore initial item selection
    reaper.PreventUIRefresh(1)
    reaper.SelectAllMediaItems(0, false)
    for _, it in ipairs(selItems) do
        reaper.SetMediaItemSelected(it, true)
    end
    reaper.PreventUIRefresh(-1)
    reaper.UpdateArrange()
end


-- Function to update track volumes
local function update_track_volumes()
    local num_tracks = reaper.CountTracks(0)
    for i = 0, num_tracks - 1 do
        local track = reaper.GetTrack(0, i)
        if track then
            State.tracks.volumes[i] = reaper.GetMediaTrackInfo_Value(track, "D_VOL")
        end
    end
end

-- Throttled updater 
local function update_track_volumes_throttled()
    if not State.perf then State.perf = {} end
    local now = reaper.time_precise()
    local interval = State.perf.volumeUpdateInterval or 0.2 -- 200 ms default
    local force = State.perf.forceVolumeUpdate == true
    local last = State.perf.lastVolumeUpdate or 0
    if force or (now - last) >= interval then
        update_track_volumes()
        State.perf.lastVolumeUpdate = now
        State.perf.forceVolumeUpdate = false
    end
end



-- Function to change a track's pitch
local function changePitch(trackIndex, pitchChange)
    reaper.Undo_BeginBlock()
    reaper.PreventUIRefresh(1)

    
    local selItems = {}
    local numItems = reaper.CountMediaItems(0)
    for i = 0, numItems - 1 do
        local it = reaper.GetMediaItem(0, i)
        if it and reaper.IsMediaItemSelected(it) then
            table.insert(selItems, it)
        end
    end

    -- Get the specified track
    local track = reaper.GetTrack(0, trackIndex)
    if track then
       
        local item_count = reaper.CountTrackMediaItems(track)
        if item_count == 0 then
            notifyInfo("No takes found to transpose.")
        end
        for i = 0, item_count - 1 do
            local item = reaper.GetTrackMediaItem(track, i)
            if item then
                reaper.SetMediaItemSelected(item, true)
                local take = reaper.GetActiveTake(item)
                if take then
                    local current_pitch = reaper.GetMediaItemTakeInfo_Value(take, "D_PITCH")
                    reaper.SetMediaItemTakeInfo_Value(take, "D_PITCH", current_pitch + pitchChange)
                end
            end
        end
    end

    reaper.UpdateArrange()
    reaper.PreventUIRefresh(-1)
    reaper.Undo_EndBlock("Change pitch on track", -1)

    reaper.PreventUIRefresh(1)
    reaper.SelectAllMediaItems(0, false)
    for _, it in ipairs(selItems) do
        reaper.SetMediaItemSelected(it, true)
    end
    reaper.PreventUIRefresh(-1)
    reaper.UpdateArrange()
end

-- Delete all items on a track
local function deleteAllItemsOnTrack(trackIndex)
    local track = reaper.GetTrack(0, trackIndex)
    if not track then return end
    reaper.Undo_BeginBlock()
    reaper.PreventUIRefresh(1)
    local i = reaper.CountTrackMediaItems(track) - 1
    while i >= 0 do
        local item = reaper.GetTrackMediaItem(track, i)
        if item then reaper.DeleteTrackMediaItem(track, item) end
        i = i - 1
    end
    reaper.UpdateArrange()
    reaper.PreventUIRefresh(-1)
    reaper.Undo_EndBlock("Delete all items on track", -1)
end

-- Helper: count lanes for a track robustly (FIXEDLANES or PLAYLIST count)
local function getTrackLaneCount(tr)
    if not tr then return nil end
    local ok, chunk = reaper.GetTrackStateChunk(tr, "", false)
    if not ok or not chunk or chunk == "" then return nil end
    -- Prefer numeric count from FIXEDLANES when present
    local num = chunk:match("FIXEDLANES%s+(%d+)")
    if num then
        local n = tonumber(num)
        if n and n > 0 then return n end
    end
    -- Fallback: count PLAYLIST blocks
    local c = 0
    for _ in string.gmatch(chunk, "PLAYLIST") do c = c + 1 end
    return (c > 0) and c or 1
end

-- Helper to reset a track to a single empty lane
local function resetTrackToSingleEmptyLane(trackIndex)
    local track = reaper.GetTrack(0, trackIndex)
    if not track then return end
    
    reaper.Undo_BeginBlock()
    reaper.PreventUIRefresh(1)
    reaper.Main_OnCommand(40297, 0) 
    reaper.SetOnlyTrackSelected(track)

    -- Remove all media items from the track 
    local i = reaper.CountTrackMediaItems(track) - 1
    local removed_items = 0
    while i >= 0 do
        local item = reaper.GetTrackMediaItem(track, i)
        if item then reaper.DeleteTrackMediaItem(track, item); removed_items = removed_items + 1 end
        i = i - 1
    end


    -- Delete lanes with a fixed, safe cap to ensure reduction to 1
    
    for n = 1, 64 do
        reaper.Main_OnCommand(42648, 0)
    end
    -- Hard-enforce FIXEDLANES=1 in the track chunk to avoid accidental disabling
    do
        local ok, chunk = reaper.GetTrackStateChunk(track, "", false)
        if ok and chunk and #chunk > 0 then
            local before_cnt = getTrackLaneCount(track)
            local new_chunk
            if chunk:match("FIXEDLANES%s+%d+") then
                new_chunk = chunk:gsub("FIXEDLANES%s+%d+", "FIXEDLANES 1")
            else
                -- Insert FIXEDLANES 1 near the start of the TRACK chunk
                new_chunk = chunk:gsub("(\nTRACK(.-)\n)", function(hdr)
                    return hdr .. "FIXEDLANES 1 0 0 0 0\n"
                end, 1)
                if new_chunk == chunk then
                    -- Fallback: append at end if header pattern not matched
                    new_chunk = chunk .. "\nFIXEDLANES 1 0 0 0 0\n"
                end
            end
            if new_chunk and new_chunk ~= chunk then
                reaper.SetTrackStateChunk(track, new_chunk, false)
            end
            local after_cnt = getTrackLaneCount(track)
        end
    end

    local final_after = getTrackLaneCount(track)
   

    reaper.PreventUIRefresh(-1)
    reaper.Undo_EndBlock("Floopa: reset track to single empty lane", -1)
    reaper.UpdateArrange()
end

-- Helper: reapply base color to all Floopa tracks
local function applyBaseColorsToFloopaTracks()
    local list = getFloopaTracks()
    for _, e in ipairs(list) do
        reaper.SetTrackColor(e.track, FLOOPA_TRACK_COLOR_BASE)
    end
    reaper.UpdateArrange()
end

-- Helper: keep Floopa track colors in sync with current selection
local function syncFloopaTrackColorsWithSelection()
    local list = getFloopaTracks()
    local changed = false
    for _, e in ipairs(list) do
        local isSel = reaper.IsTrackSelected(e.track)
        local desired = isSel and FLOOPA_TRACK_COLOR_SELECTED or FLOOPA_TRACK_COLOR_BASE
        local cur = reaper.GetTrackColor(e.track)
        if cur ~= desired then
            reaper.SetTrackColor(e.track, desired)
            changed = true
        end
    end
    if changed then
        reaper.UpdateArrange()
        reaper.TrackList_AdjustWindows(false)
    end
end

-- Ensure defaults before recording: Add lanes when recording ON and fixed lanes present
local function ensureRecordingLaneDefaults()
    -- Toggle global "Add lanes when recording" ONLY if setup is completed
    local allowGlobalToggle = (State and State.setup and State.setup.floopaSetupDone) or false
    if allowGlobalToggle and reaper.GetToggleCommandState(41329) ~= 1 then
        reaper.Main_OnCommand(41329, 0)
    end
    -- Ensure each Floopa track has FIXEDLANES=1 in chunk (minimum)
    local flist = getFloopaTracks()
    for _, e in ipairs(flist) do
        if e.num >= 1 and e.num <= 5 then
            local ok, chunk = reaper.GetTrackStateChunk(e.track, "", false)
            if ok and chunk and #chunk > 0 then
                if not chunk:match("FIXEDLANES%s+%d+") or chunk:match("FIXEDLANES%s+0") then
                    local new_chunk
                    if chunk:match("FIXEDLANES%s+%d+") then
                        new_chunk = chunk:gsub("FIXEDLANES%s+%d+", "FIXEDLANES 1")
                    else
                        new_chunk = chunk:gsub("(\nTRACK(.-)\n)", function(hdr)
                            return hdr .. "FIXEDLANES 1 0 0 0 0\n"
                        end, 1)
                        if new_chunk == chunk then new_chunk = chunk .. "\nFIXEDLANES 1 0 0 0 0\n" end
                    end
                    if new_chunk and new_chunk ~= chunk then
                        reaper.SetTrackStateChunk(e.track, new_chunk, false)
                    end
                end
            end
        end
    end
end

-- Function to delete all takes recorded on the first 5 Floopa tracks
clearAllFloopa = function()
    local flist = getFloopaTracks()
    if not flist or #flist == 0 then
        notifyInfo("No Floopa tracks found. Run 'Setup Floopa' first.", 2.0)
        return
    end

    notifyInfo("Clear All", 1.5)
    reaper.Undo_BeginBlock()
    reaper.PreventUIRefresh(1)
    for _, e in ipairs(flist) do
        local tr = e.track
        local before = tr and getTrackLaneCount(tr) or "?"
        local idx1 = tr and reaper.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER") or nil
        local zeroIndex = (idx1 and idx1 > 0) and (idx1 - 1) or nil
        if zeroIndex ~= nil then
            resetTrackToSingleEmptyLane(zeroIndex)
        end
        local after = tr and getTrackLaneCount(tr) or "?"
        notifyInfo(string.format("Floopa %d lanes=%s", e.num or 0, tostring(after)), 1.0)
    end

    reaper.GetSet_LoopTimeRange(true, false, 0, 0, false)
    
    State.loop.locked = false
    State.loop.startPos = nil
 
    applyBaseColorsToFloopaTracks()
    reaper.UpdateArrange()
    reaper.PreventUIRefresh(-1)
    reaper.Undo_EndBlock("Clear all Floopa tracks and reset lanes", -1)
   
    reaper.Main_OnCommand(40297, 0)
end


local function anyTrackSelected()
    local numTracks = reaper.CountTracks(0)
    for i = 0, numTracks - 1 do
        local tr = reaper.GetTrack(0, i)
        if tr and reaper.IsTrackSelected(tr) then
            return true
        end
    end
    return false
end

-- Global color definitions
local function applyTheme()
    local color_count, style_var_count = applyThemeBase()

    if State.ui and State.ui.ctx then
        local added = 0
        if reaper.ImGui_StyleVar_SeparatorTextAlign then
            reaper.ImGui_PushStyleVar(State.ui.ctx, reaper.ImGui_StyleVar_SeparatorTextAlign(), 0.5, 0.5)
            added = added + 1
        end
        if reaper.ImGui_StyleVar_SeparatorTextBorderSize then
            reaper.ImGui_PushStyleVar(State.ui.ctx, reaper.ImGui_StyleVar_SeparatorTextBorderSize(), uiScale(2))
            added = added + 1
        end
        if reaper.ImGui_StyleVar_SeparatorTextPadding then
            reaper.ImGui_PushStyleVar(State.ui.ctx, reaper.ImGui_StyleVar_SeparatorTextPadding(), uiScale(10), uiScale(5))
            added = added + 1
        end
        return color_count, style_var_count + added
    end
    return color_count, style_var_count
end

local show_modal = false



-- One-time initialization of persisted inputs and auto-recarm
local function bootstrapOnce()
    
    if not State.setup.inputsApplied then
        -- Applica gli input solo alle tracce Floopa identificate per nome
        local floopaTracks = getFloopaTracks()
        for _, ft in ipairs(floopaTracks) do
            local key = tostring(ft.num - 1)
            local v = extGet("track_input_" .. key)
            if v == "midi" then
                reaper.SetMediaTrackInfo_Value(ft.track, "I_RECINPUT", 4096 + 0x7E0)
            elseif v == "audio" then
                reaper.SetMediaTrackInfo_Value(ft.track, "I_RECINPUT", 0)
            end
        end
        State.setup.inputsApplied = true
    end
    
    if not State.setup.autoRecArmApplied then
        local autoRecEnabled = getPersistedAutoRecArm()
        applyAutoRecArmToFloopaTracks(autoRecEnabled)
        State.setup.autoRecArmApplied = true
    end
    
    if not State.perf then State.perf = {} end
    State.perf.lastVolumeUpdate = reaper.time_precise()
    -- Performance defaults: slow down UI polling to reduce frame load
    State.perf.volumeUpdateInterval = State.perf.volumeUpdateInterval or 0.5  -- seconds
    State.perf.hudInterval = State.perf.hudInterval or 0.8                     -- seconds
    State.perf.lastHudUpdate = State.perf.lastHudUpdate or 0

    -- HUD default: disable if unset, to avoid unnecessary UI churn
    local hudPref = extGet("hud_enable")
    if hudPref == nil or hudPref == "" then extSet("hud_enable", "0") end
end


  -- === HELP MODAL ==========================================
  -- User guide with wrapped text and descriptive sections
  -- =========================================================
  local function drawHelpModal()
     if not (State and State.ui and State.ui.ctx) then return end
     
     local modalW, modalH = 720, 600
     local winX, winY = reaper.ImGui_GetWindowPos(State.ui.ctx)
     local winW, winH = reaper.ImGui_GetWindowSize(State.ui.ctx)
     if winX and winY and winW and winH then
         reaper.ImGui_SetNextWindowSize(State.ui.ctx, modalW, modalH, reaper.ImGui_Cond_Always())
         reaper.ImGui_SetNextWindowPos(State.ui.ctx, winX + (winW - modalW) * 0.5, winY + (winH - modalH) * 0.5, reaper.ImGui_Cond_Appearing())
     end
     local flags = reaper.ImGui_WindowFlags_NoResize() | reaper.ImGui_WindowFlags_NoMove()
     if reaper.ImGui_BeginPopupModal(State.ui.ctx, "Help", true, flags) then
         local childFlags = (reaper.ImGui_ChildFlags_Borders and reaper.ImGui_ChildFlags_Borders()) or 0
         if reaper.ImGui_BeginChild(State.ui.ctx, "HelpScroll", -1, -1, childFlags) then
           
             -- Overview
             reaper.ImGui_SeparatorText(State.ui.ctx, "What is Floopa Station")
             reaper.ImGui_TextWrapped(State.ui.ctx, "Floopa Station is a live-looping station for REAPER: it creates and manages 5 dedicated tracks, integrates transport controls, loop recording with Auto‑Loop, a visual Beat Counter and a loop progress bar, plus Audio/MIDI input and customizable shortcuts.")
             reaper.ImGui_Dummy(State.ui.ctx, 0, uiScale(10))

             reaper.ImGui_TextWrapped(State.ui.ctx, "• Use 'Setup Floopa' to initialize the tracks and routing.")
             reaper.ImGui_TextWrapped(State.ui.ctx, "• Use 'Revert Default' to remove the tracks and restore settings.")
             reaper.ImGui_TextWrapped(State.ui.ctx, "• Use 'Loop Length' to set the desired measures; select '--' to remove the selection and loop points.")
             reaper.ImGui_TextWrapped(State.ui.ctx, "• Use 'Clean' to remove empty MIDI/Audio items (< -50dB) and unused lanes from Floopa tracks.")
             reaper.ImGui_TextWrapped(State.ui.ctx, "• Enable 'Auto Loop' if you want recordings to define loop length and alignment automatically, at any position on the timeline.")
            reaper.ImGui_TextWrapped(State.ui.ctx, "• Configure 'Start' (Alignment: Measure/Exact) and 'End' (Rounding: Smart/Nearest/Forward) for Auto-Loop.")
            reaper.ImGui_TextWrapped(State.ui.ctx, "• Use 'Rec' to record and 'Play/Pause' to listen inside the loop.")
            reaper.ImGui_TextWrapped(State.ui.ctx, "• The Beat Counter shows the current meter and the progress bar displays loop progression.")
            reaper.ImGui_TextWrapped(State.ui.ctx, "• In the 'FLOOPA TRACKS' panel you will find info for the selected track and shortcuts for input, mute, FX, reverse and transpose.")
             reaper.ImGui_Spacing(State.ui.ctx)

             -- Main controls
             reaper.ImGui_SeparatorText(State.ui.ctx, "Main controls")
             reaper.ImGui_TextWrapped(State.ui.ctx, "• Play/Pause, Record Toggle, Metronome, Click Track.")
             reaper.ImGui_TextWrapped(State.ui.ctx, "• Auto-Loop: Start Align (Measure/Exact) and End Rounding (Smart/Nearest/Forward).")
             reaper.ImGui_TextWrapped(State.ui.ctx, "• Audio/MIDI input per Floopa tracks; Mute, FX, Reverse, Transpose ±12.")
             reaper.ImGui_TextWrapped(State.ui.ctx, "• Undo Lane and Undo All for quick take management.")
             reaper.ImGui_Spacing(State.ui.ctx)

             -- Auto-Loop details 
            reaper.ImGui_SeparatorText(State.ui.ctx, "Auto-Loop details")
            reaper.ImGui_TextWrapped(State.ui.ctx, "Auto-Loop uses your first recording pass to set loop length and position, then applies rounding at loop end. Configure Start Align and End Rounding to match your workflow.")
            reaper.ImGui_BulletText(State.ui.ctx, "Start Align: Measure (align to bar start) or Exact (align to selection start)")
            reaper.ImGui_BulletText(State.ui.ctx, "End Rounding: Smart / Nearest / Forward")
            reaper.ImGui_BulletText(State.ui.ctx, "Tolerance (Epsilon): Dynamic or Strict (ms)")
            reaper.ImGui_BulletText(State.ui.ctx, "Works from any position on the timeline; recording no longer needs to start at bar 1.")
            reaper.ImGui_Spacing(State.ui.ctx)
            
            -- Count-In
            reaper.ImGui_SeparatorText(State.ui.ctx, "Count-In")
            reaper.ImGui_TextWrapped(State.ui.ctx, "When enabled, Count-In plays pre-roll clicks before recording only.")
            reaper.ImGui_Spacing(State.ui.ctx)

            -- Beat Counter
            reaper.ImGui_SeparatorText(State.ui.ctx, "Beat Counter")
            reaper.ImGui_TextWrapped(State.ui.ctx, "Displays current measure/beat during playback and recording.")
            reaper.ImGui_BulletText(State.ui.ctx, "Syncs with Time Selection and Repeat loop for clear bar starts")
            reaper.ImGui_BulletText(State.ui.ctx, "Visual guide for overdubs, punch-ins, precise timing")
            reaper.ImGui_BulletText(State.ui.ctx, "Toggle via the 'Beat Counter' checkbox in Main controls")
            reaper.ImGui_Spacing(State.ui.ctx)

            reaper.ImGui_SeparatorText(State.ui.ctx, "Micro-Fades")
            reaper.ImGui_TextWrapped(State.ui.ctx, "Micro-Fades gently smooth clip edges to avoid clicks. Project-scoped setting; duration clamped to 0-500 ms (rounded to 10 ms steps).")
            reaper.ImGui_BulletText(State.ui.ctx, "Default: OFF at startup; enable via 'Auto Fades' in main controls")
            reaper.ImGui_BulletText(State.ui.ctx, "Duration: milliseconds (0-500, rounded to 10 ms steps)")
            reaper.ImGui_BulletText(State.ui.ctx, "Shape: Linear / Exponential / Logarithmic")
             reaper.ImGui_Spacing(State.ui.ctx)

             reaper.ImGui_SeparatorText(State.ui.ctx, "Examples")
             reaper.ImGui_TextWrapped(State.ui.ctx, "Grid-aligned looping: Start Align=Measure, Epsilon=Dynamic; Micro-Fades=On, 40ms, Exponential.")
             reaper.ImGui_TextWrapped(State.ui.ctx, "Precise audio edit: Start Align=Exact, Epsilon=Strict (30ms); Micro-Fades=On, 10ms, Linear.")
             reaper.ImGui_Spacing(State.ui.ctx)

             -- Shortcut legend 
             reaper.ImGui_SeparatorText(State.ui.ctx, "Shortcut legend")
             if reaper.ImGui_BeginTable(State.ui.ctx, "help_shortcuts", 2, reaper.ImGui_TableFlags_Borders() | reaper.ImGui_TableFlags_RowBg()) then
                 reaper.ImGui_TableSetupColumn(State.ui.ctx, "Action", reaper.ImGui_TableColumnFlags_WidthStretch())
                 reaper.ImGui_TableSetupColumn(State.ui.ctx, "Key", reaper.ImGui_TableColumnFlags_WidthFixed(), 140)
                 reaper.ImGui_TableHeadersRow(State.ui.ctx)
                 for _, action in ipairs(State.mappings.actions or {}) do
                     local id, label = action.id, action.label
                     local keyLabel
                     if id == 'setup_revert' then
                         keyLabel = 'K, L'
                     elseif id == 'select_trk' then
                         keyLabel = '1, 2, 3, 4, 5'
                     else
                         keyLabel = getKeyName(State.mappings.data[id])
                     end
                     reaper.ImGui_TableNextRow(State.ui.ctx)
                     reaper.ImGui_TableSetColumnIndex(State.ui.ctx, 0)
                     reaper.ImGui_Text(State.ui.ctx, tostring(label))
                     reaper.ImGui_TableSetColumnIndex(State.ui.ctx, 1)
                     reaper.ImGui_Text(State.ui.ctx, tostring(keyLabel))
                 end
                 reaper.ImGui_EndTable(State.ui.ctx)
             end
             reaper.ImGui_Spacing(State.ui.ctx)

             -- Prerequisites
             reaper.ImGui_SeparatorText(State.ui.ctx, "Prerequisites")
             reaper.ImGui_BulletText(State.ui.ctx, "Recent REAPER version (latest stable recommended).")
             reaper.ImGui_BulletText(State.ui.ctx, "ReaImGui installed via ReaPack (Dear ImGui for ReaScript).")
             reaper.ImGui_BulletText(State.ui.ctx, "SWS Extension installed (required for some project settings).")
             reaper.ImGui_BulletText(State.ui.ctx, "Getting started: press 'Setup Floopa' and assign shortcuts in the 'Key Mapping' modal.")
             reaper.ImGui_Spacing(State.ui.ctx)

             
             -- Close button
            local availW = reaper.ImGui_GetContentRegionAvail(State.ui.ctx)
            local btnW = uiScale(100)
            reaper.ImGui_SetCursorPosX(State.ui.ctx, (availW - btnW) * 0.5)
             with_vars({{reaper.ImGui_StyleVar_FramePadding(), 7.0, 7.0}} , function()
                if reaper.ImGui_Button(State.ui.ctx, "Close", btnW, uiScale(30)) then
                    reaper.ImGui_CloseCurrentPopup(State.ui.ctx)
                end
             end)

             reaper.ImGui_EndChild(State.ui.ctx)
         end
         reaper.ImGui_EndPopup(State.ui.ctx)
     end
 end


-- === KEY MAPPING MODAL ====================================
-- Shortcut assignment with action/key table
-- ===========================================================
local function drawKeyMappingModal()
     if not (State and State.ui and State.ui.ctx) then return end
     local modalW, modalH = uiScale(700), uiScale(620)
     local winX, winY = reaper.ImGui_GetWindowPos(State.ui.ctx)
     local winW, winH = reaper.ImGui_GetWindowSize(State.ui.ctx)
     if winX and winY and winW and winH then
         reaper.ImGui_SetNextWindowSize(State.ui.ctx, modalW, modalH, reaper.ImGui_Cond_Always())
         reaper.ImGui_SetNextWindowPos(State.ui.ctx, winX + (winW - modalW) * 0.5, winY + (winH - modalH) * 0.5, reaper.ImGui_Cond_Appearing())
     end
     local km_flags = reaper.ImGui_WindowFlags_NoResize() | reaper.ImGui_WindowFlags_NoMove()
    if reaper.ImGui_BeginPopupModal(State.ui.ctx, "Key Mapping", true, km_flags) then
        
        State.mappings.modalOpen = true
        reaper.ImGui_Text(State.ui.ctx, "Assign keys to actions")
        reaper.ImGui_Separator(State.ui.ctx)
        reaper.ImGui_Text(State.ui.ctx, "Tip: use TAB/Shift+TAB to navigate fields.")
        with_vars({{reaper.ImGui_StyleVar_ItemSpacing(), 10, 8}}, function()
        reaper.ImGui_Dummy(State.ui.ctx, 0, uiScale(5))
         if reaper.ImGui_IsWindowAppearing(State.ui.ctx) then
             State.mappings.feedback = nil
         end

        if reaper.ImGui_BeginTable(State.ui.ctx, "km_table", 4, reaper.ImGui_TableFlags_Borders() | reaper.ImGui_TableFlags_RowBg()) then
            reaper.ImGui_TableSetupColumn(State.ui.ctx, "Action", reaper.ImGui_TableColumnFlags_WidthFixed(), uiScale(170))
            reaper.ImGui_TableSetupColumn(State.ui.ctx, "Current", reaper.ImGui_TableColumnFlags_WidthFixed(), uiScale(90))
            reaper.ImGui_TableSetupColumn(State.ui.ctx, "Input", reaper.ImGui_TableColumnFlags_WidthFixed(), uiScale(90))
             reaper.ImGui_TableSetupColumn(State.ui.ctx, "Buttons", reaper.ImGui_TableColumnFlags_WidthStretch())
             reaper.ImGui_TableHeadersRow(State.ui.ctx)

            local function row(label, id, quick)
                reaper.ImGui_TableNextRow(State.ui.ctx)
                reaper.ImGui_TableSetColumnIndex(State.ui.ctx, 0)
                local fb = State.mappings.feedback
                local isErr = fb and fb.kind == "error"
                local isTarget = isErr and fb.target_id == id
                local isConflict = isErr and fb.conflict_id == id
                local highlight = isTarget or isConflict
                if highlight then
                    with_colors({{reaper.ImGui_Col_Text(), get_special_color("red_button")}}, function()
                        reaper.ImGui_Text(State.ui.ctx, label)
                    end)
                else
                    reaper.ImGui_Text(State.ui.ctx, label)
                end

                reaper.ImGui_TableSetColumnIndex(State.ui.ctx, 1)
                local cur = State.mappings.data[id]
                if id == 'setup_revert' then
                    -- Read-only map
                    local text = cur and getKeyName(cur) or 'K, L'
                    with_colors({{reaper.ImGui_Col_Text(), THEME_COLORS[reaper.ImGui_Col_TextDisabled()]}} , function()
                        reaper.ImGui_Text(State.ui.ctx, text)
                       
                    end)
                    -- Input:read-only
                    reaper.ImGui_TableSetColumnIndex(State.ui.ctx, 2)
                    with_colors({{reaper.ImGui_Col_Text(), THEME_COLORS[reaper.ImGui_Col_TextDisabled()]}} , function()
                        reaper.ImGui_Text(State.ui.ctx, "Read-only")
                       
                    end)
                    -- Buttons column
                    reaper.ImGui_TableSetColumnIndex(State.ui.ctx, 3)
                    with_colors({{reaper.ImGui_Col_Text(), THEME_COLORS[reaper.ImGui_Col_TextDisabled()]}} , function()
                        reaper.ImGui_Text(State.ui.ctx, "Fixed mapping")
                        
                    end)
                    return
                elseif id == 'select_trk' then
                    -- Read-only: show only default mapping
                    with_colors({{reaper.ImGui_Col_Text(), THEME_COLORS[reaper.ImGui_Col_TextDisabled()]}} , function()
                        reaper.ImGui_Text(State.ui.ctx, '1, 2, 3, 4, 5')
                        
                    end)
                    -- Input column: read-only 
                    reaper.ImGui_TableSetColumnIndex(State.ui.ctx, 2)
                    with_colors({{reaper.ImGui_Col_Text(), THEME_COLORS[reaper.ImGui_Col_TextDisabled()]}} , function()
                        reaper.ImGui_Text(State.ui.ctx, "Read-only")
                        if reaper.ImGui_IsItemHovered(State.ui.ctx) then
                            reaper.ImGui_BeginTooltip(State.ui.ctx)
                            reaper.ImGui_Text(State.ui.ctx, "Locked/Read-only")
                            reaper.ImGui_EndTooltip(State.ui.ctx)
                        end
                    end)
                    --  Buttons
                    reaper.ImGui_TableSetColumnIndex(State.ui.ctx, 3)
                    with_colors({{reaper.ImGui_Col_Text(), THEME_COLORS[reaper.ImGui_Col_TextDisabled()]}} , function()
                        reaper.ImGui_Text(State.ui.ctx, "Fixed mapping")
                        if reaper.ImGui_IsItemHovered(State.ui.ctx) then
                            reaper.ImGui_BeginTooltip(State.ui.ctx)
                            reaper.ImGui_Text(State.ui.ctx, "Locked/Read-only")
                            reaper.ImGui_EndTooltip(State.ui.ctx)
                        end
                    end)
                    return
                else
                    if isTarget then
                        with_colors({{reaper.ImGui_Col_Text(), get_special_color("red_button")}}, function()
                            reaper.ImGui_Text(State.ui.ctx, "Conflict")
                            if reaper.ImGui_IsItemHovered(State.ui.ctx) then
                                reaper.ImGui_BeginTooltip(State.ui.ctx)
                                reaper.ImGui_Text(State.ui.ctx, fb and fb.msg or "Conflict")
                                reaper.ImGui_EndTooltip(State.ui.ctx)
                            end
                        end)
                    elseif isConflict then
                        with_colors({{reaper.ImGui_Col_Text(), get_special_color("red_button")}}, function()
                            reaper.ImGui_Text(State.ui.ctx, getKeyName(cur))
                            if reaper.ImGui_IsItemHovered(State.ui.ctx) then
                                reaper.ImGui_BeginTooltip(State.ui.ctx)
                                reaper.ImGui_Text(State.ui.ctx, fb and fb.msg or "Conflict")
                                reaper.ImGui_EndTooltip(State.ui.ctx)
                            end
                        end)
                    else
                        reaper.ImGui_Text(State.ui.ctx, getKeyName(cur))
                    end
                end

                reaper.ImGui_TableSetColumnIndex(State.ui.ctx, 2)
                reaper.ImGui_SetNextItemWidth(State.ui.ctx, 90)
                local buf = tostring(State.mappings.manual_input[id] or "")
                local changed, newval = reaper.ImGui_InputText(State.ui.ctx, "##key_"..id, buf)
                if changed then State.mappings.manual_input[id] = newval end

                 reaper.ImGui_TableSetColumnIndex(State.ui.ctx, 3)
                 with_vars({{reaper.ImGui_StyleVar_FrameRounding(), UI_CONST.BUTTON_ROUNDING}} , function()
                 if reaper.ImGui_Button(State.ui.ctx, "Set##"..id, uiScale(50), uiScale(24)) then
                     local kc = parseKeyInput(State.mappings.manual_input[id])
                     if kc then
                   
                         setMapping(id, kc)
                     else
                         State.mappings.feedback = { msg = "Key not recognized. Try e.g. R, Space, F5.", ts = reaper.time_precise(), kind = "error" }
                     end
                 end
                 if quick then
                     for _,q in ipairs(quick) do
                         reaper.ImGui_SameLine(State.ui.ctx)
                         if reaper.ImGui_Button(State.ui.ctx, q.label.."##"..id..q.code, uiScale(40), uiScale(24)) then
                             setMapping(id, q.code)
                         end
                     end
                 end
                 reaper.ImGui_SameLine(State.ui.ctx)
                 if reaper.ImGui_Button(State.ui.ctx, "Learn##"..id, uiScale(60), uiScale(24)) then
                     State.mappings.learning = { id = id, ts = reaper.time_precise() }
                     State.mappings.feedback = { msg = "Press a key for "..label, ts = reaper.time_precise(), kind = "ok" }
                 end
                 local learningActive = State.mappings.learning and State.mappings.learning.id == id
                 if learningActive then
                     if not State.mappings._candidateKeys then
                         State.mappings._candidateKeys = {
                             reaper.ImGui_Key_A(), reaper.ImGui_Key_B(), reaper.ImGui_Key_C(), reaper.ImGui_Key_D(), reaper.ImGui_Key_E(), reaper.ImGui_Key_F(), reaper.ImGui_Key_G(),
                             reaper.ImGui_Key_H(), reaper.ImGui_Key_I(), reaper.ImGui_Key_J(), reaper.ImGui_Key_K(), reaper.ImGui_Key_L(), reaper.ImGui_Key_M(), reaper.ImGui_Key_N(),
                             reaper.ImGui_Key_O(), reaper.ImGui_Key_P(), reaper.ImGui_Key_Q(), reaper.ImGui_Key_R(), reaper.ImGui_Key_S(), reaper.ImGui_Key_T(), reaper.ImGui_Key_U(),
                             reaper.ImGui_Key_V(), reaper.ImGui_Key_W(), reaper.ImGui_Key_X(), reaper.ImGui_Key_Y(), reaper.ImGui_Key_Z(),
                             reaper.ImGui_Key_0(), reaper.ImGui_Key_1(), reaper.ImGui_Key_2(), reaper.ImGui_Key_3(), reaper.ImGui_Key_4(), reaper.ImGui_Key_5(), reaper.ImGui_Key_6(), reaper.ImGui_Key_7(), reaper.ImGui_Key_8(), reaper.ImGui_Key_9(),
                             reaper.ImGui_Key_Space(), reaper.ImGui_Key_Enter(), reaper.ImGui_Key_Tab(), reaper.ImGui_Key_Escape(), reaper.ImGui_Key_Backspace(), reaper.ImGui_Key_Delete(),
                             reaper.ImGui_Key_F1(), reaper.ImGui_Key_F2(), reaper.ImGui_Key_F3(), reaper.ImGui_Key_F4(), reaper.ImGui_Key_F5(), reaper.ImGui_Key_F6(), reaper.ImGui_Key_F7(), reaper.ImGui_Key_F8(), reaper.ImGui_Key_F9(), reaper.ImGui_Key_F10(), reaper.ImGui_Key_F11(), reaper.ImGui_Key_F12(),
                         }
                     end
                     for _, code in ipairs(State.mappings._candidateKeys) do
                         if reaper.ImGui_IsKeyPressed(State.ui.ctx, code) then
                             setMapping(id, code)
                             State.mappings.learning = nil
                         end
                     end
                     reaper.ImGui_SameLine(State.ui.ctx)
                     reaper.ImGui_Text(State.ui.ctx, "Press a key...")
                 end
                 reaper.ImGui_SameLine(State.ui.ctx)
                if reaper.ImGui_Button(State.ui.ctx, "Clear##"..id, uiScale(58), uiScale(24)) then
                    State.mappings.data[id] = nil
                    saveMappings()
                    State.mappings.feedback = { msg = "Removed mapping for "..label, ts = reaper.time_precise(), kind = "ok" }
                end
                end)

            end

            -- Category: Main Control
            reaper.ImGui_TableNextRow(State.ui.ctx)
            reaper.ImGui_TableSetColumnIndex(State.ui.ctx, 0)
            with_colors({{reaper.ImGui_Col_Text(), get_special_color("cyan_text")}} , function()
                reaper.ImGui_Text(State.ui.ctx, "MAIN CONTROL")
            end)
            reaper.ImGui_TableSetColumnIndex(State.ui.ctx, 1)
            reaper.ImGui_Text(State.ui.ctx, "")
            reaper.ImGui_TableSetColumnIndex(State.ui.ctx, 2)
            reaper.ImGui_Text(State.ui.ctx, "")
            reaper.ImGui_TableSetColumnIndex(State.ui.ctx, 3)
            reaper.ImGui_Text(State.ui.ctx, "")

            row("Setup/Revert Floopa",            "setup_revert")
            row("Play/Pause",                     "play_pause",   { {label="Space", code=reaper.ImGui_Key_Space()} })
            row("Record Toggle",                  "record_toggle",{ {label="R", code=reaper.ImGui_Key_R()} })
            row("Toggle Metronome",               "metronome",    { {label="T", code=reaper.ImGui_Key_T()} })
            row("Toggle Click Track",             "toggle_click", { {label="C", code=reaper.ImGui_Key_C()} })

            -- Category: Track Control
            reaper.ImGui_TableNextRow(State.ui.ctx)
            reaper.ImGui_TableSetColumnIndex(State.ui.ctx, 0)
            with_colors({{reaper.ImGui_Col_Text(), get_special_color("cyan_text")}} , function()
                reaper.ImGui_Text(State.ui.ctx, "TRACK CONTROL")
            end)
            reaper.ImGui_TableSetColumnIndex(State.ui.ctx, 1)
            reaper.ImGui_Text(State.ui.ctx, "")
            reaper.ImGui_TableSetColumnIndex(State.ui.ctx, 2)
            reaper.ImGui_Text(State.ui.ctx, "")
            reaper.ImGui_TableSetColumnIndex(State.ui.ctx, 3)
            reaper.ImGui_Text(State.ui.ctx, "")

            row("Select Track 1..5",              "select_trk")
            row("Mute Selected Track",            "mute_trk",     { {label="M", code=reaper.ImGui_Key_M()} })
            row("Effects Selected Track",         "fx_trk",       { {label="F", code=reaper.ImGui_Key_F()} })
            row("Reverse Selected Track",         "rev_trk",      { {label="S", code=reaper.ImGui_Key_S()} })
            row("Toggle Input (Audio/MIDI)",       "toggle_input", { {label="I", code=reaper.ImGui_Key_I()} })
            row("Transpose +12",                  "pitch_up",     { {label="Z", code=reaper.ImGui_Key_Z()} })
            row("Transpose -12",                  "pitch_down",   { {label="X", code=reaper.ImGui_Key_X()} })
            row("Undo All Lanes",                 "undo_all",     { {label="Del", code=reaper.ImGui_Key_Delete()} })
            row("Undo Lane",                       "undo_lane",    { {label="Backspace", code=reaper.ImGui_Key_Backspace()} })

             reaper.ImGui_EndTable(State.ui.ctx)
         end

         reaper.ImGui_Dummy(State.ui.ctx, 0, uiScale(8))
         if State.mappings.feedback then
             local msg = State.mappings.feedback.msg
             local kind = State.mappings.feedback.kind
             local color = (kind == "error") and get_special_color("status_error_text") or get_special_color("status_ok_text")
             with_colors({{reaper.ImGui_Col_Text(), color}} , function()
                 reaper.ImGui_Text(State.ui.ctx, msg)
             end)
         end

         reaper.ImGui_Dummy(State.ui.ctx, 0, uiScale(6))
         local window_width = reaper.ImGui_GetContentRegionAvail(State.ui.ctx)
        local button_width = uiScale(100)
        reaper.ImGui_SetCursorPosX(State.ui.ctx, (window_width - button_width) * 0.5)
         with_vars({{reaper.ImGui_StyleVar_FrameRounding(), UI_CONST.BUTTON_ROUNDING}} , function()
            if reaper.ImGui_Button(State.ui.ctx, "Close", button_width, uiScale(25)) then
                
                 State.mappings.modalOpen = false
                 reaper.ImGui_CloseCurrentPopup(State.ui.ctx)
             end
         end)
         end) 
         reaper.ImGui_EndPopup(State.ui.ctx)
        
     else
       
        State.mappings.modalOpen = false
     end
end


-- === MAIN CONTROL =================================
-- Top buttons, header, and transport controls
-- ===========================================================
-- Helper: open external script "Floopa MIDI Map.lua" as separate action
local function getThisScriptDir()
    local src = debug.getinfo(1, 'S').source or ''
    local path = src:sub(1,1) == '@' and src:sub(2) or src
    return path:match('^(.*)[\\/]') or ''
end

local function joinPath(base, leaf)
    local sep = package.config:sub(1,1)
    if base:sub(-1) == sep then return base .. leaf end
    return base .. sep .. leaf
end

local function findScriptCommandId(scriptPath)
    local kb = joinPath(reaper.GetResourcePath(), 'reaper-kb.ini')
    local f = io.open(kb, 'r')
    if not f then return nil end
    local cmd
    for line in f:lines() do
        if line:find('^SCR') then
            local lineNorm = line:gsub('\\','/'):lower()
            local pathNorm = scriptPath:gsub('\\','/'):lower()
            if lineNorm:find(pathNorm, 1, true) then
                -- Tokenize: SCR <section> <id> <path>
                local tokens = {}
                for t in line:gmatch('%S+') do tokens[#tokens+1] = t end
                local idtok = tokens[3]
                if idtok then
                    if idtok:sub(1,3) == '_RS' then
                        local named = reaper.NamedCommandLookup(idtok)
                        if named and named ~= 0 then cmd = named break end
                    else
                        local num = tonumber(idtok)
                        if num and num ~= 0 then cmd = num break end
                    end
                end
            end
        end
    end
    f:close()
    return cmd
end

local function findScriptCommandIdByFilename(filename)
    local kb = joinPath(reaper.GetResourcePath(), 'reaper-kb.ini')
    local f = io.open(kb, 'r')
    if not f then return nil end
    local cmd
    local nameLower = filename:lower()
    for line in f:lines() do
        if line:find('^SCR') then
            local lower = line:lower()
            if lower:find(nameLower, 1, true) then
                -- Prefer named command if present
                local idtok = line:match('^SCR%s+%d+%s+(_RS%w+)') or line:match('^SCR%s+%d+%s+(%d+)')
                if idtok then
                    if idtok:sub(1,3) == '_RS' then
                        local named = reaper.NamedCommandLookup(idtok)
                        if named and named ~= 0 then cmd = named break end
                    else
                        local num = tonumber(idtok)
                        if num and num ~= 0 then cmd = num break end
                    end
                end
            end
        end
    end
    f:close()
    return cmd
end

-- Lazy-loader  MIDI Map 
local MidiMapModule = nil
local function ensureMidiMapModule()
    if MidiMapModule then return true end
    local thisDir = getThisScriptDir()
    local modulePath = joinPath(thisDir, 'modules/midi-map.lua')
    local ok, modOrErr = pcall(function() return dofile(modulePath) end)
    if ok and type(modOrErr) == 'table' then
        MidiMapModule = modOrErr
        return true
    else
        reaper.ShowMessageBox('Cannot load MIDI Map module:\n'..tostring(modOrErr), 'Floopa Station', 0)
        return false
    end
end

local function openMidiMap()
    if ensureMidiMapModule() then
        reaper.ImGui_OpenPopup(State.ui.ctx, 'MIDI Map')
    end
end

local function drawMidiMapModal()
    if not MidiMapModule then return end
    local visible = reaper.ImGui_BeginPopupModal(State.ui.ctx, 'MIDI Map', true)
    if visible then
        State.mappings.modalOpen = true
        MidiMapModule.renderPanel(State.ui.ctx)
        reaper.ImGui_Separator(State.ui.ctx)
        if reaper.ImGui_Button(State.ui.ctx, 'Close', uiScale(120), uiScale(28)) then
            State.mappings.modalOpen = false
            reaper.ImGui_CloseCurrentPopup(State.ui.ctx)
        end
        reaper.ImGui_EndPopup(State.ui.ctx)
    else
        State.mappings.modalOpen = false
    end
end

renderMainControls = function()
    if not (State and State.ui and State.ui.ctx) then return end
    
    reaper.ImGui_Dummy(State.ui.ctx, 0, uiScale(2))

    
    local topH = uiScale(30)

    do
        local bw = uiScale(140)
        local spacing = rowSpacing()
        local total = bw * 5 + spacing * 4
        centerCursorForWidth(State.ui.ctx, total)
    end

    -- Setup Floopa
    with_vars({{reaper.ImGui_StyleVar_FrameRounding(), UI_CONST.BUTTON_ROUNDING}} , function()
        if reaper.ImGui_Button(State.ui.ctx, "Setup Floopa", uiScale(140), topH) then setupFloopa() end
    end)
    reaper.ImGui_SameLine(State.ui.ctx)

    -- Revert Default
    with_vars({{reaper.ImGui_StyleVar_FrameRounding(), UI_CONST.BUTTON_ROUNDING}} , function()
        if reaper.ImGui_Button(State.ui.ctx, "Revert Default", uiScale(140), topH) then 
            revertFloopa()
        end
    end)
    reaper.ImGui_SameLine(State.ui.ctx)

    -- Assign Keys and Help  Modals
    with_vars({{reaper.ImGui_StyleVar_FrameRounding(), UI_CONST.BUTTON_ROUNDING}} , function()
        if reaper.ImGui_Button(State.ui.ctx, "Assign Keys", uiScale(140), topH) then
            -- Immediately set the flag to block global shortcuts
            State.mappings.modalOpen = true
            reaper.ImGui_OpenPopup(State.ui.ctx, "Key Mapping")
        end
    end)
    reaper.ImGui_SameLine(State.ui.ctx)
    -- MIDI Map button
    with_vars({{reaper.ImGui_StyleVar_FrameRounding(), UI_CONST.BUTTON_ROUNDING}} , function()
        if reaper.ImGui_Button(State.ui.ctx, "MIDI Map", uiScale(140), topH) then
            State.mappings.modalOpen = true
            openMidiMap()
        end
    end)
    reaper.ImGui_SameLine(State.ui.ctx)
    with_vars({{reaper.ImGui_StyleVar_FrameRounding(), UI_CONST.BUTTON_ROUNDING}} , function()
        if reaper.ImGui_Button(State.ui.ctx, "Help", uiScale(140), topH) then
            reaper.ImGui_OpenPopup(State.ui.ctx, "Help") -- Open modal window
        end
    end)



    -- Header and Transport Controls
    reaper.ImGui_Dummy(State.ui.ctx, 0, uiScale(5))
    reaper.ImGui_SeparatorText(State.ui.ctx, "MAIN CONTROLS")
    do
        local formW = math.min(reaper.ImGui_GetContentRegionAvail(State.ui.ctx) or uiScale(820), uiScale(820))
        local formH = uiScale(240)
        centerCursorForWidth(State.ui.ctx, formW)
        if reaper.ImGui_BeginChild(State.ui.ctx, "MainControlsForm", formW, formH, 0) then
            drawTransportControls()
            reaper.ImGui_Dummy(State.ui.ctx, 0, uiScale(6))
            drawLoopProgressBarEnhanced()
            reaper.ImGui_EndChild(State.ui.ctx)
        end
    end

   
    with_vars({{reaper.ImGui_StyleVar_WindowPadding(), 20, 20}} , function()
     
        drawHelpModal()
        drawKeyMappingModal()
        drawMidiMapModal()
    end)

    
end

-- Override consumeMidiMapCommand after helpers are defined 
function consumeMidiMapCommand()
    if State.mappings and State.mappings.modalOpen then return end
    local tsStr = reaper.GetExtState(MIDI_NS, "command_ts")
    local cmdStr = reaper.GetExtState(MIDI_NS, "command")
    if tsStr and tsStr ~= "" then
        local ts = tonumber(tsStr) or 0
        if ts > midi_last_ts then
            midi_last_ts = ts
            if type(cmdStr) == 'string' and cmdStr ~= '' then
                local n = tonumber(cmdStr:match('^select_trk:(%d+)$'))
                if n and n >= 1 and n <= 5 then
                    selectTrack(n - 1)
                elseif cmdStr == 'record_toggle' then
                    local last = midi_last_cmd_ts[cmdStr] or 0
                    local cooldown = (MIDI_CMD_COOLDOWN and MIDI_CMD_COOLDOWN.record_toggle) or 1.0
                    if (ts - last) >= cooldown then
                        midi_last_cmd_ts[cmdStr] = ts
                        reaper.Main_OnCommand(1013, 0)
                    end
                elseif cmdStr == 'play_pause' then
                    toggleTransportPlayStop()
                elseif cmdStr == 'toggle_click' then
                    if toggleClickTrackPreservingSelection then
                        toggleClickTrackPreservingSelection()
                    else
                        reaper.Main_OnCommand(40364, 0)
                    end
                else
                    local selectedIndex = nil
                    for si = 0, 4 do
                        local tr = reaper.GetTrack(0, si)
                        if tr and reaper.IsTrackSelected(tr) then selectedIndex = si; break end
                    end
                    if selectedIndex ~= nil then
                        if cmdStr == 'undo_lane' then
                            reaper.SetOnlyTrackSelected(reaper.GetTrack(0, selectedIndex))
                            reaper.Main_OnCommand(42648, 0)
                        elseif cmdStr == 'undo_all' then
                            resetTrackToSingleEmptyLane(selectedIndex)
                        elseif cmdStr == 'fx_trk' then
                            reaper.SetOnlyTrackSelected(reaper.GetTrack(0, selectedIndex))
                            reaper.Main_OnCommand(40291, 0)
                        elseif cmdStr == 'rev_trk' then
                            toggleReverse(selectedIndex)
                        elseif cmdStr == 'pitch_up' then
                            changePitch(selectedIndex, 12)
                        elseif cmdStr == 'pitch_down' then
                            changePitch(selectedIndex, -12)
                        elseif cmdStr == 'mute_trk' then
                            toggleTrackMute(selectedIndex)
                        elseif cmdStr == 'toggle_input' then
                            toggleTrackInput(selectedIndex)
                        end
                    end
                end
                
                reaper.SetExtState(MIDI_NS, "command", "", false)
            end
        end
    end
end

-- Dedicated Beat Counter 
renderBeatCounter = function()
    if not (State and State.ui and State.ui.ctx) then return end
    reaper.ImGui_Dummy(State.ui.ctx, 0, uiScale(5))
    reaper.ImGui_SeparatorText(State.ui.ctx, "BEAT COUNTER")
    drawBeatCounterSection()
end

-- Helper animation border for track groups
local function updateTrackBorder(i, x, y, group_width, group_height, track, palette_override)
    if not (State and State.ui and State.ui.ctx) then return end
    local draw_list = reaper.ImGui_GetWindowDrawList(State.ui.ctx)
    local mx, my = reaper.ImGui_GetMousePos(State.ui.ctx)
    local hovered = (mx >= x and mx <= x + group_width and my >= y and my <= y + group_height)
    local mouse_down = reaper.ImGui_IsMouseDown(State.ui.ctx, 0)

    local palette = palette_override or (State.trackBorder.themes[State.trackBorder.theme] or State.trackBorder.themes.dark)
    local is_selected = false
    local armed = false
    local is_muted = false
    local is_playing = (reaper.GetPlayState() & 1) == 1
    if track then
        is_selected = reaper.IsTrackSelected(track)
        armed = (reaper.GetMediaTrackInfo_Value(track, "I_RECARM") == 1)
        is_muted = (reaper.GetMediaTrackInfo_Value(track, "B_MUTE") == 1)
    end

    local target_state
    if is_selected and armed then
        if is_muted then
            target_state = "muted"
        elseif is_playing then
            target_state = "play"
        else
            target_state = "selected"
        end
    else
        target_state = (hovered and mouse_down) and "active"
                     or (is_selected and "selected")
                     or (hovered and "hover")
                     or "normal"
    end

    State.trackBorder.anim[i] = State.trackBorder.anim[i] or { state = "normal", current = palette.normal }
    local anim = State.trackBorder.anim[i]
    if anim.state ~= target_state then
        anim.from = anim.current or palette.normal
        anim.to = palette[target_state] or palette.normal
        anim.start = reaper.time_precise()
        anim.state = target_state
    end

    local now = reaper.time_precise()
    local t = 0
    if anim.start then
        t = math.min(1.0, (now - anim.start) / (State.trackBorder.duration or 0.30))
    end
    local function easeInOutCubic(u)
        if u < 0.5 then return 4*u*u*u end
        return 1 - ((-2*u + 2)^3)/2
    end
    local u = easeInOutCubic(t)
    local function lerp(a, b, s) return (a or 0) + ((b or 0) - (a or 0)) * s end
    local r = lerp((anim.from or palette.normal)[1], (anim.to or palette.normal)[1], u)
    local g = lerp((anim.from or palette.normal)[2], (anim.to or palette.normal)[2], u)
    local b = lerp((anim.from or palette.normal)[3], (anim.to or palette.normal)[3], u)
    local a = lerp((anim.from or palette.normal)[4], (anim.to or palette.normal)[4], u)
    anim.current = {r, g, b, a}
    State.trackBorder.anim[i] = anim

    local border_color = reaper.ImGui_ColorConvertDouble4ToU32(r, g, b, a)
    reaper.ImGui_DrawList_AddRect(draw_list, x, y, x + group_width, y + group_height, border_color, 0, 0, 2.0)
end


local function updateTrackBorderAnim(i, palette)
    if not State.tracks then return end
    local rect = State.tracks.ui_rects and State.tracks.ui_rects[i]
    if not rect then return end
    updateTrackBorder(i, rect.x, rect.y, rect.w, rect.h, rect.track, palette)
end

-- Helper: track controls (Select/Input/Mute/Undo/FX/Reverse/Pitch)
local function renderTrackControls(i)
    local ctx = ensureCtx(); if not ctx then return end
    local group_width = UI_CONST.GROUP_W
    local track = reaper.GetTrack(0, i)

    local label_text = "Floopa " .. (i + 1)
    local text_width = reaper.ImGui_CalcTextSize(ctx, label_text)
    local text_padding = (group_width - text_width) / 2
    reaper.ImGui_Dummy(ctx, 0, UI_CONST.SPACING_SM)
    reaper.ImGui_SetCursorPosX(ctx, reaper.ImGui_GetCursorPosX(ctx) + text_padding)

    local ps = reaper.GetPlayState()
    local isRecording = ((ps & 4) == 4)
    local isSelected = track and (reaper.IsTrackSelected(track) or reaper.GetMediaTrackInfo_Value(track, "I_SELECTED") == 1) or false
    local isTrackArmed = track and (reaper.GetMediaTrackInfo_Value(track, "I_RECARM") == 1) or false
    local shouldHighlight = isRecording and isSelected and isTrackArmed
    local tx, ty = reaper.ImGui_GetCursorScreenPos(ctx)
    if shouldHighlight then
        local dl = reaper.ImGui_GetWindowDrawList(ctx)
        local th = reaper.ImGui_GetTextLineHeight(ctx)
        local pad_x = UI_CONST.LABEL_PAD_X
        local pad_y = UI_CONST.LABEL_PAD_Y
        local bg_col = get_special_color("track_highlight_bg")
        reaper.ImGui_DrawList_AddRectFilled(dl, tx - pad_x, ty - pad_y, tx + text_width + pad_x, ty + th + pad_y, bg_col, 4)
    end
    reaper.ImGui_Text(ctx, label_text)
    reaper.ImGui_Dummy(ctx, 0, UI_CONST.SPACING_SM)


    if reaper.ImGui_Button(ctx, "Select##select_" .. i, UI_CONST.BUTTON_W, UI_CONST.BUTTON_H) then
        selectTrack(i)
    end

    if track then
        local inputType = reaper.GetMediaTrackInfo_Value(track, "I_RECINPUT")
        local inputLabel = (inputType >= 4096) and "MIDI" or "Audio"
        if reaper.ImGui_Button(ctx, inputLabel .. "##input_" .. i, UI_CONST.BUTTON_W, UI_CONST.BUTTON_H) then
            toggleTrackInput(i)
        end

        local muteState = reaper.GetMediaTrackInfo_Value(track, "B_MUTE") == 1
        if reaper.ImGui_Button(ctx, (muteState and "Unmute" or "Mute") .. "##mute_" .. i, UI_CONST.BUTTON_W, UI_CONST.BUTTON_H) then
            toggleTrackMute(i)
        end

        if reaper.ImGui_Button(ctx, "Undo##undo_" .. i, UI_CONST.SMALL_BUTTON_W, UI_CONST.SMALL_BUTTON_H) then
            reaper.SetOnlyTrackSelected(reaper.GetTrack(0, i))
            reaper.Main_OnCommand(42648, 0)
        end
        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_Button(ctx, "Undo All##undoall_" .. i, UI_CONST.SMALL_BUTTON_W, UI_CONST.SMALL_BUTTON_H) then
            resetTrackToSingleEmptyLane(i)
        end

        if reaper.ImGui_Button(ctx, "FX##fx_" .. i, UI_CONST.BUTTON_W, UI_CONST.BUTTON_H) then
            reaper.SetOnlyTrackSelected(reaper.GetTrack(0, i))
            reaper.Main_OnCommand(40291, 0)
        end

        if reaper.ImGui_Button(ctx, "Reverse##reverse_" .. i, UI_CONST.BUTTON_W, UI_CONST.BUTTON_H) then
            toggleReverse(i)
        end

        if reaper.ImGui_Button(ctx, "+12##plus12_" .. i, UI_CONST.SMALL_BUTTON_W, UI_CONST.SMALL_BUTTON_H) then
            changePitch(i, 12)
        end
        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_Button(ctx, "-12##minus12_" .. i, UI_CONST.SMALL_BUTTON_W, UI_CONST.SMALL_BUTTON_H) then
            changePitch(i, -12)
        end
    end
end

-- Helper: slider volumes
local function renderVolumeSlider(i)
    local ctx = ensureCtx(); if not ctx then return end
    local group_width = UI_CONST.GROUP_W
    local track = reaper.GetTrack(0, i)
    reaper.ImGui_Dummy(ctx, 0, UI_CONST.SPACING_SM)
    local text_width_v = reaper.ImGui_CalcTextSize(ctx, "Volume")
    local text_padding_v = (group_width - text_width_v) / 2
    reaper.ImGui_SetCursorPosX(ctx, reaper.ImGui_GetCursorPosX(ctx) + text_padding_v)
    reaper.ImGui_Text(ctx, "Volume")

    local slider_width = UI_CONST.SLIDER_W
    local slider_padding = (group_width - slider_width) / 2
    reaper.ImGui_SetCursorPosX(ctx, reaper.ImGui_GetCursorPosX(ctx) + slider_padding)

    with_vars({{reaper.ImGui_StyleVar_FrameRounding(), UI_CONST.BUTTON_ROUNDING}}, function()
        local v = State.tracks.volumes[i] or 1.0
        if v <= 0 or v ~= v then v = 1e-6 end
        local volume_db = 20 * math.log(v) / math.log(10)
        local volume_db_text = string.format("%.2f dB", volume_db)

        local changed, new_volume = reaper.ImGui_VSliderDouble(ctx, "##" .. i, slider_width, UI_CONST.SLIDER_H, State.tracks.volumes[i] or 1.0, 0.0, 2.0, volume_db_text)

        local isHovered = reaper.ImGui_IsItemHovered(ctx)
        local isActive  = reaper.ImGui_IsItemActive(ctx)

        if changed then
            new_volume = math.max(0.0, math.min(2.0, math.floor(new_volume / 0.01 + 0.5) * 0.01))
            State.tracks.volumes[i] = new_volume
            if track then reaper.SetMediaTrackInfo_Value(track, "D_VOL", new_volume) end
        else
            if track then
                local trackVol = reaper.GetMediaTrackInfo_Value(track, "D_VOL") or 1.0
                if not isActive and not isHovered then
                    if math.abs((State.tracks.volumes[i] or 1.0) - trackVol) > 1e-6 then
                        State.tracks.volumes[i] = trackVol
                    end
                end
            end
        end

        if reaper.ImGui_IsMouseClicked and (isHovered or isActive) and reaper.ImGui_IsMouseClicked(ctx, 1) then
            local reset = 1.0
            State.tracks.volumes[i] = reset
            if track then reaper.SetMediaTrackInfo_Value(track, "D_VOL", reset) end
            statusSet(string.format("Track %d volume reset to 0 dB", i + 1), "info", 1.5)
        end
    end)
end



-- === TRACKS GROUP=======================================
-- Track controls: mute, FX, reverse, input type, and pitch
-- ===========================================================
local function renderTracks()
    local ctx = ensureCtx(); if not ctx then return end
   
    reaper.ImGui_Dummy(State.ui.ctx, 0, uiScale(5))
    reaper.ImGui_SeparatorText(State.ui.ctx, "FLOOPA TRACKS")

    
    do
        local selectedIndex = nil
        for si = 0, 4 do
            local tr = reaper.GetTrack(0, si)
            if tr and reaper.IsTrackSelected(tr) then selectedIndex = si break end
        end
        if selectedIndex ~= nil then
            local tr = reaper.GetTrack(0, selectedIndex)
            if tr then
                local inputType = reaper.GetMediaTrackInfo_Value(tr, "I_RECINPUT")
                local inputLabel = (inputType >= 4096) and "MIDI" or "Audio"
                reaper.ImGui_PushStyleColor(State.ui.ctx, reaper.ImGui_Col_Text(), get_special_color("cyan_text"))
                reaper.ImGui_Text(State.ui.ctx, string.format("Selected: Floopa %d — Input: %s", selectedIndex + 1, inputLabel))
                reaper.ImGui_PopStyleColor(State.ui.ctx)
                
            end
        else
            
            with_colors({{reaper.ImGui_Col_Text(), get_special_color("muted_text")}}, function()
                reaper.ImGui_Text(State.ui.ctx, "No track selected")
            end)
        end
    end

    -- Controls for the first 5 Floopa tracks (centered)
    do
        local spacing = rowSpacing()
        local totalW = UI_CONST.GROUP_W * 5 + spacing * 4
        centerCursorForWidth(ctx, totalW)
    end
    -- Controls for the first 5 Floopa tracks
    for i = 0, 4 do
        local x, y = reaper.ImGui_GetCursorScreenPos(ctx)
        reaper.ImGui_BeginGroup(ctx)

        local group_width = UI_CONST.GROUP_W
        local track = reaper.GetTrack(0, i)
       
        renderTrackControls(i)
        renderVolumeSlider(i)

        reaper.ImGui_Dummy(ctx, 0, UI_CONST.SPACING_SM)
        reaper.ImGui_EndGroup(ctx)

        local _, y2 = reaper.ImGui_GetCursorScreenPos(ctx)
        local group_height = y2 - y

        State.tracks.ui_rects = State.tracks.ui_rects or {}
        State.tracks.ui_rects[i] = { x = x, y = y, w = group_width, h = group_height, track = track }
        updateTrackBorderAnim(i, (State.trackBorder and State.trackBorder.themes and State.trackBorder.themes[State.trackBorder.theme]) or nil)
        if i < 4 then
            reaper.ImGui_SameLine(ctx)
        end
    end
end

local function myWindow()
    local fs = uiScale(13)
    if fs < 11 then fs = 11 end
    PushFontCompat(State.ui.ctx, State.ui.sans_serif, fs)
    -- Update track volumes 
    update_track_volumes_throttled()
    
    -- Render main controls section
    renderMainControls()


  
  renderTracks()


 reaper.ImGui_Dummy(State.ui.ctx, 0, uiScale(30))


    renderStatusBar()

    reaper.ImGui_PopFont(State.ui.ctx)


end


-- === MAIN WINDOW & LOOP ===================================
-- Window creation, theme management, modals, and main loop
-- ===========================================================
local function loop()
    local color_count, style_var_count = applyTheme() 

    reaper.ImGui_SetNextWindowSize(State.ui.ctx, 870, 870, reaper.ImGui_Cond_FirstUseEver())

    local MIN_W, MIN_H = 700, 620
    if State.ui and State.ui.last_w and State.ui.last_h then
        if State.ui.last_w < MIN_W or State.ui.last_h < MIN_H then
            reaper.ImGui_SetNextWindowSize(State.ui.ctx, MIN_W, MIN_H, reaper.ImGui_Cond_Always())
        end
    end

    -- Window flags 
    local window_flags = 
        reaper.ImGui_WindowFlags_NoCollapse() 
        | reaper.ImGui_WindowFlags_NoScrollbar() 

    

    -- Create window
    local visible, open = reaper.ImGui_Begin(State.ui.ctx, "Floopa-Station", true, window_flags)

    if visible then
        local winW, winH = reaper.ImGui_GetWindowSize(State.ui.ctx)
        local baseW, baseH = 870, 870
        if winW and winH then
            local sW = winW / baseW
            local sH = winH / baseH
            local s = sW
            if sH < s then s = sH end
            local minScale = math.max(MIN_W / baseW, MIN_H / baseH)
            if s < minScale then s = minScale end
            if s > 2.0 then s = 2.0 end
            State.ui.scale = s
            State.ui.last_w, State.ui.last_h = winW, winH
            UI_CONST.GROUP_W = uiScale(160)
            UI_CONST.BUTTON_W = uiScale(160)
            UI_CONST.BUTTON_H = uiScale(30)
            UI_CONST.SMALL_BUTTON_W = uiScale(75)
            UI_CONST.SMALL_BUTTON_H = uiScale(30)
            UI_CONST.SLIDER_W = uiScale(60)
            UI_CONST.SLIDER_H = uiScale(150)
            UI_CONST.SPACING_XS = uiScale(5)
            UI_CONST.SPACING_SM = uiScale(10)
            UI_CONST.SPACING_MD = uiScale(15)
            UI_CONST.LABEL_PAD_X = uiScale(6)
            UI_CONST.LABEL_PAD_Y = uiScale(2)
            UI_CONST.BUTTON_ROUNDING = uiScale(5)
        end
        -- Keep track colors aligned with REAPER selection even when clicking outside the script
        if syncFloopaTrackColorsWithSelection then syncFloopaTrackColorsWithSelection() end
        
        -- Hint
        if reaper.ImGui_IsWindowAppearing(State.ui.ctx) and reaper.ImGui_SetWindowFocus then
            reaper.ImGui_SetWindowFocus(State.ui.ctx)
        end
        
        local mappingModalOpen = State.mappings and State.mappings.modalOpen
        -- Consume external commands from MIDI Map 
        consumeMidiMapCommand()
        if not mappingModalOpen and not State.mappings.data.setup_revert then
            if keyPressedOnce(reaper.ImGui_Key_K()) then setupFloopa() end
            if keyPressedOnce(reaper.ImGui_Key_L()) then revertFloopa() end
        end
        
        if not mappingModalOpen then
            local selectKeys = { reaper.ImGui_Key_1(), reaper.ImGui_Key_2(), reaper.ImGui_Key_3(), reaper.ImGui_Key_4(), reaper.ImGui_Key_5() }
            for idx = 0, 4 do
                if keyPressedOnce(selectKeys[idx + 1]) then
                    selectTrack(idx)
                    break
                end
            end
        end

        if not mappingModalOpen then
        for aid, kc in pairs(State.mappings.data) do
            
            if aid == 'select_trk' then goto continue_mapping_loop end
            local tag = 'mapping_' .. tostring(aid)
                local function handlePress(pressedKey)
                    if aid == 'rec' or aid == 'record_toggle' then
                        reaper.Main_OnCommand(1013, 0)
                    elseif aid == 'stop' or aid == 'play_pause' then
                        toggleTransportPlayStop()
                    elseif aid == 'metronome' then
                        reaper.Main_OnCommand(40364, 0)
                    elseif aid == 'toggle_click' then
                        if toggleClickTrackPreservingSelection then
                            toggleClickTrackPreservingSelection()
                        else
                            notifyInfo("Click Track action not available (initializing)", 2.0)
                        end
                elseif aid == 'setup_revert' then
                    if pressedKey == reaper.ImGui_Key_K() then
                        setupFloopa()
                    elseif pressedKey == reaper.ImGui_Key_L() then
                        revertFloopa()
                    end
                elseif aid == 'select_trk' then
                    local keyToIndex = {
                        [reaper.ImGui_Key_1()] = 0, [reaper.ImGui_Key_6()] = 0,
                        [reaper.ImGui_Key_2()] = 1, [reaper.ImGui_Key_7()] = 1,
                        [reaper.ImGui_Key_3()] = 2, [reaper.ImGui_Key_8()] = 2,
                        [reaper.ImGui_Key_4()] = 3, [reaper.ImGui_Key_9()] = 3,
                        [reaper.ImGui_Key_5()] = 4, [reaper.ImGui_Key_0()] = 4,
                    }
                    local idx = keyToIndex[pressedKey]
                    if idx ~= nil then selectTrack(idx) end
                else
                    -- Actions that operate on currently selected Floopa track
                    local selectedIndex = nil
                    for si = 0, 4 do
                        local tr = reaper.GetTrack(0, si)
                        if tr and reaper.IsTrackSelected(tr) then selectedIndex = si break end
                    end
                    if selectedIndex ~= nil then
                        if aid == 'undo_lane' then
                            reaper.SetOnlyTrackSelected(reaper.GetTrack(0, selectedIndex))
                            reaper.Main_OnCommand(42648, 0)
                        elseif aid == 'undo_all' then
                            resetTrackToSingleEmptyLane(selectedIndex)
                        elseif aid == 'fx_trk' then
                            reaper.SetOnlyTrackSelected(reaper.GetTrack(0, selectedIndex))
                            reaper.Main_OnCommand(40291, 0)
                        elseif aid == 'rev_trk' then
                            toggleReverse(selectedIndex)
                        elseif aid == 'pitch_up' then
                            changePitch(selectedIndex, 12)
                        elseif aid == 'pitch_down' then
                            changePitch(selectedIndex, -12)
                        elseif aid == 'mute_trk' then
                            toggleTrackMute(selectedIndex)
                        elseif aid == 'toggle_input' then
                            toggleTrackInput(selectedIndex)
                        end
                    end
                end
            end

            local function normalizedKey(k)
                if type(k) == 'number' and k >= 32 and k <= 126 then
                    local converted = keyFromAscii(k)
                    if converted then return converted end
                    return nil
                end
                return k
            end

            if type(kc) == 'table' then
                for _, k in ipairs(kc) do
                    local nk = normalizedKey(k)
                    if nk and keyPressedOnceTagged(nk, tag) then
                        handlePress(nk)
                        break
                    end
                end
            else
                local nkc = normalizedKey(kc)
                if nkc and keyPressedOnceTagged(nkc, tag) then
                    handlePress(nkc)
                end
            end
            ::continue_mapping_loop::
        end
        end

       
        
        updateStatusHUD()
        myWindow()

        -- Auto Loop Length polling (record start/stop detection and quantization)
        autoLoopPoll()

        

        reaper.ImGui_End(State.ui.ctx)
    end

   
    end_theme(color_count, style_var_count) 


    if open then
        
        State.transport.prevPlayState = reaper.GetPlayState()
        reaper.defer(loop)
    else
        if MidiMapModule and MidiMapModule.disable then
            MidiMapModule.disable()
        end
        revertFloopa()
        
        if reaper.ImGui_DestroyContext and State and State.ui and State.ui.ctx then
            reaper.ImGui_DestroyContext(State.ui.ctx)
            State.ui.ctx = nil
        end
    end
end

-- Restore user metronome settings automatically if script exits while Count-In is ON
if reaper and reaper.atexit then
    reaper.atexit(function()
        revertFloopa()
    end)
end


-- Bootstrap side-effects 
bootstrapOnce()
sanityCheckOnStartup()
if not _G.__FLOOPA_NO_GUI__ then
    reaper.defer(loop)  -- Start the GUI
else
    if reaper and reaper.ShowConsoleMsg then reaper.ShowConsoleMsg('[Main] GUI disabled (__FLOOPA_NO_GUI__=true)\n') end
end

-- Helper: get GUIDs of currently selected tracks
function getSelectedTrackGUIDs()
    local guids = {}
    local numTracks = reaper.CountTracks(0)
    for i = 0, numTracks - 1 do
        local tr = reaper.GetTrack(0, i)
        if tr and reaper.IsTrackSelected(tr) then
            table.insert(guids, reaper.GetTrackGUID(tr))
        end
    end
    return guids
end

-- Helper: restore selection from GUIDs
local function restoreSelectionByGUIDs(guids)
    local map = {}
    for _, g in ipairs(guids or {}) do map[g] = true end
    
    reaper.Main_OnCommand(40297, 0)
    local numTracks = reaper.CountTracks(0)
    for i = 0, numTracks - 1 do
        local tr = reaper.GetTrack(0, i)
        if tr and map[reaper.GetTrackGUID(tr)] then
            reaper.SetTrackSelected(tr, true)
        end
    end
end

-- Toggle Click Track
function toggleClickTrackPreservingSelection()
    local prevSel = getSelectedTrackGUIDs() 
    local start_t, end_t = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
    local hasLoop = (start_t and end_t and (end_t > start_t))
    local playstate_before = reaper.GetPlayState()
    reaper.Undo_BeginBlock()
    reaper.PreventUIRefresh(1)
    
    local function findClickTrack()
        local numTracks = reaper.CountTracks(0)
        for i = 0, numTracks - 1 do
            local t = reaper.GetTrack(0, i)
            local ok, name = reaper.GetSetMediaTrackInfo_String(t, "P_NAME", "", false)
            if ok and name then
                local n = tostring(name):gsub("^%s+", ""):gsub("%s+$", ""):lower()
                if n == "floopa click track" or n == "click track" then return t, i end
            end
        end
        return nil, nil
    end
    local clickTrack, clickIndex = findClickTrack()
    if clickTrack then
        
        reaper.DeleteTrack(clickTrack)
    else
        
        local flist = getFloopaTracks()
        local insertIndex = 5 
        if #flist > 0 then
            
            local maxIdx1 = 0
            for _, e in ipairs(flist) do
                local idx1 = reaper.GetMediaTrackInfo_Value(e.track, "IP_TRACKNUMBER") -- 1-based
                if idx1 and idx1 > maxIdx1 then maxIdx1 = idx1 end
            end
            insertIndex = math.max(0, (maxIdx1 or 1) - 1) + 1 -- zero-based + 1 to place after
        end
        -- Insert the new track. If insertIndex is greater than the current track count,
        
        reaper.InsertTrackAtIndex(insertIndex, true)
        local total = reaper.CountTracks(0)
        local idx = math.min(insertIndex, math.max(0, total - 1))
        local newTrack = reaper.GetTrack(0, idx)
        if newTrack then
          
            reaper.GetSetMediaTrackInfo_String(newTrack, "P_NAME", "Floopa Click Track", true)
            local col = (reaper.ColorToNative(186, 60, 229) | 0x1000000)
            reaper.SetTrackColor(newTrack, col)          
            reaper.SetMediaTrackInfo_Value(newTrack, "I_RECARM", 0)          
            reaper.SetMediaTrackInfo_Value(newTrack, "B_AUTO_RECARM", 0)           
            reaper.SetOnlyTrackSelected(newTrack)
            reaper.Main_OnCommand(40013, 0) 
        end
    end
   
    restoreSelectionByGUIDs(prevSel)
   
    if hasLoop then
        local isPlaying = ((playstate_before & 1) == 1) or ((playstate_before & 4) == 4)
        if not isPlaying then
            reaper.SetEditCurPos(start_t or 0, false, false)
        end
    end
    reaper.PreventUIRefresh(-1)
    reaper.Undo_EndBlock("Toggle Click Track (preserve selection, arm off, set color/name)", -1)
end
