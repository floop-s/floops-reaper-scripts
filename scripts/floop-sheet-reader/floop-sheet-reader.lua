-- Floop Sheet Reader - PDF and Image Viewer
-- @description Floop Sheet Reader: load and view PDF and image files.
-- @version 2.2.1
-- @author Floop-s
-- @license GPL-3.0
-- @changelog
--   - Update Poppler Windows binary download link and SHA256 verification hash.
-- @about
--   Windows-only script.
--
--   # Sheet Reader v2.0
--   © 2025 2026 Floop-s
--
--   Load and view PDF and image files directly inside Reaper.
--   Uses Poppler for PDF-to-image conversion.
--   First, the script checks if "pdftoppm" is installed. If not, it prompts the user  
--   to install Poppler automatically. Poppler is downloaded from the official release  
--   page and extracted to the Reaper resource folder:  
--   https://github.com/oschwartz10612/poppler-windows/releases/download/v26.02.0-0/Release-26.02.0-0.zip
--   Once installed, the script converts PDF pages into images and displays them in the GUI.  
--
--    Requires:
--     reapack.com/repos/cfillion/reaimgui/ReaImGui_*.ext >= 0.10.2
--     reapack.com/repos/reapack/sws/SWS_*.ext
--    keywords: sheet, pdf, image, viewer, score, music
-- @provides
--   [main] floop-sheet-reader.lua

local reaper = reaper

--windows only script check
local os_name = reaper.GetOS()
if not os_name:match("Win") then
  reaper.MB(
    "This script is supported on Windows only.",
    "Unsupported Operating System",
    0
  )
  return
end


local function have_reaimGui()
    return reaper.APIExists and reaper.APIExists('ImGui_CreateContext')
end

local function have_sws()
    return reaper.APIExists and (reaper.APIExists('CF_ShellExecute') or reaper.APIExists('BR_Win32_ShellExecute'))
end

if not have_reaimGui() or not have_sws() then
    local missing = {}
    if not have_reaimGui() then missing[#missing + 1] = 'ReaImGui' end
    if not have_sws() then missing[#missing + 1] = 'SWS' end
    local msg = 'ReaImGui: ReaScript binding for Dear ImGui and SWS/S&M extensions are required.\n' .. table.concat(missing, ', ') .. '\nInstall them and try again.'
    reaper.ShowMessageBox(msg, 'Missing Dependencies', 0)
    return
end

local ctx = reaper.ImGui_CreateContext('PDF Viewer')

-- ui configuration
local ui_config = {
    window_width = 900,
    window_height = 800,
    zoom_level = 1.0,
    zoom_max = 5.0,
    fit_width = true,
    btn_spacing = 8,
    btn_height = 0,
    rounding_frame = 10,
    rounding_window = 8,
    frame_padding_x = 6,
    frame_padding_y = 6,
    window_padding_x = 10,
    window_padding_y = 10,
}
local sans_serif = reaper.ImGui_CreateFont("sans-serif", 13)
reaper.ImGui_Attach(ctx, sans_serif)

local last_pdf_dir = ""
local last_img_dir = ""

local function load_saved_dirs()
    if reaper.HasExtState("FloopSheetReader", "LastPdfDir") then
        last_pdf_dir = reaper.GetExtState("FloopSheetReader", "LastPdfDir")
    end
    if reaper.HasExtState("FloopSheetReader", "LastImgDir") then
        last_img_dir = reaper.GetExtState("FloopSheetReader", "LastImgDir")
    end
end
load_saved_dirs()

local function get_parent_dir(p)
    if not p or p == '' then return '' end
    local dir = p:match("^(.*)[\\/][^\\/]+$")
    return dir or ''
end

local function save_last_dir(key, path)
    if not path or path == "" then return end
    local dir = get_parent_dir(path)
    if dir and dir ~= "" then
        local dir_with_slash = dir .. "\\"
        reaper.SetExtState("FloopSheetReader", key, dir_with_slash, true)
        if key == "LastPdfDir" then last_pdf_dir = dir_with_slash
        elseif key == "LastImgDir" then last_img_dir = dir_with_slash end
    end
end

local function join_path(a, b)
    local sep = package.config and package.config:sub(1,1) or '\\'
    if sep ~= '\\' then sep = '\\' end
    if a:sub(-1) == '/' or a:sub(-1) == '\\' then
        return a .. b
    else
        return a .. sep .. b
    end
end

local function sanitize_name(name)
    name = name:gsub("^%s+", "")
    name = name:gsub("%s+$", "")
    name = name:gsub("[<>:\"/\\|%?%*]", "_")
    return name
end

local function get_pdf_output_dir(path)
    local base = join_path(reaper.GetResourcePath(), 'pdf_images')
    local fname = path:match("([^\\/]+)$") or 'pdf'
    local name = sanitize_name(fname:gsub("%.[Pp][Dd][Ff]$", ""))
    return join_path(base, name)
end

local THEME_COLORS = {
    [reaper.ImGui_Col_WindowBg()] = 0x1E2328FF,
    [reaper.ImGui_Col_PopupBg()] = 0x1E2328FF,
    [reaper.ImGui_Col_TitleBg()] = 0x20252BFF,
    [reaper.ImGui_Col_TitleBgActive()] = 0x1E2328FF,
    [reaper.ImGui_Col_Button()] = 0xFFFF00FF,
    [reaper.ImGui_Col_ButtonHovered()] = 0xFFFF99FF,
    [reaper.ImGui_Col_ButtonActive()] = 0xCCAA00FF,
    [reaper.ImGui_Col_Text()] = 0xFFFF00FF,
    [reaper.ImGui_Col_Separator()] = 0xCCAA00FF,
    [reaper.ImGui_Col_ResizeGrip()] = 0xF4F360FF,
    [reaper.ImGui_Col_ResizeGripHovered()] = 0xEAF016FF,
    [reaper.ImGui_Col_ResizeGripActive()] = 0xE6DF30FF,
}

local PALETTE = {
    primary = 0xFFFF00FF,
    primaryHover = 0xFFFF99FF,
    primaryActive = 0xCCAA00FF,
    text = 0x000000FF,
    textAlt = 0xFFFF99FF,
    statusOk = 0xFFFF99FF,
    statusError = 0xD94E14FF,
    popupBg = 0x1E2328FF,
    titleBg = 0x1E2328FF,
    titleBgActive = 0x1E2328FF,
    checkMark = 0x000000FF,
    separator = 0xFFFF00FF,
}

local STYLE = {
    clusterSpacing = 20,
    rightMargin = 20,
    buttonW = 30,
}

local Theme = {}
local STYLE_COUNTER = { color = 0, var = 0 }

function Theme.pushButtonPrimary()
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), PALETTE.text)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), PALETTE.primary)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), PALETTE.primaryHover)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), PALETTE.primaryActive)
    STYLE_COUNTER.color = STYLE_COUNTER.color + 4
end

function Theme.popButtonPrimary()
    local n = 4
    local k = STYLE_COUNTER.color or 0
    if k > 0 then
        local pop_n = math.min(n, k)
        reaper.ImGui_PopStyleColor(ctx, pop_n)
        STYLE_COUNTER.color = k - pop_n
    end
end

function Theme.pushButtonDisabled()
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), PALETTE.primaryActive)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), PALETTE.primaryActive)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), PALETTE.primaryActive)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), PALETTE.primaryActive)
    STYLE_COUNTER.color = STYLE_COUNTER.color + 4
end

function Theme.popButtonDisabled()
    local n = 4
    local k = STYLE_COUNTER.color or 0
    if k > 0 then
        local pop_n = math.min(n, k)
        reaper.ImGui_PopStyleColor(ctx, pop_n)
        STYLE_COUNTER.color = k - pop_n
    end
