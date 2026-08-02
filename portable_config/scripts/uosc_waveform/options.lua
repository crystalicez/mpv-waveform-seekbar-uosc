local util = require("uosc_waveform.util")

local M = {}

local DEFAULTS = {
    enabled = true,
    ffmpeg_path = "ffmpeg",
    opacity = 0.38,
    color_mode = "auto",
    light_color = "#101010",
    dark_color = "#F2F2F2",
    source_width = 4096,
    source_height = 128,
    displayed_height_ratio = 0.78,
    reserved_marker_ratio = 0.20,
    reserved_progress_px = 2,
    minimum_timeline_width = 320,
    resize_debounce_ms = 120,
    mouse_update_interval_ms = 16,
    media_debounce_ms = 250,
    cache_dir = "~~/cache/uosc-waveform",
    max_cache_age_days = 60,
    max_cache_mb = 512,
    stale_lock_seconds = 900,
    lock_poll_ms = 500,
    compatibility = "uosc-5.12",
    adapter_override = "",
    log_level = "warn",
    analysis_sample_rate = 8000,
    generation_timeout_seconds = 180,
    overlay_id = 63,
    startup_osd = false,
    diagnostic_log = true,
}

local function copy_defaults()
    return util.shallow_copy(DEFAULTS)
end

function M.defaults()
    return copy_defaults()
end

