local M = {}

local key_cache = setmetatable({}, { __mode = "k" })

local function parse_version(version)
    local major, minor = tostring(version or ""):match("(%d+)%.(%d+)")
    return tonumber(major), tonumber(minor)
end

local function is_development_build(version)
    local text = tostring(version or "")
    if text == "" then return false end
    if text:match("%d+%.%d+%.%d+%-%d+%-g[%da-fA-F]+") then return true end
    if not text:match("%d+%.%d+") then return true end
    return text:lower():find("git", 1, true) ~= nil
end

local function probe_underscore_key(mpv)
    if not mpv or not mpv.command_native then return false end
    -- Use a read-only command. The old overlay-remove probe could erase overlay
    -- ID 63 owned by another script on development builds with unusual version
    -- strings.
    local ok, result = pcall(mpv.command_native, { _name = "expand-path", path = "~~/" })
    return ok and type(result) == "string" and result ~= ""
end

local function command_name_key(mpv)
    if type(mpv) == "table" and key_cache[mpv] then return key_cache[mpv] end
    local version = mpv and mpv.get_property_native and mpv.get_property_native("mpv-version", "") or ""
    local major, minor = parse_version(version)
    local key
    if major and (major > 0 or minor >= 42) then
        key = "_name"
    elseif is_development_build(version) and probe_underscore_key(mpv) then
        key = "_name"
    else
        key = "name"
    end
    if type(mpv) == "table" then key_cache[mpv] = key end
    return key
end

function M.named_command(mpv, command_name, fields)
    local command = {}
    for key, value in pairs(fields or {}) do command[key] = value end
    command[command_name_key(mpv)] = command_name
    return command
end

return M
