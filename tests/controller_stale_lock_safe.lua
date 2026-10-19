local root = assert(arg[1], "source root required")
package.path = root .. "/portable_config/scripts/?.lua;" .. root .. "/portable_config/scripts/?/init.lua;" .. package.path
local source = "/tmp/stale-lock-source.m4a"
local events = {}
local start_count, lock_remove_count, exclusive_attempts = 0, 0, 0
local lock_path
local media = {
    path = source, ["stream-open-filename"] = source, duration = 12,
    aid = 1, ["track-list"] = {{type="audio", id=1, selected=true, ["ff-index"]=0}},
}
local mp = {
    get_property_native=function(name, default) local value=media[name]; if value==nil then return default end; return value end,
    observe_property=function() end,
    register_event=function(name, callback) events[name]=callback end,
    register_script_message=function() end,
    add_key_binding=function() end,
    command_native=function() return {} end,
    command_native_async=function()
        start_count = start_count + 1
        return { id = start_count }
    end,
    abort_async_command=function() end,
    msg={info=function() end,warn=function() end,debug=function() end,error=function() end},
}
local fs = {
    info=function(path)
        if path == source then return {size=200,mtime=1,is_file=true,is_dir=false} end
        if path == lock_path then return {size=40,mtime=1,is_file=true,is_dir=false} end
    end,
    size=function(path) return path == lock_path and 40 or nil end,
    exists=function(path) return path == lock_path end,
    read=function(path) if path == lock_path then return "created=1\nowner=old-session\npid=0\n" end end,
    create_exclusive=function(path)
        assert(path == lock_path)
        exclusive_attempts = exclusive_attempts + 1
        return false, "exists"
    end,
    remove=function(path)
        if path == lock_path then lock_remove_count=lock_remove_count+1 end
        return true
    end,
    mkdir=function() return true end,
    list=function() return {} end,
}
local cache = require("uosc_waveform.cache")
local original_paths = cache.paths
cache.paths = function(...)
    local p = original_paths(...)
    lock_path = p.lock
    return p
end
local controller = require("uosc_waveform.controller")
local app = controller.start({
    mp=mp, fs=fs, now=function() return 5000 end, session_id="our-session",
    raw_options={cache_dir="/tmp/cache", media_debounce_ms=0, generation_timeout_seconds=0},
    context={config_dir="/tmp",platform="other"}, uosc_config={},uosc_detected=true,
})
events["file-loaded"]()
local state = app:debug_state()
assert(state.state == controller.STATES.GENERATING, "stale peer lock should allow unowned generation")
assert(exclusive_attempts == 1 and start_count == 1)
assert(lock_remove_count == 0, "stale lock must never be unlinked based on an earlier status check")
app:shutdown()
assert(lock_remove_count == 0, "unowned generation must not remove a peer lock on shutdown")
cache.paths = original_paths
print("PASS controller_stale_lock_safe")
