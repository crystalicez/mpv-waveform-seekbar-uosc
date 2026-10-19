local util = require("uosc_waveform.util")

local M = {}

local CACHE_FORMAT = 6

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
        "filter=peak-metadata-v1:pts-aligned:async:first-pts-zero:astats-peak:sqrt",
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
        width = width,
        height = height,
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

local function parse_manifest(text)
    if type(text) ~= "string" or text == "" then return nil end
    local result = {}
    for line in text:gmatch("[^\r\n]+") do
        local key, value = line:match("^([%w_-]+)=(.*)$")
        if not key then return nil end
        result[key] = value
    end
    return result
end

function M.manifest_content(paths, expected_size, metadata)
    metadata = metadata or {}
    return table.concat({
        "cache-format=" .. tostring(CACHE_FORMAT),
        "key=" .. tostring(paths.key or ""),
        "width=" .. tostring(tonumber(metadata.width) or tonumber(paths.width) or 0),
        "height=" .. tostring(tonumber(metadata.height) or tonumber(paths.height) or 0),
        "size=" .. tostring(tonumber(expected_size) or 0),
        "created=" .. tostring(tonumber(metadata.created) or 0),
        "",
    }, "\n")
end

function M.validate_entry(fs, paths, expected_size)
    if not paths then return false, "missing-paths" end
    local actual = fs and fs.size and fs.size(paths.raw) or nil
    if actual == nil then return false, "missing-raw" end
    if actual ~= expected_size then return false, "invalid-size" end
    local text = fs and fs.read and fs.read(paths.meta) or nil
    if text == nil then return false, "missing-meta" end
    local manifest = parse_manifest(text)
    if not manifest then return false, "invalid-meta" end
    if tonumber(manifest["cache-format"]) ~= CACHE_FORMAT then return false, "meta-format-mismatch" end
    if manifest.key ~= tostring(paths.key) then return false, "meta-key-mismatch" end
    if tonumber(manifest.size) ~= tonumber(expected_size) then return false, "meta-size-mismatch" end
    if tonumber(manifest.width) ~= tonumber(paths.width) then return false, "meta-width-mismatch" end
    if tonumber(manifest.height) ~= tonumber(paths.height) then return false, "meta-height-mismatch" end
    if tonumber(manifest.created) == nil then return false, "meta-created-invalid" end
    return true
end

function M.publish_entry(fs, paths, temp_raw, expected_size, metadata)
    if not fs or not fs.size or fs.size(temp_raw) ~= expected_size then
        if fs and fs.remove then fs.remove(temp_raw) end
        return false, "invalid-size"
    end
    if M.validate_entry(fs, paths, expected_size) then
        if fs.remove then fs.remove(temp_raw) end
        return false, "destination-exists"
    end

    -- Publication must never replace a peer's destination on POSIX, where
    -- ordinary rename() otherwise overwrites existing files atomically.
    local publish_move = fs.rename_noreplace or fs.rename
    local moved, move_error = publish_move(temp_raw, paths.raw)
    local adopted_orphan = false
    if not moved then
        if M.validate_entry(fs, paths, expected_size) then
            if fs.remove then fs.remove(temp_raw) end
            return false, "destination-exists"
        end
        -- Another writer (or a crashed instance) may have published a full
        -- raw bitmap but not yet committed its manifest. All publishers for
        -- this key use the same cache identity and dimensions. The raw was
        -- linked into place only after size validation; complete its missing
        -- manifest without replacing the peer's raw bytes.
        if fs.size(paths.raw) == expected_size
            and fs.read and fs.read(paths.meta) == nil then
            adopted_orphan = true
        else
            return false, "raw-publish-failed:" .. tostring(move_error), temp_raw
        end
    end

    local meta_temp = tostring(temp_raw) .. ".meta.tmp"
    local manifest = M.manifest_content(paths, expected_size, metadata)
    if not fs.write then return false, "meta-write-failed:write-unavailable", paths.raw end
    local wrote, write_error = fs.write(meta_temp, manifest)
    if not wrote then
        if fs.remove then fs.remove(meta_temp) end
        return false, "meta-write-failed:" .. tostring(write_error),
            adopted_orphan and temp_raw or paths.raw
    end
    local meta_moved, meta_error = publish_move(meta_temp, paths.meta)
    if not meta_moved then
        if M.validate_entry(fs, paths, expected_size) then
            if fs.remove then
                fs.remove(meta_temp)
                if adopted_orphan then fs.remove(temp_raw) end
            end
            return false, "destination-exists"
        end
        if fs.remove then fs.remove(meta_temp) end
        return false, "meta-publish-failed:" .. tostring(meta_error),
            adopted_orphan and temp_raw or paths.raw
    end
    if not M.validate_entry(fs, paths, expected_size) then
        return false, "commit-validation-failed", adopted_orphan and temp_raw or paths.raw
    end
    if adopted_orphan and fs.remove then fs.remove(temp_raw) end
    return true
end

local function lock_metadata(fs, lock_path)
    if fs.read then
        local content = fs.read(lock_path)
        if type(content) == "string" then
            local created = tonumber(content:match("created=(%-?%d+)"))
            local pid = tonumber(content:match("pid=(%d+)"))
            if created then return created, pid end
        end
    end
    if fs.mtime then return tonumber(fs.mtime(lock_path)), nil end
    return nil, nil
end

