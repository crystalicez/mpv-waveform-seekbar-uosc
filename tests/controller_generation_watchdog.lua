local root = assert(arg[1], "source root required")
package.path = root .. "/portable_config/scripts/?.lua;" .. root .. "/portable_config/scripts/?/init.lua;" .. package.path
local source="/tmp/hung.m4a"
local events,timers={},{}
local aborted=0
local files={}
local props={path=source,["stream-open-filename"]=source,duration=10,aid=1,
    ["track-list"]={{type="audio",id=1,selected=true,["ff-index"]=0}},["background-color"]="#000000"}
local mp={
 get_property_native=function(n,d) local v=props[n]; if v==nil then return d end; return v end,
 observe_property=function() end,register_event=function(n,cb) events[n]=cb end,
 register_script_message=function() end,add_key_binding=function() end,command_native=function() return true end,
 command_native_async=function() return 77 end,
 abort_async_command=function(id) assert(id==77); aborted=aborted+1 end,
 add_timeout=function(seconds,cb)
   local timer={seconds=seconds,callback=cb,dead=false}
   function timer:kill() self.dead=true end
   timers[#timers+1]=timer
   return timer
 end,
 msg={info=function() end,warn=function() end,debug=function() end,error=function() end},
}
local fs={
 info=function(path) if path==source then return {size=100,mtime=1,is_file=true,is_dir=false} end end,
 size=function(path) return files[path] and #files[path] or nil end,exists=function(path) return files[path]~=nil end,
 read=function(path) return files[path] end,write=function(path,c) files[path]=c; return true end,
 create_exclusive=function(path,c) files[path]=c; return true end,
 remove=function(path) files[path]=nil; return true end,rename=function() return true end,mkdir=function() return true end,list=function() return {} end,
}
local controller=require("uosc_waveform.controller")
local app=controller.start({mp=mp,fs=fs,now=function() return 1000 end,session_id="watchdog",
 raw_options={cache_dir="/tmp/cache",media_debounce_ms=0,resize_debounce_ms=0,source_width=8,source_height=8,
   generation_timeout_seconds=3},context={config_dir="/tmp",platform="other"},uosc_config={},uosc_detected=true})
events["file-loaded"]()
assert(app:debug_state().generation_phase=="analyzing","hung job must be in analyzing phase")
local watchdog
for _,timer in ipairs(timers) do if math.abs(timer.seconds-3)<0.001 then watchdog=timer end end
assert(watchdog and not watchdog.dead,"generation watchdog must be armed")
watchdog.callback()
local state=app:debug_state()
assert(aborted==1,"watchdog must abort FFmpeg")
assert(state.state==controller.STATES.ERROR,"watchdog must enter ERROR")
assert(state.generation_phase==nil,"watchdog must clear phase")
assert(state.last_error and state.last_error.code=="generation-timeout","watchdog error must be structured")
assert(state.active_temp==nil,"watchdog must remove active temp ownership")
assert(not files[state.paths.lock],"watchdog must release owned lock")
print("PASS controller_generation_watchdog")
