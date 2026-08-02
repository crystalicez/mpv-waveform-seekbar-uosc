local root = assert(arg[1], "source root required")
package.path = root .. "/portable_config/scripts/?.lua;" .. root .. "/portable_config/scripts/?/init.lua;" .. package.path
local observers, events, commands, cancelled = {}, {}, {}, 0
local source = [[C:\Media\clip.mkv]]
local props = {
    path=source, ["stream-open-filename"]=source, duration=20, aid=1, edition=0, ["audio-delay"]=0,
    ["track-list"]={{type="video",selected=true},{type="audio",id=1,selected=true,["ff-index"]=1}},
    ["demuxer-start-time"]=0, ["background-color"]="#000000",
}
local mp={
    get_property_native=function(name,default) local v=props[name]; if v==nil then return default end; return v end,
    observe_property=function(name,_,cb) observers[name]=cb end,
    register_event=function(name,cb) events[name]=cb end,
    register_script_message=function() end, add_key_binding=function() end,
    command_native=function() return true end,
    command_native_async=function(cmd) commands[#commands+1]=cmd; return #commands end,
    abort_async_command=function() cancelled=cancelled+1 end,
    msg={info=function() end,warn=function() end,debug=function() end},
}
local files={}
local fs={
    info=function(path) if path==source or path==source:lower() then return {size=100,mtime=1,is_file=true,is_dir=false} end end,
    size=function(path) return files[path] and #files[path] or nil end,
    exists=function(path) return files[path]~=nil end,
    read=function(path) return files[path] end,
    create_exclusive=function() return false,"disabled" end,
    remove=function(path) files[path]=nil; return true end,
    rename=function(a,b) files[b]=files[a]; files[a]=nil; return true end,
    mkdir=function() return true end,
    list=function() return {} end,
}
local function filter(cmd) for i,v in ipairs(cmd.args) do if v=="-filter_complex" then return cmd.args[i+1] end end end
local controller=require("uosc_waveform.controller")
controller.start({ mp=mp,fs=fs,raw_options={cache_dir=[[C:\Cache]],media_debounce_ms=0},context={config_dir="",platform="windows"},uosc_config={},uosc_detected=true })
events["file-loaded"]()
assert(#commands==1 and not filter(commands[1]):find("asetpts=",1,true))
props["audio-delay"]=1.5
observers["audio-delay"]()
assert(#commands==2, "audio-delay change must regenerate waveform")
assert(cancelled==1, "audio-delay change must cancel stale analysis")
assert(filter(commands[2]):find("asetpts=PTS+1.5/TB",1,true), "waveform must follow positive mpv audio-delay")
print("PASS controller_audio_delay")
