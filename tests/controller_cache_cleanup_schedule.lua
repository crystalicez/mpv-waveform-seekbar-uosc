local root=assert(arg[1],"source root required")
package.path=root.."/portable_config/scripts/?.lua;"..root.."/portable_config/scripts/?/init.lua;"..package.path
local peak_metadata=assert(loadfile(root.."/tests/helpers/peak_metadata.lua"))()
local events,callbacks={},{}
local now_value=1000
local current=1
local function source() return "/tmp/song"..current..".m4a" end
local props={duration=10,aid=1,["track-list"]={{type="audio",id=1,selected=true,["ff-index"]=0}},
 ["background-color"]="#000000",["osd-width"]=800,["osd-height"]=600,["display-hidpi-scale"]=1,
 ["mouse-pos"]={x=400,y=590,hover=true},focused=true}
local mp={
 get_property_native=function(n,d)
  if n=="path" or n=="stream-open-filename" then return source() end
  local v=props[n];if v==nil then return d end;return v
 end,
 observe_property=function() end,register_event=function(n,cb) events[n]=cb end,register_script_message=function() end,
 add_key_binding=function() end,command_native=function() return true end,
 command_native_async=function(_,cb) callbacks[#callbacks+1]=cb;return #callbacks end,
 abort_async_command=function() end,msg={info=function() end,warn=function() end,debug=function() end,error=function() end},
}
local files={}
local list_calls=0
local fs={
 info=function(path)
  if path:match("^/tmp/song%d+%.m4a$") then return {size=100+current,mtime=current,is_file=true,is_dir=false} end
  local v=files[path];if v then return {size=#v,mtime=now_value,is_file=true,is_dir=false} end
 end,
 size=function(p) return files[p] and #files[p] or nil end,mtime=function(p) return files[p] and now_value or nil end,
 exists=function(p) return files[p]~=nil end,read=function(p) return files[p] end,
 write=function(p,c) files[p]=c;return true end,create_exclusive=function(p,c) files[p]=c;return true end,
 remove=function(p) files[p]=nil;return true end,rename=function(a,b) if files[b] then return false,"exists" end;files[b]=files[a];files[a]=nil;return true end,
 mkdir=function() return true end,
 list=function()
  list_calls=list_calls+1
  local out={};for p,v in pairs(files) do out[#out+1]={path=p,size=#v,mtime=now_value} end;return out
 end,
}
local controller=require("uosc_waveform.controller")
local app=controller.start({mp=mp,fs=fs,now=function() return now_value end,session_id="cleanup",
 raw_options={cache_dir="/tmp/cache",media_debounce_ms=0,resize_debounce_ms=0,source_width=256,source_height=16,
  minimum_timeline_width=1,generation_timeout_seconds=0,max_cache_mb=64},
 context={config_dir="/tmp",platform="other"},uosc_config={timeline_size=40,controls_size=0},uosc_detected=true})
for index=1,9 do
 current=index
 events["file-loaded"]()
 local cb=callbacks[#callbacks]
 assert(cb,"generation callback missing for "..index)
 cb(true,{status=0,stdout=peak_metadata(256,10,-6),stderr=""},nil)
 assert(app:debug_state().state==controller.STATES.READY_VISIBLE)
end
assert(list_calls==2,"cleanup must run on first ready and after eight additional publishes; got "..list_calls)
now_value=1701
current=1
events["file-loaded"]() -- cache hit; time-based cleanup without a recurring timer
assert(app:debug_state().state==controller.STATES.READY_VISIBLE)
assert(list_calls==3,"a ready transition after ten minutes must trigger cleanup")
print("PASS controller_cache_cleanup_schedule")
