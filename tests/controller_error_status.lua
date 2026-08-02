local root=assert(arg[1],"source root required")
package.path=root.."/portable_config/scripts/?.lua;"..root.."/portable_config/scripts/?/init.lua;"..package.path
local source="/tmp/error.m4a"
local events,callback={},nil
local osd
local props={path=source,["stream-open-filename"]=source,duration=10,aid=1,
 ["track-list"]={{type="audio",id=1,selected=true,["ff-index"]=0}},["background-color"]="#000000"}
local mp={get_property_native=function(n,d) local v=props[n];if v==nil then return d end;return v end,
 observe_property=function() end,register_event=function(n,cb) events[n]=cb end,register_script_message=function() end,
 add_key_binding=function() end,command_native=function() return true end,
 command_native_async=function(_,cb) callback=cb;return 1 end,abort_async_command=function() end,
 osd_message=function(text) osd=text end,msg={info=function() end,warn=function() end,debug=function() end,error=function() end}}
local fs={info=function(p) if p==source then return {size=1,mtime=1,is_file=true,is_dir=false} end end,
 size=function() end,exists=function() return false end,read=function() end,write=function() return true end,
 create_exclusive=function() return false,"disabled" end,remove=function() return true end,rename=function() return true end,
 mkdir=function() return true end,list=function() return {} end}
local controller=require("uosc_waveform.controller")
local app=controller.start({mp=mp,fs=fs,raw_options={cache_dir="/tmp/cache",media_debounce_ms=0,
 generation_timeout_seconds=0},context={config_dir="/tmp",platform="other"},uosc_config={},uosc_detected=true})
events["file-loaded"]()
callback(false,{status=1,stderr="No such filter: 'astats'"},nil)
local state=app:debug_state()
assert(state.state==controller.STATES.ERROR)
assert(state.last_error and state.last_error.code=="ffmpeg-feature-unsupported")
local text=app:show_status()
assert(text==osd,"show_status must return the displayed text")
assert(text:find("phase=none",1,true),"status must include phase")
assert(text:find("error=ffmpeg-feature-unsupported",1,true),"status must include structured error")
assert(text:find("detail=No such filter",1,true),"status must include concise detail")
print("PASS controller_error_status")
