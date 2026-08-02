local root = assert(arg[1], "source root required")
package.path = root .. "/portable_config/scripts/?.lua;" .. root .. "/portable_config/scripts/?/init.lua;" .. package.path

local observers, events, timers = {}, {}, {}
local hidden, shown = 0, 0
local mouse = { x = 640, y = 710, hover = true }
local props = {
    path = "clip.mkv", ["stream-open-filename"] = "clip.mkv", duration = 10, aid = 1,
    ["track-list"] = {{ type="video", selected=true }, { type="audio", id=1, selected=true, ["ff-index"]=1 }},
    ["mouse-pos"] = mouse, ["osd-width"] = 1280, ["osd-height"] = 720,
    ["display-hidpi-scale"] = 1, focused = true, ["cursor-autohide"] = 100,
    ["cursor-autohide-fs-only"] = false,
}

package.preload["uosc_waveform.options"] = function()
    return {
        defaults=function() return {
            enabled=true, cache_dir="cache", source_width=4, source_height=2,
            max_cache_age_days=60, max_cache_mb=512, stale_lock_seconds=900,
            resize_debounce_ms=0, mouse_update_interval_ms=0, media_debounce_ms=0,
            compatibility="uosc-5.12", adapter_override="",
        } end,
        normalize=function(raw) return raw, {} end,
        choose_waveform_color=function() return "#FFFFFF" end,
    }
end
package.preload["uosc_waveform.geometry"] = function()
    return {
        parse_uosc=function() return { adapter="uosc-5.12", valid=true, autohide=true, animation_duration=0 }, {} end,
        compute=function(_, state)
            if not state.mouse_hover and state.forced_visibility == nil then return nil, "timeline-minimized" end
            return {x=0,y=0,width=100,height=20,source_crop_top=0,source_crop_height=2,visibility=1}
        end,
    }
end
package.preload["uosc_waveform.overlay"] = function()
    return { new=function() return {
        show=function() shown=shown+1; return true end,
        hide=function() hidden=hidden+1 end,
        id=function() return 63 end,
    } end }
end
package.preload["uosc_waveform.media"] = function()
    return { inspect=function() return {
        supported=true, source_path="clip.mkv", source_size=1, source_mtime=1,
        input_path="clip.mkv", input_size=1, input_mtime=1, duration=10,
        edition=0, demuxer_start_time=0, audio_delay=0, media_type="video",
        track={id=1,ff_index=1,audio_ordinal=0,external=false},
    } end }
end
package.preload["uosc_waveform.cache"] = function()
    return {
        expected_size=function() return 1 end, identity=function() return "id" end,
        paths=function() return {raw="raw",key="id",lock="lock",temp="temp.tmp"} end,
        validate=function() return true end, cleanup_candidates=function() return {} end,
        stale_auxiliary_candidates=function() return {} end, lock_status=function() return "free" end,
        remove_owned_lock=function() return true end,
    }
end
package.preload["uosc_waveform.ffmpeg"] = function() return {} end

local mp = {
    get_property_native=function(name, default) local v=props[name]; if v==nil then return default end; return v end,
    observe_property=function(name,_,cb) observers[name]=cb end,
    register_event=function(name,cb) events[name]=cb end,
    register_script_message=function() end, add_key_binding=function() end,
    add_timeout=function(seconds,cb)
        local timer={seconds=seconds,callback=cb,dead=false}
        function timer:kill() self.dead=true end
        timers[#timers+1]=timer
        return timer
    end,
    msg={info=function() end,warn=function() end,debug=function() end},
}
local fs={
    info=function() return {size=1,mtime=1,is_file=true,is_dir=false} end,
    size=function(path) return path=="raw" and 1 or nil end,
    exists=function() return false end, mkdir=function() return true end,
    list=function() return {} end, remove=function() return true end,
}

local controller=require("uosc_waveform.controller")
controller.start({mp=mp,fs=fs,context={config_dir="",platform="windows"},uosc_config={autohide="yes"},uosc_detected=true})
events["file-loaded"]()
assert(shown == 1, "cache hit must initially show the waveform")
observers["mouse-pos"]("mouse-pos", mouse)
assert(#timers >= 1, "mouse movement must queue uosc-compatible cursor autohide")
local timer=timers[#timers]
assert(math.abs(timer.seconds - 0.1) < 1e-6, "autohide timeout must mirror cursor-autohide")
timer.callback()
assert(hidden >= 1, "autohide timeout must hide the waveform when uosc hides its cursor UI")

-- Any real pointer movement must cancel the synthetic hidden state and reveal
-- according to fresh proximity again.
mouse.x = mouse.x + 1
observers["mouse-pos"]("mouse-pos", mouse)
assert(shown >= 2, "pointer movement after autohide must reveal waveform again")

-- mpv accepts special cursor-autohide choices in addition to milliseconds.
-- Both their textual and native numeric sentinel forms must be preserved.
props["cursor-autohide"] = "no"
observers["cursor-autohide"]("cursor-autohide", "no")
local timers_before_no = #timers
mouse.x = mouse.x + 1
observers["mouse-pos"]("mouse-pos", mouse)
assert(#timers == timers_before_no, "cursor-autohide=no must not queue a timer")

props["cursor-autohide"] = -1
observers["cursor-autohide"]("cursor-autohide", -1)
mouse.x = mouse.x + 1
observers["mouse-pos"]("mouse-pos", mouse)
assert(#timers == timers_before_no, "native cursor-autohide=-1 must mean no")

props["cursor-autohide"] = "always"
observers["cursor-autohide"]("cursor-autohide", "always")
local hidden_before_always = hidden
mouse.x = mouse.x + 1
observers["mouse-pos"]("mouse-pos", mouse)
assert(hidden > hidden_before_always, "cursor-autohide=always must hide immediately")

-- A fresh move reveals it, then the native -2 sentinel hides immediately too.
props["cursor-autohide"] = "no"
observers["cursor-autohide"]("cursor-autohide", "no")
mouse.x = mouse.x + 1
observers["mouse-pos"]("mouse-pos", mouse)
props["cursor-autohide"] = -2
observers["cursor-autohide"]("cursor-autohide", -2)
hidden_before_always = hidden
mouse.x = mouse.x + 1
observers["mouse-pos"]("mouse-pos", mouse)
assert(hidden > hidden_before_always, "native cursor-autohide=-2 must mean always")

print("PASS controller_autohide")
