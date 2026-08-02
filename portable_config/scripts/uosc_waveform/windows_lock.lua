local M = {}

local VARIABLE_NAMES = {
    MPV_WAVEFORM_LOCK_PATH = true,
    MPV_WAVEFORM_LOCK_CREATED = true,
    MPV_WAVEFORM_LOCK_OWNER = true,
    MPV_WAVEFORM_LOCK_PID = true,
    MPV_WAVEFORM_PROCESS_ID = true,
    MPV_WAVEFORM_DIRECTORY_PATH = true,
    MPV_WAVEFORM_SOURCE_PATH = true,
    MPV_WAVEFORM_DESTINATION_PATH = true,
    MPV_WAVEFORM_DELETE_PATH = true,
}

local POWERSHELL_COMMAND = table.concat({
    "$ErrorActionPreference='Stop';",
    "$p=$env:MPV_WAVEFORM_LOCK_PATH;",
    "$created=$env:MPV_WAVEFORM_LOCK_CREATED;",
    "$owner=$env:MPV_WAVEFORM_LOCK_OWNER;",
    "$pidValue=$env:MPV_WAVEFORM_LOCK_PID;",
    "$c=\"created=$created`nowner=$owner`npid=$pidValue`n\";",
    "$b=[Text.Encoding]::UTF8.GetBytes($c);",
    "$s=[IO.File]::Open($p,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read);",
    "try{$s.Write($b,0,$b.Length)}finally{if($null -ne $s){$s.Dispose()}}",
})


local MKDIR_COMMAND = table.concat({
    "$ErrorActionPreference='Stop';",
    "[IO.Directory]::CreateDirectory($env:MPV_WAVEFORM_DIRECTORY_PATH) | Out-Null",
})

local MOVE_COMMAND = table.concat({
    "$ErrorActionPreference='Stop';",
    "[IO.File]::Move($env:MPV_WAVEFORM_SOURCE_PATH,$env:MPV_WAVEFORM_DESTINATION_PATH)",
})

local DELETE_COMMAND = table.concat({
    "$ErrorActionPreference='Stop';",
    "[IO.File]::Delete($env:MPV_WAVEFORM_DELETE_PATH)",
})

local PROCESS_ALIVE_COMMAND = table.concat({
    "$ErrorActionPreference='Stop';",
    "$pidValue=[int]$env:MPV_WAVEFORM_PROCESS_ID;",
    "Get-Process -Id $pidValue -ErrorAction Stop | Out-Null",
})

local function variable_name(item)
    return tostring(item or ""):match("^([^=]+)=")
end


local function clean_environment(inherited_env)
    local env = {}
    for _, item in ipairs(inherited_env or {}) do
        local name = variable_name(item)
        if not (name and VARIABLE_NAMES[name:upper()]) then
            env[#env + 1] = item
        end
    end
    return env
end

function M.command_spec(path, created, owner, pid, inherited_env)
    local env = clean_environment(inherited_env)
    env[#env + 1] = "MPV_WAVEFORM_LOCK_PATH=" .. tostring(path or "")
    env[#env + 1] = "MPV_WAVEFORM_LOCK_CREATED=" .. tostring(tonumber(created) or 0)
    env[#env + 1] = "MPV_WAVEFORM_LOCK_OWNER=" .. tostring(owner or "unknown")
    env[#env + 1] = "MPV_WAVEFORM_LOCK_PID=" .. tostring(tonumber(pid) or 0)

    return {
        args = {
            "powershell.exe",
            "-NoProfile",
            "-NonInteractive",
            "-Command",
            POWERSHELL_COMMAND,
        },
        env = env,
    }
end


function M.mkdir_command_spec(path, inherited_env)
    local env = clean_environment(inherited_env)
    env[#env + 1] = "MPV_WAVEFORM_DIRECTORY_PATH=" .. tostring(path or "")
    return {
        args = {
            "powershell.exe",
            "-NoProfile",
            "-NonInteractive",
            "-Command",
            MKDIR_COMMAND,
        },
        env = env,
    }
end

function M.move_command_spec(source, destination, inherited_env)
    local env = clean_environment(inherited_env)
    env[#env + 1] = "MPV_WAVEFORM_SOURCE_PATH=" .. tostring(source or "")
    env[#env + 1] = "MPV_WAVEFORM_DESTINATION_PATH=" .. tostring(destination or "")
    return {
        args = {
            "powershell.exe",
            "-NoProfile",
            "-NonInteractive",
            "-Command",
            MOVE_COMMAND,
        },
        env = env,
    }
end

function M.delete_command_spec(path, inherited_env)
    local env = clean_environment(inherited_env)
    env[#env + 1] = "MPV_WAVEFORM_DELETE_PATH=" .. tostring(path or "")
    return {
        args = {
            "powershell.exe",
            "-NoProfile",
            "-NonInteractive",
            "-Command",
            DELETE_COMMAND,
        },
        env = env,
    }
end

function M.process_alive_command_spec(pid, inherited_env)
    local env = clean_environment(inherited_env)
    env[#env + 1] = "MPV_WAVEFORM_PROCESS_ID=" .. tostring(tonumber(pid) or 0)
    return {
        args = {
            "powershell.exe",
            "-NoProfile",
            "-NonInteractive",
            "-Command",
            PROCESS_ALIVE_COMMAND,
        },
        env = env,
    }
end

return M
