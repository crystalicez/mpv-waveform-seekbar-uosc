local root = assert(arg[1], "source root required")
package.path = table.concat({root .. "/portable_config/scripts/?.lua", root .. "/portable_config/scripts/?/init.lua", package.path}, ";")

local source = [[C:\Media\publish.mkv]]
local events, callback, shown_path = {}, nil, nil
local props = {
    path=source, ["stream-open-filename"]=source, duration=10, aid=1, edition=0,
    ["track-list"]={{type="video",selected=true},{type="audio",id=1,selected=true,["ff-index"]=1}},
    ["background-color"]="#000000", ["osd-width"]=800, ["osd-height"]=600,
    ["display-hidpi-scale"]=1, ["mouse-pos"]={x=400,y=590,hover=true}, focused=true,
}
local mp={
    get_property_native=function(name,default) local v=props[name]; if v==nil then return default end; return v end,
    observe_property=function() end,
    register_event=function(name,cb) events[name]=cb end,
    register_script_message=function() end, add_key_binding=function() end,
    command_native=function(command)
        if command.name == "overlay-add" or command._name == "overlay-add" then shown_path=command.file end
        return true
    end,
    command_native_async=function(_,cb) callback=cb; return 1 end,
    abort_async_command=function() end,
    msg={info=function() end,warn=function() end,debug=function() end},
}
local files={}
local removed={}
local fs={
    info=function(path)
        if path==source or path==source:lower() then return {size=100,mtime=1,is_file=true,is_dir=false} end
        local v=files[path]; if v then return {size=#v,mtime=1,is_file=true,is_dir=false} end
        return nil
    end,
    size=function(path) local v=files[path]; return v and #v or nil end,
    exists=function(path) return files[path]~=nil end,
    read=function(path) return files[path] end,
    create_exclusive=function() return false,"disabled" end,
    remove=function(path) removed[#removed+1]=path; files[path]=nil; return true end,
    rename=function() return false,"destination busy" end,
    mkdir=function() return true end,
    list=function() return {} end,
}

local controller=require("uosc_waveform.controller")
local app=controller.start({
    mp=mp,fs=fs,now=function() return 1000 end,session_id="fallback",
    raw_options={cache_dir=[[C:\Cache]],media_debounce_ms=0,resize_debounce_ms=0,source_width=256,source_height=16,minimum_timeline_width=1},
    context={config_dir=[[C:\Config]],platform="windows"},
    uosc_config={timeline_size=40,progress="windowed",progress_size=2},uosc_detected=true,
})
events["file-loaded"]()
local before=app:debug_state()
assert(callback and before.active_temp, "generation must expose a unique active temp")
files[before.paths.raw]="BAD" -- unresolved stale destination; never delete it speculatively
files[before.active_temp]=string.rep("\0",before.expected_size)
callback(true,{status=0,stdout="",stderr=""},nil)
local after=app:debug_state()
assert(after.state==controller.STATES.READY_VISIBLE,"valid session temp must keep waveform usable when cache publication fails")
assert(after.raw==before.active_temp and after.ephemeral==true,"fallback output must be marked ephemeral")
assert(shown_path==before.active_temp,"overlay must render the preserved session temp")
assert(files[before.paths.raw]=="BAD","fallback must not delete a raced destination")
app:shutdown()
assert(files[before.active_temp]==nil,"ephemeral session output must be removed on shutdown")
print("PASS controller_publish_fallback")
