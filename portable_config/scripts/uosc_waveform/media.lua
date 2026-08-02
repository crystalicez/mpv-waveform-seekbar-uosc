local util = require("uosc_waveform.util")

local M = {}

local function unsupported(reason, silent)
    return { supported = false, reason = reason, silent = silent == true }
end

local function is_windows_path(path)
    return type(path) == "string" and (
        path:match("^[A-Za-z]:[\\/]") ~= nil
        or path:sub(1, 2) == "\\\\"
        or path:find("\\", 1, true) ~= nil
    )
end

local function normalized_path(path)
    if type(path) ~= "string" then return nil end
    if is_windows_path(path) then return util.normalize_windows_path(path) end
    return path
end

local function finite_number(value, fallback)
    local number = tonumber(value)
    if not number or number ~= number or number == math.huge or number == -math.huge then return fallback end
    return number
end

local function track_list(snapshot)
    return type(snapshot and snapshot.track_list) == "table" and snapshot.track_list or {}
end

local function is_rejected_source(path)
    if type(path) ~= "string" or path == "" then return true, "missing-path" end
    local lower = path:lower()
    if path == "-" or lower:match("^fd://") or lower:match("^memory://") then return true, "pipe-source" end
    if lower:match("^dvd://") or lower:match("^bd://") or lower:match("^bluray://") then return true, "disc-source" end
    if lower:match("^\\\\[.?]\\pipe\\") then return true, "pipe-source" end
    if util.is_url(path) then return true, "network-source" end
    return false
end

local function file_info(fs, original, normalized)
    if not fs or not fs.info then return nil end
    local info = fs.info(original)
    if not info and normalized ~= original then info = fs.info(normalized) end
    if not info or info.is_dir or info.is_file == false then return nil end
    return info
end

local function valid_nonnegative_integer(value)
    value = tonumber(value)
    return value ~= nil and value >= 0 and value == math.floor(value) and value or nil
end

local function track_is_external(track)
    return track.external == true or track["external-filename"] ~= nil
end

local function external_source_key(track)
    local filename = track["external-filename"]
    if type(filename) ~= "string" or filename == "" then return nil end
    -- Windows paths are case-insensitive in the supported runtime. Lowercasing
    -- only affects source grouping for the ordinal fallback; the original path
    -- is retained for filesystem and FFmpeg calls.
    local normalized = normalized_path(filename)
    return is_windows_path(filename) and normalized:lower() or normalized
end

local function audio_ordinal_for(track_list, target)
    local target_external = track_is_external(target)
    local target_source = target_external and external_source_key(target) or nil
    local ordinal = 0
    for _, track in ipairs(track_list or {}) do
        if track.type == "audio" then
            local same_input
            if target_external then
                same_input = track_is_external(track) and external_source_key(track) == target_source
            else
                same_input = not track_is_external(track)
            end
            if same_input then
                if track == target then return ordinal end
                ordinal = ordinal + 1
            end
        end
    end
    return nil
end

local function selected_audio(snapshot)
    local tracks = track_list(snapshot)

    -- lavfi-complex selects its input tracks independently from the normal
    -- `aid` selection. In that mode mpv can report aid=no even while audio is
    -- actively decoded through a graph such as [aid1] ... [ao]. The official
    -- current-tracks/audio property resolves to the first lavfi-selected audio
    -- track, so use it before interpreting aid=no as an explicit mute.
    local lavfi = snapshot.lavfi_complex
    local current = snapshot.current_audio
    if type(lavfi) == "string" and lavfi ~= "" and type(current) == "table"
        and (current.type == nil or current.type == "audio") then
        for _, track in ipairs(tracks) do
            if track.type == "audio" and current.id ~= nil
                and tostring(track.id) == tostring(current.id) then
                return track, audio_ordinal_for(tracks, track)
            end
        end
    end

    if snapshot.aid == "no" or snapshot.aid == false then return nil end

    -- During playback `aid` is the effective main audio track ID. Prefer it
    -- over `selected`, because selected can briefly lag behind aid during a
    -- runtime switch and can be true for multiple tracks with lavfi-complex.
    local aid = snapshot.aid
    if aid ~= nil and aid ~= "auto" then
        for _, track in ipairs(tracks) do
            if track.type == "audio" and tostring(track.id) == tostring(aid) then
                return track, audio_ordinal_for(tracks, track)
            end
        end
    end

    local first_selected
    for _, track in ipairs(tracks) do
        if track.type == "audio" and track.selected == true then
            if tonumber(track["main-selection"]) == 0 then
                return track, audio_ordinal_for(tracks, track)
            end
            first_selected = first_selected or track
        end
    end
    if first_selected then return first_selected, audio_ordinal_for(tracks, first_selected) end

    -- Some audio-only containers expose the track list before mpv has filled
    -- in `aid`, `selected`, and `main-selection`. When automatic selection is
    -- still settling and there is exactly one audio track, it is unambiguous
    -- and safe to use that track. Explicit `aid=no` was handled above, and an
    -- explicit numeric aid that does not match must remain unsupported.
    if aid == nil or aid == "auto" then
        local only_audio
        for _, track in ipairs(tracks) do
            if track.type == "audio" then
                if only_audio then return nil end
                only_audio = track
            end
        end
        if only_audio then return only_audio, audio_ordinal_for(tracks, only_audio) end
    end
    return nil