local function warning(warnings, field, message)
    warnings[#warnings + 1] = field .. ": " .. message
end

local function number_or_default(raw, key, default, low, high, warnings, integer)
    local value = tonumber(raw[key])
    if value == nil or value ~= value or value == math.huge or value == -math.huge then
        if raw[key] ~= nil then warning(warnings, key, "expected number; using default") end
        return default
    end
    local clamped = util.clamp(value, low, high)
    if integer then clamped = util.round(clamped) end
    if clamped ~= value then warning(warnings, key, "clamped to safe range") end
    return clamped
end

local function bool_value(value, default, warnings, key)
    if value == nil then return default end
    if type(value) == "boolean" then return value end
    if type(value) == "number" then return value ~= 0 end
    local text = tostring(value):lower()
    if text == "yes" or text == "true" or text == "1" or text == "on" then return true end
    if text == "no" or text == "false" or text == "0" or text == "off" then return false end
    warning(warnings, key, "expected boolean; using default")
    return default
end

local function valid_color(value)
    return type(value) == "string" and value:match("^#%x%x%x%x%x%x$") ~= nil
end

local function normalized_color(raw, key, default, warnings)
    local value = raw[key]
    if value == nil then return default end
    if not valid_color(value) then
        warning(warnings, key, "expected #RRGGBB; using default")
        return default
    end
    return value:upper()
end

local function expand_cache_dir(value, context)
    value = tostring(value or DEFAULTS.cache_dir)
    local config_dir = tostring(context.config_dir or "")
    if value:sub(1, 2) == "~~" then
        local suffix = value:sub(3):gsub("^[\\/]+", "")
        value = util.join_path(config_dir, suffix)
    end
    if context.platform == "windows" then return util.normalize_windows_path(value) end
    return value
end

function M.normalize(raw, context)
    raw = raw or {}
    context = context or {}
    local warnings = {}
    local result = copy_defaults()

    result.enabled = bool_value(raw.enabled, DEFAULTS.enabled, warnings, "enabled")
    result.startup_osd = bool_value(raw.startup_osd, DEFAULTS.startup_osd, warnings, "startup_osd")
    result.diagnostic_log = bool_value(raw.diagnostic_log, DEFAULTS.diagnostic_log, warnings, "diagnostic_log")
    local ffmpeg_path = tostring(raw.ffmpeg_path or DEFAULTS.ffmpeg_path):match("^%s*(.-)%s*$")
    if ffmpeg_path == "" then
        warning(warnings, "ffmpeg_path", "empty value; using default")
        ffmpeg_path = DEFAULTS.ffmpeg_path
    end
    result.ffmpeg_path = ffmpeg_path
    result.opacity = number_or_default(raw, "opacity", DEFAULTS.opacity, 0, 1, warnings, false)
    result.source_width = number_or_default(raw, "source_width", DEFAULTS.source_width, 256, 16384, warnings, true)
    result.source_height = number_or_default(raw, "source_height", DEFAULTS.source_height, 16, 512, warnings, true)
    result.displayed_height_ratio = number_or_default(raw, "displayed_height_ratio", DEFAULTS.displayed_height_ratio, 0.05, 1, warnings, false)
    result.reserved_marker_ratio = number_or_default(raw, "reserved_marker_ratio", DEFAULTS.reserved_marker_ratio, 0, 0.8, warnings, false)
    result.reserved_progress_px = number_or_default(raw, "reserved_progress_px", DEFAULTS.reserved_progress_px, 0, 64, warnings, true)
    result.minimum_timeline_width = number_or_default(raw, "minimum_timeline_width", DEFAULTS.minimum_timeline_width, 1, 16384, warnings, true)
    result.resize_debounce_ms = number_or_default(raw, "resize_debounce_ms", DEFAULTS.resize_debounce_ms, 0, 5000, warnings, true)
    result.mouse_update_interval_ms = number_or_default(raw, "mouse_update_interval_ms", DEFAULTS.mouse_update_interval_ms, 0, 1000, warnings, true)
    result.media_debounce_ms = number_or_default(raw, "media_debounce_ms", DEFAULTS.media_debounce_ms, 0, 5000, warnings, true)
    result.max_cache_age_days = number_or_default(raw, "max_cache_age_days", DEFAULTS.max_cache_age_days, 1, 3650, warnings, true)
    result.max_cache_mb = number_or_default(raw, "max_cache_mb", DEFAULTS.max_cache_mb, 64, 1048576, warnings, true)
    result.stale_lock_seconds = number_or_default(raw, "stale_lock_seconds", DEFAULTS.stale_lock_seconds, 30, 604800, warnings, true)
    result.lock_poll_ms = number_or_default(raw, "lock_poll_ms", DEFAULTS.lock_poll_ms, 100, 5000, warnings, true)
    result.analysis_sample_rate = number_or_default(raw, "analysis_sample_rate", DEFAULTS.analysis_sample_rate, 1000, 192000, warnings, true)
    result.generation_timeout_seconds = number_or_default(
        raw, "generation_timeout_seconds", DEFAULTS.generation_timeout_seconds, 0, 3600, warnings, true
    )
    result.overlay_id = number_or_default(raw, "overlay_id", DEFAULTS.overlay_id, 0, 63, warnings, true)

    local color_mode = tostring(raw.color_mode or DEFAULTS.color_mode):lower()
    if color_mode ~= "auto" and color_mode ~= "light" and color_mode ~= "dark" then
        warning(warnings, "color_mode", "expected auto, light, or dark; using default")
        color_mode = DEFAULTS.color_mode
    end
    result.color_mode = color_mode
    result.light_color = normalized_color(raw, "light_color", DEFAULTS.light_color, warnings)
    result.dark_color = normalized_color(raw, "dark_color", DEFAULTS.dark_color, warnings)
    local cache_dir = tostring(raw.cache_dir or DEFAULTS.cache_dir):match("^%s*(.-)%s*$")
    if cache_dir == "" then
        warning(warnings, "cache_dir", "empty value; using default")
        cache_dir = DEFAULTS.cache_dir
    end
    result.cache_dir = expand_cache_dir(cache_dir, context)
    local compatibility = tostring(raw.compatibility or DEFAULTS.compatibility):match("^%s*(.-)%s*$")
    result.compatibility = compatibility ~= "" and compatibility or DEFAULTS.compatibility
    result.adapter_override = tostring(raw.adapter_override or DEFAULTS.adapter_override):match("^%s*(.-)%s*$")
    local log_level = tostring(raw.log_level or DEFAULTS.log_level):lower():match("^%s*(.-)%s*$")
    if log_level ~= "error" and log_level ~= "warn" and log_level ~= "info"
        and log_level ~= "debug" then
        warning(warnings, "log_level", "expected error, warn, info, or debug; using default")
        log_level = DEFAULTS.log_level
    end
    result.log_level = log_level

    return result, warnings
end

local function trim(value)
    return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function strip_comment(line)
    local quote = nil
    local escaped = false
    for index = 1, #line do
        local character = line:sub(index, index)
        if escaped then
            escaped = false
        elseif character == "\\" and quote then
            escaped = true
        elseif character == '"' or character == "'" then
            if quote == character then quote = nil elseif not quote then quote = character end
        elseif character == "#" and not quote then
            if index == 1 or line:sub(index - 1, index - 1):match("%s") then
                return line:sub(1, index - 1)
            end
        end
    end
    return line
end

local function unquote(value)
    if #value >= 2 then
        local first, last = value:sub(1, 1), value:sub(-1)
        if (first == '"' and last == '"') or (first == "'" and last == "'") then
            return value:sub(2, -2)
        end
    end
    return value
end

function M.parse_key_value_file(text)
    local result = {}
    for line in tostring(text or ""):gmatch("[^\r\n]+") do
        line = trim(strip_comment(line))
        if line ~= "" and line:sub(1, 1) ~= "#" then
            local key, value = line:match("^([%w_.-]+)%s*=%s*(.-)%s*$")
            if key then result[key] = unquote(trim(value)) end
        end
    end
    return result
end


local function luminance(color)
    local ok, r, g, b = pcall(util.hex_to_rgb, color)
    if not ok then return nil end
    local function linear(channel)
        local value = channel / 255
        if value <= 0.04045 then return value / 12.92 end
        return ((value + 0.055) / 1.055) ^ 2.4
    end
    return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
end

local function extract_background(uosc_config, mpv_background)
    local explicit = uosc_config and uosc_config.background_color
    if type(explicit) == "string" then
        local hex = explicit:match("#?(%x%x%x%x%x%x)")
        if hex then return "#" .. hex end
    end
    local compound = uosc_config and uosc_config.color
    if type(compound) == "string" then
        local hex = compound:match("[%s,]background%s*=%s*#?(%x%x%x%x%x%x)")
            or compound:match("^background%s*=%s*#?(%x%x%x%x%x%x)")
        if hex then return "#" .. hex end
        local direct = compound:match("^#?(%x%x%x%x%x%x)$")
        if direct then return "#" .. direct end
    end
    if type(mpv_background) == "string" then
        local hex = mpv_background:match("#?(%x%x%x%x%x%x)")
        if hex then return "#" .. hex end
    end
    return "#000000"
end

function M.choose_waveform_color(opts, uosc_config, mpv_background)
    if opts.color_mode == "light" then return opts.light_color end
    if opts.color_mode == "dark" then return opts.dark_color end
    local background = extract_background(uosc_config or {}, mpv_background)
    local value = luminance(background) or 0
    if value >= 0.5 then return opts.light_color end
    return opts.dark_color
end

return M
