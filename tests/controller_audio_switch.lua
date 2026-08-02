local root = assert(arg[1], "source root required")
package.path = table.concat({
    root .. "/portable_config/scripts/?.lua",
    root .. "/portable_config/scripts/?/init.lua",
    package.path,
}, ";")

local pending_timers, observers, events = {}, {}, {}
local commands, callbacks, cancelled = {}, {}, 0
local source = [[C:\Media\multi.mkv]]
local props = {
    path = source,
    ["stream-open-filename"] = source,
    duration = 120,
    aid = 1,
    edition = 0,
    ["track-list"] = {
        { type = "video", id = 1, selected = true, ["ff-index"] = 0 },
        { type = "audio", id = 1, selected = true, ["ff-index"] = 1 },
        { type = "audio", id = 2, selected = false, ["ff-index"] = 2 },
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
    observe_property = function(name, _, callback) observers[name] = callback end,
    register_event = function(name, callback) events[name] = callback end,
    register_script_message = function() end,
    add_key_binding = function() end,
    add_timeout = function(_, callback)
        local timer = { callback = callback, dead = false }
        function timer:kill() self.dead = true end
        pending_timers[#pending_timers + 1] = timer
        return timer
    end,
    command_native = function() return true end,
    command_native_async = function(command, callback)
        commands[#commands + 1] = command
        callbacks[#callbacks + 1] = callback
        return #commands
    end,
    abort_async_command = function() cancelled = cancelled + 1 end,
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
    create_exclusive = function() return false, "lock-disabled-for-test" end,
    remove = function(path) files[path] = nil; return true end,
    rename = function(src, dst) files[dst] = files[src]; files[src] = nil; return true end,
    mkdir = function() return true end,
    list = function() return {} end,
}

local function flush_timers()
    local timers = pending_timers
    pending_timers = {}
    for _, timer in ipairs(timers) do if not timer.dead then timer.callback() end end
end

local function filter_from(command)
    local args = command.args
    for index, value in ipairs(args) do
        if value == "-filter_complex" then return args[index + 1] end
    end
    error("missing -filter_complex")
end

local controller = require("uosc_waveform.controller")
local app = controller.start({
    mp = mp,
    fs = fs,
    now = function() return 1000 end,
    session_id = "audio-switch",
    raw_options = { cache_dir = [[C:\Cache]], media_debounce_ms = 10, resize_debounce_ms = 0 },
    context = { config_dir = [[C:\Config]], platform = "windows" },
    uosc_config = { timeline_size = 40 },
    uosc_detected = true,
})

events["file-loaded"]()
flush_timers()
assert(#commands == 1, "initial audio track must start one FFmpeg job")
assert(filter_from(commands[1]):find("[0:1]", 1, true), "initial job must select ff-index 1")

-- Simulate aid changing before track-list.selected catches up. The effective
-- aid property must be enough to switch the waveform to stream 2.
props.aid = 2
observers.aid()
flush_timers()
assert(#commands == 2, "changing aid must start a new FFmpeg job")
assert(cancelled == 1, "changing aid must cancel the old FFmpeg job")
assert(filter_from(commands[2]):find("[0:2]", 1, true), "new job must select ff-index 2")
assert(app:debug_state().state == controller.STATES.GENERATING, "new audio waveform must be generating")

print("PASS controller_audio_switch")