end

function Theme.pushCheckboxPrimary()
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(), PALETTE.primary)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBgHovered(), PALETTE.primaryHover)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBgActive(), PALETTE.primaryActive)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_CheckMark(), PALETTE.checkMark)
    STYLE_COUNTER.color = STYLE_COUNTER.color + 4
end

function Theme.popCheckboxPrimary()
    local n = 4
    local k = STYLE_COUNTER.color or 0
    if k > 0 then
        local pop_n = math.min(n, k)
        reaper.ImGui_PopStyleColor(ctx, pop_n)
        STYLE_COUNTER.color = k - pop_n
    end
end

function Theme.pushInputPrimary()
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(), PALETTE.primaryActive)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), PALETTE.text)
    STYLE_COUNTER.color = STYLE_COUNTER.color + 2
end

function Theme.popInputPrimary()
    local n = 2
    local k = STYLE_COUNTER.color or 0
    if k > 0 then
        local pop_n = math.min(n, k)
        reaper.ImGui_PopStyleColor(ctx, pop_n)
        STYLE_COUNTER.color = k - pop_n
    end
end

function Theme.pushProgressPrimary()
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(), PALETTE.primary)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_PlotHistogram(), PALETTE.primaryActive)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), PALETTE.text)
    STYLE_COUNTER.color = STYLE_COUNTER.color + 3
end

function Theme.popProgressPrimary()
    local n = 3
    local k = STYLE_COUNTER.color or 0
    if k > 0 then
        local pop_n = math.min(n, k)
        reaper.ImGui_PopStyleColor(ctx, pop_n)
        STYLE_COUNTER.color = k - pop_n
    end
end

function Theme.pushItemSpacing(x, y)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ItemSpacing(), x, y)
    STYLE_COUNTER.var = STYLE_COUNTER.var + 1
end

function Theme.popItemSpacing()
    local k = STYLE_COUNTER.var or 0
    if k > 0 then
        reaper.ImGui_PopStyleVar(ctx)
        STYLE_COUNTER.var = k - 1
    end
end

function Theme.pushTextAlt()
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), PALETTE.textAlt)
    STYLE_COUNTER.color = STYLE_COUNTER.color + 1
end


function Theme.popText()
    local k = STYLE_COUNTER.color or 0
    if k > 0 then
        reaper.ImGui_PopStyleColor(ctx)
        STYLE_COUNTER.color = k - 1
    end
end

function Theme.pushSeparator()
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Separator(), PALETTE.separator)
    STYLE_COUNTER.color = STYLE_COUNTER.color + 1
end

function Theme.popSeparator()
    local k = STYLE_COUNTER.color or 0
    if k > 0 then
        reaper.ImGui_PopStyleColor(ctx)
        STYLE_COUNTER.color = k - 1
    end
end

function Theme.pushModal()
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_PopupBg(), PALETTE.popupBg)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_TitleBg(), PALETTE.titleBg)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_TitleBgActive(), PALETTE.titleBgActive)
    STYLE_COUNTER.color = STYLE_COUNTER.color + 3
end

function Theme.popModal()
    reaper.ImGui_PopStyleColor(ctx, 3)
    STYLE_COUNTER.color = math.max(0, STYLE_COUNTER.color - 3)
end

-- function to apply theme
local function applyTheme()
    local style_count = 0
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameRounding(), ui_config.rounding_frame); style_count = style_count + 1
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowRounding(), ui_config.rounding_window); style_count = style_count + 1
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowPadding(), ui_config.window_padding_x, ui_config.window_padding_y); style_count = style_count + 1
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FramePadding(), ui_config.frame_padding_x, ui_config.frame_padding_y); style_count = style_count + 1
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ItemSpacing(), ui_config.btn_spacing, ui_config.btn_spacing); style_count = style_count + 1
    local color_count = 0
    for id, val in pairs(THEME_COLORS) do
        reaper.ImGui_PushStyleColor(ctx, id, val)
        color_count = color_count + 1
    end
    return color_count, style_count
end

-- path and variables to store data
local pdf_path = ''
local images = {}
local textures = {}
local current_page = 1
local total_pages = 0
local all_page_paths = {}
local status_message = 'Status: all systems are ready'
local status_is_error = false
local open_about = false

-- helper to safely quote command-line arguments
local function quote_arg(s)
    s = tostring(s or "")
    s = s:gsub('"', '""')
    return '"' .. s .. '"'
end

local function ps_quote(s)
    s = tostring(s or '')
    s = s:gsub("'", "''")
    return "'" .. s .. "'"
end
local function log(msg) end

local function file_exists(path)
    local f = io.open(path, 'rb')
    if f then f:close() return true end
    return false
end

local function get_file_size(path)
    local f = io.open(path, 'rb')
    if not f then return 0 end
    local size = f:seek('end')
    f:close()
    return size or 0
end

local function has_allowed_extension(path, exts)
    local lower = tostring(path or ''):lower()
    for _, ext in ipairs(exts) do
        if lower:sub(-#ext) == ext then return true end
    end
    return false
end

local function is_valid_pdf(path)
    return file_exists(path) and has_allowed_extension(path, {'.pdf'})
end

local function is_valid_image(path)
    return file_exists(path) and has_allowed_extension(path, {'.png', '.jpg', '.jpeg'})
end

local function is_valid_pdftoppm_bin(bin)
    local exe = join_path(bin, 'pdftoppm.exe')
    local f = io.open(exe, 'rb')
    if not f then return false end
    f:close()
    local cmd = string.format('%s -v 2>&1', quote_arg(exe))
    local h = io.popen(cmd)
    local out = h and h:read('*a') or ''
    if h then h:close() end
    return out:find('pdftoppm version') ~= nil
end

local cache_dirs = {}
local cache_selection = {}
local conversion_state = nil
local convert_progress = 0
local last_poll_time = 0
local download_progress = 0
local texture_recreate_tried = {}

-- check if poppler is installed in the resource folder
local function find_poppler_bin()
    local base = reaper.GetResourcePath() .. "\\Poppler"
    local i = 0
    while true do
        local dir = reaper.EnumerateSubdirectories and reaper.EnumerateSubdirectories(base, i)
        if not dir then break end
        local top = base .. "\\" .. dir
        local candidate1 = top .. "\\Library\\bin"
        if is_valid_pdftoppm_bin(candidate1) then return candidate1 end
        local j = 0
        while true do
            local sub = reaper.EnumerateSubdirectories and reaper.EnumerateSubdirectories(top, j)
            if not sub then break end
            local candidate2 = top .. "\\" .. sub .. "\\Library\\bin"
            if is_valid_pdftoppm_bin(candidate2) then return candidate2 end
            j = j + 1
        end
        i = i + 1
    end
    local fallback1 = base .. "\\poppler-26.02.0-0\\Library\\bin"
    if is_valid_pdftoppm_bin(fallback1) then return fallback1 end
    local fallback2 = base .. "\\poppler-25.12.0-0\\Library\\bin"
    if is_valid_pdftoppm_bin(fallback2) then return fallback2 end
    local fallback3 = base .. "\\poppler-24.08.0\\Library\\bin"
    if is_valid_pdftoppm_bin(fallback3) then return fallback3 end
    return nil
end

local pdftoppm_installed_cache = nil

-- check if pdftoppm is installed
local function is_pdftoppm_installed()
    if pdftoppm_installed_cache ~= nil then return pdftoppm_installed_cache end
    if find_poppler_bin() then
        pdftoppm_installed_cache = true
        return true
    end
    local handle = io.popen("pdftoppm -v 2>nul")
    local result = handle and handle:read("*a") or ""
    if handle then handle:close() end
    pdftoppm_installed_cache = (result and result:find("pdftoppm version") ~= nil)
    return pdftoppm_installed_cache
end

local function is_poppler_installed()
    return find_poppler_bin() ~= nil
end

-- install poppler
local download_state = nil

local function install_pdftoppm()
    local url = "https://github.com/oschwartz10612/poppler-windows/releases/download/v26.02.0-0/Release-26.02.0-0.zip"
    status_message = 'Checking connectivity...'
    
    local zip_path = join_path(reaper.GetResourcePath(), 'Poppler.zip')
    local extract_path = join_path(reaper.GetResourcePath(), 'Poppler')
    reaper.RecursiveCreateDirectory(extract_path, 0)
    
    local vbs = join_path(extract_path, '_download_poppler.vbs')
    local ps1_path = join_path(extract_path, '_download_poppler.ps1')
    local done_file = join_path(extract_path, '_install_done.txt')
    local err_file = join_path(extract_path, '_install_err.txt')
    
    os.remove(done_file)
    os.remove(err_file)

    local expected_sha256 = '993e4a94376ed712fafc7058d724ea0b943d118bbd2305cd9ed55174eb85cda5'

    local ps_cmd = string.format([[
Try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $ProgressPreference="SilentlyContinue"
    Invoke-WebRequest -UseBasicParsing -Headers @{ "User-Agent" = "Mozilla/5.0" } -Uri '%s' -OutFile '%s'
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath '%s').Hash
    if ($hash -ne '%s') { throw "SHA256 mismatch" }
    Expand-Archive -LiteralPath '%s' -DestinationPath '%s' -Force
    Remove-Item -LiteralPath '%s' -Force
    Set-Content -Path '%s' -Value 'done'
} Catch {
    Set-Content -Path '%s' -Value $_.Exception.Message
}
]], url, zip_path, zip_path, expected_sha256, zip_path, extract_path, zip_path, done_file, err_file)

    local f_ps1 = io.open(ps1_path, 'w')
    if f_ps1 then f_ps1:write(ps_cmd); f_ps1:close() else return false end

    local cmd = 'powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File ' .. quote_arg(ps1_path)
    local vbs_content = 'Set sh = CreateObject("WScript.Shell")\r\nsh.Run ' .. quote_arg(cmd) .. ', 0, False\r\n'
    
    local f = io.open(vbs, 'w')
    if not f then return false end
    f:write(vbs_content)
    f:close()

    os.execute('wscript.exe //B //Nologo ' .. quote_arg(vbs))
    
    download_state = {
        active = true, 
        start = reaper.time_precise and reaper.time_precise() or 0, 
        vbs = vbs, 
        ps1 = ps1_path,
        extract = extract_path, 
        zip = zip_path, 
        done_file = done_file,
        err_file = err_file
    }
    status_is_error = false
    status_message = 'Downloading & Installing Poppler…'
    return true
