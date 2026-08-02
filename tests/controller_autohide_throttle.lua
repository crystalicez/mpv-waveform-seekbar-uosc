local root=assert(arg[1],"source root required")
package.path=root.."/portable_config/scripts/?.lua;"..root.."/portable_config/scripts/?/init.lua;"..package.path
local observers,events,timers={},{},{}
package.preload["uosc_waveform.options"]=function() return {defaults=function() return {enabled=true,cache_dir="cache",source_width=4,source_height=2,max_cache_age_days=60,max_cache_mb=512,
 stale_lock_seconds=900,resize_debounce_ms=0,mouse_update_interval_ms=16,media_debounce_ms=0,generation_timeout_seconds=0,
 compatibility="uosc-5.12",adapter_override="",log_level="warn"} end,normalize=function(raw) return raw,{} end,choose_waveform_color=function() return "#fffFFF" end} end
package.preload["uosc_waveform.geometry"]=function() return {parse_uosc=function() return {adapter="uosc-5.12",valid=true,autohide=true,animation_duration=0},{} end,
 compute=function() return {x=0,y=0,width=10,height=2,source_crop_top=0,source_crop_height=2,visibility=1} end} end
package.preload["uosc_waveform.overlay"]=function() return {new=function() return {show=function() return true end,hide=function() end,id=function() return 63 end} end} end
package.preload["uosc_waveform.media"]=function() return {inspect=function() return {supported=true,source_path="x",source_size=1,source_mtime=1,input_path="x",input_size=1,input_mtime=1,duration=10,track={id=1,ff_index=0,audio_ordinal=0},media_type="audio"} end} end
package.preload["uosc_waveform.cache"]=function() return {expected_size=function() return 1 end,identity=function() return "id" end,
 paths=function() return {key="id",raw="raw",meta="meta",lock="lock",temp="temp",width=4,height=2} end,validate=function() return true end,validate_entry=function() return true end,
 cleanup_groups=function() return {} end,stale_auxiliary_candidates=function() return {} end,lock_status=function() return "free" end,remove_owned_lock=function() return true end} end
package.preload["uosc_waveform.ffmpeg"]=function() return {} end
local mouse={x=1,y=1,hover=true}
local props={["mouse-pos"]=mouse,["cursor-autohide"]=1000,["cursor-autohide-fs-only"]=false,focused=true}
local mp={get_property_native=function(n,d)local v=props[n];if v==nil then return d end;return v end,
 observe_property=function(n,_,cb) observers[n]=cb end,register_event=function(n,cb) events[n]=cb end,register_script_message=function() end,add_key_binding=function() end,
 add_timeout=function(seconds,cb)local t={seconds=seconds,callback=cb,dead=false};function t:kill() self.dead=true end;timers[#timers+1]=t;return t end,
 msg={info=function() end,warn=function() end,debug=function() end,error=function() end}}
local fs={size=function(p)return p=="raw" and 1 or nil end,read=function() return "" end,exists=function() return false end,mkdir=function() return true end,list=function() return {} end,remove=function() return true end}
local controller=require("uosc_waveform.controller")
controller.start({mp=mp,fs=fs,context={config_dir="",platform="other"},uosc_config={autohide="yes"},uosc_detected=true})
events["file-loaded"]()
for i=1,100000 do mouse.x=i;observers["mouse-pos"]("mouse-pos",mouse) end
assert(#timers==1,"raw mouse burst must allocate one throttled timer, got "..#timers)
timers[1].dead=true;timers[1].callback()
assert(#timers==2,"throttled frame must arm exactly one autohide timer")
for i=1,100000 do mouse.x=i+100000;observers["mouse-pos"]("mouse-pos",mouse) end
assert(#timers==3,"second raw burst must allocate only one new mouse timer")
timers[3].dead=true;timers[3].callback()
assert(#timers==4,"second frame must replace autohide once, not per raw event")
local active=0
for _,t in ipairs(timers) do if not t.dead then active=active+1 end end
assert(active==1,"only the latest autohide timer should remain active; active="..active)
print("PASS controller_autohide_throttle")
