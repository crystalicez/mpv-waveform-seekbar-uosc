local cache = require("uosc_waveform.cache")
local ffmpeg = require("uosc_waveform.ffmpeg")
local geometry = require("uosc_waveform.geometry")
local media = require("uosc_waveform.media")
local options = require("uosc_waveform.options")
local overlay = require("uosc_waveform.overlay")
local util = require("uosc_waveform.util")

local M = {}

local STATES = {
    DISABLED = "DISABLED",
    UNSUPPORTED = "UNSUPPORTED",
    WAITING_FOR_LOCK = "WAITING_FOR_LOCK",
    GENERATING = "GENERATING",
    READY_HIDDEN = "READY_HIDDEN",
    READY_VISIBLE = "READY_VISIBLE",
    ERROR = "ERROR",
}

local function merge(base, values)
    local result = util.shallow_copy(base)
    for key, value in pairs(values or {}) do result[key] = value end
    return result
end

local function call_if(object, method, ...)
    if object and object[method] then return object[method](...) end
    return nil
end

function M.start(deps)
    assert(deps and deps.mp, "mp dependency required")
    assert(deps.fs, "filesystem dependency required")
    local mp = deps.mp
    local fs = deps.fs
    local now = deps.now or os.time
    local session_id = tostring(deps.session_id or ("session-" .. tostring(now())))
    local context = deps.context or { config_dir = "", platform = package.config:sub(1, 1) == "\\" and "windows" or "other" }

    local raw_options = merge(options.defaults(), deps.raw_options)
    if deps.options_api and deps.options_api.read_options and not deps.raw_options then
        deps.options_api.read_options(raw_options, "uosc-waveform")
    end
    local opts, option_warnings = options.normalize(raw_options, context)
    local uosc_raw = util.shallow_copy(deps.uosc_config or {})
    local uosc_detected = deps.uosc_detected
    if uosc_detected == nil then uosc_detected = next(deps.uosc_config or {}) ~= nil end
    if opts.adapter_override ~= "" then
        uosc_raw.compatibility = opts.adapter_override
    else
        -- File-path detection is only advisory. uosc may be loaded from a custom
        -- script path or a frontend-specific config directory (for example mpv.net).
        uosc_raw.compatibility = opts.compatibility
    end
    local uosc_config, geometry_warnings = geometry.parse_uosc(uosc_raw)
    local renderer = overlay.new(mp, opts)

    local app = {}
    local enabled = opts.enabled
    local state = enabled and STATES.UNSUPPORTED or STATES.DISABLED
    local unsupported_reason = enabled and "not-inspected" or nil
    local token = 0
    local active_job = nil
    local active_attempt = nil
    local geometry_timer = nil
    local mouse_timer = nil
    local cursor_fade_timer = nil
    local cursor_fade_generation = 0
    local cursor_autohide_timer = nil
    local cursor_autohidden = false
    local forced_visibility = nil
    local last_visibility = 0
    local last_mouse_hover = nil
    local media_timer = nil
    local lock_timer = nil
    local paths = nil
    local expected_size = cache.expected_size(opts)
    local current_media = nil
    local current_identity = nil
    local current_raw = nil
    local current_ephemeral = false
    local owned_lock = nil
    local active_temp = nil
    local attempt_serial = 0
    local cleanup_performed = false
    local shutdown = false

    local log_ranks = { error = 1, warn = 2, info = 3, debug = 4 }
    local configured_log_rank = log_ranks[opts.log_level] or log_ranks.warn
    local function log(level, message)
        local rank = log_ranks[level] or log_ranks.info
        if rank > configured_log_rank then return end
        local text = tostring(message)
        local logger = mp.msg and mp.msg[level]
        if logger then logger("[uosc-waveform] " .. text) end
        if deps.external_log then pcall(deps.external_log, level, text) end
    end
    log("info", string.format(
        "controller-start version=%s frontend=%s uosc_detected=%s diagnostic=%s",
        tostring(deps.script_version or "unknown"), tostring(deps.frontend_name or "mpv"),
        tostring(uosc_detected), tostring(deps.diagnostic_path or "disabled")
    ))
    if not uosc_detected then
        log("warn", "uosc-file-not-detected: continuing with configured geometry adapter")
    end
    for _, warning in ipairs(option_warnings) do log("warn", warning) end
    for _, warning in ipairs(geometry_warnings) do log("warn", warning) end

    local function get_native(name, default)
        if mp.get_property_native then
            local value = mp.get_property_native(name, default)
            if value ~= nil then return value end
        end
        return default
    end

    local geometry_values = {}
    local GEOMETRY_MISSING = {}
    local last_mouse = nil
    local function geometry_value(name, default)
        local value = geometry_values[name]
        if value == GEOMETRY_MISSING then return default end
        if value == nil then
            value = get_native(name)
            geometry_values[name] = value ~= nil and value or GEOMETRY_MISSING
        end
        return value ~= nil and value or default
    end

    local function media_snapshot()
        return {
            path = get_native("path"),
            stream_open_filename = get_native("stream-open-filename"),
            duration = get_native("duration"),
            edition = get_native("edition"),
            aid = get_native("aid"),
            track_list = get_native("track-list", {}),
            demuxer_start_time = get_native("demuxer-start-time", 0),
            rebase_start_time = get_native("rebase-start-time", true),
            audio_delay = get_native("audio-delay", 0),
        }
    end

    local function geometry_state()
        local mouse = last_mouse or get_native("mouse-pos", {}) or {}
        last_mouse = mouse
        local mouse_hover = mouse.hover ~= false
        if last_mouse_hover == nil then last_mouse_hover = mouse_hover end
        local osd_dimensions = geometry_value("osd-dimensions", {}) or {}
        local osd_width = tonumber(geometry_value("osd-width"))
            or tonumber(osd_dimensions.w or osd_dimensions.width) or 0
        local osd_height = tonumber(geometry_value("osd-height"))
            or tonumber(osd_dimensions.h or osd_dimensions.height) or 0
        return {
            osd_width = osd_width,
            osd_height = osd_height,
            hidpi_scale = tonumber(geometry_value("display-hidpi-scale", 1)) or 1,
            fullscreen = geometry_value("fullscreen", false) == true,
            maximized = geometry_value("window-maximized", false) == true,
            border = geometry_value("border", true) == true,
            title_bar = geometry_value("title-bar", true) ~= false,
            playlist_count = tonumber(geometry_value("playlist-count", 0)) or 0,
            mouse_x = tonumber(mouse.x),
            mouse_y = tonumber(mouse.y),
            mouse_hover = mouse_hover and not cursor_autohidden
                and geometry_value("focused", true) ~= false
                and geometry_value("user-data/mpv/context-menu/open", false) ~= true
                and geometry_value("user-data/mpv/console/open", false) ~= true,
            paused = geometry_value("pause", false) == true,
            menu_open = deps.menu_open and deps.menu_open() or false,
            menu_obstructs_timeline = deps.menu_obstructs_timeline and deps.menu_obstructs_timeline() or false,
            timeline_expanded_hint = deps.timeline_expanded_hint and deps.timeline_expanded_hint() or nil,
            forced_visibility = forced_visibility,
            media_type = current_media and current_media.media_type or nil,
        }
    end

    local function remove_owned_lock()
        if owned_lock then
            local lock = owned_lock
            owned_lock = nil
            local ok, err = cache.remove_owned_lock(fs, lock.path, lock.owner)
            if ok == false and err ~= "not-owner" then
                log("warn", "lock-remove-failed:" .. tostring(err or lock.path))
            elseif ok == false then
                log("debug", "lock-owner-changed:" .. tostring(lock.path))
            end
        end
    end

    local function cancel_timer(timer)
        if timer and timer.kill then timer:kill() end
    end

    local function cancel_active_generation()
        active_attempt = nil
        if active_job and not active_job:done() then
            active_job:cancel()
            log("debug", "generation-cancelled:" .. tostring(paths and paths.key or "unknown"))
        end
        active_job = nil
        cancel_timer(lock_timer)
        lock_timer = nil
        if active_temp and fs.remove then fs.remove(active_temp) end
        active_temp = nil
        remove_owned_lock()
    end

    local function nearly_equal(left, right)
        left, right = tonumber(left), tonumber(right)
        if left == nil or right == nil then return left == right end
        return math.abs(left - right) <= 1e-6
    end

    local function metadata_matches(before, after)
        if not after or not after.supported then return false end
        local before_track = before.track or {}
        local after_track = after.track or {}
        return before.source_path == after.source_path
            and before.source_size == after.source_size
            and before.source_mtime == after.source_mtime
            and before.input_path == after.input_path
            and before.input_size == after.input_size
            and before.input_mtime == after.input_mtime
            and nearly_equal(before.duration, after.duration)
            and nearly_equal(before.source_duration, after.source_duration)
            and before.edition == after.edition
            and nearly_equal(before.demuxer_start_time, after.demuxer_start_time)
            and before.rebase_start_time == after.rebase_start_time
            and nearly_equal(before.timeline_offset, after.timeline_offset)
            and nearly_equal(before.audio_delay, after.audio_delay)
            and tostring(before_track.id) == tostring(after_track.id)
            and before_track.ff_index == after_track.ff_index
            and before_track.audio_ordinal == after_track.audio_ordinal
            and before_track.external == after_track.external
            and before_track.external_filename == after_track.external_filename
    end

    local function clear_current_raw()
        local raw, ephemeral = current_raw, current_ephemeral
        current_raw = nil
        current_ephemeral = false
        if ephemeral and raw and fs.remove then fs.remove(raw) end
    end

    local function cleanup_cache()
        if cleanup_performed or not fs.list then return end
        cleanup_performed = true
        local entries = fs.list(opts.cache_dir) or {}
        local protected = {}
        if current_raw then protected[current_raw] = true end
        if paths then protected[paths.lock] = true end
        if active_temp then protected[active_temp] = true end
        for _, path in ipairs(cache.stale_auxiliary_candidates(
            entries, now(), opts.stale_lock_seconds, protected
        )) do
            if fs.remove then fs.remove(path) end
        end
        local candidates = cache.cleanup_candidates(
            entries,
            now(),
            opts.max_cache_age_days * 86400,
            opts.max_cache_mb * 1024 * 1024
        )
        for _, path in ipairs(candidates) do
            if path ~= current_raw and fs.remove then fs.remove(path) end
        end
    end

    function app:refresh_geometry(reason)
        if shutdown or not enabled or not current_raw then
            renderer:hide()
            if not enabled then state = STATES.DISABLED end
            return false
        end
        local previous_state = state
        local rect, geometry_reason = geometry.compute(uosc_config, geometry_state(), opts)
        if not rect then
            renderer:hide()
            if geometry_reason == "timeline-minimized" then last_visibility = 0 end
            state = STATES.READY_HIDDEN
            if previous_state ~= STATES.READY_HIDDEN then
                log("debug", "overlay-hidden:" .. tostring(geometry_reason or reason))
            end
            return false
        end
        last_visibility = tonumber(rect.visibility) or last_visibility
        if renderer:show(current_raw, opts.source_width, opts.source_height, rect) then
            state = STATES.READY_VISIBLE
            if previous_state ~= STATES.READY_VISIBLE then
                log("debug", "overlay-visible:id=" .. tostring(renderer:id()))
            end
            return true
        end
        state = STATES.ERROR
        local valid, validation_reason = cache.validate(fs, current_raw, expected_size)
        if not valid then
            current_raw = nil
            current_ephemeral = false
            log("warn", "overlay-cache-invalid:" .. tostring(validation_reason or "missing"))
            app:refresh_media("overlay-cache-invalid")
            return false
        end
        log("warn", "overlay-add-failed:command-failed")
        return false
    end

    local function schedule_geometry(reason)
        cancel_timer(geometry_timer)
        geometry_timer = nil
        if opts.resize_debounce_ms <= 0 or not mp.add_timeout then
            app:refresh_geometry(reason)
            return
        end
        geometry_timer = mp.add_timeout(opts.resize_debounce_ms / 1000, function()
            geometry_timer = nil
            app:refresh_geometry(reason)
        end)
    end

    -- uosc derives timeline visibility directly from cursor proximity. Mouse
    -- movement therefore needs a render-rate throttle, not the much slower
    -- resize debounce used for window geometry changes.
    local function schedule_mouse_geometry(reason)
        if opts.mouse_update_interval_ms <= 0 or not mp.add_timeout then
            app:refresh_geometry(reason)
            return
        end
        if mouse_timer then return end
        mouse_timer = mp.add_timeout(opts.mouse_update_interval_ms / 1000, function()
            mouse_timer = nil
            app:refresh_geometry(reason)
        end)
    end

    local function cancel_cursor_fade()
        cursor_fade_generation = cursor_fade_generation + 1
        cancel_timer(cursor_fade_timer)
        cursor_fade_timer = nil
        forced_visibility = nil
    end

    -- uosc fades timeline/controls after mouse.hover becomes false by using its
    -- exponential tween helper. The decay is chosen so 99% of the distance is
    -- covered in animation_duration at the configured render interval.
    local function start_cursor_leave_fade()
        cancel_cursor_fade()
        local from = util.clamp(tonumber(last_visibility) or 0, 0, 1)
        if from <= 0 then
            app:refresh_geometry("mouse-leave")
            return
        end

        local duration_ms = math.max(0, tonumber(uosc_config.animation_duration) or 100)
        if duration_ms <= 0 or not mp.add_timeout then
            app:refresh_geometry("mouse-leave")
            return
        end

        forced_visibility = from
        app:refresh_geometry("mouse-leave-start")
        local generation = cursor_fade_generation
        local configured_interval = tonumber(opts.mouse_update_interval_ms) or 16
        local interval_ms = configured_interval > 0 and configured_interval or (1000 / 60)
        local target_ticks = math.max(duration_ms, 1) / interval_ms
        local decay = 1 - (0.01 ^ (1 / target_ticks))
        local cutoff = from * 0.01

        local function tick()
            if generation ~= cursor_fade_generation or shutdown then return end
            forced_visibility = forced_visibility + ((0 - forced_visibility) * decay)
            if forced_visibility <= cutoff then
                forced_visibility = 0
                app:refresh_geometry("mouse-leave-end")
                forced_visibility = nil
                cursor_fade_timer = nil
                return
            end
            app:refresh_geometry("mouse-leave-tick")
            cursor_fade_timer = mp.add_timeout(interval_ms / 1000, tick)
        end
        cursor_fade_timer = mp.add_timeout(interval_ms / 1000, tick)
    end

    local function cancel_cursor_autohide()
        cancel_timer(cursor_autohide_timer)
        cursor_autohide_timer = nil
    end

    local function cursor_autohide_allowed()
        if not uosc_config.autohide then return false end
        local fullscreen_only = geometry_value("cursor-autohide-fs-only", false) == true
        if fullscreen_only and geometry_value("fullscreen", false) ~= true then return false end
        if deps.menu_open and deps.menu_open() then return false end
        if geometry_value("user-data/mpv/context-menu/open", false) == true then return false end
        if geometry_value("user-data/mpv/console/open", false) == true then return false end
        return true
    end

    local function parse_cursor_autohide(value)
        if value == nil then return 1000 end
        if value == false then return nil end
        if type(value) == "string" then
            local normalized = value:lower():match("^%s*(.-)%s*$")
            if normalized == "no" or normalized == "never" then return nil end
            if normalized == "always" then return 0 end
            value = tonumber(normalized)
        end
        value = tonumber(value)
        if not value then return 1000 end
        -- mpv represents the option choices as negative sentinels internally:
        -- -1 = no, -2 = always. Handle both native and textual forms.
        if value == -1 then return nil end
        if value == -2 then return 0 end
        return math.max(0, value)
    end

    local function perform_cursor_autohide()
        cursor_autohide_timer = nil
        cursor_autohidden = true
        start_cursor_leave_fade()
    end

    local function queue_cursor_autohide()
        cancel_cursor_autohide()
        if not cursor_autohide_allowed() then return end
        local timeout_ms = parse_cursor_autohide(geometry_value("cursor-autohide", 1000))
        if timeout_ms == nil then return end
        if timeout_ms == 0 or not mp.add_timeout then
            perform_cursor_autohide()
            return
        end
        cursor_autohide_timer = mp.add_timeout(timeout_ms / 1000, perform_cursor_autohide)
    end

    local function handle_mouse_geometry(mouse)
        mouse = mouse or get_native("mouse-pos", {}) or {}
        last_mouse = mouse
        local hover = mouse.hover ~= false
        if last_mouse_hover == nil then last_mouse_hover = hover end
        if not hover and last_mouse_hover then
            last_mouse_hover = false
            cursor_autohidden = false
            cancel_cursor_autohide()
            start_cursor_leave_fade()
            return
        end
        if hover and cursor_autohidden then
            cursor_autohidden = false
            cancel_cursor_fade()
        end
        if hover and not last_mouse_hover then
            last_mouse_hover = true
            cancel_cursor_fade()
        else
            last_mouse_hover = hover
        end
        schedule_mouse_geometry("property:mouse-pos")
        if hover then queue_cursor_autohide() end
    end

    local function show_ready(raw_path, reason, ephemeral)
        if current_ephemeral and current_raw and current_raw ~= raw_path and fs.remove then
            fs.remove(current_raw)
        end
        current_raw = raw_path
        current_ephemeral = ephemeral == true
        state = STATES.READY_HIDDEN
        app:refresh_geometry(reason)
        cleanup_cache()
    end

    local function wait_for_lock(refresh_token)
        state = STATES.WAITING_FOR_LOCK
        if not mp.add_timeout then return end
        lock_timer = mp.add_timeout(opts.lock_poll_ms / 1000, function()
            lock_timer = nil
            if refresh_token == token and enabled and not shutdown then app:refresh_media("lock-poll") end
        end)
    end

    local function failure_detail(result)
        for _, value in ipairs({ result.error_string, result.stderr, result.stdout }) do
            local text = value ~= nil and tostring(value) or ""
            if text ~= "" then return text end
        end
        return "status=" .. tostring(result.status)
    end

    local function launch_generation(refresh_token, info, color, generation_paths, force_audio_ordinal)
        attempt_serial = attempt_serial + 1
        local attempt_temp = generation_paths.temp:gsub("%.tmp$", "")
            .. "." .. tostring(refresh_token) .. "." .. tostring(attempt_serial) .. ".tmp"
        local built, argv = pcall(
            ffmpeg.build_generate_argv,
            opts.ffmpeg_path, info, opts, attempt_temp, color, force_audio_ordinal
        )
        if not built then
            remove_owned_lock()
            state = STATES.ERROR
            log("warn", "generation-build-failed:" .. tostring(argv))
            return
        end
        state = STATES.GENERATING
        log("debug", "generation-started:" .. generation_paths.key
            .. (force_audio_ordinal and ":ordinal-fallback" or ":ff-index"))

        local attempt = { temp = attempt_temp }
        active_attempt = attempt
        active_temp = attempt_temp
        local job = ffmpeg.start(mp, argv, function(result)
            if refresh_token ~= token or shutdown or active_attempt ~= attempt then
                if fs.remove then fs.remove(attempt.temp) end
                return
            end
            active_attempt = nil
            active_job = nil
            active_temp = nil
            local completed_paths = util.shallow_copy(generation_paths)
            completed_paths.temp = attempt.temp
            if result.killed then
                if fs.remove then fs.remove(completed_paths.temp) end
                remove_owned_lock()
                return
            end
            if result.status ~= 0 or result.success == false then
                if fs.remove then fs.remove(completed_paths.temp) end
                local can_retry_ordinal = not force_audio_ordinal
                    and info.track and info.track.ff_index ~= nil
                    and info.track.audio_ordinal ~= nil
                    and ffmpeg.is_stream_mapping_error(result)
                if can_retry_ordinal then
                    log("warn", "ff-index-mapping-failed; retrying-audio-ordinal")
                    launch_generation(refresh_token, info, color, generation_paths, true)
                    return
                end
                remove_owned_lock()
                state = STATES.ERROR
                log("warn", "generation-failed:" .. failure_detail(result))
                return
            end
            local after = media.inspect(media_snapshot(), fs)
            if not metadata_matches(info, after) then
                if fs.remove then fs.remove(completed_paths.temp) end
                remove_owned_lock()
                state = STATES.UNSUPPORTED
                log("warn", "source-changed-during-generation")
                return
            end
            local published, publish_error = cache.publish(fs, completed_paths.temp, completed_paths.raw, expected_size)
            remove_owned_lock()
            if not published then
                local winner = cache.validate(fs, completed_paths.raw, expected_size)
                if winner then
                    log("debug", "cache-publish-race-won-by-peer:" .. completed_paths.key)
                    show_ready(completed_paths.raw, "peer-publish")
                    return
                end
                local temporary_valid = cache.validate(fs, completed_paths.temp, expected_size)
                if temporary_valid then
                    log("warn", "cache-publish-failed:" .. tostring(publish_error)
                        .. "; using-session-temp")
                    show_ready(completed_paths.temp, "session-temp", true)
                    return
                end
                state = STATES.ERROR
                log("warn", "cache-publish-failed:" .. tostring(publish_error))
                return
            end
            log("debug", "generation-complete:" .. completed_paths.key)
            show_ready(completed_paths.raw, "generation-complete")
        end)
        if active_attempt == attempt and not job:done() then active_job = job end
    end

    local function start_generation(refresh_token, info, color)
        local generation_paths = paths
        local lock_ok, lock_error = cache.acquire_lock(fs, generation_paths.lock, now(), session_id)
        if not lock_ok then
            local status = cache.lock_status(fs, generation_paths.lock, now(), opts.stale_lock_seconds)
            if status == "active" then
                wait_for_lock(refresh_token)
                return
            end
            -- Locking is an optimization for avoiding duplicate analysis. It must
            -- never prevent playback or waveform generation on systems where the
            -- PowerShell lock helper is unavailable or behaves differently.
            log("warn", "lock-unavailable:" .. tostring(lock_error or status) .. "; continuing-unlocked")
        else
            owned_lock = { path = generation_paths.lock, owner = session_id }
            -- With exclusive ownership it is safe to clear a truncated
            -- canonical payload before Windows rename. Without this, an
            -- invalid destination can force session-temp fallback forever.
            local destination_valid = cache.validate(fs, generation_paths.raw, expected_size)
            if not destination_valid and fs.exists and fs.exists(generation_paths.raw) and fs.remove then
                local removed, remove_error = fs.remove(generation_paths.raw)
                if removed == false then
                    log("warn", "invalid-cache-remove-failed:" .. tostring(remove_error or generation_paths.raw))
                else
                    log("debug", "invalid-cache-removed:" .. tostring(generation_paths.key))
                end
            end
        end
        launch_generation(refresh_token, info, color, generation_paths, false)
    end

    function app:refresh_media(reason)
        if shutdown then return end

        if not enabled then
            token = token + 1
            cancel_active_generation()
            cancel_cursor_fade()
            cancel_cursor_autohide()
            renderer:hide()
            clear_current_raw()
            current_identity = nil
            current_media = nil
            paths = nil
            unsupported_reason = nil
            state = STATES.DISABLED
            return
        end

        local info = media.inspect(media_snapshot(), fs)
        if not info.supported then
            token = token + 1
            cancel_active_generation()
            cancel_cursor_fade()
            cancel_cursor_autohide()
            renderer:hide()
            clear_current_raw()
            current_identity = nil
            current_media = nil
            paths = nil
            unsupported_reason = info.reason
            state = STATES.UNSUPPORTED
            log("debug", "unsupported:" .. tostring(info.reason))
            return
        end

        unsupported_reason = nil
        local color = options.choose_waveform_color(opts, uosc_raw, get_native("background-color", "#000000"))
        opts.waveform_color = color
        local next_identity = cache.identity(info, opts)

        if current_identity == next_identity then
            if active_job and not active_job:done() then
                log("debug", "refresh-coalesced:generation-active:" .. tostring(reason))
                return
            end
            if state == STATES.WAITING_FOR_LOCK and reason ~= "lock-poll" then
                log("debug", "refresh-coalesced:waiting-lock:" .. tostring(reason))
                return
            end
            if current_raw and cache.validate(fs, current_raw, expected_size) then
                app:refresh_geometry(reason or "same-media")
                return
            end
        end

        token = token + 1
        local refresh_token = token
        cancel_active_generation()
        renderer:hide()
        clear_current_raw()
        current_identity = next_identity
        current_media = info
        paths = cache.paths(opts.cache_dir, current_identity, session_id)
        local mkdir_ok, mkdir_error = call_if(fs, "mkdir", opts.cache_dir)
        if mkdir_ok == false then
            state = STATES.ERROR
            log("warn", "cache-directory-create-failed:" .. tostring(mkdir_error or opts.cache_dir))
            return
        end

        local hit = cache.validate(fs, paths.raw, expected_size)
        if hit then
            log("debug", "cache-hit:" .. paths.key)
            show_ready(paths.raw, reason or "cache-hit")
            return
        end
        local lock_state = cache.lock_status(fs, paths.lock, now(), opts.stale_lock_seconds)
        if lock_state == "active" then
            wait_for_lock(refresh_token)
            return
        elseif lock_state == "stale" and fs.remove then
            fs.remove(paths.lock)
        end
        start_generation(refresh_token, info, color)
    end

    function app:toggle()
        if enabled then
            enabled = false
            cancel_active_generation()
            cancel_cursor_fade()
            cancel_cursor_autohide()
            renderer:hide()
            state = STATES.DISABLED
            log("info", "disabled")
        else
            enabled = true
            log("info", "enabled")
            if current_raw and cache.validate(fs, current_raw, expected_size) then
                app:refresh_geometry("toggle")
            else
                app:refresh_media("toggle")
            end
        end
    end

    function app:show_status()
        local details = string.format(
            "uosc-waveform %s\nstate=%s\nreason=%s\nconfig=%s\nuosc_file=%s\nlog=%s",
            tostring(deps.script_version or "unknown"), tostring(state),
            tostring(unsupported_reason or "none"), tostring(context.config_dir or ""),
            tostring(uosc_detected), tostring(deps.diagnostic_path or "disabled")
        )
        if mp.osd_message then mp.osd_message(details, 8) end
        log("info", "status-request state=" .. tostring(state) .. " reason=" .. tostring(unsupported_reason or "none"))
        return details
    end

    function app:shutdown()
        if shutdown then return end
        shutdown = true
        cancel_active_generation()
        cancel_timer(media_timer)
        media_timer = nil
        cancel_timer(geometry_timer)
        geometry_timer = nil
        cancel_timer(mouse_timer)
        mouse_timer = nil
        cancel_cursor_fade()
        cancel_cursor_autohide()
        renderer:hide()
        clear_current_raw()
    end

    function app:debug_state()
        return {
            state = state,
            token = token,
            paths = paths,
            active_temp = active_temp,
            expected_size = expected_size,
            job_id = active_job and active_job.id or nil,
            enabled = enabled,
            raw = current_raw,
            ephemeral = current_ephemeral,
            identity = current_identity,
            unsupported_reason = unsupported_reason,
        }
    end

    local function schedule_media(reason)
        cancel_timer(media_timer)
        media_timer = nil
        if opts.media_debounce_ms <= 0 or not mp.add_timeout then
            app:refresh_media(reason)
            return
        end
        media_timer = mp.add_timeout(opts.media_debounce_ms / 1000, function()
            media_timer = nil
            app:refresh_media(reason)
        end)
    end

    local registering_observers = true
    local media_observers = {
        "path", "stream-open-filename", "duration", "aid", "edition", "track-list", "audio-delay",
        "demuxer-start-time", "rebase-start-time",
    }
    for _, property in ipairs(media_observers) do
        local property_name = property
        if mp.observe_property then
            mp.observe_property(property_name, "native", function()
                if not registering_observers then schedule_media("property:" .. property_name) end
            end)
        end
    end
    local geometry_observers = {
        "osd-width", "osd-height", "osd-dimensions", "display-hidpi-scale", "fullscreen", "window-maximized", "border",
        "title-bar", "playlist-count", "pause", "cursor-autohide", "cursor-autohide-fs-only", "focused",
        "user-data/uosc/menu/type", "shared-script-properties",
        "user-data/mpv/context-menu/open", "user-data/mpv/console/open",
    }
    for _, property in ipairs(geometry_observers) do
        local property_name = property
        if mp.observe_property then
            mp.observe_property(property_name, "native", function(_, value)
                if value == nil then value = get_native(property_name) end
                geometry_values[property_name] = value ~= nil and value or GEOMETRY_MISSING
                if not registering_observers then
                    if not cursor_autohide_allowed() then cancel_cursor_autohide() end
                    schedule_geometry("property:" .. property_name)
                end
            end)
        end
    end
    if mp.observe_property then
        mp.observe_property("mouse-pos", "native", function(_, mouse)
            if not registering_observers then handle_mouse_geometry(mouse) end
        end)
        mp.observe_property("touch-pos", "native", function(_, touches)
            local touch = type(touches) == "table" and touches[1] or nil
            if not registering_observers and type(touch) == "table" then
                handle_mouse_geometry({ x = touch.x, y = touch.y, hover = true })
            end
        end)
    end
    if mp.observe_property then
        mp.observe_property("background-color", "native", function()
            if not registering_observers then schedule_media("background-color") end
        end)
    end
    registering_observers = false
    if mp.register_event then
        mp.register_event("file-loaded", function() schedule_media("file-loaded") end)
        -- `file-loaded` can arrive before selection metadata is fully visible
        -- for some audio-only containers. `playback-restart` is the stable
        -- post-initialization retry point and is harmless for already-ready
        -- media because refresh_media coalesces identical identities.
        mp.register_event("playback-restart", function()
            -- Avoid rescanning on every seek. Retry only while initialization
            -- is blocked by properties that can legitimately settle late.
            if state == STATES.UNSUPPORTED and (
                unsupported_reason == "missing-path"
                or unsupported_reason == "invalid-duration"
                or unsupported_reason == "no-audio"
            ) then
                schedule_media("playback-restart")
            end
        end)
        mp.register_event("end-file", function()
            token = token + 1
            cancel_timer(media_timer)
            media_timer = nil
            cancel_active_generation()
            cancel_cursor_fade()
            cancel_cursor_autohide()
            renderer:hide()
            clear_current_raw()
            current_media = nil
            current_identity = nil
            paths = nil
            last_visibility = 0
            unsupported_reason = "end-file"
            state = STATES.UNSUPPORTED
        end)
        mp.register_event("shutdown", function() app:shutdown() end)
    end
    if mp.register_script_message then mp.register_script_message("uosc-waveform-toggle", function() app:toggle() end) end
    if mp.add_key_binding then
        mp.add_key_binding("Alt+w", "uosc-waveform-toggle", function() app:toggle() end)
        mp.add_key_binding("Alt+Shift+w", "uosc-waveform-status", function() app:show_status() end)
    end

    return app
end

M.STATES = STATES

return M
