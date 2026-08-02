local root = assert(arg[1], "source root required")
package.path = root .. "/portable_config/scripts/?.lua;" .. root .. "/portable_config/scripts/?/init.lua;" .. package.path
local media = require("uosc_waveform.media")

local source = "/tmp/song.m4a"
local fs = { info = function(path)
    if path == source then return { size = 100, mtime = 1, is_file = true, is_dir = false } end
end }

local result = media.inspect({
    path = source,
    duration = 60,
    aid = "auto",
    track_list = {
        { type = "audio", id = 1, ["ff-index"] = 0 },
    },
}, fs)

assert(result.supported, "a sole audio track must be usable while mpv selection metadata is still settling: " .. tostring(result.reason))
assert(result.track.id == 1, "the sole audio track must be selected as fallback")
local explicit_mismatch = media.inspect({
    path = source,
    duration = 60,
    aid = 9,
    track_list = {
        { type = "audio", id = 1, ["ff-index"] = 0 },
    },
}, fs)
assert(not explicit_mismatch.supported and explicit_mismatch.reason == "no-audio",
    "a sole-track fallback must not override an explicit unmatched aid")

local ambiguous = media.inspect({
    path = source,
    duration = 60,
    aid = "auto",
    track_list = {
        { type = "audio", id = 1, ["ff-index"] = 0 },
        { type = "audio", id = 2, ["ff-index"] = 1 },
    },
}, fs)
assert(not ambiguous.supported and ambiguous.reason == "no-audio",
    "automatic fallback must not guess between multiple unselected audio tracks")
print("PASS media_single_audio_fallback")
