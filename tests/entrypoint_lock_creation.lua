local root = assert(arg[1], "source root required")
local scripts = root .. "/portable_config/scripts"
package.path = scripts .. "/?.lua;" .. scripts .. "/?/init.lua;" .. package.path

local commands, captured, existing_path = {}, nil, nil
local execute_real = false

package.preload["mp.utils"] = function()
    return {
        file_info = function(path)
            if path == existing_path then return { is_file = true } end
            return nil
        end,
        readdir = function() return {} end,
    }
end
package.preload["mp.options"] = function()
    return { read_options = function(opts) opts.diagnostic_log = "no" end }
end
package.loaded["uosc_waveform.controller"] = {
    start = function(context)
        captured = context
        return context
    end,
}

local function shell_quote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

_G.mp = {
    get_script_directory = function() return scripts end,
    get_property_native = function(name, default)
        if name == "mpv-version" then return "0.41.0" end
        return default
    end,
    get_time = function() return 1 end,
    command_native = function(command)
        if command[1] == "expand-path" then return root end
        assert(command.name == "subprocess" or command._name == "subprocess")
        commands[#commands + 1] = command
        if execute_real then
            local quoted = {}
            for i, value in ipairs(command.args) do quoted[i] = shell_quote(value) end
            local status = os.execute(table.concat(quoted, " ") .. " 2>/dev/null")
            return { status = (status == true or status == 0) and 0 or 1 }
        end
        return { status = 0 }
    end,
}

local entry = assert(loadfile(scripts .. "/uosc-waveform.lua"))
entry()
local fs = assert(captured and captured.fs, "must capture filesystem adapter")
local payload = "created=123\nowner=weird ' $HOME ; ไทย\npid=4321\n"
local path = "/tmp/waveform test ' $HOME ; [unicode] .lock"
local windows = package.config:sub(1, 1) == "\\"

if windows then
    local real_open = io.open
    local mode_attempts = 0
    io.open = function(name, mode)
        if mode == "wx" then
            mode_attempts = mode_attempts + 1
            error("invalid mode") -- some Windows Lua builds throw instead of returning nil
        end
        return real_open(name, mode)
    end

    local ok, err = fs.create_exclusive(path, payload, 123)
    assert(ok, tostring(err))
    assert(mode_attempts == 1, "Windows must try the native exclusive mode")
    local spec = assert(commands[#commands])
    assert(spec.args[1] == "powershell.exe", "invalid-mode error must reach the CreateNew fallback")
    assert(spec.args[#spec.args]:find("CreateNew", 1, true), "fallback must be exclusive")

    existing_path = path
    local count = #commands
    assert(not fs.create_exclusive(path, payload, 123), "existing lock must be preserved")
    assert(#commands == count, "existing lock must not trigger fallback creation")
    existing_path = nil

    io.open = function(name, mode)
        if mode == "wx" then
            return {
                write = function(_, value) assert(value == payload); return true end,
                close = function() end,
            }
        end
        return real_open(name, mode)
    end
    assert(fs.create_exclusive(path, payload, 123), "native exclusive creation should still work")
    assert(#commands == count, "native creation should not run PowerShell")
    io.open = real_open
else
    local real_open = io.open
    io.open = function(name, mode)
        assert(mode ~= "wx", "POSIX must not call the unsupported wx mode")
        return real_open(name, mode)
    end
    local ok, err = fs.create_exclusive(path, payload, 123)
    assert(ok, tostring(err))
    local spec = assert(commands[#commands])
    assert(spec.args[1] == "/bin/sh" and spec.args[2] == "-c", "POSIX must invoke sh directly")
    assert(spec.args[3] == 'set -C; printf %s "$2" > "$1"', "POSIX must use noclobber redirection")
    assert(spec.args[4] == "uosc-waveform-lock" and spec.args[5] == path and spec.args[6] == payload,
        "path and payload must be literal positional arguments, not shell source")
    io.open = real_open

    local temp = os.tmpname()
    os.remove(temp)
    local real_path = temp .. " ' ; ไทย $HOME.lock"
    execute_real = true
    local created, create_err = fs.create_exclusive(real_path, payload, 123)
    assert(created, tostring(create_err))
    local f = assert(io.open(real_path, "rb"))
    local first = f:read("*a")
    f:close()
    assert(first == payload, "POSIX creation must preserve all literal bytes")
    local replaced = fs.create_exclusive(real_path, "overwritten", 124)
    assert(not replaced, "second contender must not replace the first lock")
    f = assert(io.open(real_path, "rb"))
    assert(f:read("*a") == payload, "existing POSIX lock must remain untouched")
    f:close()
    assert(os.remove(real_path), "POSIX test lock cleanup")
end

print("PASS entrypoint_lock_creation")
