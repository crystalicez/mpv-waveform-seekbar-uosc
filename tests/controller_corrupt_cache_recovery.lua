local root=assert(arg[1],"source root required")
package.path=root.."/portable_config/scripts/?.lua;"..root.."/portable_config/scripts/?/init.lua;"..package.path
local events={}
local source=[[C:\Media\clip.mkv]]
local props={path=source,["stream-open-filename"]=source,duration=10,aid=1,edition=0,
    ["track-list"]={{type="audio",id=1,selected=true,["ff-index"]=0}},["background-color"]="#000000"}
local files={}
local corrupt_removed=false
local started=0
local function is_raw(path) return tostring(path):match("%.bgra$")~=nil end
local mp={
    get_property_native=function(n,d) local v=props[n]; if v==nil then return d end; return v end,
    observe_property=function() end,register_event=function(n,cb) events[n]=cb end,
    register_script_message=function() end,add_key_binding=function() end,command_native=function() return true end,
    command_native_async=function()
        assert(corrupt_removed,"owned generation must remove an invalid canonical cache before FFmpeg")
        started=started+1; return started
    end,
    abort_async_command=function() end,msg={error=function() end,warn=function() end,info=function() end,debug=function() end},
}
local fs={
    info=function(path)
        if path==source or path==source:lower() then return {size=100,mtime=1,is_file=true,is_dir=false} end
        if files[path] then return {size=#files[path],mtime=1,is_file=true,is_dir=false} end
        if is_raw(path) and not corrupt_removed then return {size=1,mtime=1,is_file=true,is_dir=false} end
    end,
    size=function(path)
        if files[path] then return #files[path] end
        if is_raw(path) and not corrupt_removed then return 1 end
    end,
    exists=function(path) return files[path]~=nil or (is_raw(path) and not corrupt_removed) end,
    read=function(path) return files[path] end,
    create_exclusive=function(path,content) if files[path] then return false,"exists" end; files[path]=content; return true end,
    remove=function(path)
        if is_raw(path) then corrupt_removed=true else files[path]=nil end
        return true
    end,
    rename=function() return true end,mkdir=function() return true end,list=function() return {} end,
}
local controller=require("uosc_waveform.controller")
local app=controller.start({mp=mp,fs=fs,now=function() return 100 end,session_id="owner",
    raw_options={cache_dir=[[C:\Cache]],media_debounce_ms=0},context={config_dir="",platform="windows"},
    uosc_config={},uosc_detected=true})
events["file-loaded"]()
assert(corrupt_removed,"truncated canonical cache should be cleaned under the owned lock")
assert(started==1 and app:debug_state().state==controller.STATES.GENERATING)
print("PASS controller_corrupt_cache_recovery")
