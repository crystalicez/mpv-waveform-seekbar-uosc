local root = assert(arg[1], "source root required")
package.path = root .. "/portable_config/scripts/?.lua;" .. root .. "/portable_config/scripts/?/init.lua;" .. package.path

local observers, events, async_callbacks = {}, {}, {}
local source = "/tmp/song.m4a"
local props = {
    path = source,
    ["stream-open-filename"] = source,
    duration = 10,
    aid = "auto",
    edition = 0,
    ["audio-delay"] = 0,
    ["track-list"] = {},
    ["demuxer-start-time"] = 0,
    ["rebase-start-time"] = true,
    ["background-color"] = "#000000",
    ["osd-width"] = 1000,
    ["osd-height"] = 600,
    ["display-hidpi-scale"] = 1,
    ["mouse-pos"] = { x = 500, y = 590, hover = true },
    border = true,
    ["title-bar"] = true,
}
local mp = {
    get_property_native = function(name, default)
        local value = props[name]
        if value == nil then return default end
        return value
    end,
    observe_property = function(name, _, callback) observers[name] = callback end,
    register_event = function(name, callback) events[name] = callback end,
    register_script_message = function() end,
    add_key_binding = function() end,
    command_native = function() return true end,
    command_native_async = function(command, callback)
        async_callbacks[#async_callbacks + 1] = { command = command, callback = callback }
        return #async_callbacks
    end,
    abort_async_command = function() end,
    msg = { info=function() end, warn=function() end, debug=function() end, error=function() end },
}
local fs = {
    info = function(path)
        if path == source then return { size = 100, mtime = 1, is_file = true, is_dir = false } end
    end,
    size = function() return nil end,
    mtime = function() return nil end,
    exists = function() return false end,
    read = function() return nil end,
    write = function() return true end,
    create_exclusive = function() return true end,
    remove = function() return true end,
    rename = function() return true end,
    mkdir = function() return true end,
    list = function() return {} end,
}

local controller = require("uosc_waveform.controller")
local app = controller.start({
    mp = mp,
    fs = fs,
    raw_options = { cache_dir = "/tmp/cache", media_debounce_ms = 0, resize_debounce_ms = 0 },
    context = { config_dir = "/tmp", platform = "other" },
    uosc_config = { controls_size = 0 },
    uosc_detected = true,
})

assert(events["file-loaded"], "file-loaded event must be registered")
events["file-loaded"]()
assert(app:debug_state().state == "UNSUPPORTED", "empty early track-list must be transiently unsupported")

props.aid = 1
props["track-list"] = {
    { type = "audio", id = 1, selected = true, ["main-selection"] = 0, ["ff-index"] = 0 },
}
assert(events["playback-restart"], "controller must retry media inspection at playback-restart")
events["playback-restart"]()
assert(app:debug_state().state == "GENERATING", "late audio selection must start waveform generation")
assert(#async_callbacks == 1, "late audio selection must launch FFmpeg exactly once")
events["playback-restart"]()
assert(#async_callbacks == 1, "playback-restart must not rescan once media is generating or ready")
print("PASS controller_audio_playback_restart")
