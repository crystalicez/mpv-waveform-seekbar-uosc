local util = require("uosc_waveform.util")

local M = {}

local ADAPTERS = { ["uosc-5.12"] = true }

local DEFAULTS = {
    compatibility = "uosc-5.12",
    timeline_size = 40,
    timeline_border = 1,
    timeline_style = "line",
    timeline_line_width = 2,
    timeline_persistency = "",
    progress = "windowed",
    progress_size = 2,
    progress_line_width = 20,
    controls_size = 32,
    controls_margin = 8,
    controls_persistency = "",
    autohide = false,
    top_bar = "no-border",
    top_bar_size = 40,
    top_bar_controls = "right",
    top_bar_title = "yes",
    proximity_in = 40,
    proximity_out = 120,
    animation_duration = 100,
    window_border_size = 1,
    scale = 1,
    scale_fullscreen = 1.3,
}

local function parse_number(raw, key, default, low, high, warnings)
    local value = raw[key]
    if value == nil or value == "" then return default, true end
    value = tonumber(value)
    if not value or value ~= value or value == math.huge or value == -math.huge then
        warnings[#warnings + 1] = key .. ": expected number"
        return default, false
    end
    if value < low or value > high then
        warnings[#warnings + 1] = key .. ": outside supported range"
        return util.clamp(value, low, high), false
    end
    return value, true
end


local function parse_boolean(raw, key, default, warnings)
    local value = raw[key]
    if value == nil or value == "" then return default end
    if type(value) == "boolean" then return value end
    if type(value) == "number" then return value ~= 0 end
    local text = tostring(value):lower()
    if text == "yes" or text == "true" or text == "1" or text == "on" then return true end
    if text == "no" or text == "false" or text == "0" or text == "off" then return false end
    warnings[#warnings + 1] = key .. ": expected boolean"
    return default
end

local function parse_tokens(value)
    local result = {}
    for token in tostring(value or ""):gmatch("[^,%s]+") do result[token:lower()] = true end
    return result
end

function M.parse_uosc(raw)
    raw = raw or {}
    local warnings = {}
    local valid = true
    local function number(key, default, low, high)
        local value, ok = parse_number(raw, key, default, low, high, warnings)
        valid = valid and ok
        return value
    end

    local style = tostring(raw.timeline_style or DEFAULTS.timeline_style):lower()
    if style ~= "bar" and style ~= "line" then
        warnings[#warnings + 1] = "timeline_style: expected bar or line"
        style = DEFAULTS.timeline_style
        valid = false
    end
    local progress = tostring(raw.progress or DEFAULTS.progress):lower()
    if progress ~= "always" and progress ~= "never" and progress ~= "windowed" and progress ~= "fullscreen" then
        warnings[#warnings + 1] = "progress: unsupported value"
        progress = DEFAULTS.progress
        valid = false
    end

    local proximity_in = number("proximity_in", DEFAULTS.proximity_in, 0, 4096)
    local proximity_out = number("proximity_out", DEFAULTS.proximity_out, 0, 8192)
    if proximity_out <= proximity_in then
        proximity_out = proximity_in + 1
        warnings[#warnings + 1] = "proximity_out: raised above proximity_in"
    end

    local timeline_persistency = tostring(raw.timeline_persistency or DEFAULTS.timeline_persistency)
    local controls_persistency = tostring(raw.controls_persistency or DEFAULTS.controls_persistency)
    local top_bar = tostring(raw.top_bar or DEFAULTS.top_bar):lower()
    if top_bar ~= "never" and top_bar ~= "no-border" and top_bar ~= "always" then
        warnings[#warnings + 1] = "top_bar: unsupported value"
        top_bar = DEFAULTS.top_bar
        valid = false
    end
    local top_bar_controls = tostring(raw.top_bar_controls or DEFAULTS.top_bar_controls):lower()
    if top_bar_controls == "yes" then
        top_bar_controls = "right"
    elseif top_bar_controls ~= "left" and top_bar_controls ~= "right"
        and top_bar_controls ~= "no" and top_bar_controls ~= "" then
        warnings[#warnings + 1] = "top_bar_controls: unsupported value"
        top_bar_controls = "no"
    end
    local config = {
        adapter = tostring(raw.compatibility or raw.adapter or DEFAULTS.compatibility),
        valid = valid,
        timeline_size = number("timeline_size", DEFAULTS.timeline_size, 0, 512),
        timeline_border = number("timeline_border", DEFAULTS.timeline_border, 0, 64),
        timeline_style = style,
        timeline_line_width = number("timeline_line_width", DEFAULTS.timeline_line_width, 1, 64),
        timeline_persistency = timeline_persistency,
        persistency = parse_tokens(timeline_persistency),
        progress = progress,
        progress_size = number("progress_size", DEFAULTS.progress_size, 0, 64),
        progress_line_width = number("progress_line_width", DEFAULTS.progress_line_width, 0, 100),
        controls_size = number("controls_size", DEFAULTS.controls_size, 0, 512),
        controls_margin = number("controls_margin", DEFAULTS.controls_margin, 0, 256),
        controls_persistency = controls_persistency,
        controls_persistency_tokens = parse_tokens(controls_persistency),
        autohide = parse_boolean(raw, "autohide", DEFAULTS.autohide, warnings),
        top_bar = top_bar,
        top_bar_size = number("top_bar_size", DEFAULTS.top_bar_size, 0, 512),
        top_bar_controls = top_bar_controls ~= "no" and top_bar_controls ~= "",
        top_bar_title = tostring(raw.top_bar_title or DEFAULTS.top_bar_title),
        proximity_in = proximity_in,
        proximity_out = proximity_out,
        animation_duration = number("animation_duration", DEFAULTS.animation_duration, 0, 10000),
        window_border_size = number("window_border_size", DEFAULTS.window_border_size, 0, 128),
        scale = number("scale", DEFAULTS.scale, 0.1, 8),
        scale_fullscreen = number("scale_fullscreen", DEFAULTS.scale_fullscreen, 0.1, 8),
        disabled = parse_tokens(raw.disable_elements or ""),
    }
    config.valid = valid
    return config, warnings
end

local function positive_dimensions(state)
    local width, height = tonumber(state.osd_width), tonumber(state.osd_height)
    return width and height and width > 0 and height > 0
end

local function progress_visible(config, state)
    local fullormaxed = state.fullscreen == true or state.maximized == true
    if config.progress == "always" then return true end
    if config.progress == "never" then return false end
    if config.progress == "fullscreen" then return fullormaxed end
    return not fullormaxed
end


local function top_bar_enabled(config, state)
    if config.disabled and config.disabled.top_bar then return false end
    local has_content = config.top_bar_controls
        or tostring(config.top_bar_title or "yes") ~= "no"
        or (tonumber(state.playlist_count) or 0) > 1
    if not has_content then return false end
    if config.top_bar == "always" then return true end
    if config.top_bar ~= "no-border" then return false end
    return state.border ~= true or state.title_bar == false or state.fullscreen == true
end

local function persistency_evidence(tokens, state)
    tokens = tokens or {}
    local fullormaxed = state.fullscreen == true or state.maximized == true
    if state.paused and tokens.paused then return true end
    if fullormaxed and tokens.fullscreen then return true end
    if not fullormaxed and tokens.windowed then return true end
    if state.media_type and tokens[state.media_type] then return true end
    return false
end

-- Exact signed point-to-rectangle distance used by uosc's Element:update_proximity().
-- Negative values mean the cursor is inside the rectangle.
local function point_to_rectangle_proximity(point, rect)
    local dx = math.max(rect.ax - point.x, point.x - rect.bx)
    local dy = math.max(rect.ay - point.y, point.y - rect.by)
    local distance = math.sqrt(math.max(0, dx) ^ 2 + math.max(0, dy) ^ 2)
    return distance + math.min(0, math.max(dx, dy))
end

local function proximity_visibility(config, state, rect)
    if state.mouse_hover == false then return 0, math.huge end
    local x, y = tonumber(state.mouse_x), tonumber(state.mouse_y)
    if not x or not y then return 0, math.huge end
    -- uosc places the cursor in the middle of the reported pixel.
    local point = { x = x + 0.5, y = y + 0.5 }
    local raw = point_to_rectangle_proximity(point, rect)
    local range = config.proximity_out - config.proximity_in
    local visibility = 1 - (util.clamp(raw - config.proximity_in, 0, range) / range)
    return visibility, raw
end

local function visibility(config, state, timeline_rect, controls_rect)
    if state.timeline_expanded_hint == true then return 1, "hint", nil, nil end

    local forced = tonumber(state.forced_visibility)
    if forced ~= nil then forced = util.clamp(forced, 0, 1) end

    local timeline_visibility, timeline_source, timeline_raw
    if persistency_evidence(config.persistency, state) then
        timeline_visibility, timeline_source, timeline_raw = 1, "timeline-persistency", nil
    elseif forced ~= nil then
        timeline_visibility, timeline_source, timeline_raw = forced, "forced", nil
    else
        timeline_visibility, timeline_raw = proximity_visibility(config, state, timeline_rect)
        timeline_source = "timeline"
    end

    local controls_visibility, controls_raw = 0, math.huge
    local controls_source = "controls"
    if not (config.disabled and config.disabled.controls) and config.controls_size > 0 then
        if persistency_evidence(config.controls_persistency_tokens, state) then
            controls_visibility, controls_source = 1, "controls-persistency"
        elseif forced ~= nil then
            controls_visibility, controls_source, controls_raw = forced, "forced", nil
        else
            controls_visibility, controls_raw = proximity_visibility(config, state, controls_rect)
        end
    end

    if controls_visibility > timeline_visibility then
        return controls_visibility, controls_source, timeline_raw, controls_raw
    end
    return timeline_visibility, timeline_source, timeline_raw, controls_raw
end

function M.compute(config, state, waveform_opts)
    config = config or {}
    state = state or {}
    waveform_opts = waveform_opts or {}
    if not ADAPTERS[config.adapter] then return nil, "unsupported-adapter" end
    if config.valid == false then return nil, "malformed-uosc-config" end
    if config.disabled and config.disabled.timeline then return nil, "timeline-disabled" end
    if not positive_dimensions(state) then return nil, "invalid-osd-size" end
    if state.menu_open and state.menu_obstructs_timeline ~= false then return nil, "menu-obstructs-timeline" end

    local hidpi = tonumber(state.hidpi_scale) or 1
    if hidpi <= 0 then hidpi = 1 end
    local fullormaxed = state.fullscreen == true or state.maximized == true
    local configured_scale = fullormaxed and tonumber(config.scale_fullscreen) or tonumber(config.scale)
    configured_scale = configured_scale or 1
    local ui_scale = hidpi * configured_scale

    local timeline_px = util.round(config.timeline_size * ui_scale)
    local top_border_px = util.round(config.timeline_border * ui_scale)
    -- uosc only draws its custom border while windowed and native mpv border
    -- is disabled. Fullscreen/maximized/native-border layouts use zero inset.
    local window_border_enabled = not (config.disabled and config.disabled.window_border)
        and not fullormaxed and state.border ~= true
    local window_border_px = window_border_enabled and util.round(config.window_border_size * ui_scale) or 0
    local width = util.round(state.osd_width) - window_border_px * 2
    if width < (tonumber(waveform_opts.minimum_timeline_width) or 320) then return nil, "timeline-too-narrow" end
    if timeline_px <= 0 then return nil, "timeline-disabled" end

    -- Timeline:decide_enabled() disables the element if the top bar and window
    -- borders leave less than timeline_size + 10 px of vertical space.
    local top_bar_px = top_bar_enabled(config, state) and util.round(config.top_bar_size * ui_scale) or 0
    local available_space = util.round(state.osd_height) - window_border_px * 2 - top_bar_px
    if available_space < timeline_px + 10 then return nil, "timeline-obstructed" end

    local bottom = util.round(state.osd_height) - window_border_px
    local timeline_rect = {
        ax = window_border_px,
        ay = bottom - timeline_px - top_border_px,
        bx = util.round(state.osd_width) - window_border_px,
        by = bottom,
    }
    local controls_margin_px = util.round(config.controls_margin * ui_scale)
    local controls_size_px = util.round(config.controls_size * ui_scale)
    local controls_rect = {
        ax = window_border_px + controls_margin_px,
        ay = timeline_rect.ay - controls_margin_px - controls_size_px,
        bx = util.round(state.osd_width) - window_border_px - controls_margin_px,
        by = timeline_rect.ay - controls_margin_px,
    }

    local visibility_value, visibility_source, timeline_raw, controls_raw =
        visibility(config, state, timeline_rect, controls_rect)

    local configured_progress_px = progress_visible(config, state) and util.round(config.progress_size * ui_scale) or 0
    local effective_size = configured_progress_px
        + math.ceil((timeline_px - configured_progress_px) * visibility_value)

    -- With visibility 0 uosc only draws the minimized progress line. The waveform
    -- stays absent until there is actual expanded content to inhabit.
    if visibility_value <= 0 or effective_size <= configured_progress_px then
        return nil, "timeline-minimized"
    end

    local reserved_progress_px = util.round((tonumber(waveform_opts.reserved_progress_px) or 0) * ui_scale)
    local progress_px = math.max(configured_progress_px, reserved_progress_px)

    local marker_ratio = util.clamp(tonumber(waveform_opts.reserved_marker_ratio) or 0, 0, 0.8)
    local full_marker_px = util.round(timeline_px * marker_ratio)
    local marker_px = util.round(full_marker_px * visibility_value)

    -- Marker clearance used to be reserved only above the waveform while the
    -- progress line was reserved only below it. That made the waveform look
    -- lower than the visual center of uosc's timeline. Use the larger reserve
    -- as a symmetric inset, preserving both clearances while keeping equal
    -- empty space above and below throughout the proximity animation.
    local symmetric_inset = math.max(marker_px, progress_px)
    local available = effective_size - symmetric_inset * 2
    if available <= 2 then return nil, "timeline-too-thin" end

    local height_ratio = util.clamp(tonumber(waveform_opts.displayed_height_ratio) or 1, 0.05, 1)
    local height = math.max(1, util.round(available * height_ratio))
    height = math.min(height, available)
    -- Match parity with the effective timeline so the two margins can be
    -- exactly equal in integer overlay coordinates instead of differing by 1px.
    if (effective_size - height) % 2 ~= 0 then
        if height > 1 then height = height - 1 else height = math.min(available, height + 1) end
    end
    local effective_top = bottom - effective_size
    local y = effective_top + math.floor((effective_size - height) / 2)

    local source_height = math.max(1, util.round(tonumber(waveform_opts.source_height) or 128))
    -- Do not crop the source waveform vertically. We already reserve chapter/marker
    -- space in destination geometry above, so cropping here would clip waveform peaks
    -- a second time and make the top look flattened.
    local source_crop_top = 0
    local source_crop_height = source_height

    return {
        x = window_border_px,
        y = y,
        width = width,
        height = height,
        source_crop_top = source_crop_top,
        source_crop_height = source_crop_height,
        scale = ui_scale,
        visibility = visibility_value,
        visibility_source = visibility_source,
        effective_timeline_size = effective_size,
        timeline_proximity_raw = timeline_raw,
        controls_proximity_raw = controls_raw,
    }
end

M.ADAPTERS = ADAPTERS
M.point_to_rectangle_proximity = point_to_rectangle_proximity

return M
