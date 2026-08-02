local root = assert(arg[1], "source root required")
package.path = table.concat({
    root .. "/portable_config/scripts/?.lua",
    root .. "/portable_config/scripts/?/init.lua",
    package.path,
}, ";")

local geometry = require("uosc_waveform.geometry")

local function approx(actual, expected, epsilon, message)
    epsilon = epsilon or 1e-6
    assert(math.abs(actual - expected) <= epsilon,
        string.format("%s: expected %.6f, got %.6f", message or "values differ", expected, actual))
end

local raw = {
    compatibility = "uosc-5.12",
    timeline_size = 40,
    timeline_border = 1,
    timeline_style = "line",
    progress = "windowed",
    progress_size = 2,
    window_border_size = 1,
    scale = 1,
    scale_fullscreen = 1.3,
    controls_size = 32,
    controls_margin = 8,
    controls_persistency = "",
    disable_elements = "controls",
    proximity_in = 40,
    proximity_out = 120,
}
local config = assert((geometry.parse_uosc(raw)))
local waveform = {
    minimum_timeline_width = 1,
    reserved_marker_ratio = 0,
    reserved_progress_px = 0,
    displayed_height_ratio = 1,
    source_height = 128,
}
local base = {
    osd_width = 1000,
    osd_height = 600,
    hidpi_scale = 1,
    fullscreen = false,
    maximized = false,
    mouse_x = 4,
    mouse_y = 350,
    mouse_hover = true,
    paused = false,
    media_type = "video",
}

local function with(values)
    local state = {}
    for key, value in pairs(base) do state[key] = value end
    for key, value in pairs(values or {}) do state[key] = value end
    return state
end

-- Outside proximity_out, uosc keeps only its minimized progress line. The
-- waveform must be absent rather than popping in at full height.
local hidden, hidden_reason = geometry.compute(config, with({ mouse_y = 350 }), waveform)
assert(hidden == nil and hidden_reason == "timeline-minimized",
    "far cursor must keep waveform hidden with the minimized uosc timeline")

-- uosc computes visibility continuously from signed cursor-to-rectangle
-- distance. At 79.5 px from the full timeline hitbox with in=40/out=120,
-- visibility is 0.50625 and effective size is progress + ceil(delta * v).
local partial = assert(geometry.compute(config, with({ mouse_y = 478 }), waveform))
approx(partial.visibility, 0.50625, 1e-6, "partial proximity visibility")
assert(partial.effective_timeline_size == 22,
    "effective timeline size must use uosc progress + ceil((size-progress)*visibility)")
assert(partial.height == 18, "waveform must preserve symmetric progress clearance while expanding")
assert(partial.y == 579, "partial waveform must remain centered in the animated timeline")

-- Inside the timeline hitbox, visibility is exactly 1 and final geometry must
-- remain identical to the already validated full-height placement.
local full = assert(geometry.compute(config, with({ mouse_y = 590 }), waveform))
approx(full.visibility, 1, 0, "inside visibility")
assert(full.effective_timeline_size == 40, "inside timeline must fully expand")
assert(full.y == 561 and full.height == 36, "full geometry must stay vertically centered with symmetric progress clearance")

-- Timeline visibility inherits Controls visibility in uosc. Use a deliberately
-- tiny timeline proximity range so only the controls rectangle can reveal it.
local controls_config = assert((geometry.parse_uosc({
    compatibility = "uosc-5.12",
    timeline_size = 40,
    timeline_border = 1,
    progress = "windowed",
    progress_size = 2,
    window_border_size = 1,
    controls_size = 32,
    controls_margin = 8,
    proximity_in = 0,
    proximity_out = 10,
})))
local inherited = assert(geometry.compute(controls_config, with({ mouse_x = 500, mouse_y = 530 }), waveform))
approx(inherited.visibility, 1, 0, "controls inherited visibility")
assert(inherited.visibility_source == "controls", "controls must be reported as the winning visibility source")

-- Persistency is also inherited from controls by Timeline:get_visibility().
local persistent_config = assert((geometry.parse_uosc({
    compatibility = "uosc-5.12",
    timeline_size = 40,
    timeline_border = 1,
    progress = "windowed",
    progress_size = 2,
    window_border_size = 1,
    controls_size = 32,
    controls_margin = 8,
    controls_persistency = "paused",
    proximity_in = 40,
    proximity_out = 120,
})))
local persistent = assert(geometry.compute(persistent_config, with({ mouse_x = 500, mouse_y = 300, paused = true }), waveform))
approx(persistent.visibility, 1, 0, "controls persistency visibility")
assert(persistent.visibility_source == "controls-persistency",
    "controls persistency must reveal timeline exactly like uosc")

