local observers, events = {}, {}
local mouse = { x = 100, y = 400, hover = true }
local shown_heights = {}
local timers = {}

package.preload["uosc_waveform.util"] = function()
    return {
        shallow_copy = function(value)
            local out = {}
            for key, item in pairs(value or {}) do out[key] = item end
            return out
        end,
    }
end
package.preload["uosc_waveform.options"] = function()
    return {
        defaults = function()
            return {
                enabled = true,
                compatibility = "uosc-5.12",
                adapter_override = "",
                resize_debounce_ms = 120,
                mouse_update_interval_ms = 0,
                media_debounce_ms = 0,
                cache_dir = "cache",
                max_cache_age_days = 60,
                max_cache_mb = 512,
                source_width = 4,
                source_height = 2,
                stale_lock_seconds = 900,
                lock_poll_ms = 500,
            }
        end,
        normalize = function(raw) return raw, {} end,
        choose_waveform_color = function() return "#FFFFFF" end,
    }
end
package.preload["uosc_waveform.geometry"] = function()
    return {
        parse_uosc = function(raw) return { adapter = raw.compatibility, valid = true }, {} end,
        compute = function(_, state)
            return {
                x = 0, y = 0, width = 100,
                height = state.mouse_y >= 500 and 20 or 5,
                source_crop_top = 0, source_crop_height = 2,
            }
        end,
    }
end
package.preload["uosc_waveform.overlay"] = function()
    return {
        new = function()
            return {
                show = function(_, _, _, _, rect)
                    shown_heights[#shown_heights + 1] = rect.height
                    return true
                end,
                hide = function() end,
                id = function() return 63 end,
            }
        end,
    }
end
package.preload["uosc_waveform.media"] = function()
    return {
        inspect = function()
            return {
                supported = true,
                source_path = "video.mkv", source_size = 1, source_mtime = 1,
                input_path = "video.mkv", input_size = 1, input_mtime = 1,
                duration = 10, edition = 0, demuxer_start_time = 0,
                track = { id = 1, ff_index = 1, audio_ordinal = 0, external = false },
            }
        end,
    }
end
package.preload["uosc_waveform.cache"] = function()
    return {
        expected_size = function() return 1 end,
        identity = function() return "id" end,
        paths = function() return { raw = "cache.bgra", key = "id", lock = "lock", temp = "temp" } end,
        validate = function() return true end,
        cleanup_candidates = function() return {} end,
        stale_auxiliary_candidates = function() return {} end,
        lock_status = function() return "missing" end,
        remove_owned_lock = function() return true end,
    }
end
package.preload["uosc_waveform.ffmpeg"] = function() return {} end

local mp = {
    get_property_native = function(name, default)
        local values = {
            path = "video.mkv", duration = 10, aid = 1,
            ["track-list"] = {{ type = "audio", selected = true, id = 1 }},
            ["osd-width"] = 800, ["osd-height"] = 600,
            ["display-hidpi-scale"] = 1,
            ["mouse-pos"] = mouse,
            ["background-color"] = "#000000",
        }
        if values[name] ~= nil then return values[name] end
        return default
    end,
    observe_property = function(name, _, callback) observers[name] = callback end,
    register_event = function(name, callback) events[name] = callback end,
    register_script_message = function() end,
    add_key_binding = function() end,
    add_timeout = function(_, callback)
        local timer = { callback = callback, dead = false }
        function timer:kill() self.dead = true end
        timers[#timers + 1] = timer
        return timer
    end,
    msg = { warn = function() end, info = function() end, debug = function() end, error = function() end },
}
local fs = {
    mkdir = function() return true end,
    list = function() return {} end,
    exists = function() return true end,
}

package.path = arg[1] .. "/?.lua;" .. arg[1] .. "/?/init.lua;" .. package.path
local controller = require("uosc_waveform.controller")
controller.start({
    mp = mp,
    fs = fs,
    raw_options = nil,
    context = { config_dir = "config", platform = "windows" },
    uosc_config = {},
    uosc_detected = true,
})

assert(events["file-loaded"], "file-loaded handler must be registered")
events["file-loaded"]()
assert(#shown_heights == 1 and shown_heights[1] == 5, "initial cache hit must render current proximity height")

mouse.y = 550
observers["mouse-pos"]()
assert(#shown_heights == 2 and shown_heights[2] == 20,
    "mouse movement must refresh waveform geometry immediately instead of using resize debounce")
assert(#timers == 0, "mouse_update_interval_ms=0 must not create a timer")

print("PASS controller_mouse_proximity")
