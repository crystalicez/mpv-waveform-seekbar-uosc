local mpv_compat = require("uosc_waveform.mpv_compat")

local M = {}

local function selected_stream_label(media_info, force_audio_ordinal)
    local track = assert(media_info.track, "media track required")
    if not force_audio_ordinal and type(track.ff_index) == "number" and track.ff_index >= 0 then
        return string.format("[0:%d]", track.ff_index)
    end
    local ordinal = tonumber(track.audio_ordinal)
    assert(ordinal and ordinal >= 0, "audio stream index unavailable")
    return string.format("[0:a:%d]", ordinal)
end

local function timestamp_shift_filter(delay)
    delay = tonumber(delay) or 0
    if math.abs(delay) < 1e-9 then return nil end
    if delay > 0 then return string.format("asetpts=PTS+%.9g/TB", delay) end
    return string.format("asetpts=PTS-%.9g/TB", math.abs(delay))
end


function M.build_peak_argv(executable, media_info, opts, force_audio_ordinal)
    local stream = selected_stream_label(media_info, force_audio_ordinal == true)
    local duration = assert(tonumber(media_info.duration), "media duration required")
    assert(duration > 0, "media duration must be positive")
    local sample_rate = assert(tonumber(opts.analysis_sample_rate), "analysis_sample_rate required")
    local width = assert(tonumber(opts.source_width), "source_width required")
    assert(sample_rate > 0 and width > 0, "analysis dimensions must be positive")
    local duration_text = string.format("%.9g", duration)
    local samples_per_frame = math.max(1, math.ceil(sample_rate * duration / width))
    local filters = {}
    local shift = timestamp_shift_filter(
        (tonumber(media_info.audio_delay) or 0) + (tonumber(media_info.timeline_offset) or 0)
    )
    if shift then filters[#filters + 1] = shift end
    filters[#filters + 1] = "aformat=channel_layouts=mono"
    filters[#filters + 1] = "aresample=" .. tostring(sample_rate) .. ":async=1:first_pts=0"
    filters[#filters + 1] = "apad=whole_dur=" .. duration_text
    filters[#filters + 1] = "atrim=duration=" .. duration_text
    filters[#filters + 1] = "asetnsamples=n=" .. tostring(samples_per_frame) .. ":p=1"
    filters[#filters + 1] = "astats=metadata=1:reset=1:measure_perchannel=Peak_level:measure_overall=none"
    filters[#filters + 1] = "ametadata=print:key=lavfi.astats.1.Peak_level:file=-[analysis]"
    local filter = stream .. table.concat(filters, ",")

    return {
        tostring(executable or "ffmpeg"),
        "-hide_banner",
        "-loglevel", "error",
        "-nostdin",
        "-i", assert(media_info.input_path, "input_path required"),
        "-filter_complex", filter,
        "-map", "[analysis]",
        "-vn",
        "-sn",
        "-dn",
        "-f", "null",
        "-",
    }
end

function M.is_feature_unsupported(result)
    local detail = table.concat({
        tostring(result and result.error_string or ""),
        tostring(result and result.stderr or ""),
        tostring(result and result.stdout or ""),
    }, "\n"):lower()
    if detail:find("no such filter", 1, true) then
        return detail:find("astats", 1, true) ~= nil
            or detail:find("asetnsamples", 1, true) ~= nil
            or detail:find("ametadata", 1, true) ~= nil
    end
    if detail:find("option not found", 1, true) or detail:find("error applying option", 1, true) then
        return detail:find("astats", 1, true) ~= nil
            or detail:find("asetnsamples", 1, true) ~= nil
            or detail:find("ametadata", 1, true) ~= nil
            or detail:find("peak_level", 1, true) ~= nil
    end
    return false
end

function M.is_stream_mapping_error(result)
    local detail = table.concat({
        tostring(result and result.error_string or ""),
        tostring(result and result.stderr or ""),
        tostring(result and result.stdout or ""),
    }, "\n"):lower()
    return detail:find("matches no streams", 1, true) ~= nil
        or detail:find("stream specifier", 1, true) ~= nil
        or detail:find("media type mismatch", 1, true) ~= nil
        or detail:find("cannot find a matching stream", 1, true) ~= nil
end

function M.start(mpv, argv, callback)
    assert(mpv and mpv.command_native_async, "mpv async command API required")
    assert(type(callback) == "function", "callback required")
    local finished = false
    local cancelled = false
    local id
    local job = {}

    local function complete(success, result, error_string)
        if finished then return end
        finished = true
        result = result or {}
        callback({
            status = tonumber(result.status),
            stdout = tostring(result.stdout or ""),
            stderr = tostring(result.stderr or ""),
            error_string = error_string and tostring(error_string) or nil,
            killed = cancelled or result.killed == true or error_string == "killed",
            success = success == true,
        })
    end

    local ok, async_id = pcall(
        mpv.command_native_async,
        mpv_compat.named_command(mpv, "subprocess", {
            playback_only = false,
            capture_stdout = true,
            capture_stderr = true,
            capture_size = 8 * 1024 * 1024,
            args = argv,
        }),
        complete
    )
    if ok then
        id = async_id
    else
        complete(false, {}, async_id)
    end

    job.id = id
    function job:cancel()
        if finished or cancelled then return end
        cancelled = true
        if id ~= nil and mpv.abort_async_command then pcall(mpv.abort_async_command, id) end
    end
    function job:done() return finished end
    function job:cancelled() return cancelled end
    return job
end

return M
