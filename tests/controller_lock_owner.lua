local root = assert(arg[1], "source root required")
package.path = root .. "/portable_config/scripts/?.lua;" .. root .. "/portable_config/scripts/?/init.lua;" .. package.path
local events={}
local source=[[C:\Media\clip.mkv]]
local props={path=source,["stream-open-filename"]=source,duration=10,aid=1,edition=0,["audio-delay"]=0,
    ["track-list"]={{type="audio",id=1,selected=true,["ff-index"]=0}},["background-color"]="#000000"}
local mp={
    get_property_native=function(n,d) local v=props[n]; if v==nil then return d end; return v end,
    observe_property=function() end, register_event=function(n,cb) events[n]=cb end,
    register_script_message=function() end, add_key_binding=function() end,
    command_native=function() return true end,
    command_native_async=function() return 1 end, abort_async_command=function() end,
    msg={info=function() end,warn=function() end,debug=function() end},
}
local files={}
local fs={
    info=function(path)
        if path==source or path==source:lower() then return {size=100,mtime=1,is_file=true,is_dir=false} end
        local c=files[path]; if c then return {size=#c,mtime=1,is_file=true,is_dir=false} end
    end,
    size=function(path) return files[path] and #files[path] or nil end,
    exists=function(path) return files[path]~=nil end,
    read=function(path) return files[path] end,
    create_exclusive=function(path,content) if files[path] then return false,"exists" end; files[path]=content; return true end,
    remove=function(path) files[path]=nil; return true end,
    rename=function(a,b) files[b]=files[a]; files[a]=nil; return true end,
    mkdir=function() return true end, list=function() return {} end,
}
local controller=require("uosc_waveform.controller")
local app=controller.start({mp=mp,fs=fs,now=function() return 100 end,session_id="ours",raw_options={cache_dir=[[C:\Cache]],media_debounce_ms=0},context={config_dir="",platform="windows"},uosc_config={},uosc_detected=true})
events["file-loaded"]()
local lock=assert(app:debug_state().paths.lock)
assert(files[lock] and files[lock]:find("owner=ours",1,true), "instance must own initial lock")
files[lock]="created=101\nowner=peer\n"
app:shutdown()
assert(files[lock] ~= nil, "shutdown must not delete a lock that was replaced by another owner")
print("PASS controller_lock_owner")
