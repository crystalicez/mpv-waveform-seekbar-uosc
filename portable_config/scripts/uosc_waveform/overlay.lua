local mpv_compat = require("uosc_waveform.mpv_compat")

local M = {}

local function positive_integer(value)
    return type(value) == "number" and value > 0 and value == math.floor(value)
end

local function signature(raw_path, source_width, source_height, rect)
    return table.concat({
        tostring(raw_path), tostring(source_width), tostring(source_height),
        tostring(rect.x), tostring(rect.y), tostring(rect.width), tostring(rect.height),
        tostring(rect.source_crop_top or 0), tostring(rect.source_crop_height or source_height),
    }, "|")
end

function M.new(mpv, opts)
    assert(mpv and mpv.command_native, "mpv command API required")
    opts = opts or {}
    local overlay_id = tonumber(opts.overlay_id) or 63
    local visible = false
    local last = nil
    local renderer = {}

    function renderer:show(raw_path, source_width, source_height, rect)
        if type(raw_path) ~= "string" or raw_path == "" or type(rect) ~= "table" then return false end
        source_width = tonumber(source_width)
        source_height = tonumber(source_height)
        local crop_top = tonumber(rect.source_crop_top) or 0
        local crop_height = tonumber(rect.source_crop_height) or source_height
        if not positive_integer(source_width) or not positive_integer(source_height)
            or crop_top < 0 or crop_top ~= math.floor(crop_top)
            or not positive_integer(crop_height) or crop_top + crop_height > source_height
            or not positive_integer(tonumber(rect.width)) or not positive_integer(tonumber(rect.height)) then
            return false
        end

        local current = signature(raw_path, source_width, source_height, rect)
        if visible and current == last then return true end
        local command = mpv_compat.named_command(mpv, "overlay-add", {
            id = overlay_id,
            x = math.floor(tonumber(rect.x) or 0),
            y = math.floor(tonumber(rect.y) or 0),
            file = raw_path,
            offset = crop_top * source_width * 4,
            fmt = "bgra",
            w = source_width,
            h = crop_height,
            stride = source_width * 4,
            dw = math.floor(rect.width),
            dh = math.floor(rect.height),
        })
        local ok, result = pcall(mpv.command_native, command)
        -- mp.command_native signals errors as nil, error (not necessarily a throw).
        if not ok or result == nil or result == false then return false end
        visible = true
        last = current
        return true
    end

    function renderer:hide()
        if not visible then return end
        pcall(mpv.command_native, mpv_compat.named_command(mpv, "overlay-remove", { id = overlay_id }))
        visible = false
        last = nil
    end

    function renderer:is_visible() return visible end
    function renderer:last_signature() return last end
    function renderer:id() return overlay_id end

    return renderer
end

return M
