local entry = assert(arg[1], "entry path required")
local config_dir = assert(arg[2], "config path required")
if package.config:sub(1, 1) == "\\" then
    os.execute(string.format('mkdir "%s" >nul 2>&1', config_dir))
else
    os.execute(string.format('mkdir -p "%s"', config_dir))
end

package.preload["mp.utils"] = function()
    return {
        file_info = function() return nil end,
        readdir = function() return {} end,
    }
end

package.preload["mp.options"] = function()
    return { read_options = function(options)
        options.startup_osd = true
        options.diagnostic_log = true
    end }
end

local expanded = {}
local osd_messages = {}
_G.mp = {
    get_script_directory = function() return nil end,
    get_script_name = function() return "uosc_waveform" end,
    get_property_native = function(name, default)
        if name == "user-data/frontend/name" then return "mpv.net" end
        return default
    end,
    command_native = function(command)
        if type(command) == "table" and command[1] == "expand-path" then
            expanded[#expanded + 1] = command[2]
            return config_dir
        end
        return {}
    end,
    observe_property = function() end,
    register_event = function() end,
    register_script_message = function() end,
    add_key_binding = function() end,
    osd_message = function(message)
        osd_messages[#osd_messages + 1] = message
    end,
    msg = {
        warn = function() end,
        info = function() end,
        debug = function() end,
        error = function() end,
    },
}

local chunk, load_error = loadfile(entry)
assert(chunk, load_error)
local ok, result = pcall(chunk)
assert(ok, result)
assert(type(result) == "table", "entrypoint should return controller instance")
assert(expanded[1] == "~~home/", "entrypoint must resolve the actual config directory with ~~home/")
assert(#osd_messages >= 1 and osd_messages[1]:find("0.3.1", 1, true), "startup OSD should prove the versioned script loaded")

local log_path = config_dir:gsub("[\\/]$", "") .. package.config:sub(1, 1) .. "uosc-waveform.log"
local log = assert(io.open(log_path, "rb"), "diagnostic log should be created inside config directory")
local text = log:read("*a")
log:close()
assert(text:find("frontend=mpv.net", 1, true), "diagnostic log should include frontend")
assert(text:find("config_dir=", 1, true), "diagnostic log should include config directory")

print("PASS bootstrap_single_file")