-- mouse.hover=false is the same leave signal uosc uses to reset proximity.
local left, left_reason = geometry.compute(config, with({ mouse_y = 590, mouse_hover = false }), waveform)
assert(left == nil and left_reason == "timeline-minimized", "mouse leave must reset proximity")

-- On cursor leave uosc temporarily assigns forced_visibility and exponentially
-- tweens it to zero. The waveform adapter must accept the same intermediate
-- visibility even though mouse.hover is already false.
local fading = assert(geometry.compute(config, with({
    mouse_y = 590, mouse_hover = false, forced_visibility = 0.5,
}), waveform))
approx(fading.visibility, 0.5, 1e-6, "forced cursor-leave visibility")
assert(fading.visibility_source == "forced", "forced visibility must win while cursor-leave tween is active")
assert(fading.effective_timeline_size == 21,
    "forced visibility must use uosc effective-size calculation")


-- uosc only enables WindowBorder while windowed and native mpv decorations are
-- disabled. Native-border, fullscreen and maximized layouts must not inherit
-- the configured custom inset.
local native_border = assert(geometry.compute(config, with({ border = true, title_bar = true, mouse_y = 590 }), waveform))
assert(native_border.x == 0 and native_border.width == 1000,
    "native mpv borders must disable uosc's custom window-border inset")
assert(native_border.y == 562 and native_border.height == 36,
    "native-border geometry must remain symmetrically centered at the actual OSD bottom")

local fullscreen = assert(geometry.compute(config, with({
    border = false, title_bar = false, fullscreen = true, mouse_y = 590,
}), waveform))
assert(fullscreen.x == 0 and fullscreen.width == 1000,
    "fullscreen geometry must not reserve the windowed custom border")
assert(fullscreen.effective_timeline_size == 52,
    "fullscreen geometry must apply uosc scale_fullscreen")

-- Timeline:decide_enabled() marks the timeline obstructed when an enabled top
-- bar leaves less than timeline_size + 10 px. Mirror that conservative hide.
local tiny_config = assert((geometry.parse_uosc({
    compatibility = "uosc-5.12",
    timeline_size = 40,
    timeline_border = 1,
    progress = "windowed",
    progress_size = 2,
    window_border_size = 1,
    top_bar = "no-border",
    top_bar_size = 40,
    top_bar_controls = "right",
    top_bar_title = "yes",
    controls_size = 0,
    proximity_in = 40,
    proximity_out = 120,
})))
local obstructed, obstructed_reason = geometry.compute(tiny_config, with({
    osd_height = 85, border = false, title_bar = false, mouse_y = 80,
}), waveform)
assert(obstructed == nil and obstructed_reason == "timeline-obstructed",
    "waveform must hide when uosc disables an obstructed timeline")

local no_top_config = assert((geometry.parse_uosc({
    compatibility = "uosc-5.12",
    timeline_size = 40,
    timeline_border = 1,
    progress = "windowed",
    progress_size = 2,
    window_border_size = 1,
    top_bar = "never",
    top_bar_size = 40,
    controls_size = 0,
    proximity_in = 40,
    proximity_out = 120,
})))
local unobstructed = assert(geometry.compute(no_top_config, with({
    osd_height = 85, border = false, title_bar = false, mouse_y = 80,
}), waveform))
assert(unobstructed.height > 0, "disabled top bar must not falsely obstruct the timeline")


-- Disabled uosc elements must not leave phantom geometry reservations.
local disabled_decor_config = assert((geometry.parse_uosc({
    compatibility = "uosc-5.12",
    timeline_size = 40,
    timeline_border = 1,
    progress = "windowed",
    progress_size = 2,
    window_border_size = 7,
    top_bar = "always",
    top_bar_size = 40,
    disable_elements = "window_border,top_bar,controls",
    proximity_in = 40,
    proximity_out = 120,
})))
local disabled_decor = assert(geometry.compute(disabled_decor_config, with({
    osd_height = 55, border = false, title_bar = false, mouse_y = 50,
}), waveform))
assert(disabled_decor.x == 0 and disabled_decor.width == 1000,
    "disabled window_border must not inset the waveform")
assert(disabled_decor.height > 0,
    "disabled top_bar must not falsely mark the timeline obstructed")

print("PASS geometry_proximity")
