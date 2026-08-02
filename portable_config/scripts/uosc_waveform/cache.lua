local util = require("uosc_waveform.util")

local M = {}

local CACHE_FORMAT = 5

local function field(value)
    if value == nil then return "" end
    if type(value) == "boolean" then return value and "1" or "0" end
    return tostring(value)
end

function M.identity(media_info, opts)
    local track = media_info.track or {}
    local color = opts.waveform_color or opts.color or opts.dark_color or ""
    local lines = {
        "cache-format=" .. CACHE_FORMAT,
        "source-path=" .. field(media_info.source_path),
        "source-size=" .. field(media_info.source_size),
        "source-mtime=" .. field(media_info.source_mtime),
        "input-path=" .. field(media_info.input_path),
        "input-size=" .. field(media_info.input_size),
        "input-mtime=" .. field(media_info.input_mtime),
        "duration=" .. field(media_info.duration),
        "source-duration=" .. field(media_info.source_duration),
        "edition=" .. field(media_info.edition),
        "demuxer-start-time=" .. field(media_info.demuxer_start_time),
        "rebase-start-time=" .. field(media_info.rebase_start_time),
        "timeline-offset=" .. field(media_info.timeline_offset),
        "audio-delay=" .. field(media_info.audio_delay),
        "track-id=" .. field(track.id),
        "track-ff-index=" .. field(track.ff_index),
        "track-audio-ordinal=" .. field(track.audio_ordinal),
        "track-external=" .. field(track.external),
        "source-width=" .. field(opts.source_width),
        "source-height=" .. field(opts.source_height),
        "opacity=" .. field(opts.opacity),
        "waveform-color=" .. field(color),
        "analysis-sample-rate=" .. field(opts.analysis_sample_rate),
        "filter=pts-aligned:async:first-pts-zero:showwavespic:peak:sqrt:scale",
    }
    return table.concat(lines, "\n")
end

local function identity_dimension(canonical, name, fallback)
    local value = tostring(canonical):match("\n" .. name .. "=(%d+)")
        or tostring(canonical):match("^" .. name .. "=(%d+)")
    return tonumber(value) or fallback
end

function M.paths(cache_dir, canonical_string, session_id)
    local width = identity_dimension(canonical_string, "source%-width", 4096)
    local height = identity_dimension(canonical_string, "source%-height", 128)
    local key = string.format("%s-%dx%d", util.hash64(canonical_string), width, height)
    local prefix = util.join_path(cache_dir, key)
    local session = tostring(session_id or "session"):gsub("[^%w_.-]", "_")
    return {
        key = key,
        raw = prefix .. ".bgra",
        temp = prefix .. "." .. session .. ".tmp",
        lock = prefix .. ".lock",
        meta = prefix .. ".meta",
    }
end

function M.expected_size(opts)
    return assert(tonumber(opts.source_width), "source_width required")
        * assert(tonumber(opts.source_height), "source_height required") * 4
end

function M.validate(fs, raw_path, expected_size)
    local actual = fs and fs.size and fs.size(raw_path) or nil
    if actual == nil then return false, "missing" end
    if actual ~= expected_size then return false, "invalid-size" end
    return true
end

local function lock_created(fs, lock_path)
    if fs.read then
        local content = fs.read(lock_path)
        local parsed = content and tonumber(content:match("created=(%-?%d+)") or "")
        if parsed then return parsed end
    end
    if fs.mtime then return tonumber(fs.mtime(lock_path)) end
    return nil
end

function M.lock_status(fs, lock_path, now, stale_seconds)
    if not fs or not fs.exists or not fs.exists(lock_path) then return "free" end
    local created = lock_created(fs, lock_path)
    if not created then return "stale" end
    if tonumber(now) - created >= tonumber(stale_seconds) then return "stale" end
    return "active"
end

local function safe_owner(owner)
    return tostring(owner or "unknown"):gsub("[\r\n]", "_")
end

function M.acquire_lock(fs, lock_path, now, owner)
    local content = string.format("created=%d\nowner=%s\n", tonumber(now) or 0, safe_owner(owner))
    if fs and fs.create_exclusive then
        local ok, err = fs.create_exclusive(lock_path, content, tonumber(now) or 0)
        if not ok then return false, err or "exists" end
        return true
    end
    if fs and fs.exists and fs.exists(lock_path) then return false, "exists" end
    return M.write_lock(fs, lock_path, now, owner)
end

