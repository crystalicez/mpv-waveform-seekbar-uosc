local captured_compatibility
local overlay_shown = false

package.preload["uosc_waveform.util"] = function()
    return {
        shallow_copy = function(value)
            local out = {}
            for k, v in pairs(value or {}) do out[k] = v end
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
                resize_debounce_ms = 0,
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
            captured_compatibility = raw.compatibility
            return { adapter = raw.compatibility, valid = true }, {}
        end,
        compute = function()
            return { x = 0, y = 0, width = 100, height = 10, source_crop_top = 0, source_crop_height = 2 }
        end,
    }
end
package.preload["uosc_waveform.overlay"] = function()
    return {
        new = function()
            return {
                show = function() overlay_shown = true; return true end,
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
                duration = 10, edition = 0, track = { id = 1 },
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
        validate_entry = function() return true end,
        cleanup_candidates = function() return {} end,
        cleanup_groups = function() return {} end,
        stale_auxiliary_candidates = function() return {} end,
        lock_status = function() return "missing" end,
        remove_owned_lock = function() return true end,
    }
end
package.preload["uosc_waveform.ffmpeg"] = function() return {} end

local file_loaded
local mp = {
    get_property_native = function(name, default)
        local values = {
            path = "video.mkv", duration = 10, aid = 1,
            ["track-list"] = {{ type = "audio", selected = true, id = 1 }},
            ["osd-width"] = 800, ["osd-height"] = 450,
            ["display-hidpi-scale"] = 1,
            ["mouse-pos"] = { x = 10, y = 445 },
            ["background-color"] = "#000000",
        }
        if values[name] ~= nil then return values[name] end
        return default
    end,
    observe_property = function() end,
    register_event = function(name, callback) if name == "file-loaded" then file_loaded = callback end end,
    register_script_message = function() end,
    add_key_binding = function() end,
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
    mp = mp, fs = fs, raw_options = nil,
    context = { config_dir = "config", platform = "windows" },
    uosc_config = {}, uosc_detected = false,
})
assert(captured_compatibility == "uosc-5.12", "nonstandard uosc path must not disable configured adapter")
assert(file_loaded, "file-loaded handler not registered")
file_loaded()
assert(overlay_shown, "overlay should still render when uosc path detection is false")
print("PASS controller_nonstandard_uosc")
