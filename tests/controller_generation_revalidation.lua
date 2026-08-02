local root = assert(arg[1], "source root required")
package.path = table.concat({
    root .. "/portable_config/scripts/?.lua",
    root .. "/portable_config/scripts/?/init.lua",
    package.path,
}, ";")

local source = [[C:\Media\multi.mkv]]
local events, async_callback = {}, nil
local props = {
    path = source,
    ["stream-open-filename"] = source,
    duration = 120,
    aid = 1,
    edition = 0,
    ["track-list"] = {
        { type = "audio", id = 1, selected = true, ["ff-index"] = 1 },
    },
    ["demuxer-start-time"] = 0,
    ["background-color"] = "#000000",
}
local mp = {
    get_property_native = function(name, default)
        local value = props[name]
        if value == nil then return default end
        return value
    end,
    observe_property = function() end,
    register_event = function(name, callback) events[name] = callback end,
    register_script_message = function() end,
    add_key_binding = function() end,
    command_native = function() return true end,
    command_native_async = function(_, callback) async_callback = callback; return 1 end,
    abort_async_command = function() end,
    msg = { info = function() end, warn = function() end, debug = function() end },
}
local files = {}
local fs = {
    info = function(path)
        if path == source or path == source:lower() then return { size = 1000, mtime = 123, is_file = true, is_dir = false } end
        local content = files[path]
        if content then return { size = #content, mtime = 123, is_file = true, is_dir = false } end
        return nil
    end,
    size = function(path) local value = files[path]; return value and #value or nil end,
    mtime = function() return 123 end,
    exists = function(path) return files[path] ~= nil end,
    read = function(path) return files[path] end,
    create_exclusive = function() return false, "disabled" end,
    remove = function(path) files[path] = nil; return true end,
    rename = function(src, dst) files[dst] = files[src]; files[src] = nil; return true end,
    mkdir = function() return true end,
    list = function() return {} end,
}

local controller = require("uosc_waveform.controller")
local app = controller.start({
    mp = mp,
    fs = fs,
    now = function() return 1000 end,
    session_id = "revalidate",
    raw_options = {
        cache_dir = [[C:\Cache]],
        media_debounce_ms = 0,
        resize_debounce_ms = 0,
        source_width = 256,
        source_height = 16,
    },
    context = { config_dir = [[C:\Config]], platform = "windows" },
    uosc_config = { timeline_size = 40 },
    uosc_detected = true,
})

events["file-loaded"]()
assert(async_callback, "generation must start")
local before = app:debug_state()
files[before.active_temp] = string.rep("\0", before.expected_size)

-- Same mpv track ID, but the demux-to-FFmpeg mapping changed before the async
-- job completed. Publishing that result would associate the old stream with
-- the new track identity.
props["track-list"] = {
    { type = "audio", id = 1, selected = true, ["ff-index"] = 2 },
}
async_callback(true, { status = 0, stdout = "", stderr = "" }, nil)
local after = app:debug_state()
assert(after.state == controller.STATES.UNSUPPORTED, "changed stream mapping must reject the completed generation")
assert(after.raw == nil, "stale audio-track output must not be published")
assert(not files[before.paths.raw], "stale audio-track output must not enter the shared cache")

print("PASS controller_generation_revalidation")
