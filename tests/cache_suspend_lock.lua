local root=assert(arg[1],"source root required")
package.path=root.."/portable_config/scripts/?.lua;"..root.."/portable_config/scripts/?/init.lua;"..package.path
local cache=require("uosc_waveform.cache")
local content="created=100\nowner=peer\npid=4242\n"
local alive=true
local liveness_calls=0
local written=nil
local fs={
 exists=function(path) return path=="/cache/a.lock" end,
 read=function() return content end,
 process_alive=function(pid) liveness_calls=liveness_calls+1;assert(pid==4242);return alive end,
 create_exclusive=function(path,payload) written=payload;return true end,
}
assert(cache.lock_status(fs,"/cache/a.lock",500,900)=="active","young lock must be active")
assert(liveness_calls==0,"young lock must not spawn a liveness check")
assert(cache.lock_status(fs,"/cache/a.lock",3700,900)=="active","old lock with live PID must survive suspend")
assert(liveness_calls==1)
alive=false
assert(cache.lock_status(fs,"/cache/a.lock",3700,900)=="stale","old lock with dead PID must be stale")
assert(liveness_calls==2)
local no_probe={exists=fs.exists,read=fs.read}
assert(cache.lock_status(no_probe,"/cache/a.lock",3700,900)=="stale","old lock without liveness bridge must fail stale")
content="created=100\nowner=legacy\n"
assert(cache.lock_status(fs,"/cache/a.lock",3700,900)=="stale","legacy old lock without PID must be stale")
content="garbage"
assert(cache.lock_status(fs,"/cache/a.lock",3700,900)=="stale","malformed lock must be stale")
local ok=cache.acquire_lock(fs,"/cache/new.lock",100,"ours",777)
assert(ok and written:find("created=100",1,true) and written:find("owner=ours",1,true),"lock payload must retain created and owner")
assert(written:find("pid=777",1,true),"lock payload must include owner PID")
print("PASS cache_suspend_lock")