end

local function step_download()
    if not download_state or not download_state.active then return end
    local timeout = 600 -- 10 minutes max for download and extract
    local now = reaper.time_precise and reaper.time_precise() or 0
    local elapsed = now - download_state.start
    
    if file_exists(download_state.zip) then
        local sz = get_file_size(download_state.zip)
        download_progress = math.min(0.9, sz / 41000000)
    else
        if download_progress > 0 then
            download_progress = 0.95
            status_message = 'Extracting Poppler…'
        else
            download_progress = math.min(0.1, elapsed / 10)
        end
    end

    if file_exists(download_state.done_file) then
        download_state.active = false
        status_is_error = false
        status_message = 'Poppler installed'
        download_progress = 1.0
        os.remove(download_state.vbs)
        os.remove(download_state.ps1)
        os.remove(download_state.done_file)
        os.remove(download_state.err_file)
        return
    end

    if file_exists(download_state.err_file) then
        download_state.active = false
        status_is_error = true
        local f = io.open(download_state.err_file, 'r')
        local err_msg = f and f:read('*a') or 'Unknown error'
        if f then f:close() end
        status_message = 'Poppler installation failed: ' .. err_msg:sub(1, 30)
        return
    end

    if elapsed > timeout then
        download_state.active = false
        status_is_error = true
        status_message = 'Poppler download timeout'
        return
    end
end


local function count_pages_in_dir(output_dir)
    local max_n = 0
    local i = 0
    while true do
        local name = reaper.EnumerateFiles and reaper.EnumerateFiles(output_dir, i)
        if not name then break end
        local n = name:match("^page%-(%d+)%.png$")
        if n then
            n = tonumber(n)
            if n and n > max_n then max_n = n end
        end
        i = i + 1
    end
    return max_n
end



