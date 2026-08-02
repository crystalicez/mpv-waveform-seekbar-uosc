local root = assert(arg[1], "source root required")
package.path = table.concat({
    root .. "/portable_config/scripts/?.lua",
    root .. "/portable_config/scripts/?/init.lua",
    package.path,
}, ";")

local started = 0
local external_levels = {}
local events = {}
local props = {
    path = [[C:\Media\clip.mkv]],
    ["stream-open-filename"] = [[C:\Media\clip.mkv]],
    duration = 120,
    aid = 1,
    edition = 0,
    ["track-list"] = {
        { type = "video", selected = true, id = 1 },
        { type = "audio", selected = true, id = 1, ["ff-index"] = 1 },
    },
    ["demuxer-start-time"] = 0,
    ["background-color"] = "#000000",
}
local mp = {
    get_property_native = function(name, default) local v = props[name]; if v == nil then return default end; return v end,
    observe_property = function() end,
    register_event = function(name, callback) events[name] = callback end,
    register_script_message = function() end,
    add_key_binding = function() end,
    command_native = function() return true end,
    command_native_async = function() started = started + 1; return started end,
    abort_async_command = function() end,
    msg = { info = function() end, warn = function() end, debug = function() end },
}
local fs = {
    info = function(path)
        if path == props.path then return { size = 1000, mtime = 123, is_file = true, is_dir = false } end
        return nil
    end,
    size = function() return nil end,
    mtime = function() return nil end,
    exists = function() return false end,
    read = function() return nil end,
    create_exclusive = function() return false, "powershell-exit-1" end,
    remove = function() return true end,
    mkdir = function() return true end,
    list = function() return {} end,
}
local controller = require("uosc_waveform.controller")
local app = controller.start({
    mp = mp,
    fs = fs,
    now = function() return 1000 end,
    session_id = "test-session",
    raw_options = { cache_dir = [[C:\Cache]], media_debounce_ms = 0 },
    context = { config_dir = [[C:\Config]], platform = "windows" },
    uosc_config = { timeline_size = 40 },
    uosc_detected = true,
    external_log = function(level) external_levels[#external_levels + 1] = level end,
})

events["file-loaded"]()
assert(started == 1, "lock failure without an active lock must not block ffmpeg")
assert(app:debug_state().state == controller.STATES.GENERATING, "lock failure must fail open")
for _, level in ipairs(external_levels) do
    assert(level == "warn" or level == "error", "default log_level=warn must suppress info/debug disk logs")
end
assert(#external_levels >= 1, "lock failure warning should remain visible at warn level")
print("PASS controller_lock_fail_open")
