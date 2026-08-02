local observers, events = {}, {}
local mouse = { x = 100, y = 550, hover = true }
local rendered = {}
local timers = {}

package.preload["uosc_waveform.util"] = function()
    return {
        shallow_copy = function(value)
            local out = {}
            for key, item in pairs(value or {}) do out[key] = item end
            return out
        end,
        clamp = function(value, low, high)
            if value < low then return low end
            if value > high then return high end
            return value
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
        parse_uosc = function(raw)
            return { adapter = raw.compatibility, valid = true, animation_duration = 100 }, {}
        end,
        compute = function(_, state)
            local visibility = state.forced_visibility
            if visibility == nil then visibility = state.mouse_hover == false and 0 or 1 end
            if visibility <= 0 then return nil, "timeline-minimized" end
            return {
                x = 0, y = 0, width = 100,
                height = math.max(1, math.floor(20 * visibility + 0.5)),
                source_crop_top = 0, source_crop_height = 2,
                visibility = visibility,
            }
        end,
    }
end
package.preload["uosc_waveform.overlay"] = function()
    return {
        new = function()
            return {
                show = function(_, _, _, _, rect)
                    rendered[#rendered + 1] = rect.visibility
                    return true
                end,
                hide = function() rendered[#rendered + 1] = 0 end,
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
    uosc_config = { animation_duration = 100 },
    uosc_detected = true,
})

events["file-loaded"]()
assert(rendered[#rendered] == 1, "initial cursor proximity must render fully visible")

mouse.hover = false
observers["mouse-pos"]("mouse-pos", mouse)
assert(rendered[#rendered] == 1,
    "cursor leave must start from current visibility rather than hiding immediately")
assert(#timers >= 1, "cursor leave must schedule uosc-style fade ticks")

local first_timer = timers[#timers]
first_timer.callback()
local first_decay = rendered[#rendered]
assert(first_decay > 0 and first_decay < 1,
    "first cursor-leave tick must reduce visibility without snapping to zero")

-- Re-entering must cancel the forced fade and immediately return to live mouse proximity.
mouse.hover = true
observers["mouse-pos"]("mouse-pos", mouse)
assert(rendered[#rendered] == 1, "mouse re-entry must cancel fade and restore live proximity")

print("PASS controller_mouse_fade")
