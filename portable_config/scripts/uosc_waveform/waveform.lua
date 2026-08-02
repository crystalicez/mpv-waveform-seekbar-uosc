local util = require("uosc_waveform.util")

local M = {}

local function positive_integer(value)
    return type(value) == "number" and value > 0 and value == math.floor(value)
end

local function finite_number(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function parse_peak_value(text)
    text = tostring(text or ""):match("^%s*(.-)%s*$"):lower()
    if text == "-inf" or text == "-infinity" then return 0 end
    if text == "inf" or text == "+inf" or text == "infinity" or text == "+infinity"
        or text == "nan" or text == "+nan" or text == "-nan" then
        return nil
    end
    local db = tonumber(text)
    if not finite_number(db) then return nil end
    local linear = 10 ^ (db / 20)
    if not finite_number(linear) then return nil end
    return math.sqrt(util.clamp(linear, 0, 1))
end

function M.parse_peak_metadata(text, duration, width)
    duration = tonumber(duration)
    width = tonumber(width)
    if not finite_number(duration) or duration <= 0 then return nil, "invalid-duration" end
    if not positive_integer(width) then return nil, "invalid-width" end
    text = tostring(text or "")
    if not text:find("%S") then return nil, "empty-output" end

    local frames = {}
    local pending = nil
    local saw_frame = false
    for line in (text .. "\n"):gmatch("(.-)\r?\n") do
        if line:match("^%s*frame:") then
            if pending and pending.amplitude == nil then return nil, "missing-peak-level" end
            local raw_time = line:match("pts_time:([^%s]+)")
            local pts_time = raw_time and tonumber(raw_time) or nil
            if not finite_number(pts_time) then return nil, "malformed-pts-time" end
            if #frames > 0 and pts_time < frames[#frames].pts_time then
                return nil, "non-monotonic-pts"
            end
            pending = { pts_time = pts_time }
            frames[#frames + 1] = pending
            saw_frame = true
        else
            local raw_peak = line:match("lavfi%.astats%.1%.Peak_level%s*=%s*(.-)%s*$")
            if raw_peak ~= nil then
                if not pending or pending.amplitude ~= nil then return nil, "orphan-peak-level" end
                local amplitude = parse_peak_value(raw_peak)
                if amplitude == nil then return nil, "invalid-peak-level" end
                pending.amplitude = amplitude
            end
        end
    end
    if not saw_frame then return nil, "empty-output" end
    if pending and pending.amplitude == nil then return nil, "missing-peak-level" end

    local peaks = {}
    for x = 1, width do peaks[x] = 0 end
    for index, frame in ipairs(frames) do
        local interval_start = math.max(0, frame.pts_time)
        local next_frame = frames[index + 1]
        local interval_end = math.min(duration, next_frame and next_frame.pts_time or duration)
        if interval_end > interval_start and interval_start < duration then
            local first_pixel = math.floor((interval_start / duration) * width)
            local after_last = math.ceil((interval_end / duration) * width)
            first_pixel = util.clamp(first_pixel, 0, width)
            after_last = util.clamp(after_last, 0, width)
            for pixel = first_pixel, after_last - 1 do
                local table_index = pixel + 1
                if frame.amplitude > peaks[table_index] then peaks[table_index] = frame.amplitude end
            end
        end
    end
    return peaks
end

function M.render_bgra(peaks, width, height, color, opacity)
    width = tonumber(width)
    height = tonumber(height)
    if not positive_integer(width) then return nil, "invalid-width" end
    if not positive_integer(height) then return nil, "invalid-height" end
    if type(peaks) ~= "table" or #peaks ~= width then return nil, "peak-count-mismatch" end

    local ok, red, green, blue = pcall(util.hex_to_rgb, color)
    if not ok then return nil, "invalid-color" end
    local alpha = util.round(util.clamp(tonumber(opacity) or 0, 0, 1) * 255)
    local function premultiply(channel) return util.round(channel * alpha / 255) end
    local colored = string.char(premultiply(blue), premultiply(green), premultiply(red), alpha)
    local transparent = "\0\0\0\0"
    local center = (height - 1) / 2
    local half_span = height / 2
    local rows = {}

    for y = 0, height - 1 do
        local distance = math.abs(y - center)
        local row = {}
        for x = 1, width do
            local amplitude = tonumber(peaks[x])
            if not finite_number(amplitude) then return nil, "invalid-peak" end
            amplitude = util.clamp(amplitude, 0, 1)
            row[x] = amplitude > 0 and distance < amplitude * half_span and colored or transparent
        end
        rows[y + 1] = table.concat(row)
    end
    return table.concat(rows)
end

return M