function M.write_lock(fs, lock_path, now, owner)
    if not fs or not fs.write then return false, "write-unavailable" end
    local content = string.format("created=%d\nowner=%s\n", tonumber(now) or 0, safe_owner(owner))
    local ok, err = fs.write(lock_path, content, tonumber(now) or 0)
    if ok == false then return false, err or "write-failed" end
    return true
end

function M.lock_owner(fs, lock_path)
    if not fs or not fs.read then return nil end
    local content = fs.read(lock_path)
    return content and content:match("owner=([^\r\n]+)") or nil
end

function M.remove_owned_lock(fs, lock_path, owner)
    if not fs or not fs.exists or not fs.exists(lock_path) then return true end
    if owner and M.lock_owner(fs, lock_path) ~= tostring(owner) then return false, "not-owner" end
    return fs.remove(lock_path)
end


local function basename(path)
    return tostring(path or ""):match("([^\\/]+)$") or tostring(path or "")
end

local function cache_suffix(path)
    local name = basename(path)
    local hash, suffix = name:match("^([%da-fA-F]+)%-%d+x%d+(.*)$")
    if not hash or (#hash ~= 8 and #hash ~= 16) then return nil end
    return suffix
end

local function is_cache_payload(path)
    local suffix = cache_suffix(path)
    return suffix == ".bgra" or suffix == ".meta"
end

local function is_cache_auxiliary(path)
    local suffix = cache_suffix(path)
    return suffix == ".lock" or (suffix and suffix:match("^%..+%.tmp$") ~= nil)
end

local function is_cleanup_eligible(entry)
    if entry.active then return false end
    return is_cache_payload(entry.path)
end

function M.cleanup_candidates(entries, now, max_age_seconds, max_total_bytes)
    local eligible = {}
    for _, entry in ipairs(entries or {}) do
        if is_cleanup_eligible(entry) and (tonumber(entry.mtime) or 0) > 0 then
            eligible[#eligible + 1] = {
                path = entry.path,
                size = tonumber(entry.size) or 0,
                mtime = tonumber(entry.mtime) or 0,
            }
        end
    end
    table.sort(eligible, function(a, b)
        if a.mtime == b.mtime then return tostring(a.path) < tostring(b.path) end
        return a.mtime < b.mtime
    end)

    local selected, selected_set = {}, {}
    local total = 0
    for _, entry in ipairs(eligible) do total = total + entry.size end

    for _, entry in ipairs(eligible) do
        if tonumber(now) - entry.mtime >= tonumber(max_age_seconds) then
            selected[#selected + 1] = entry.path
            selected_set[entry.path] = true
            total = total - entry.size
        end
    end

    for _, entry in ipairs(eligible) do
        if total <= tonumber(max_total_bytes) then break end
        if not selected_set[entry.path] then
            selected[#selected + 1] = entry.path
            selected_set[entry.path] = true
            total = total - entry.size
        end
    end
    return selected
end

function M.publish(fs, temp_path, raw_path, expected_size)
    if not fs or not fs.size or fs.size(temp_path) ~= expected_size then
        if fs and fs.remove then fs.remove(temp_path) end
        return false, "invalid-size"
    end

    -- Never delete a complete cache entry written by another mpv instance.
    -- On Windows rename normally fails if the destination appeared after our
    -- preflight check; the controller then validates and adopts that winner.
    local destination_valid = M.validate(fs, raw_path, expected_size)
    if destination_valid then
        if fs.remove then fs.remove(temp_path) end
        return false, "destination-exists"
    end
    local ok, err = fs.rename(temp_path, raw_path)
    if not ok then
        local winner = M.validate(fs, raw_path, expected_size)
        if winner then
            if fs.remove then fs.remove(temp_path) end
            return false, "destination-exists"
        end
        -- Keep our complete session-unique temp available as a non-persistent
        -- fallback. This avoids deleting a raced destination just to make the
        -- waveform visible on Windows, where rename cannot replace a file.
        return false, "rename-failed:" .. tostring(err)
    end
    return true
end

function M.stale_auxiliary_candidates(entries, now, stale_seconds, protected)
    local selected = {}
    protected = protected or {}
    for _, entry in ipairs(entries or {}) do
        local path = tostring(entry.path or "")
        local mtime = tonumber(entry.mtime) or 0
        local age = mtime > 0 and (tonumber(now) - mtime) or -1
        if is_cache_auxiliary(path) and not protected[path] and mtime > 0
            and age >= tonumber(stale_seconds) then
            selected[#selected + 1] = path
        end
    end
    table.sort(selected)
    return selected
end

return M
