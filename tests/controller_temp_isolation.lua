local root = assert(arg[1], "source root required")
package.path = table.concat({
    root .. "/portable_config/scripts/?.lua",
    root .. "/portable_config/scripts/?/init.lua",
    package.path,
}, ";")

local source = [[C:\Media\race.mkv]]
local observers, events, callbacks, commands = {}, {}, {}, {}
local props = {
    path = source,
    ["stream-open-filename"] = source,
    duration = 60,
    aid = 1,
    edition = 0,
    ["audio-delay"] = 0,
    ["track-list"] = {
        { type = "video", id = 1, selected = true },
        { type = "audio", id = 1, selected = true, ["ff-index"] = 1 },
    },
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
    command_native = function() return true end,
    command_native_async = function(command, callback)
        commands[#commands + 1] = command
        callbacks[#callbacks + 1] = callback
        return #commands
    end,
    abort_async_command = function() end,
    msg = { info = function() end, warn = function() end, debug = function() end },
}
local files = {}
local fs = {
    info = function(path)
        if path == source or path == source:lower() then
            return { size = 1000, mtime = 123, is_file = true, is_dir = false }
        end
        local content = files[path]
        if content then return { size = #content, mtime = 123, is_file = true, is_dir = false } end
        return nil
    end,
    size = function(path) local value = files[path]; return value and #value or nil end,
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
    session_id = "same-session",
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
assert(#commands == 1, "first generation must start")
local temp_a1 = app:debug_state().active_temp

props["audio-delay"] = 1
observers["audio-delay"]()
assert(#commands == 2, "identity change must start a second generation")

props["audio-delay"] = 0
observers["audio-delay"]()
assert(#commands == 3, "returning to the original identity must start a new generation")
local temp_a2 = app:debug_state().active_temp
assert(temp_a1 ~= temp_a2, "each async attempt must use a unique temporary path")
files[temp_a2] = "ACTIVE-NEW-ATTEMPT"

-- Deliver the cancelled callback after the new same-identity attempt has begun.
-- It may clean only its own temp, never the replacement attempt's output.
callbacks[1](false, { status = -1, killed = true }, "killed")
assert(files[temp_a2] == "ACTIVE-NEW-ATTEMPT",
    "a stale callback must not delete a newer same-session temporary output")
assert(app:debug_state().active_temp == temp_a2,
    "debug state must retain the currently active unique temporary path")

print("PASS controller_temp_isolation")
