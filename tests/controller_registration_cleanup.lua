local root=assert(arg[1],"source root required")
package.path=root.."/portable_config/scripts/?.lua;"..root.."/portable_config/scripts/?/init.lua;"..package.path
local observed,events,messages,bindings={},{},{},{}
local removed_observers,removed_events,removed_messages,removed_bindings={},{},{},{}
local properties={}
local mp={
 command_native=function() return true end,
 get_property_native=function(name,default)local v=properties[name];if v==nil then return default end;return v end,
 set_property_native=function(name,value) properties[name]=value end,
 observe_property=function(name,kind,cb) observed[#observed+1]={name=name,kind=kind,cb=cb} end,
 unobserve_property=function(cb) removed_observers[cb]=(removed_observers[cb] or 0)+1 end,
 register_event=function(name,cb) events[#events+1]={name=name,cb=cb} end,
 unregister_event=function(cb) removed_events[cb]=(removed_events[cb] or 0)+1 end,
 register_script_message=function(name,cb) messages[#messages+1]={name=name,cb=cb} end,
 unregister_script_message=function(name) removed_messages[name]=(removed_messages[name] or 0)+1 end,
 add_key_binding=function(key,name,cb) bindings[#bindings+1]={key=key,name=name,cb=cb} end,
 remove_key_binding=function(name) removed_bindings[name]=(removed_bindings[name] or 0)+1 end,
 msg={info=function() end,warn=function() end,debug=function() end,error=function() end},
}
local fs={remove=function() return true end}
local controller=require("uosc_waveform.controller")
local app=controller.start({mp=mp,fs=fs,session_id="owner-a",raw_options={enabled=false},context={config_dir="",platform="other"},uosc_config={},uosc_detected=true})
assert(#observed>0 and #events>0 and #messages==1 and #bindings==2,"startup must register all callback classes")
assert(properties["user-data/uosc-waveform/owner"]=="owner-a","startup must claim same-process ownership")
app:shutdown()
for _,item in ipairs(observed) do assert(removed_observers[item.cb]==1,"every observer callback must be removed exactly once") end
for _,item in ipairs(events) do assert(removed_events[item.cb]==1,"every event callback must be removed exactly once") end
for _,item in ipairs(messages) do assert(removed_messages[item.name]==1,"every script message must be removed exactly once") end
for _,item in ipairs(bindings) do assert(removed_bindings[item.name]==1,"every key binding must be removed exactly once") end
assert(properties["user-data/uosc-waveform/owner"]==nil or properties["user-data/uosc-waveform/owner"]=="","shutdown must release ownership")
app:shutdown()
for _,item in ipairs(observed) do assert(removed_observers[item.cb]==1,"second shutdown must not unobserve twice") end
for _,item in ipairs(events) do assert(removed_events[item.cb]==1,"second shutdown must not unregister events twice") end
print("PASS controller_registration_cleanup")