end

function M.inspect(snapshot, fs)
    snapshot = snapshot or {}
    local source_original = snapshot.stream_open_filename
    if type(source_original) ~= "string" or source_original == "" then source_original = snapshot.path end
    local rejected, reason = is_rejected_source(source_original)
    if rejected then return unsupported(reason, reason == "missing-path") end

    local source_duration = finite_number(snapshot.duration)
    if not source_duration or source_duration <= 0 then return unsupported("invalid-duration", true) end
    local demuxer_start_time = finite_number(snapshot.demuxer_start_time, 0)
    local rebase_start_time = snapshot.rebase_start_time ~= false
    -- Match uosc's timeline duration when mpv is configured not to rebase a
    -- non-zero demuxer start time. The waveform gets the same leading offset
    -- instead of being stretched over the longer seekbar.
    local timeline_offset = rebase_start_time and 0 or demuxer_start_time
    local duration = source_duration + timeline_offset
    if duration <= 0 then return unsupported("invalid-timeline-duration", false) end

    local track, audio_ordinal = selected_audio(snapshot)
    if not track then return unsupported("no-audio", true) end

    local source_path = normalized_path(source_original)
    local source_info = file_info(fs, source_original, source_path)
    if not source_info then return unsupported("missing-source", false) end

    local external = track_is_external(track)
    local input_original = source_original
    if external then
        input_original = track["external-filename"]
        if type(input_original) ~= "string" or input_original == "" then
            return unsupported("missing-external-audio", false)
        end
        local input_rejected, input_reason = is_rejected_source(input_original)
        if input_rejected then return unsupported(input_reason, false) end
    end
    local input_path = normalized_path(input_original)
    local input_info = external and file_info(fs, input_original, input_path) or source_info
    if not input_info then return unsupported("missing-input", false) end

    local warnings = {}
    local ff_index = valid_nonnegative_integer(track["ff-index"])
    if ff_index == nil then warnings[#warnings + 1] = "missing-ff-index" end
    local audio_delay = finite_number(snapshot.audio_delay, 0)
    if audio_delay ~= tonumber(snapshot.audio_delay or 0) then warnings[#warnings + 1] = "invalid-audio-delay" end

    local has_video = false
    for _, candidate in ipairs(track_list(snapshot)) do
        -- uosc classifies the media disposition from available tracks, not only
        -- the currently selected video track. Cover art/image tracks do not make
        -- an audio file behave as video.
        if candidate.type == "video" and candidate.image ~= true and candidate.albumart ~= true then
            has_video = true
            break
        end
    end

    return {
        supported = true,
        input_path = input_path,
        input_size = tonumber(input_info.size) or 0,
        input_mtime = tonumber(input_info.mtime) or 0,
        source_path = source_path,
        source_size = tonumber(source_info.size) or 0,
        source_mtime = tonumber(source_info.mtime) or 0,
        duration = duration,
        source_duration = source_duration,
        edition = tonumber(snapshot.edition) or 0,
        demuxer_start_time = demuxer_start_time,
        rebase_start_time = rebase_start_time,
        timeline_offset = timeline_offset,
        audio_delay = audio_delay,
        media_type = has_video and "video" or "audio",
        track = {
            id = track.id,
            ff_index = ff_index,
            audio_ordinal = audio_ordinal,
            external = external,
            external_filename = external and input_path or nil,
            codec = track.codec,
            lang = track.lang,
            title = track.title,
        },
        warnings = warnings,
    }
end

return M
