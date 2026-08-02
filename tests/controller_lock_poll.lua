local root = assert(arg[1], "source root required")
package.path = root .. "/portable_config/scripts/?.lua;" .. root .. "/portable_config/scripts/?/init.lua;" .. package.path

local events, timers = {}, {}
local source = [[C:\Media\clip.mkv]]
local props = {
    path = source, ["stream-open-filename"] = source, duration = 10, aid = 1, edition = 0,
    ["track-list"] = {{type="audio", id=1, selected=true, ["ff-index"]=0}},
    ["background-color"] = "#000000",
}
local mp = {
    get_property_native=function(name, default) local v=props[name]; if v==nil then return default end; return v end,
    observe_property=function() end,
    register_event=function(name, cb) events[name]=cb end,
    register_script_message=function() end, add_key_binding=function() end,
    add_timeout=function(seconds, cb)
        local timer={seconds=seconds, callback=cb, dead=false}
        function timer:kill() self.dead=true end
        timers[#timers+1]=timer
        return timer
    end,
    command_native=function() return true end,
    command_native_async=function() error("generation must not start while peer cache is expected") end,
    msg={info=function() end,warn=function() end,debug=function() end},
}
local files = {}
local now = 100
local fs = {
    info=function(path)
        if path==source or path==source:lower() then return {size=100,mtime=1,is_file=true,is_dir=false} end
        if files[path] then return {size=files[path].size,mtime=now,is_file=true,is_dir=false} end
    end,
    size=function(path) return files[path] and files[path].size or nil end,
    exists=function(path) return files[path] ~= nil end,
    read=function(path) return files[path] and files[path].content or nil end,
    create_exclusive=function(path, content)
        if files[path] then return false, "exists" end
        files[path]={size=#content,content=content}; return true
    end,
    remove=function(path) files[path]=nil; return true end,
    rename=function() return false,"unexpected" end,
    mkdir=function() return true end, list=function() return {} end,
}

local controller=require("uosc_waveform.controller")
local app=controller.start({
    mp=mp, fs=fs, now=function() return now end, session_id="waiter",
    raw_options={cache_dir=[[C:\Cache]], source_width=4, source_height=2,
        media_debounce_ms=0, lock_poll_ms=10},
    context={config_dir="",platform="windows"}, uosc_config={}, uosc_detected=true,
})

-- Derive the paths, then simulate a peer-owned active lock before the first refresh.
-- Initial unsupported state has no paths, so create the exact cache paths from the
-- same media metadata through the public controller refresh once the lock fixture
-- can be installed by intercepting create_exclusive.
local original_create = fs.create_exclusive
fs.create_exclusive=function(path, content)
    files[path]={size=30, content="created=100\nowner=peer\n"}
    return false,"exists"
end

events["file-loaded"]()
assert(app:debug_state().state == controller.STATES.WAITING_FOR_LOCK, "active peer lock must enter waiting state")
local paths=assert(app:debug_state().paths)
assert(#timers >= 1, "waiting state must schedule a lock poll")

-- Peer finishes between polls: valid canonical cache appears and lock disappears.
files[paths.raw]={size=256*16*4,content=string.rep("x",256*16*4)}
files[paths.lock]=nil
fs.create_exclusive=original_create
local poll=timers[#timers]
assert(not poll.dead, "lock poll timer should still be active")
poll.callback()
assert(app:debug_state().state ~= controller.STATES.WAITING_FOR_LOCK,
    "lock poll must re-check peer output instead of coalescing forever")
assert(app:debug_state().raw == paths.raw, "lock poll must adopt the peer cache")

print("PASS controller_lock_poll")
