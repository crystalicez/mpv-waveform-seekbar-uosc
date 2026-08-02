local root=assert(arg[1],"source root required")
package.path=root.."/portable_config/scripts/?.lua;"..root.."/portable_config/scripts/?/init.lua;"..package.path
local windows_lock=require("uosc_waveform.windows_lock")
local spec=windows_lock.process_alive_command_spec(4242,{
 "PATH=C:\\Windows\\System32",
 "mpv_waveform_process_id=stale",
})
assert(type(spec)=="table" and type(spec.args)=="table" and type(spec.env)=="table")
assert(spec.args[1]=="powershell.exe" and #spec.args==5 and spec.args[4]=="-Command")
assert(spec.args[5]:find("Get%-Process"),"liveness command must query the process")
assert(spec.args[5]:find("MPV_WAVEFORM_PROCESS_ID",1,true),"PID must be read from environment")
local env,count={},0
for _,item in ipairs(spec.env) do
 local name,value=item:match("^([^=]+)=(.*)$")
 if name then env[name:upper()]=value end
 if item:upper():match("^MPV_WAVEFORM_PROCESS_ID=") then count=count+1 end
end
assert(env.PATH==[[C:\Windows\System32]])
assert(env.MPV_WAVEFORM_PROCESS_ID=="4242")
assert(count==1,"stale inherited PID variable must be replaced")
print("PASS windows_process_alive_command")
