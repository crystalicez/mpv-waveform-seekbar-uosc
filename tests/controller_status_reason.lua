local root = assert(arg[1], "source root required")
package.path = root .. "/portable_config/scripts/?.lua;" .. root .. "/portable_config/scripts/?/init.lua;" .. package.path

local events = {}
local source = "/tmp/song.m4a"
local props = {
    path = source, ["stream-open-filename"] = source, duration = 10, aid = "auto", ["track-list"] = {},
    ["demuxer-start-time"] = 0, ["rebase-start-time"] = true, ["audio-delay"] = 0,
    ["osd-width"] = 1000, ["osd-height"] = 600, ["display-hidpi-scale"] = 1,
    ["mouse-pos"] = { x = 500, y = 590, hover = true }, border = true, ["title-bar"] = true,
}
local last_osd
local mp = {
    get_property_native = function(name, default) local value=props[name]; if value==nil then return default end; return value end,
    observe_property = function() end,
    register_event = function(name, callback) events[name] = callback end,
    register_script_message = function() end,
    add_key_binding = function() end,
    command_native = function() return true end,
    osd_message = function(text) last_osd = text end,
    msg = { info=function() end, warn=function() end, debug=function() end, error=function() end },
}
local fs = {
    info=function(path) if path==source then return {size=100,mtime=1,is_file=true,is_dir=false} end end,
    mkdir=function() return true end, list=function() return {} end,
}
local controller = require("uosc_waveform.controller")
local app = controller.start({mp=mp,fs=fs,raw_options={cache_dir="/tmp/cache",media_debounce_ms=0},context={config_dir="/tmp",platform="other"},uosc_config={},uosc_detected=true})
events["file-loaded"]()
local details = app:show_status()
assert(details:find("reason=no%-audio"), "status must expose the unsupported reason")
assert(last_osd == details, "OSD must show the same diagnostic details")
print("PASS controller_status_reason")