local function list_missing_pages(output_dir, pages)
    local missing = {}
    local avail = {}
    local idx = 0
    while true do
        local name = reaper.EnumerateFiles and reaper.EnumerateFiles(output_dir, idx)
        if not name then break end
        local n = name:match('^page%-(%d+)%.png$')
        if n then
            n = tonumber(n)
            if n and n >= 1 then avail[n] = true end
        end
        idx = idx + 1
    end
    for i = 1, pages do
        if not avail[i] then missing[#missing + 1] = i end
    end
    return missing
end

local function create_validated_texture(path)
    local tex = reaper.ImGui_CreateImage(path)
    if not tex then return nil end
    reaper.ImGui_Attach(ctx, tex)
    local ok, w, h = pcall(reaper.ImGui_Image_GetSize, tex)
    if ok and w and w > 0 and h and h > 0 then
        return tex
    end
    if reaper.ImGui_Detach then reaper.ImGui_Detach(ctx, tex) end
    return nil
end
local finalize_current_page
local function convert_pdf_to_images(pdf_path, output_dir)
    log('convert_pdf_to_images: pdf=' .. tostring(pdf_path) .. ' out=' .. tostring(output_dir))

    -- Fast path: if cache already has a complete contiguous set of pages,
    -- skip any external commands entirely
    local existing_max = count_pages_in_dir(output_dir)
    if existing_max > 0 then
        local missing_fast = list_missing_pages(output_dir, existing_max)
        if #missing_fast == 0 then
            total_pages = existing_max
            log('convert_pdf_to_images: fast-path using cache, pages=' .. tostring(existing_max))
            finalize_current_page(output_dir)
            return
        end
    end

    if not is_pdftoppm_installed() and not is_poppler_installed() then
        local retval = reaper.ShowMessageBox("Poppler is required to convert PDF files into viewable images.\n\nThis process will automatically download the Poppler binary package from the official GitHub source (oschwartz10612/poppler-windows) and extract it to your Reaper Resource Path.\n\nDo you wish to proceed with the automatic installation?", "Poppler Installation", 4)
        if retval ~= 6 then
            status_is_error = true
            status_message = 'Poppler is not installed: conversion not available'
            return
        end
        if not install_pdftoppm() then
            status_is_error = true
            status_message = 'Poppler installation failed'
            return
        end
        return
    end
    local bin = find_poppler_bin()
    local pdfinfo_cmd
    local q_pdf = quote_arg(pdf_path)
    if bin then
        pdfinfo_cmd = string.format('set "PATH=%s;%%PATH%%" && "%s\\pdfinfo.exe" %s 2>&1', bin, bin, q_pdf)
    else
        pdfinfo_cmd = string.format('pdfinfo %s 2>&1', q_pdf)
    end
    local h = io.popen(pdfinfo_cmd)
    local info = h and h:read("*a") or ""
    if h then h:close() end
    local pages_count = tonumber(info:match("Pages:%s*(%d+)"))
    if pages_count then
        total_pages = pages_count
        status_is_error = false
        status_message = 'Document found: ' .. tostring(total_pages) .. ' pages'
    else
        total_pages = 0
        status_is_error = true
        status_message = 'Conversion: no pages found'
    end
    local need_conversion = false
    local missing = {}
    if total_pages > 0 then
        missing = list_missing_pages(output_dir, total_pages)
        need_conversion = (#missing > 0)
    else
        need_conversion = true
    end
    if need_conversion then
        local exe = bin and (join_path(bin, 'pdftoppm.exe')) or 'pdftoppm'
        local out_prefix = join_path(output_dir, 'page')
        local pid_path = join_path(output_dir, 'pdftoppm.pid')
        local out_log = join_path(output_dir, 'pdftoppm.out.txt')
        local err_log = join_path(output_dir, 'pdftoppm.err.txt')
        local wd = bin or ''
        local range = (total_pages and total_pages > 0) and string.format(' -f 1 -l %d', total_pages) or ''
        local cmdline = string.format('cmd.exe /c ""%s"%s %s %s > %s 2> %s"', exe, ' -q -png' .. range, quote_arg(pdf_path), quote_arg(out_prefix), quote_arg(out_log), quote_arg(err_log))
        local vbs_path = join_path(output_dir, '_run_pdftoppm.vbs')
        local vbs_content = 'Set sh = CreateObject("WScript.Shell")\r\nsh.CurrentDirectory = ' .. quote_arg(wd) .. '\r\nsh.Run ' .. quote_arg(cmdline) .. ', 0, False\r\n'
        local vf = io.open(vbs_path, 'w')
        if vf then vf:write(vbs_content) vf:close() end
        log('Convert: exe=' .. tostring(exe))
        log('Convert: cmdline=' .. tostring(cmdline))
        log('Convert: wd=' .. tostring(wd))
        os.execute('wscript.exe //B //Nologo ' .. quote_arg(vbs_path))
        local ps = 'powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command '
        local ps_pid = '$t=' .. ps_quote(exe) .. '; Start-Sleep -Milliseconds 800; $p = Get-Process -Name pdftoppm -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $t } | Sort-Object StartTime | Select-Object -Last 1; if ($p) { Set-Content -Path ' .. ps_quote(pid_path) .. ' -Value $p.Id }'
        os.execute(ps .. quote_arg(ps_pid))
        local pf = io.open(pid_path, 'r')
        local pid_val = nil
        if pf then pid_val = tonumber((pf:read('*a') or ''):match('%d+')); pf:close() end
        log('Convert: pid=' .. tostring(pid_val))
        local now = reaper.time_precise and reaper.time_precise() or nil
        conversion_state = {bin = bin, pdf = pdf_path, out = output_dir, total = total_pages > 0 and total_pages or 0, active = true, last_created = 0, last_change_time = now, pid_path = pid_path, pid = pid_val, exe_path = exe, out_log = out_log, err_log = err_log, logged_error = false, vbs = vbs_path, throttle = 0.2, size = get_file_size(pdf_path)}
        convert_progress = 0
    else
        
    end
end
 
local function load_all_pages(output_dir)
    log("load_all_pages: output_dir=" .. tostring(output_dir))
    local by_index = {}
    local idx = 0
    while true do
        local name = reaper.EnumerateFiles and reaper.EnumerateFiles(output_dir, idx)
        log("load_all_pages: enumerated file=" .. tostring(name))
        if not name then break end
        local n = name:match('^page%-(%d+)%.png$')
        if n then
            n = tonumber(n)
            log("load_all_pages: matched page=" .. tostring(n))
            if n and n >= 1 then
                by_index[n] = join_path(output_dir, name)
            end
        end
        idx = idx + 1
    end
    local all_images = {}
    for i = 1, total_pages do
        local p = by_index[i]
        log("load_all_pages: page=" .. tostring(i) .. " path=" .. tostring(p))
        if p then
            all_images[i] = p
        end
    end
    log("load_all_pages: all_images count=" .. tostring(#all_images))
    return all_images
end

function finalize_current_page(output_dir)
    log("finalize_current_page: output_dir=" .. tostring(output_dir))
    all_page_paths = load_all_pages(output_dir)
    do
        local c = 0
        for _, _ in pairs(all_page_paths) do c = c + 1 end
        log("finalize_current_page: mapped count=" .. tostring(c) .. " total_pages=" .. tostring(total_pages))
    end
    local image_path = all_page_paths[current_page]
    log("finalize_current_page: current_page=" .. tostring(current_page) .. " image_path=" .. tostring(image_path))
    if image_path then
        images = {image_path}
        local texture = create_validated_texture(image_path)
        if not texture then
            log("finalize_current_page: texture creation failed")
        else
            local existing = textures[image_path]
            if existing then
                if reaper.ImGui_Detach then reaper.ImGui_Detach(ctx, existing) end
                if reaper.ImGui_DestroyImage then reaper.ImGui_DestroyImage(existing) end
            end
            textures[image_path] = texture
        end
    end
end

local function open_pdf()
    -- Clear previous textures to free memory
    textures = {}
    
    images = {}
    all_page_paths = {}
    
    if pdf_path ~= '' then
        log('open_pdf: pdf_path=' .. tostring(pdf_path))
        local output_dir = get_pdf_output_dir(pdf_path)
        log('open_pdf: output_dir=' .. tostring(output_dir))
        reaper.RecursiveCreateDirectory(output_dir, 0)
        
        -- Convert all pages at once (asincrono, finalize sarà chiamata in step_conversion)
        convert_pdf_to_images(pdf_path, output_dir)
    end
end

-- Function to navigate to a specific page
local function go_to_page(page_number)
    if page_number < 1 then page_number = 1 end
    if page_number > total_pages then page_number = total_pages end
    
    if current_page ~= page_number then
        log('go_to_page: requested=' .. tostring(page_number))
        current_page = page_number
        
        for path, texture in pairs(textures) do
            if reaper.ImGui_Detach then reaper.ImGui_Detach(ctx, texture) end
            if reaper.ImGui_DestroyImage then
                reaper.ImGui_DestroyImage(texture)
            end
        end
        textures = {}
        
        -- Load the new page from already converted images
        local image_path = all_page_paths[current_page]
        if not image_path then
            for i = current_page, total_pages do
                if all_page_paths[i] then
                    image_path = all_page_paths[i]
                    current_page = i
                    break
                end
            end
            if not image_path then
                for i = current_page, 1, -1 do
                    if all_page_paths[i] then
                        image_path = all_page_paths[i]
                        current_page = i
                        break
                    end
                end
            end
        end
        log('go_to_page: final_page=' .. tostring(current_page) .. ' image_path=' .. tostring(image_path))
        if image_path then
            images = {image_path}
            local texture = create_validated_texture(image_path)
            if texture then
                textures[image_path] = texture
            end
        end
    end
end

-- Function to delete image files from the output directory
local function delete_image_files(output_dir)
    local to_remove = {}
    local i = 0
    while true do
        local name = reaper.EnumerateFiles and reaper.EnumerateFiles(output_dir, i)
        if not name then break end
        if name:match('^page%-%d+%.png$') then
            to_remove[#to_remove + 1] = join_path(output_dir, name)
        end
        i = i + 1
    end
    for _, path in ipairs(to_remove) do
        os.remove(path)
    end
end

local function remove_directory(dir)
    local cmd = string.format("powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command \"Remove-Item -LiteralPath %s -Force -Recurse\"", ps_quote(dir))
    os.execute(cmd)
end

local function get_cache_base_dir()
    return join_path(reaper.GetResourcePath(), 'pdf_images')
end

local function refresh_cache_dirs()
    local base = get_cache_base_dir()
    reaper.RecursiveCreateDirectory(base, 0)
    cache_dirs = {}
    local i = 0
    while true do
        local name = reaper.EnumerateSubdirectories and reaper.EnumerateSubdirectories(base, i)
        if not name then break end
        cache_dirs[#cache_dirs + 1] = name
        if cache_selection[name] == nil then cache_selection[name] = false end
        i = i + 1
    end
end

local function delete_cache_dir(name)
    local base = get_cache_base_dir()
    local dir = join_path(base, name)
    delete_image_files(dir)
    remove_directory(dir)
end

local function delete_selected_caches()
    local base = get_cache_base_dir()
    local deleted = {}
    for _, name in ipairs(cache_dirs) do
        if cache_selection[name] then
            delete_cache_dir(name)
            deleted[#deleted + 1] = name
        end
    end
    if pdf_path ~= '' then
        local cur = get_pdf_output_dir(pdf_path)
        for _, name in ipairs(deleted) do
            if cur == join_path(base, name) then
                total_pages = 0
                all_page_paths = {}
                images = {}
                textures = {}
                break
            end
        end
    end
    refresh_cache_dirs()
end

local function delete_all_caches()
    for _, name in ipairs(cache_dirs) do
        delete_cache_dir(name)
    end
    if pdf_path ~= '' then
        total_pages = 0
        all_page_paths = {}
        images = {}
        textures = {}
    end
    refresh_cache_dirs()
end

local function step_conversion()
    if not conversion_state or not conversion_state.active then return end
    local st = conversion_state
    local created
    local now = reaper.time_precise and reaper.time_precise() or nil
    local throttle = st.throttle or 0.2
    if now and last_poll_time ~= 0 and (now - last_poll_time) < throttle then
        created = st.last_created or 0
    else
        local prev = st.last_created or 0
        created = count_pages_in_dir(st.out)
        if created ~= prev then
            st.last_change_time = now or st.last_change_time
            st.throttle = math.max(0.1, throttle - 0.05)
        else
            st.throttle = math.min(0.5, throttle + 0.05)
        end
        st.last_created = created
        if now then last_poll_time = now end
    end
    local stall_threshold
    do
        local pages = st.total or 0
        local size_mb = (st.size or 0) / (1024 * 1024)
        if pages >= 300 or size_mb >= 50 then
            stall_threshold = 5.0
        elseif pages >= 100 or size_mb >= 20 then
            stall_threshold = 4.0
        else
            stall_threshold = 3.5
        end
    end
    if st.total > 0 then
        convert_progress = math.min(1, created / st.total)
        local stalled = st.last_change_time and now and (now - st.last_change_time) > stall_threshold
        if created == 0 then
            local e_sz = (st.err_log and file_exists(st.err_log)) and get_file_size(st.err_log) or 0
            local o_sz = (st.out_log and file_exists(st.out_log)) and get_file_size(st.out_log) or 0
            if (e_sz > 0 or o_sz > 0) and (not st.logged_error) then
                status_is_error = true
                status_message = 'Conversion error: see log file'
                if e_sz > 0 then
                    local f = io.open(st.err_log, 'rb')
                    local buf = f and f:read(1024) or ''
                    if f then f:close() end
                    log('pdftoppm stderr: ' .. tostring(buf))
                end
                if o_sz > 0 then
                    local f2 = io.open(st.out_log, 'rb')
                    local buf2 = f2 and f2:read(1024) or ''
                    if f2 then f2:close() end
                    log('pdftoppm stdout: ' .. tostring(buf2))
                end
                st.logged_error = true
            end
        end
        if created >= st.total or (created > 0 and stalled) then
            st.active = false
            if created < st.total then st.total = created end
            total_pages = st.total
            finalize_current_page(st.out)
            if st.vbs then os.remove(st.vbs) end
            if st.pid_path then os.remove(st.pid_path) end
            if st.out_log then os.remove(st.out_log) end
            if st.err_log then os.remove(st.err_log) end
        end
    else
        convert_progress = 0
        local stalled = st.last_change_time and now and (now - st.last_change_time) > stall_threshold
        if created == 0 then
            local e_sz = (st.err_log and file_exists(st.err_log)) and get_file_size(st.err_log) or 0
            local o_sz = (st.out_log and file_exists(st.out_log)) and get_file_size(st.out_log) or 0
            if (e_sz > 0 or o_sz > 0) and (not st.logged_error) then
                status_is_error = true
                status_message = 'Conversion error: see log file'
                if e_sz > 0 then
                    local f = io.open(st.err_log, 'rb')
                    local buf = f and f:read(1024) or ''
                    if f then f:close() end
                    log('pdftoppm stderr: ' .. tostring(buf))
                end
                if o_sz > 0 then
                    local f2 = io.open(st.out_log, 'rb')
                    local buf2 = f2 and f2:read(1024) or ''
                    if f2 then f2:close() end
                    log('pdftoppm stdout: ' .. tostring(buf2))
                end
                st.logged_error = true
            end
        end
        if created > 0 and stalled then
            st.total = created
            st.active = false
            total_pages = st.total
            finalize_current_page(st.out)
            if st.vbs then os.remove(st.vbs) end
            if st.pid_path then os.remove(st.pid_path) end
            if st.out_log then os.remove(st.out_log) end
            if st.err_log then os.remove(st.err_log) end
        end
    end
end

local function abort_conversion()
    if not conversion_state or not conversion_state.active then return end
    local st = conversion_state
    do
        log("Abort: begin")
        local pid = st.pid
        if (not pid) and st.pid_path then
            local f = io.open(st.pid_path, 'r')
            if f then
                local s = f:read('*a') or ''
                f:close()
                pid = tonumber(s:match('%d+'))
            end
        end
        log("Abort: pid=" .. tostring(pid))
        local stopped = false
        if pid and pid > 0 then
            local ps1 = string.format([[powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "$ErrorActionPreference='SilentlyContinue'; Stop-Process -Id %d -Force; Start-Sleep -Milliseconds 300; if (Get-Process -Id %d) { Write-Output 'still_running' } else { Write-Output 'stopped' }"]], pid, pid)
            local h = io.popen(ps1)
            local out = h and h:read("*a") or ""
            if h then h:close() end
            out = tostring(out or ""):gsub("%s+", "")
            log("Abort: pid stop result=" .. out)
            stopped = (out == "stopped")
            if not stopped then
                os.execute(string.format('taskkill /F /PID %d', pid))
            end
        end
        if not stopped then
            local target = st.exe_path or ''
            if target ~= '' then
                local ps2 = string.format([[powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "$ErrorActionPreference='SilentlyContinue'; $t = %s; $procs = Get-Process -Name pdftoppm | Where-Object { $_.Path -eq $t }; foreach ($p in $procs) { Stop-Process -Id $p.Id -Force }; ($procs | Measure-Object).Count"]], ps_quote(target))
                local h2 = io.popen(ps2)
                local out2 = h2 and h2:read("*a") or ""
                if h2 then h2:close() end
                out2 = tostring(out2 or ""):gsub("%s+", "")
                log("Abort: path-targeted stop count=" .. out2)
            else
                log("Abort: no exe_path available for targeted stop")
            end
        end
    end
    st.active = false
    if st.vbs then os.remove(st.vbs) end
    if st.pid_path then os.remove(st.pid_path) end
    local outdir = st.out
    if outdir and outdir ~= '' then
        delete_image_files(outdir)
        remove_directory(outdir)
    end
    for path, texture in pairs(textures) do
        if reaper.ImGui_Detach then reaper.ImGui_Detach(ctx, texture) end
        if reaper.ImGui_DestroyImage then
            reaper.ImGui_DestroyImage(texture)
        end
    end
    images = {}
    textures = {}
    all_page_paths = {}
    total_pages = 0
    conversion_state = nil
    convert_progress = 0
    status_is_error = false
    status_message = 'Status: all systems are ready'
    reaper.ShowMessageBox('Conversion aborted successfully.', 'Conversion', 0)
end

-- Function to clear images and textures
local function clear_images_and_textures()
    for path, texture in pairs(textures) do
        if reaper.ImGui_Detach then reaper.ImGui_Detach(ctx, texture) end
        if reaper.ImGui_DestroyImage then
            reaper.ImGui_DestroyImage(texture)
        end
    end
    images = {}
    textures = {}
end

-- Register the cleanup function to be called when the script exits
reaper.atexit(clear_images_and_textures)


local function draw_nav_button(label, enabled, page, w, h)
    if enabled then Theme.pushButtonPrimary() else Theme.pushButtonDisabled() end
    if reaper.ImGui_Button(ctx, label, w, h) and enabled then
        go_to_page(page)
    end
    if enabled then Theme.popButtonPrimary() else Theme.popButtonDisabled() end
end

local function render_ui()
    reaper.ImGui_SetNextWindowSize(ctx, ui_config.window_width, ui_config.window_height, reaper.ImGui_Cond_FirstUseEver())
    local theme_color_count, theme_style_count = applyTheme()
    reaper.ImGui_PushFont(ctx, sans_serif, 13)
    local window_flags = reaper.ImGui_WindowFlags_NoCollapse()
    local btn_h_global = (ui_config.btn_height and ui_config.btn_height > 0) and ui_config.btn_height or reaper.ImGui_GetFrameHeight(ctx)

    local visible, open = reaper.ImGui_Begin(ctx, 'Sheet Reader v-2.0 | PDF & Image Viewer', true, window_flags)
    if visible then
        reaper.ImGui_Dummy(ctx, 0, 5)
        
        -- Drag and drop handling
        if reaper.ImGui_BeginDragDropTarget(ctx) then
            local rv, count = reaper.ImGui_AcceptDragDropPayloadFiles(ctx)
            if rv and count > 0 then
                local ok, filename = reaper.ImGui_GetDragDropPayloadFile(ctx, 0)
                if ok and filename then
                    if is_valid_pdf(filename) then
                        for path, texture in pairs(textures) do
                            if reaper.ImGui_Detach then reaper.ImGui_Detach(ctx, texture) end
                            if reaper.ImGui_DestroyImage then reaper.ImGui_DestroyImage(texture) end
                        end
                        textures = {}
                        pdf_path = filename 
                        current_page = 1
                        open_pdf()
                    elseif is_valid_image(filename) then
                        pdf_path = ''
                        total_pages = 1
                        current_page = 1
                        images = {filename}
                        for path, texture in pairs(textures) do
                            if reaper.ImGui_Detach then reaper.ImGui_Detach(ctx, texture) end
                            if reaper.ImGui_DestroyImage then reaper.ImGui_DestroyImage(texture) end
                        end
                        textures = {}
                        texture_recreate_tried = {}
                        local texture = create_validated_texture(filename)
                        if texture then
                            textures[filename] = texture
                            status_is_error = false
                            status_message = 'Image loaded'
                        else
                            status_is_error = true
                            status_message = 'Image loading failed'
                            images = {}
                        end
                    end
                end
            end
            reaper.ImGui_EndDragDropTarget(ctx)
        end
        
        
        
        -- button to select pdf and image files
        Theme.pushButtonPrimary()
        if reaper.ImGui_Button(ctx, 'Select PDF', 160, btn_h_global) then
            local retval, selected_path = reaper.GetUserFileNameForRead(last_pdf_dir, 'Select PDF', '*.pdf')
            if retval then 
                save_last_dir("LastPdfDir", selected_path)
                log('Select PDF: ' .. tostring(selected_path))
                if not is_valid_pdf(selected_path) then
                    status_is_error = true
                    status_message = 'Invalid PDF file'
                else
                    for path, texture in pairs(textures) do
                        if reaper.ImGui_Detach then reaper.ImGui_Detach(ctx, texture) end
                        if reaper.ImGui_DestroyImage then
                            reaper.ImGui_DestroyImage(texture)
                        end
                    end
                    textures = {}
                    pdf_path = selected_path 
                    current_page = 1
                    log('Open PDF begin')
                    open_pdf() 
                end
            end
        end
        Theme.popButtonPrimary()

        reaper.ImGui_SameLine(ctx)
        Theme.pushButtonPrimary()
        if reaper.ImGui_Button(ctx, 'Clear Cache', 160, btn_h_global) then
            refresh_cache_dirs()
            reaper.ImGui_OpenPopup(ctx, 'Cache Manager')
        end
        Theme.popButtonPrimary()

        reaper.ImGui_SameLine(ctx)
        Theme.pushButtonPrimary()
        if reaper.ImGui_Button(ctx, 'Select Image', 160, btn_h_global) then
            local retval, selected_path = reaper.GetUserFileNameForRead(last_img_dir, 'Select Image', '*.png;*.jpg;*.jpeg')
            if retval then
                save_last_dir("LastImgDir", selected_path)
                log('Select Image: ' .. tostring(selected_path))
                if not is_valid_image(selected_path) then
                    status_is_error = true
                    status_message = 'Invalid image file'
                else
                    pdf_path = ''
                    total_pages = 1
                    current_page = 1
                    images = {selected_path}
                    for path, texture in pairs(textures) do
                        if reaper.ImGui_Detach then reaper.ImGui_Detach(ctx, texture) end
                        if reaper.ImGui_DestroyImage then
                            reaper.ImGui_DestroyImage(texture)
                        end
                    end
                    textures = {}
                    texture_recreate_tried = {}
                    local texture = create_validated_texture(selected_path)
                    if texture then
                        textures[selected_path] = texture
                        status_is_error = false
                        status_message = 'Image loaded'
                    else
                        status_is_error = true
                        status_message = 'Image loading failed'
                        images = {}
                    end
                end
            end
        end
        Theme.popButtonPrimary()

        reaper.ImGui_SameLine(ctx)
        Theme.pushButtonPrimary()
        if reaper.ImGui_Button(ctx, ' ? ', 30, btn_h_global) then
            open_about = true
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            Theme.pushTextAlt()
            reaper.ImGui_SetTooltip(ctx, 'About / Credits')
            Theme.popText()
        end
        Theme.popButtonPrimary()

        if download_state and download_state.active then
            local base_w = 400
            Theme.pushProgressPrimary()
            reaper.ImGui_ProgressBar(ctx, download_progress, base_w, btn_h_global, status_message or 'Downloading Poppler…')
            Theme.popProgressPrimary()
            step_download()
            reaper.ImGui_Dummy(ctx, 0, 5)
        end

        if conversion_state and conversion_state.active then
            local base_w = 400
            local created = conversion_state.last_created or 0
            local txt = string.format('Converting: %d/%d', created, conversion_state.total)
            Theme.pushProgressPrimary()
            reaper.ImGui_ProgressBar(ctx, convert_progress, base_w, btn_h_global, txt)
            Theme.popProgressPrimary()
            reaper.ImGui_SameLine(ctx)
            Theme.pushButtonPrimary()
            if reaper.ImGui_Button(ctx, 'Stop Conversion', 140, btn_h_global) then
                abort_conversion()
            end
            Theme.popButtonPrimary()
            step_conversion()
            reaper.ImGui_Dummy(ctx, 0, 5)
        end

        

        do
            local txt = status_message or 'Status: all systems are ready'
            local col = status_is_error and PALETTE.statusError or PALETTE.statusOk
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), col)
            reaper.ImGui_Text(ctx, txt)
            reaper.ImGui_PopStyleColor(ctx)
            reaper.ImGui_Dummy(ctx, 0, 5)
        end
        
        -- Page navigation controls (only show for PDFs)
        if pdf_path ~= '' and total_pages > 1 then
            reaper.ImGui_Dummy(ctx, 0, 5)
            
            -- Display page info
            Theme.pushTextAlt()
            reaper.ImGui_Text(ctx, string.format("Page %d of %d", current_page, total_pages))
            Theme.popText()
            
            reaper.ImGui_SameLine(ctx)
            
            local at_first = current_page <= 1
            local at_last = current_page >= total_pages
            draw_nav_button('«', not at_first, 1, STYLE.buttonW, btn_h_global)
            
            reaper.ImGui_SameLine(ctx)
            
            draw_nav_button('◄', not at_first, current_page - 1, STYLE.buttonW, btn_h_global)
            
            reaper.ImGui_SameLine(ctx)
            
            draw_nav_button('►', not at_last, current_page + 1, STYLE.buttonW, btn_h_global)
            
            reaper.ImGui_SameLine(ctx)
            
            draw_nav_button('»', not at_last, total_pages, STYLE.buttonW, btn_h_global)
            
            -- Page input
            reaper.ImGui_SameLine(ctx)
            
     -- Input style
            Theme.pushInputPrimary()
            reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FramePadding(), 6, 6)
            reaper.ImGui_PushItemWidth(ctx, 100)
            local changed, new_page = reaper.ImGui_InputInt(ctx, '##Go to page', current_page, 1)
            if changed and new_page ~= current_page then
                if new_page < 1 then new_page = 1 end
                if new_page > total_pages then new_page = total_pages end
                go_to_page(new_page)
            end
            reaper.ImGui_PopItemWidth(ctx)
            reaper.ImGui_PopStyleVar(ctx)
            Theme.popInputPrimary()
        end

        Theme.pushTextAlt()
        reaper.ImGui_Text(ctx, "Use the N and M keys to move between pages.")
        reaper.ImGui_Text(ctx, "To zoom use Ctrl + Mouse Wheel")
        Theme.popText()
        reaper.ImGui_SameLine(ctx)
        local avail_w = select(1, reaper.ImGui_GetContentRegionAvail(ctx)) or 0
        local cur_x = reaper.ImGui_GetCursorPosX(ctx)
        local button_w = STYLE.buttonW
        local spacing_x = STYLE.clusterSpacing
        local cluster_w = button_w + spacing_x + button_w + spacing_x + button_w
        local right_margin = STYLE.rightMargin
        local target_x = cur_x + math.max(0, avail_w - cluster_w - right_margin)
        reaper.ImGui_SetCursorPosX(ctx, target_x)
        Theme.pushItemSpacing(spacing_x, 0)
        Theme.pushButtonPrimary()
        local label_toggle = ui_config.fit_width and '↔' or '▭'
        if reaper.ImGui_Button(ctx, label_toggle .. '##fitwidth-toggle', button_w, btn_h_global) then
            ui_config.fit_width = not ui_config.fit_width
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), THEME_COLORS[reaper.ImGui_Col_Text()])
            reaper.ImGui_SetTooltip(ctx, "Toggle Fit Width")
            reaper.ImGui_PopStyleColor(ctx, 1)
        end
        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_Button(ctx, '＋##zoom-plus', button_w, btn_h_global) then ui_config.zoom_level = math.min(ui_config.zoom_max, ui_config.zoom_level + 0.1) end
        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_Button(ctx, '－##zoom-minus', button_w, btn_h_global) then
            ui_config.zoom_level = math.max(0.1, ui_config.zoom_level - 0.1)
        end
        Theme.popButtonPrimary()
        Theme.popItemSpacing()

        -- Handle zoom with mouse wheel
        if reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Mod_Ctrl()) then
            local wheel = reaper.ImGui_GetMouseWheel(ctx)
            if wheel > 0 then
                ui_config.zoom_level = math.min(ui_config.zoom_max, ui_config.zoom_level + 0.1)
            elseif wheel < 0 then
                ui_config.zoom_level = ui_config.zoom_level - 0.1
                if ui_config.zoom_level < 0.1 then
                    ui_config.zoom_level = 0.1
                end
            end
        end
        
        -- Handle global shortcuts
        if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_F()) then
            ui_config.fit_width = not ui_config.fit_width
        end
        
        -- Handle page navigation with keyboard shortcuts
        if pdf_path ~= '' and total_pages > 1 then
            if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_PageUp()) then
                go_to_page(current_page - 1)
            elseif reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_PageDown()) then
                go_to_page(current_page + 1)
            elseif reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Home()) then
                go_to_page(1)
            elseif reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_End()) then
                go_to_page(total_pages)
            elseif reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_M()) and current_page < total_pages then
                go_to_page(current_page + 1)
            elseif reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_N()) and current_page > 1 then
                go_to_page(current_page - 1)
            end
        end
        
        reaper.ImGui_Dummy(ctx, 0, 5)
        Theme.pushSeparator()
        reaper.ImGui_Separator(ctx)
        Theme.popSeparator()
        
    -- draw images
    for _, image_path in ipairs(images) do
        local texture = textures[image_path]
        if not texture then
            if file_exists(image_path) and not texture_recreate_tried[image_path] then
                texture_recreate_tried[image_path] = true
                local t2 = create_validated_texture(image_path)
                if t2 then
                    textures[image_path] = t2
                    status_is_error = false
                    status_message = 'Image loaded'
                else
                    status_is_error = true
                    status_message = 'Image texture invalid'
                end
            end
        else
            if type(texture) ~= 'userdata' then
                textures[image_path] = nil
            else
                local ok, width, height = pcall(reaper.ImGui_Image_GetSize, texture)
                if not ok or not width or not height or width <= 0 or height <= 0 then
                    if reaper.ImGui_Detach then reaper.ImGui_Detach(ctx, texture) end
                    if reaper.ImGui_DestroyImage then reaper.ImGui_DestroyImage(texture) end
                    textures[image_path] = nil
                    if file_exists(image_path) and not texture_recreate_tried[image_path] then
                        texture_recreate_tried[image_path] = true
                        local t2 = create_validated_texture(image_path)
                        if t2 then
                            textures[image_path] = t2
                            status_is_error = false
                        else
                            status_is_error = true
                            status_message = 'Image texture invalid'
                        end
                    end
                else
                    local ww = reaper.ImGui_GetWindowWidth(ctx)
                    local avail_w = ww - 2 * ui_config.window_padding_x
                    local base_scale = ui_config.fit_width and (avail_w / width) or 1
                    width, height = width * base_scale * ui_config.zoom_level, height * base_scale * ui_config.zoom_level
                    local ok2 = pcall(reaper.ImGui_Image, ctx, texture, width, height, 0, 0, 1, 1)
                    if not ok2 then
                        if reaper.ImGui_Detach then reaper.ImGui_Detach(ctx, texture) end
                        if reaper.ImGui_DestroyImage then reaper.ImGui_DestroyImage(texture) end
                        textures[image_path] = nil
                        if file_exists(image_path) and not texture_recreate_tried[image_path] then
                            texture_recreate_tried[image_path] = true
                            local t3 = create_validated_texture(image_path)
                            if t3 then
                                textures[image_path] = t3
                            else
                                status_is_error = true
                                status_message = 'Image draw failed'
                            end
                        end
                    end
                end
            end
        end
    end
        reaper.ImGui_Dummy(ctx, 0, 5)
        if open_about then
            reaper.ImGui_OpenPopup(ctx, 'About / Credits')
            open_about = false
        end
        Theme.pushModal()
        if reaper.ImGui_BeginPopupModal(ctx, 'About / Credits', true, reaper.ImGui_WindowFlags_AlwaysAutoResize()) then
            reaper.ImGui_Text(ctx, 'Sheet Reader v2.0')
            reaper.ImGui_Text(ctx, 'Author: Flora Tarantino (Floop-s)')
            
            reaper.ImGui_Dummy(ctx, 0, 2)
            Theme.pushButtonPrimary()
            if reaper.ImGui_Button(ctx, 'GitHub', 90, 0) then
                if reaper.APIExists('CF_ShellExecute') then
                    reaper.CF_ShellExecute('https://github.com/floop-s/floops-reaper-scripts')
                end
            end
            reaper.ImGui_SameLine(ctx)
            if reaper.ImGui_Button(ctx, 'Ko-fi', 90, 0) then
                if reaper.APIExists('CF_ShellExecute') then
                    reaper.CF_ShellExecute('https://ko-fi.com/floopsreaperscripts')
                end
            end
            Theme.popButtonPrimary()

            reaper.ImGui_Separator(ctx)
            reaper.ImGui_Text(ctx, 'PDF conversion powered by Poppler (GPL).')
            reaper.ImGui_Text(ctx, 'Windows binaries: oschwartz10612/poppler-windows')
            Theme.pushButtonPrimary()
            if reaper.ImGui_Button(ctx, 'Poppler GitHub', 120, 0) then
                if reaper.APIExists('CF_ShellExecute') then
                    reaper.CF_ShellExecute('https://github.com/oschwartz10612/poppler-windows')
                end
            end
            Theme.popButtonPrimary()
            reaper.ImGui_EndPopup(ctx)
        end
        Theme.popModal()
        reaper.ImGui_SetNextWindowSize(ctx, 700, 420, reaper.ImGui_Cond_Appearing())
        Theme.pushModal()
        if reaper.ImGui_BeginPopupModal(ctx, 'Cache Manager', true, 0) then
            reaper.ImGui_Text(ctx, 'Cache base: ' .. get_cache_base_dir())
            local btn_h = reaper.ImGui_GetFrameHeight(ctx)
            Theme.pushButtonPrimary()
            if reaper.ImGui_Button(ctx, 'Select All', 120, btn_h) then
                for _, name in ipairs(cache_dirs) do cache_selection[name] = true end
            end
            reaper.ImGui_SameLine(ctx)
            if reaper.ImGui_Button(ctx, 'Deselect All', 120, btn_h) then
                for _, name in ipairs(cache_dirs) do cache_selection[name] = false end
            end
            reaper.ImGui_SameLine(ctx)
            if reaper.ImGui_Button(ctx, 'Open Folder', 120, btn_h) then
                local dir = get_cache_base_dir()
                if reaper.APIExists('CF_ShellExecute') then
                    reaper.CF_ShellExecute(dir)
                elseif reaper.APIExists('BR_Win32_ShellExecute') then
                    reaper.BR_Win32_ShellExecute(dir)
                end
            end
            Theme.popButtonPrimary()
            
            local entries = {}
            for _, name in ipairs(cache_dirs) do
                local dir = join_path(get_cache_base_dir(), name)
                local pages = count_pages_in_dir(dir)
                local status
                if pages > 0 then
                    local missing = list_missing_pages(dir, pages)
                    if #missing == 0 then
                        status = 'Complete'
                    else
                        status = 'Incomplete (' .. tostring(#missing) .. ' missing)'
                    end
                else
                    status = 'Empty'
                end
                entries[#entries + 1] = {name = name, dir = dir, pages = pages, status = status}
            end
            table.sort(entries, function(a, b) return a.name:lower() < b.name:lower() end)
            local flags = reaper.ImGui_TableFlags_RowBg() | reaper.ImGui_TableFlags_Borders()
            if reaper.ImGui_BeginTable(ctx, 'Cache Table', 4, flags) then
                reaper.ImGui_TableSetupColumn(ctx, 'Select', reaper.ImGui_TableColumnFlags_WidthFixed(), 80)
                reaper.ImGui_TableSetupColumn(ctx, 'Title')
                reaper.ImGui_TableSetupColumn(ctx, 'Pages', reaper.ImGui_TableColumnFlags_WidthFixed(), 80)
                reaper.ImGui_TableSetupColumn(ctx, 'Status')
            reaper.ImGui_TableHeadersRow(ctx)
            Theme.pushCheckboxPrimary()
            Theme.pushTextAlt()
            for _, e in ipairs(entries) do
                    reaper.ImGui_TableNextRow(ctx)
                    reaper.ImGui_TableSetColumnIndex(ctx, 0)
                    local changed, val = reaper.ImGui_Checkbox(ctx, '##' .. e.name, cache_selection[e.name] or false)
                    if changed then cache_selection[e.name] = val end
                    reaper.ImGui_TableSetColumnIndex(ctx, 1)
                    reaper.ImGui_Text(ctx, e.name)
                    reaper.ImGui_TableSetColumnIndex(ctx, 2)
                    reaper.ImGui_Text(ctx, tostring(e.pages))
                    reaper.ImGui_TableSetColumnIndex(ctx, 3)
                    reaper.ImGui_Text(ctx, e.status)
                end
                Theme.popText()
                Theme.popCheckboxPrimary()
                reaper.ImGui_EndTable(ctx)
            end
            reaper.ImGui_Dummy(ctx, 0, 5)
            local ww = reaper.ImGui_GetWindowWidth(ctx)
            local spacing = 8
            local total_w = 140 + 120 + 90 + spacing * 2
            local start_x = (ww - total_w) * 0.5
            if start_x > 0 then reaper.ImGui_SetCursorPosX(ctx, start_x) end
            Theme.pushButtonPrimary()
            if reaper.ImGui_Button(ctx, 'Delete Selected', 140, btn_h) then
                delete_selected_caches()
            end
            reaper.ImGui_SameLine(ctx)
            if reaper.ImGui_Button(ctx, 'Delete All', 120, btn_h) then
                reaper.ImGui_OpenPopup(ctx, 'Confirm Delete All')
            end
            reaper.ImGui_SameLine(ctx)
            if reaper.ImGui_Button(ctx, 'Close', 90, btn_h) then
                reaper.ImGui_CloseCurrentPopup(ctx)
            end
            Theme.popButtonPrimary()
            
            reaper.ImGui_SetNextWindowSize(ctx, 420, 160, reaper.ImGui_Cond_Appearing())
            if reaper.ImGui_BeginPopupModal(ctx, 'Confirm Delete All', true, 0) then
                reaper.ImGui_Text(ctx, 'Are you sure you want to delete ALL caches?')
                reaper.ImGui_Dummy(ctx, 0, 5)
                local btn_h2 = reaper.ImGui_GetFrameHeight(ctx)
                local ww2 = reaper.ImGui_GetWindowWidth(ctx)
                local spacing2 = 8
                local total_w2 = 120 + 100 + spacing2
                local start_x2 = (ww2 - total_w2) * 0.5
                if start_x2 > 0 then reaper.ImGui_SetCursorPosX(ctx, start_x2) end
                Theme.pushButtonPrimary()
                if reaper.ImGui_Button(ctx, 'Yes', 120, btn_h2) then
                    delete_all_caches()
                    reaper.ImGui_CloseCurrentPopup(ctx)
                end
                reaper.ImGui_SameLine(ctx)
                if reaper.ImGui_Button(ctx, 'No', 100, btn_h2) then
                    reaper.ImGui_CloseCurrentPopup(ctx)
                end
                Theme.popButtonPrimary()
                reaper.ImGui_EndPopup(ctx)
            end

            reaper.ImGui_EndPopup(ctx)
        end
        Theme.popModal()

    end
    reaper.ImGui_PopFont(ctx)
    reaper.ImGui_PopStyleColor(ctx, theme_color_count)
    reaper.ImGui_PopStyleVar(ctx, theme_style_count)
    reaper.ImGui_End(ctx)
    if open then reaper.defer(render_ui) end
end
render_ui()
