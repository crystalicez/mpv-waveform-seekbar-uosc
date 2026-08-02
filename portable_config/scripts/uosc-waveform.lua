local SCRIPT_VERSION = "0.2.1"

local function resolve_script_directory()
    local packaged = mp.get_script_directory and mp.get_script_directory() or nil
    if type(packaged) == "string" and packaged ~= "" then return packaged end

    local source = debug.getinfo(1, "S").source
    if type(source) == "string" and source:sub(1, 1) == "@" then
        local directory = source:sub(2):match("^(.*)[\\/][^\\/]+$")
        if directory and directory ~= "" then return directory end
    end
    return "."
end

local script_directory = resolve_script_directory()
package.path = table.concat({
    script_directory .. "/?.lua",
    script_directory .. "/?/init.lua",
    package.path,
}, ";")

local controller = require("uosc_waveform.controller")
local options = require("uosc_waveform.options")
local util = require("uosc_waveform.util")
local mpv_compat = require("uosc_waveform.mpv_compat")
local windows_lock = require("uosc_waveform.windows_lock")
local utils = require("mp.utils")
local options_api = require("mp.options")

local windows = package.config:sub(1, 1) == "\\"

local function expand_path(value)
    if mp.command_native then
        local ok, result = pcall(mp.command_native, { "expand-path", value })
        if ok and type(result) == "string" and result ~= "" then return result end
    end
    if value == "~~/" or value == "~~" or value == "~~home/" or value == "~~home" then
        return script_directory:gsub("[\\/]scripts$", "")
    end
    return value
end

local function read_binary(path)
    local file = io.open(path, "rb")
    if not file then return nil end
    local content = file:read("*a")
    file:close()
    return content
end

local function write_binary(path, content)
    local file, err = io.open(path, "wb")
    if not file then return false, err end
    local ok, write_err = file:write(content or "")
    file:close()
    if not ok then return false, write_err end
    return true
end

local function subprocess(args, extra)
    if not mp.command_native then return false, "subprocess-unavailable" end
    local fields = {
        playback_only = false,
        capture_stdout = true,
        capture_stderr = true,
        args = args,
    }
    if extra and extra.env then fields.env = extra.env end
    local ok, result = pcall(mp.command_native, mpv_compat.named_command(mp, "subprocess", fields))
    if not ok then return false, result end
    if type(result) == "table" then
        local status = tonumber(result.status)
        if status ~= nil and status ~= 0 then
            local function nonempty(value)
                if value == nil then return nil end
                local text = tostring(value)
                if text == "" then return nil end
                return text
            end
            local detail = nonempty(result.stderr)
                or nonempty(result.stdout)
                or nonempty(result.error_string)
                or ("status=" .. tostring(status))
            return false, detail
        end
    end
    return true
end

local function ensure_directory(path)
    local info = utils.file_info and utils.file_info(path) or nil
    if info and info.is_dir then return true end
    if windows then
        local inherited_env = utils.get_env_list and utils.get_env_list() or {}
        local spec = windows_lock.mkdir_command_spec(path, inherited_env)
        return subprocess(spec.args, { env = spec.env })
    end
    return subprocess({ "/bin/mkdir", "-p", path })
end

local function create_exclusive(path, content, created)
    -- Modern Windows CRT/Lua builds support exclusive "x" creation directly,
    -- which avoids spawning PowerShell on the common path. Unicode/older CRT
    -- failures fall back to the wide-path PowerShell helper below.
    local file, err = io.open(path, "wx")
    if file then
        local ok, write_err = file:write(content or "")
        file:close()
        if not ok then os.remove(path); return false, write_err end
        return true
    end
    local existing = utils.file_info and utils.file_info(path) or nil
    if existing then return false, err or "exists" end
    if windows then
        local owner = tostring(content or ""):match("owner=([^\r\n]+)") or "unknown"
        local inherited_env = utils.get_env_list and utils.get_env_list() or {}
        local spec = windows_lock.command_spec(path, created, owner, inherited_env)
        return subprocess(spec.args, { env = spec.env })
    end
    return false, err or "exists"
end

local fs = {}

function fs.info(path)
    if not utils.file_info then return nil end
    local info = utils.file_info(path)
    if not info then return nil end
    return {
        size = tonumber(info.size) or 0,
        mtime = tonumber(info.mtime or info.modification) or 0,
        is_file = info.is_file == true,
        is_dir = info.is_dir == true,
    }
end
function fs.size(path) local info = fs.info(path); return info and info.size or nil end
function fs.mtime(path) local info = fs.info(path); return info and info.mtime or nil end
function fs.exists(path) return fs.info(path) ~= nil end
function fs.read(path) return read_binary(path) end
function fs.write(path, content) return write_binary(path, content) end
function fs.create_exclusive(path, content, created) return create_exclusive(path, content, created) end
function fs.remove(path)
    if not path or path == "" then return true end
    local ok, err = os.remove(path)
    if ok or not fs.exists(path) then return true end
    if windows then
        local inherited_env = utils.get_env_list and utils.get_env_list() or {}
        local spec = windows_lock.delete_command_spec(path, inherited_env)
        local fallback_ok, fallback_err = subprocess(spec.args, { env = spec.env })
        if fallback_ok or not fs.exists(path) then return true end
        return false, fallback_err or err
    end
    return false, err
