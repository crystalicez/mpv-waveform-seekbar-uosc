local root=assert(arg[1],"source root required")
package.path=root.."/portable_config/scripts/?.lua;"..root.."/portable_config/scripts/?/init.lua;"..package.path
local observers,events={},{}
local pending_timer=nil
local live_timers=0
package.preload["uosc_waveform.options"]=function() return {
 defaults=function() return {enabled=true,cache_dir="cache",source_width=64,source_height=16,max_cache_age_days=60,max_cache_mb=512,
  stale_lock_seconds=900,resize_debounce_ms=0,mouse_update_interval_ms=16,media_debounce_ms=0,generation_timeout_seconds=0,
  compatibility="uosc-5.12",adapter_override="",log_level="error",overlay_id=63} end,
 normalize=function(raw) return raw,{} end,choose_waveform_color=function() return "#FFFFFF" end} end
package.preload["uosc_waveform.geometry"]=function() return {parse_uosc=function() return {adapter="uosc-5.12",valid=true,autohide=false,animation_duration=100},{} end,
 compute=function() return {x=0,y=0,width=640,height=16,source_crop_top=0,source_crop_height=16,visibility=1} end} end
package.preload["uosc_waveform.overlay"]=function() return {new=function() return {show=function() return true end,hide=function() end,id=function() return 63 end} end} end
package.preload["uosc_waveform.media"]=function() return {inspect=function() return {supported=true,source_path="x",source_size=1,source_mtime=1,input_path="x",input_size=1,input_mtime=1,duration=10,track={id=1,ff_index=0,audio_ordinal=0},media_type="audio"} end} end
package.preload["uosc_waveform.cache"]=function() return {expected_size=function() return 1 end,identity=function() return "id" end,
 paths=function() return {key="id",raw="raw",meta="meta",lock="lock",temp="temp",width=64,height=16} end,
 validate=function() return true end,validate_entry=function() return true end,cleanup_groups=function() return {} end,stale_auxiliary_candidates=function() return {} end,
 lock_status=function() return "free" end,remove_owned_lock=function() return true end} end
package.preload["uosc_waveform.ffmpeg"]=function() return {} end
local props={path="x",duration=10,aid=1,["track-list"]={{type="audio",id=1,selected=true,["ff-index"]=0}},
 ["mouse-pos"]={x=1,y=1,hover=true},["cursor-autohide"]="no",focused=true,["osd-width"]=1280,["osd-height"]=720}
local mp={
 get_property_native=function(n,d)local v=props[n];if v==nil then return d end;return v end,
 observe_property=function(n,_,cb)observers[n]=cb end,unobserve_property=function() end,
 register_event=function(n,cb)events[n]=cb end,unregister_event=function() end,
 register_script_message=function() end,unregister_script_message=function() end,
 add_key_binding=function() end,remove_key_binding=function() end,
 add_timeout=function(_,cb)
  live_timers=live_timers+1
  local timer={dead=false,callback=cb}
  function timer:kill() if not self.dead then self.dead=true;live_timers=live_timers-1 end end
  pending_timer=timer
  return timer
 end,
 msg={info=function() end,warn=function() end,debug=function() end,error=function() end},
}
local fs={size=function(p)return p=="raw" and 1 or nil end,read=function()return "" end,exists=function()return false end,
 mkdir=function()return true end,list=function()return {} end,remove=function()return true end}
local controller=require("uosc_waveform.controller")
local app=controller.start({mp=mp,fs=fs,raw_options={enabled=true,cache_dir="cache",source_width=64,source_height=16,max_cache_age_days=60,max_cache_mb=512,
 stale_lock_seconds=900,resize_debounce_ms=0,mouse_update_interval_ms=16,media_debounce_ms=0,generation_timeout_seconds=0,
 compatibility="uosc-5.12",adapter_override="",log_level="error",overlay_id=63},context={config_dir="",platform="other"},uosc_config={autohide="no"},uosc_detected=true})
events["file-loaded"]()
collectgarbage("collect")
local baseline=collectgarbage("count")
for i=1,1000000 do
 props["mouse-pos"].x=i%1280
 observers["mouse-pos"]("mouse-pos",props["mouse-pos"])
 if i%100==0 and pending_timer and not pending_timer.dead then
  local timer=pending_timer;pending_timer=nil;timer:kill();timer.callback()
 end
end
if pending_timer and not pending_timer.dead then local timer=pending_timer;pending_timer=nil;timer:kill();timer.callback() end
collectgarbage("collect")
local after=collectgarbage("count")
local allowance=64+baseline*0.10
assert(after-baseline<=allowance,string.format("mouse stress retained %.2fKB; allowance %.2fKB",after-baseline,allowance))
app:shutdown()
collectgarbage("collect")
assert(live_timers==0,"shutdown must leave zero active timers")
print(string.format("PASS controller_mouse_gc baseline=%.2fKB after=%.2fKB delta=%.2fKB",baseline,after,after-baseline))
