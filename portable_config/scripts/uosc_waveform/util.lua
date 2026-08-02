local M = {}

local UINT32 = 4294967296
local UINT16 = 65536

function M.clamp(value, low, high)
    return math.max(low, math.min(high, value))
end

function M.round(value)
    if value >= 0 then return math.floor(value + 0.5) end
    return math.ceil(value - 0.5)
end

function M.hex_to_rgb(value)
    local hex = assert(type(value) == "string" and value:match("^#?(%x%x%x%x%x%x)$"), "expected #RRGGBB")
    return tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16)
end

function M.premultiplied_rgba_hex(color, opacity)
    local r, g, b = M.hex_to_rgb(color)
    local a = M.round(M.clamp(tonumber(opacity) or 0, 0, 1) * 255)
    local function premul(channel)
        return M.round(channel * a / 255)
    end
    return string.format("#%02X%02X%02X%02X", premul(r), premul(g), premul(b), a)
end

local function split_segments(rest)
    local segments = {}
    for segment in rest:gmatch("[^\\]+") do
        if segment == "" or segment == "." then
            -- Ignore.
        elseif segment == ".." then
            if #segments > 0 and segments[#segments] ~= ".." then
                table.remove(segments)
            else
                segments[#segments + 1] = segment
            end
        else
            segments[#segments + 1] = segment
        end
    end
    return segments
end

function M.normalize_windows_path(path)
    assert(type(path) == "string", "path must be a string")
    if path == "" then return "" end
    local normalized = path:gsub("/", "\\")
    local prefix = ""
    local rest = normalized
    local absolute = false
    local drive_relative = false

    -- Extended-length UNC roots must preserve both server and share.
    local ext_server, ext_share, ext_tail = normalized:match("^\\\\%?\\[Uu][Nn][Cc]\\([^\\]+)\\([^\\]+)(.*)$")
    if ext_server and ext_share then
        prefix = "\\\\?\\UNC\\" .. ext_server .. "\\" .. ext_share
        rest = tostring(ext_tail or ""):gsub("^\\+", "")
        absolute = true
    else
        -- Extended-length drive paths (\\?\C:\...) are kept usable for FFmpeg
        -- and Windows APIs while still normalizing their tail segments.
        local extended_drive, extended_tail = normalized:match("^\\\\%?\\([A-Za-z]):\\(.*)$")
        if extended_drive then
            prefix = "\\\\?\\" .. extended_drive:lower() .. ":\\"
            rest = extended_tail
            absolute = true
        else
            -- Preserve ordinary UNC share roots so `..` can never climb above
            -- \\server\share.
            local server, share, tail = normalized:match("^\\\\([^\\]+)\\([^\\]+)(.*)$")
            if server and share then
                prefix = "\\\\" .. server .. "\\" .. share
                rest = tostring(tail or ""):gsub("^\\+", "")
                absolute = true
            else
                local drive, drive_tail = normalized:match("^([A-Za-z]):(.*)$")
                if drive then
                    prefix = drive:lower() .. ":"
                    rest = drive_tail
                    if rest:sub(1, 1) == "\\" then
                        prefix = prefix .. "\\"
                        rest = rest:gsub("^\\+", "")
                        absolute = true
                    else
                        drive_relative = true
                    end
                elseif normalized:sub(1, 1) == "\\" then
                    prefix = "\\"
                    rest = normalized:gsub("^\\+", "")
                    absolute = true
                end
            end
        end
    end

    local segments = split_segments(rest)
    if absolute then
        while segments[1] == ".." do table.remove(segments, 1) end
    end
    local body = table.concat(segments, "\\")
    if prefix:sub(-1) == "\\" then return prefix .. body end
    if drive_relative then return prefix .. body end
    if prefix ~= "" and body ~= "" then return prefix .. "\\" .. body end
    return prefix .. body
end

function M.is_url(value)
    if type(value) ~= "string" then return false end
    if value:match("^[A-Za-z]:[\\/]") then return false end
    return value:match("^[A-Za-z][A-Za-z0-9+.-]*://") ~= nil
end

local function bxor32(a, b)
    local result, bit = 0, 1
    a = a % UINT32
    b = b % UINT32
    for _ = 1, 32 do
        local abit = a % 2
        local bbit = b % 2
        if abit ~= bbit then result = result + bit end
        a = math.floor(a / 2)
        b = math.floor(b / 2)
        bit = bit * 2
    end
    return result
end

local function fnv_multiply(value)
    local value_lo = value % UINT16
    local value_hi = math.floor(value / UINT16)
    local multiplier_lo = 0x0193
    local multiplier_hi = 0x0100
    local low_product = value_lo * multiplier_lo
    local carry = math.floor(low_product / UINT16)
    local low = low_product % UINT16
    local high = (value_lo * multiplier_hi + value_hi * multiplier_lo + carry) % UINT16
    return high * UINT16 + low
end

function M.fnv1a32(value)
    assert(type(value) == "string", "value must be a string")
    local hash = 2166136261
    for index = 1, #value do
        hash = bxor32(hash, value:byte(index))
        hash = fnv_multiply(hash)
    end
    return string.format("%08x", hash)
end

function M.hash64(value)
    assert(type(value) == "string", "value must be a string")
    -- Two independently salted FNV-1a passes keep the implementation portable
    -- to stock Lua while reducing accidental cache-key collisions to 64 bits.
    return M.fnv1a32(value) .. M.fnv1a32("\255uosc-waveform\0" .. value)
end

function M.join_path(first, ...)
    local values = { first, ... }
    local windows = false
    for _, value in ipairs(values) do
        value = tostring(value or "")
        if value:find("\\", 1, true) or value:match("^[A-Za-z]:") then windows = true end
    end
    local separator = windows and "\\" or "/"
    local result = tostring(values[1] or "")
    for index = 2, #values do
        local part = tostring(values[index] or "")
        if part ~= "" then
            result = result:gsub("[\\/]+$", "")
            part = part:gsub("^[\\/]+", "")
            result = result .. separator .. part
        end
    end
    return result
end

function M.shallow_copy(source)
    local result = {}
    for key, value in pairs(source or {}) do result[key] = value end
    return result
end


return M
