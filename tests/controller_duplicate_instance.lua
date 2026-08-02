local root=assert(arg[1],"source root required")
package.path=root.."/portable_config/scripts/?.lua;"..root.."/portable_config/scripts/?/init.lua;"..package.path
local props={}
local registrations=0
local mp={
 command_native=function() return true end,
 get_property_native=function(name,default)local v=props[name];if v==nil then return default end;return v end,
 set_property_native=function(name,value) props[name]=value end,
 observe_property=function() registrations=registrations+1 end,unobserve_property=function() end,
 register_event=function() registrations=registrations+1 end,unregister_event=function() end,
 register_script_message=function() registrations=registrations+1 end,unregister_script_message=function() end,
 add_key_binding=function() registrations=registrations+1 end,remove_key_binding=function() end,
 osd_message=function() end,msg={info=function() end,warn=function() end,debug=function() end,error=function() end},
}
local fs={remove=function() return true end}
local controller=require("uosc_waveform.controller")
local first=controller.start({mp=mp,fs=fs,session_id="first",raw_options={enabled=false},context={config_dir="",platform="other"},uosc_config={},uosc_detected=true})
local after_first=registrations
assert(after_first>0 and props["user-data/uosc-waveform/owner"]=="first")
local second=controller.start({mp=mp,fs=fs,session_id="second",raw_options={enabled=false},context={config_dir="",platform="other"},uosc_config={},uosc_detected=true})
local second_state=second:debug_state()
assert(second_state.state==controller.STATES.ERROR,"duplicate instance must be inert ERROR")
assert(second_state.last_error and second_state.last_error.code=="duplicate-instance")
assert(registrations==after_first,"duplicate instance must not register callbacks")
assert(props["user-data/uosc-waveform/owner"]=="first","duplicate must not steal ownership")
second:shutdown()
assert(props["user-data/uosc-waveform/owner"]=="first","duplicate shutdown must not clear real owner")
first:shutdown()
local third=controller.start({mp=mp,fs=fs,session_id="third",raw_options={enabled=false},context={config_dir="",platform="other"},uosc_config={},uosc_detected=true})
assert(registrations>after_first,"clean startup after shutdown must register again")
assert(third:debug_state().state==controller.STATES.DISABLED)
third:shutdown()
print("PASS controller_duplicate_instance")
