local root = assert(arg[1], "source root required")
package.path = table.concat({
    root .. "/portable_config/scripts/?.lua",
    root .. "/portable_config/scripts/?/init.lua",
    package.path,
}, ";")

local media = require("uosc_waveform.media")
local source = [[C:\Media\multi.mkv]]
local external = [[C:\Media\commentary.mka]]
local fs = {
    info = function(path)
        if path == source or path == source:lower() then
            return { size = 1000, mtime = 10, is_file = true, is_dir = false }
        end
        if path == external or path == external:lower() then
            return { size = 500, mtime = 20, is_file = true, is_dir = false }
        end
        return nil
    end,
}

local function inspect(track_list, aid)
    return media.inspect({
        path = source,
        ["stream-open-filename"] = source,
        duration = 120,
        aid = aid,
        edition = 0,
        track_list = track_list,
    }, fs)
end

-- The effective aid must win even if track-list.selected is temporarily stale
-- or several tracks are decoded by lavfi-complex.
local exact = inspect({
    { type = "audio", id = 1, selected = true, ["ff-index"] = 1 },
    { type = "audio", id = 2, selected = false, ["ff-index"] = 2 },
}, 2)
assert(exact.supported, exact.reason)
assert(exact.track.id == 2, "effective aid must take priority over a stale selected flag")
assert(exact.track.ff_index == 2, "the selected track's ff-index must be preserved")

-- The [0:a:N] fallback is scoped to the main input. External tracks must not
-- shift the ordinal of embedded streams.
local embedded = inspect({
    { type = "audio", id = 9, selected = false, external = true, ["external-filename"] = external },
    { type = "audio", id = 1, selected = false },
    { type = "audio", id = 2, selected = true },
}, 2)
assert(embedded.supported, embedded.reason)
assert(embedded.track.external == false, "selected embedded track misclassified")
assert(embedded.track.audio_ordinal == 1, "embedded ordinal must ignore external audio tracks")

-- An external container can expose more than one audio stream. ff-index is
-- still the strongest selector and must not be discarded merely because the
-- track is external.
local external_index = inspect({
    { type = "audio", id = 4, selected = false, external = true, ["external-filename"] = external, ["ff-index"] = 1 },
    { type = "audio", id = 5, selected = true, external = true, ["external-filename"] = external, ["ff-index"] = 3 },
}, 5)
assert(external_index.supported, external_index.reason)
assert(external_index.track.external == true, "selected external track misclassified")
assert(external_index.track.ff_index == 3, "external track ff-index must be preserved")

-- If ff-index is unavailable, count only audio tracks from the same external
-- file, not tracks from the main file or another external file.
local other_external = [[C:\Media\other.mka]]
local fs2 = {
    info = function(path)
        if path == source or path == source:lower() then return { size = 1000, mtime = 10, is_file = true, is_dir = false } end
        if path == external or path == external:lower() then return { size = 500, mtime = 20, is_file = true, is_dir = false } end
        if path == other_external or path == other_external:lower() then return { size = 600, mtime = 30, is_file = true, is_dir = false } end
        return nil
    end,
}
local external_fallback = media.inspect({
    path = source,
    ["stream-open-filename"] = source,
    duration = 120,
    aid = 7,
    track_list = {
        { type = "audio", id = 1, selected = false },
        { type = "audio", id = 6, selected = false, external = true, ["external-filename"] = external },
        { type = "audio", id = 99, selected = false, external = true, ["external-filename"] = other_external },
        { type = "audio", id = 7, selected = true, external = true, ["external-filename"] = external },
    },
}, fs2)
assert(external_fallback.supported, external_fallback.reason)
assert(external_fallback.track.audio_ordinal == 1,
    "external fallback ordinal must count only audio streams from the selected external file")

print("PASS media_multi_audio")
