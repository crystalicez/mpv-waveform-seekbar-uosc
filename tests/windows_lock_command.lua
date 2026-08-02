local root = assert(arg[1], "source root required")
package.path = table.concat({
    root .. "/portable_config/scripts/?.lua",
    root .. "/portable_config/scripts/?/init.lua",
    package.path,
}, ";")

local windows_lock = require("uosc_waveform.windows_lock")
local spec = windows_lock.command_spec(
    [[C:\Users\Ice\AppData\Roaming\mpv\cache\uosc-waveform\abc.lock]],
    1785655130,
    "owner with spaces & symbols",
    4321,
    {
        "PATH=C:\\Windows\\System32",
        "TEMP=C:\\Temp",
        "mpv_waveform_lock_path=stale",
        "MPV_WAVEFORM_LOCK_OWNER=stale-owner",
    }
)

assert(type(spec) == "table", "command_spec must return a table")
assert(type(spec.args) == "table", "command_spec.args must be a table")
assert(type(spec.env) == "table", "command_spec.env must be a table")
assert(spec.args[1] == "powershell.exe", "must use Windows PowerShell")
assert(spec.args[#spec.args - 1] == "-Command", "-Command must be the last PowerShell parameter")
assert(type(spec.args[#spec.args]) == "string" and spec.args[#spec.args]:find("MPV_WAVEFORM_LOCK_PATH", 1, true),
    "the final argument must be the complete PowerShell command")
assert(#spec.args == 5, "lock path and owner must not be appended after -Command")

local env = {}
for _, item in ipairs(spec.env) do
    local name, value = item:match("^([^=]+)=(.*)$")
    if name then env[name:upper()] = value end
end
assert(env.PATH == [[C:\Windows\System32]], "must preserve inherited PATH")
assert(env.TEMP == [[C:\Temp]], "must preserve inherited TEMP")
assert(env.MPV_WAVEFORM_LOCK_PATH == [[C:\Users\Ice\AppData\Roaming\mpv\cache\uosc-waveform\abc.lock]],
    "must pass the lock path through the environment")
assert(env.MPV_WAVEFORM_LOCK_CREATED == "1785655130", "must pass the creation timestamp")
assert(env.MPV_WAVEFORM_LOCK_OWNER == "owner with spaces & symbols", "must pass owner literally")
assert(env.MPV_WAVEFORM_LOCK_PID == "4321", "must pass process ID")

local path_count, owner_count = 0, 0
for _, item in ipairs(spec.env) do
    local upper = item:upper()
    if upper:match("^MPV_WAVEFORM_LOCK_PATH=") then path_count = path_count + 1 end
    if upper:match("^MPV_WAVEFORM_LOCK_OWNER=") then owner_count = owner_count + 1 end
end
assert(path_count == 1, "must replace stale lock-path variables case-insensitively")
assert(owner_count == 1, "must replace stale owner variables case-insensitively")

print("PASS windows_lock_command")

local mkdir_spec = windows_lock.mkdir_command_spec(
    [[C:\Users\Ice\AppData\Roaming\mpv\cache\uosc-waveform]],
    { "PATH=C:\\Windows\\System32", "MPV_WAVEFORM_DIRECTORY_PATH=stale" }
)
assert(mkdir_spec.args[#mkdir_spec.args - 1] == "-Command", "mkdir must keep -Command last")
assert(#mkdir_spec.args == 5, "mkdir path must not be appended after -Command")
local mkdir_env = {}
for _, item in ipairs(mkdir_spec.env) do
    local name, value = item:match("^([^=]+)=(.*)$")
    if name then mkdir_env[name:upper()] = value end
end
assert(mkdir_env.MPV_WAVEFORM_DIRECTORY_PATH == [[C:\Users\Ice\AppData\Roaming\mpv\cache\uosc-waveform]],
    "mkdir path must be passed through the environment")
print("PASS windows_mkdir_command")

local move_spec = windows_lock.move_command_spec(
    [[C:\ผู้ใช้\wave.tmp]], [[C:\ผู้ใช้\wave.bgra]],
    {"PATH=C:\\Windows\\System32", "MPV_WAVEFORM_SOURCE_PATH=stale"}
)
assert(#move_spec.args == 5 and move_spec.args[#move_spec.args - 1] == "-Command",
    "move paths must not be appended after -Command")
local move_env = {}
for _, item in ipairs(move_spec.env) do
    local name, value = item:match("^([^=]+)=(.*)$")
    if name then move_env[name:upper()] = value end
end
assert(move_env.MPV_WAVEFORM_SOURCE_PATH == [[C:\ผู้ใช้\wave.tmp]])
assert(move_env.MPV_WAVEFORM_DESTINATION_PATH == [[C:\ผู้ใช้\wave.bgra]])
assert(move_spec.args[#move_spec.args]:find("[IO.File]::Move", 1, true),
    "move fallback must use the wide-path .NET API")
print("PASS windows_move_command")

local delete_spec = windows_lock.delete_command_spec(
    [[C:\ผู้ใช้\wave.tmp]], {"MPV_WAVEFORM_DELETE_PATH=stale"}
)
local delete_env = {}
for _, item in ipairs(delete_spec.env) do
    local name, value = item:match("^([^=]+)=(.*)$")
    if name then delete_env[name:upper()] = value end
end
assert(delete_env.MPV_WAVEFORM_DELETE_PATH == [[C:\ผู้ใช้\wave.tmp]])
assert(delete_spec.args[#delete_spec.args]:find("[IO.File]::Delete", 1, true),
    "delete fallback must use the wide-path .NET API")
print("PASS windows_delete_command")
