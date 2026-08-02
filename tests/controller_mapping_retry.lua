local root = assert(arg[1], "source root required")
package.path = root .. "/portable_config/scripts/?.lua;" .. root .. "/portable_config/scripts/?/init.lua;" .. package.path
local events, commands, callbacks = {}, {}, {}
local source=[[C:\Media\clip.mkv]]
local props={path=source,["stream-open-filename"]=source,duration=10,aid=1,edition=0,["audio-delay"]=0,
    ["track-list"]={{type="audio",id=1,selected=true,["ff-index"]=7}},["background-color"]="#000000"}
local mp={
    get_property_native=function(n,d) local v=props[n]; if v==nil then return d end; return v end,
    observe_property=function() end, register_event=function(n,cb) events[n]=cb end,
    register_script_message=function() end, add_key_binding=function() end,
    command_native=function() return true end,
    command_native_async=function(cmd,cb) commands[#commands+1]=cmd; callbacks[#callbacks+1]=cb; return #commands end,
    abort_async_command=function() end,
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
    create_exclusive=function() return false,"disabled" end,
    remove=function(path) files[path]=nil; return true end,
    rename=function(a,b) files[b]=files[a]; files[a]=nil; return true end,
    mkdir=function() return true end, list=function() return {} end,
}
local function filter(cmd) for i,v in ipairs(cmd.args) do if v=="-filter_complex" then return cmd.args[i+1] end end end
local controller=require("uosc_waveform.controller")
local app=controller.start({mp=mp,fs=fs,raw_options={cache_dir=[[C:\Cache]],media_debounce_ms=0,source_width=256,source_height=16},context={config_dir="",platform="windows"},uosc_config={},uosc_detected=true})
events["file-loaded"]()
assert(#commands==1 and filter(commands[1]):find("[0:7]",1,true))
callbacks[1](false,{status=1,stderr="Stream specifier ':7' in filtergraph matches no streams."},nil)
assert(#commands==2, "ff-index mapping failure must retry once with ordinal")
assert(filter(commands[2]):find("[0:a:0]",1,true), "retry must use audio ordinal")
assert(app:debug_state().state==controller.STATES.GENERATING)
print("PASS controller_mapping_retry")
