local root = assert(arg[1], "source root required")
local peak_metadata = assert(loadfile(root .. "/tests/helpers/peak_metadata.lua"))()
package.path = root .. "/portable_config/scripts/?.lua;" .. root .. "/portable_config/scripts/?/init.lua;" .. package.path

local observers, events, async_callbacks = {}, {}, {}
local source = "/tmp/song.flac"
local props = {
    path = source,
    ["stream-open-filename"] = source,
    duration = 10,
    aid = 1,
    edition = 0,
    ["audio-delay"] = 0,
    ["track-list"] = {
        { type = "video", id = 2, selected = true, image = true, albumart = true, ["ff-index"] = 0 },
        { type = "audio", id = 1, selected = true, ["main-selection"] = 0, ["ff-index"] = 1 },
    },
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
local files = {}
local expected_size = 256 * 16 * 4
local fs = {
    info = function(path)
        if path == source then return { size = 100, mtime = 1, is_file = true, is_dir = false } end
        if files[path] then return { size = #files[path], mtime = 2, is_file = true, is_dir = false } end
    end,
    size = function(path) return files[path] and #files[path] or nil end,
    mtime = function(path) return files[path] and 2 or nil end,
    exists = function(path) return files[path] ~= nil end,
    read = function(path) return files[path] end,
    write = function(path, content) files[path] = content; return true end,
    create_exclusive = function(path, content) files[path] = content; return true end,
    remove = function(path) files[path] = nil; return true end,
    rename = function(a, b) files[b] = files[a]; files[a] = nil; return true end,
    mkdir = function() return true end,
    list = function() return {} end,
}

local controller = require("uosc_waveform.controller")
local app = controller.start({
    mp = mp,
    fs = fs,
    raw_options = { cache_dir = "/tmp/cache", media_debounce_ms = 0, resize_debounce_ms = 0, source_width = 256, source_height = 16, generation_timeout_seconds = 0 },
    context = { config_dir = "/tmp", platform = "other" },
    uosc_config = { controls_size = 0 },
    uosc_detected = true,
})
assert(events["file-loaded"], "file-loaded must be registered")
events["file-loaded"]()
assert(app:debug_state().state == "GENERATING", "audio-only file must start waveform generation")
assert(#async_callbacks == 1, "audio-only file must launch FFmpeg")
local argv = async_callbacks[1].command.args
local filter
for i, value in ipairs(argv) do if value == "-filter_complex" then filter = argv[i + 1] end end
assert(filter and filter:find("%[0:1%]"), "audio-only file with cover art must map the audio ff-index")

async_callbacks[1].callback(true, { status = 0, success = true, stdout = peak_metadata(256, 10), stderr = "" }, nil)
local final = app:debug_state()
assert(final.state == "READY_VISIBLE", "audio-only waveform must become visible on uosc seekbar")
assert(final.raw ~= nil, "audio-only waveform must publish a cache payload")

print("PASS controller_audio_only")