function M.lock_status(fs, lock_path, now, stale_seconds)
    if not fs or not fs.exists or not fs.exists(lock_path) then return "free" end
    local created, pid = lock_metadata(fs, lock_path)
    if not created then return "stale" end
    local age = (tonumber(now) or 0) - created
    if age < (tonumber(stale_seconds) or 0) then return "active" end
    if not pid or not fs.process_alive then return "stale" end
    local ok, alive = pcall(fs.process_alive, pid)
    return ok and alive == true and "active" or "stale"
end

local function safe_owner(owner)
    return tostring(owner or "unknown"):gsub("[\r\n]", "_")
end

local function lock_content(now, owner, pid)
    local lines = {
        string.format("created=%d", tonumber(now) or 0),
        "owner=" .. safe_owner(owner),
    }
    if tonumber(pid) then lines[#lines + 1] = "pid=" .. tostring(math.floor(tonumber(pid))) end
    return table.concat(lines, "\n") .. "\n"
end

function M.acquire_lock(fs, lock_path, now, owner, pid)
    local content = lock_content(now, owner, pid)
    if fs and fs.create_exclusive then
        local ok, err = fs.create_exclusive(lock_path, content, tonumber(now) or 0)
        if not ok then return false, err or "exists" end
        return true
    end
    if fs and fs.exists and fs.exists(lock_path) then return false, "exists" end
    return M.write_lock(fs, lock_path, now, owner, pid)
end

function M.write_lock(fs, lock_path, now, owner, pid)
    if not fs or not fs.write then return false, "write-unavailable" end
    local content = lock_content(now, owner, pid)
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

local function cache_group_key(path)
    local name = basename(path)
    local key, extension = name:match("^([%da-fA-F]+%-%d+x%d+)%.(bgra)$")
    if key then return key, extension end
    key, extension = name:match("^([%da-fA-F]+%-%d+x%d+)%.(meta)$")
    return key, extension
end

function M.cleanup_groups(entries, now, max_age_seconds, max_total_bytes, protected)
    protected = protected or {}
    local groups_by_key = {}
    local locked_keys = {}
    for _, entry in ipairs(entries or {}) do
        local path = tostring(entry.path or "")
        if cache_suffix(path) == ".lock" then
            local key = basename(path):match("^([%da-fA-F]+%-%d+x%d+)%.lock$")
            if key then locked_keys[key] = true end
        end
    end
    for _, entry in ipairs(entries or {}) do
        local path = tostring(entry.path or "")
        local key = cache_group_key(path)
        if key then
            local group = groups_by_key[key]
            if not group then
                group = { key = key, paths = {}, size = 0, mtime = 0, protected = false }
                groups_by_key[key] = group
            end
            group.paths[#group.paths + 1] = path
            group.size = group.size + (tonumber(entry.size) or 0)
            group.mtime = math.max(group.mtime, tonumber(entry.mtime) or 0)
            if entry.active or protected[key] or protected[path] or locked_keys[key] then
                group.protected = true
            end
        end
    end
    local groups = {}
    local total = 0
    for _, group in pairs(groups_by_key) do
        table.sort(group.paths)
        groups[#groups + 1] = group
        total = total + group.size
    end
    table.sort(groups, function(a, b)
        if a.mtime == b.mtime then return a.key < b.key end
        return a.mtime < b.mtime
    end)

    local selected, selected_set = {}, {}
    for _, group in ipairs(groups) do
        if not group.protected and group.mtime > 0
            and tonumber(now) - group.mtime >= tonumber(max_age_seconds) then
            selected[#selected + 1] = group
            selected_set[group.key] = true
            total = total - group.size
        end
    end
    for _, group in ipairs(groups) do
        if total <= tonumber(max_total_bytes) then break end
        if not group.protected and not selected_set[group.key] then
            selected[#selected + 1] = group
            selected_set[group.key] = true
            total = total - group.size
        end
    end
    return selected
end

function M.cleanup_candidates(entries, now, max_age_seconds, max_total_bytes)
    local paths = {}
    for _, group in ipairs(M.cleanup_groups(entries, now, max_age_seconds, max_total_bytes, {})) do
        for _, path in ipairs(group.paths) do paths[#paths + 1] = path end
    end
    return paths
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
    local publish_move = fs.rename_noreplace or fs.rename
    local ok, err = publish_move(temp_path, raw_path)
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
    local locked_keys = {}
    protected = protected or {}
    for _, entry in ipairs(entries or {}) do
        local path = tostring(entry.path or "")
        if cache_suffix(path) == ".lock" then
            local key = basename(path):match("^([%da-fA-F]+%-%d+x%d+)%.lock$")
            if key then locked_keys[key] = true end
        end
    end
    for _, entry in ipairs(entries or {}) do
        local path = tostring(entry.path or "")
        local suffix = cache_suffix(path)
        local key = basename(path):match("^([%da-fA-F]+%-%d+x%d+)")
        local mtime = tonumber(entry.mtime) or 0
        local age = mtime > 0 and (tonumber(now) - mtime) or -1
        -- Time alone is not proof a lock is dead (suspend or a long running
        -- analysis). Unlinking it after a stale check also races a new owner.
        -- Until conditional atomic lock reclamation is available, never
        -- garbage-collect lock files or a locked entry's session temps.
        if suffix and suffix:match("^%..+%.tmp$") and not locked_keys[key]
            and not protected[path] and mtime > 0 and age >= tonumber(stale_seconds) then
            selected[#selected + 1] = path
        end
    end
    table.sort(selected)
    return selected
end

return M
