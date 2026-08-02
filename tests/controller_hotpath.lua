local root = assert(arg[1], "source root required")
package.path = root .. "/portable_config/scripts/?.lua;" .. root .. "/portable_config/scripts/?/init.lua;" .. package.path

local validate_calls, list_calls, shown = 0, 0, 0
local last_geometry_state
package.preload["uosc_waveform.util"] = function()
    return {
        shallow_copy = function(t) local o = {}; for k,v in pairs(t or {}) do o[k]=v end; return o end,
        clamp = function(v,l,h) return math.max(l, math.min(h,v)) end,
    }
end
package.preload["uosc_waveform.options"] = function()
    return {
        defaults = function() return {
            enabled=true, cache_dir="cache", source_width=4, source_height=2,
            max_cache_age_days=60, max_cache_mb=512, stale_lock_seconds=900,
            resize_debounce_ms=0, mouse_update_interval_ms=0, media_debounce_ms=0,
            compatibility="uosc-5.12", adapter_override="",
        } end,
        normalize = function(raw) return raw, {} end,
        choose_waveform_color = function() return "#FFFFFF" end,
    }
end
package.preload["uosc_waveform.cache"] = function()
    return {
        expected_size = function() return 32 end,
        identity = function() return "identity" end,
        paths = function() return { key="key", raw="raw", temp="tmp", lock="lock" } end,
        validate = function(_, path) validate_calls = validate_calls + 1; return path == "raw" end,
        validate_entry = function() validate_calls = validate_calls + 1; return true end,
        lock_status = function() return "free" end,
        acquire_lock = function() return false, "disabled" end,
        stale_auxiliary_candidates = function() return {} end,
        cleanup_candidates = function() return {} end,
        cleanup_groups = function() return {} end,
        remove_owned_lock = function() return true end,
    }
end
package.preload["uosc_waveform.media"] = function()
    return { inspect = function() return {
        supported=true, source_path="clip", source_size=1, source_mtime=1,
        input_path="clip", input_size=1, input_mtime=1, duration=10,
        edition=0, demuxer_start_time=0, audio_delay=0, media_type="video",
        track={id=1, ff_index=1, audio_ordinal=0, external=false},
    } end }
end
package.preload["uosc_waveform.geometry"] = function()
    return {
        parse_uosc = function(raw) return { adapter=raw.compatibility, valid=true, animation_duration=100 }, {} end,
        compute = function(_, state)
            last_geometry_state = state
            return { x=0,y=0,width=100,height=20,source_crop_top=0,source_crop_height=2,visibility=1 }
        end,
    }
end
package.preload["uosc_waveform.overlay"] = function()
    return { new = function() return {
        show=function() shown=shown+1; return true end,
        hide=function() end,
        id=function() return 63 end,
    } end }
end
package.preload["uosc_waveform.ffmpeg"] = function()
    return { build_generate_argv=function() return {} end, start=function() error("cache hit should not generate") end }
end

local observers, events = {}, {}
local property_reads = {}
local mouse = { x=100, y=100, hover=true }
local props = {
    path="clip", ["stream-open-filename"]="clip", duration=10, aid=1, edition=0,
    ["track-list"]={{type="video",selected=true},{type="audio",id=1,selected=true,["ff-index"]=1}},
    ["mouse-pos"]=mouse, ["osd-dimensions"]={w=1280,h=720},
    ["display-hidpi-scale"]=1, focused=true,
}
local mp = {
    get_property_native=function(name, default)
        property_reads[name] = (property_reads[name] or 0) + 1
        local v=props[name]; if v==nil then return default end; return v
    end,
    observe_property=function(name,_,cb) observers[name]=cb end,
    register_event=function(name,cb) events[name]=cb end,
    register_script_message=function() end, add_key_binding=function() end,
    command_native=function() return true end,
    msg={info=function() end,warn=function() end,debug=function() end},
}
local fs = {
    info=function() return {size=1,mtime=1,is_file=true,is_dir=false} end,
    size=function(path) return path=="raw" and 32 or nil end,
    exists=function() return false end,
    mkdir=function() return true end,
    list=function() list_calls=list_calls+1; return {} end,
    remove=function() return true end,
}
local controller=require("uosc_waveform.controller")
controller.start({ mp=mp, fs=fs, raw_options=nil, context={config_dir="",platform="windows"}, uosc_config={}, uosc_detected=true })
events["file-loaded"]()
assert(validate_calls == 1, "cache hit should be validated exactly once before display")
assert(list_calls == 1, "cache cleanup should run once after first ready state")
assert(last_geometry_state.osd_width == 1280 and last_geometry_state.osd_height == 720,
    "osd-dimensions must provide a compatibility fallback when scalar properties are absent")
local reads_before_mouse = 0
for _, count in pairs(property_reads) do reads_before_mouse = reads_before_mouse + count end
for i=1,20 do mouse.x=i; observers["mouse-pos"]("mouse-pos", mouse) end
local reads_after_mouse = 0
for _, count in pairs(property_reads) do reads_after_mouse = reads_after_mouse + count end
assert(validate_calls == 1, "mouse animation hot path must not stat the cache file every frame")
assert(list_calls == 1, "mouse animation must not rescan cache directory")
assert(reads_after_mouse == reads_before_mouse,
    "mouse animation must use observer-cached static geometry properties")
assert(shown >= 2, "mouse updates should still render geometry")
print("PASS controller_hotpath")
