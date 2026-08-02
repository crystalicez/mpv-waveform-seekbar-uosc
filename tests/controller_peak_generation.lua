local root = assert(arg[1], "source root required")
package.path = root .. "/portable_config/scripts/?.lua;" .. root .. "/portable_config/scripts/?/init.lua;" .. package.path
local peak_metadata = assert(loadfile(root .. "/tests/helpers/peak_metadata.lua"))()

local source = "/tmp/peak-generation.m4a"
local events, callback = {}, nil
local files = {}
local app
local write_phase, rename_phase
local props = {
    path=source, ["stream-open-filename"]=source, duration=8, aid=1, edition=0,
    ["track-list"]={{type="audio",id=1,selected=true,["ff-index"]=0}},
    ["background-color"]="#000000", ["osd-width"]=800, ["osd-height"]=600,
    ["display-hidpi-scale"]=1, ["mouse-pos"]={x=400,y=590,hover=true}, focused=true,
}
local mp={
    get_property_native=function(name,default) local v=props[name]; if v==nil then return default end; return v end,
    observe_property=function() end,
    register_event=function(name,cb) events[name]=cb end,
    register_script_message=function() end, add_key_binding=function() end,
    command_native=function() return true end,
    command_native_async=function(command,cb)
        callback=cb
        local joined=table.concat(command.args,"\n")
        assert(joined:find("astats",1,true),"controller must launch bounded peak analyzer")
        assert(not joined:find("showwavespic",1,true),"controller must not launch old renderer")
        return 1
    end,
    abort_async_command=function() end,
    msg={info=function() end,warn=function() end,debug=function() end,error=function() end},
}
local fs={
    info=function(path)
        if path==source then return {size=100,mtime=1,is_file=true,is_dir=false} end
        local v=files[path]; if v then return {size=#v,mtime=2,is_file=true,is_dir=false} end
    end,
    size=function(path) local v=files[path]; return v and #v or nil end,
    exists=function(path) return files[path]~=nil end,
    read=function(path) return files[path] end,
    write=function(path,content)
        if not path:match("%.meta%.tmp$") then
            write_phase=app and app:debug_state().generation_phase
        end
        files[path]=content
        return true
    end,
    create_exclusive=function(path,content) files[path]=content; return true end,
    remove=function(path) files[path]=nil; return true end,
    rename=function(a,b)
        rename_phase=app:debug_state().generation_phase
        files[b]=files[a]; files[a]=nil; return true
    end,
    mkdir=function() return true end, list=function() return {} end,
}
local controller=require("uosc_waveform.controller")
app=controller.start({
    mp=mp,fs=fs,now=function() return 1000 end,session_id="peak",
    raw_options={cache_dir="/tmp/cache",media_debounce_ms=0,resize_debounce_ms=0,
        source_width=256,source_height=16,minimum_timeline_width=1,generation_timeout_seconds=0},
    context={config_dir="/tmp",platform="other"},
    uosc_config={timeline_size=40,controls_size=0},uosc_detected=true,
})
events["file-loaded"]()
local started=app:debug_state()
assert(started.state==controller.STATES.GENERATING and started.generation_phase=="analyzing",
    "uncached media must enter GENERATING/analyzing")
assert(callback,"generation callback required")
callback(true,{status=0,stdout=peak_metadata(256,8,-6.0206),stderr=""},nil)
local finished=app:debug_state()
assert(write_phase=="rendering","raw bitmap must be written during rendering phase")
assert(rename_phase=="publishing","cache rename must occur during publishing phase")
assert(finished.state==controller.STATES.READY_VISIBLE,"successful peak generation must become visible")
assert(finished.generation_phase==nil,"ready state must clear generation phase")
assert(finished.raw and #files[finished.raw]==256*16*4,"published bitmap must have exact BGRA size")
assert(finished.last_error==nil,"successful generation must clear prior errors")
print("PASS controller_peak_generation")
