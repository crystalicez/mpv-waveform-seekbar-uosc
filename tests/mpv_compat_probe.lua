local root = assert(arg[1], "source root required")
package.path = root .. "/portable_config/scripts/?.lua;" .. root .. "/portable_config/scripts/?/init.lua;" .. package.path
local compat = require("uosc_waveform.mpv_compat")

local calls = {}
local dev = {
    get_property_native = function(name) if name == "mpv-version" then return "git-main" end end,
    command_native = function(command)
        calls[#calls + 1] = command
        if command._name == "expand-path" then return [[C:\Config]] end
        return false
    end,
}
local command = compat.named_command(dev, "overlay-add", { id = 63 })
assert(command._name == "overlay-add" and command.name == nil, "development build must use _name after probing")
assert(#calls == 1 and calls[1]._name == "expand-path", "compatibility probe must be read-only")
assert(calls[1]._name ~= "overlay-remove", "probe must not remove another script's overlay")

local stable_calls = 0
local stable = {
    get_property_native = function() return "0.41.0" end,
    command_native = function() stable_calls = stable_calls + 1 end,
}
local stable_command = compat.named_command(stable, "overlay-add", { id = 63 })
assert(stable_command.name == "overlay-add" and stable_command._name == nil)
assert(stable_calls == 0, "known stable versions do not need a probe")
print("PASS mpv_compat_probe")
