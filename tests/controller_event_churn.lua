local root = assert(arg[1], "source root required")
package.path = table.concat({
    root .. "/portable_config/scripts/?.lua",
    root .. "/portable_config/scripts/?/init.lua",
    package.path,
}, ";")

local started, cancelled = 0, 0
local pending_timers = {}
local observers, events = {}, {}
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
    ["osd-width"] = 1280,
    ["osd-height"] = 720,
    ["display-hidpi-scale"] = 1,
    fullscreen = false,
    ["window-maximized"] = false,
    pause = false,
    ["mouse-pos"] = { x = 640, y = 710 },
    focused = true,
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
    command_native_async = function(_, callback)
        started = started + 1
        local id = started
        -- Intentionally leave the job active.
        return id
    end,
    abort_async_command = function() cancelled = cancelled + 1 end,
    command_native = function() return true end,
    msg = { info = function() end, warn = function() end, debug = function() end },
}

local files = {}
local fs = {
    info = function(path)
        if path == props.path then return { size = 1000, mtime = 123, is_file = true, is_dir = false } end
        local content = files[path]
        if content then return { size = #content, mtime = 123, is_file = true, is_dir = false } end
        return nil
    end,
    size = function(path) local v = files[path]; return v and #v or nil end,
    mtime = function() return 123 end,
    exists = function(path) return files[path] ~= nil end,
    read = function(path) return files[path] end,
    write = function(path, content) files[path] = content; return true end,
    create_exclusive = function(path, content)
        if files[path] then return false, "exists" end
        files[path] = content
        return true
    end,
    remove = function(path) files[path] = nil; return true end,
    rename = function(src, dst) files[dst] = files[src]; files[src] = nil; return true end,
    mkdir = function() return true end,
    list = function() return {} end,
}

local function flush_timers()
    local list = pending_timers
    pending_timers = {}
    for _, timer in ipairs(list) do
        if not timer.dead then timer.callback() end
    end
end

local controller = require("uosc_waveform.controller")
local app = controller.start({
    mp = mp,
    fs = fs,
    now = function() return 1000 end,
    session_id = "test-session",
    raw_options = {
        cache_dir = [[C:\Cache]],
        resize_debounce_ms = 0,
        media_debounce_ms = 200,
        minimum_timeline_width = 1,
    },
    context = { config_dir = [[C:\Config]], platform = "windows" },
    uosc_config = { timeline_size = 40 },
    uosc_detected = true,
})

assert(events["file-loaded"], "file-loaded event must be registered")
events["file-loaded"]()
assert(started == 0, "file-loaded must be debounced")

-- Simulate the normal burst emitted by mpv while the file settles.
observers.duration()
observers["track-list"]()
observers.aid()
flush_timers()
assert(started == 1, "the property burst must start exactly one generation")
assert(cancelled == 0, "the initial property burst must not cancel generation")

-- A repeated notification with identical media identity must be coalesced.
observers["track-list"]()
flush_timers()
assert(started == 1, "identical media refresh must not restart ffmpeg")
assert(cancelled == 0, "identical media refresh must not cancel ffmpeg")
assert(app:debug_state().state == controller.STATES.GENERATING, "generation must remain active")

print("PASS controller_event_churn")