end
function fs.rename(source, destination)
    local ok, err = os.rename(source, destination)
    if ok then return true end
    if windows and fs.exists(source) and not fs.exists(destination) then
        local inherited_env = utils.get_env_list and utils.get_env_list() or {}
        local spec = windows_lock.move_command_spec(source, destination, inherited_env)
        local fallback_ok, fallback_err = subprocess(spec.args, { env = spec.env })
        if fallback_ok then return true end
        return false, fallback_err or err
    end
    return false, err
end
function fs.mkdir(path) return ensure_directory(path) end
function fs.list(directory)
    if not utils.readdir then return {} end
    local names = utils.readdir(directory, "files") or {}
    local entries = {}
    for _, name in ipairs(names) do
        local path = util.join_path(directory, name)
        local info = fs.info(path)
        if info and info.is_file then
            entries[#entries + 1] = { path = path, size = info.size, mtime = info.mtime }
        end
    end
    table.sort(entries, function(a, b) return a.path < b.path end)
    return entries
end

local config_directory = expand_path("~~home/")
local raw_options = options.defaults()
options_api.read_options(raw_options, "uosc-waveform")

local function option_enabled(value, default)
    if value == nil then return default end
    if type(value) == "boolean" then return value end
    local text = tostring(value):lower()
    if text == "yes" or text == "true" or text == "1" or text == "on" then return true end
    if text == "no" or text == "false" or text == "0" or text == "off" then return false end
    return default
end

local diagnostic_path = util.join_path(config_directory, "uosc-waveform.log")
local diagnostic_prepared = false
local function prepare_diagnostic_log()
    if diagnostic_prepared then return end
    diagnostic_prepared = true
    local info = fs.info(diagnostic_path)
    if info and info.size > 2 * 1024 * 1024 then
        local previous = diagnostic_path .. ".old"
        fs.remove(previous)
        -- Another mpv instance may have the same diagnostic file open. If
        -- rotation loses that race, keep appending instead of truncating a log
        -- that another process is actively using.
        fs.rename(diagnostic_path, previous)
    end
end
local function diagnostic_log(level, message)
    if not option_enabled(raw_options.diagnostic_log, true) then return end
    prepare_diagnostic_log()
    local file = io.open(diagnostic_path, "ab")
    if not file then return end
    file:write(string.format("%s [%s] %s\n", os.date("!%Y-%m-%dT%H:%M:%SZ"), tostring(level), tostring(message)))
    file:close()
end

local frontend_name = mp.get_property_native and mp.get_property_native("user-data/frontend/name", "mpv") or "mpv"
diagnostic_log("info", string.format(
    "loaded version=%s frontend=%s config_dir=%s script_dir=%s",
    SCRIPT_VERSION, tostring(frontend_name), tostring(config_directory), tostring(script_directory)
))
local uosc_path = util.join_path(config_directory, "script-opts", "uosc.conf")
local uosc_text = read_binary(uosc_path)
local uosc_config = options.parse_key_value_file(uosc_text or "")
local uosc_legacy_path = util.join_path(config_directory, "scripts", "uosc.lua")
local uosc_main_path = util.join_path(config_directory, "scripts", "uosc", "main.lua")
local uosc_detected = fs.exists(uosc_legacy_path) or fs.exists(uosc_main_path)
diagnostic_log("info", "uosc_file_detected=" .. tostring(uosc_detected))
if option_enabled(raw_options.startup_osd, false) and mp.osd_message then
    mp.osd_message(string.format(
        "uosc-waveform %s loaded\nFrontend: %s\nConfig: %s\nuosc file: %s",
        SCRIPT_VERSION, tostring(frontend_name), tostring(config_directory),
        uosc_detected and "found" or "not found (adapter still enabled)"
    ), 6)
end

local function uosc_menu_open()
    local menu_type = mp.get_property_native and mp.get_property_native("user-data/uosc/menu/type") or nil
    if menu_type ~= nil and menu_type ~= false and menu_type ~= "" then return true end
    local shared = mp.get_property_native and mp.get_property_native("shared-script-properties", {}) or {}
    local legacy = type(shared) == "table" and shared["uosc-menu-type"] or nil
    return legacy ~= nil and legacy ~= false and legacy ~= ""
end
local process_id = mp.get_property_native and mp.get_property_native("pid") or nil
local monotonic_id = mp.get_time and math.floor(mp.get_time() * 1000000) or 0
local pointer_id = tostring({}):match("0x(%x+)") or "mpv"
local session_seed = string.format("%d|%s|%d|%s", os.time(), tostring(process_id or "nopid"), monotonic_id, pointer_id)
local session_id = util.hash64(session_seed)

local instance = controller.start({
    mp = mp,
    utils = utils,
    options_api = options_api,
    fs = fs,
    now = os.time,
    session_id = session_id,
    raw_options = raw_options,
    context = { config_dir = config_directory, platform = windows and "windows" or "other" },
    uosc_config = uosc_config,
    uosc_detected = uosc_detected,
    menu_open = uosc_menu_open,
    script_version = SCRIPT_VERSION,
    frontend_name = frontend_name,
    diagnostic_path = diagnostic_path,
    external_log = diagnostic_log,
})

return instance
