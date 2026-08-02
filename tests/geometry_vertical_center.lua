local root = assert(arg[1], "source root required")
package.path = table.concat({
    root .. "/portable_config/scripts/?.lua",
    root .. "/portable_config/scripts/?/init.lua",
    package.path,
}, ";")

local geometry = require("uosc_waveform.geometry")
local config = assert((geometry.parse_uosc({
    compatibility = "uosc-5.12",
    timeline_size = 40,
    timeline_border = 1,
    progress = "windowed",
    progress_size = 2,
    window_border_size = 0,
    controls_size = 0,
    proximity_in = 40,
    proximity_out = 120,
})))
local waveform = {
    minimum_timeline_width = 1,
    reserved_marker_ratio = 0.20,
    reserved_progress_px = 2,
    displayed_height_ratio = 0.78,
    source_height = 128,
}
local function state(mouse_y, overrides)
    local value = {
        osd_width = 1000,
        osd_height = 600,
        hidpi_scale = 1,
        fullscreen = false,
        maximized = false,
        border = true,
        title_bar = true,
        mouse_x = 500,
        mouse_y = mouse_y,
        mouse_hover = true,
        paused = false,
        media_type = "video",
    }
    for key, item in pairs(overrides or {}) do value[key] = item end
    return value
end
local function assert_centered(rect, label, bottom)
    bottom = bottom or 600
    local effective_top = bottom - rect.effective_timeline_size
    local top_margin = rect.y - effective_top
    local bottom_margin = bottom - (rect.y + rect.height)
    assert(top_margin == bottom_margin,
        string.format("%s must be vertically centered: top=%d bottom=%d", label, top_margin, bottom_margin))
    assert(rect.source_crop_top == 0 and rect.source_crop_height == 128,
        label .. " must preserve the complete source waveform")
end

assert_centered(assert(geometry.compute(config, state(590), waveform)), "full timeline")
assert_centered(assert(geometry.compute(config, state(478), waveform)), "partial timeline")
local hidpi = assert(geometry.compute(config, state(880, {
    osd_height = 900, hidpi_scale = 1.5, mouse_y = 880,
}), waveform))
assert_centered(hidpi, "HiDPI timeline", 900)
local fullscreen = assert(geometry.compute(config, state(880, {
    osd_height = 900, fullscreen = true, mouse_y = 880,
}), waveform))
assert_centered(fullscreen, "fullscreen timeline", 900)
print("PASS geometry_vertical_center")
