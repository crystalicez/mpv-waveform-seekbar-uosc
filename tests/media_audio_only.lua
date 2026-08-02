local root = assert(arg[1], "source root required")
package.path = root .. "/portable_config/scripts/?.lua;" .. root .. "/portable_config/scripts/?/init.lua;" .. package.path
local media = require("uosc_waveform.media")

local audio_path = "/tmp/song.flac"
local fs = { info = function(path)
    if path == audio_path then return { size = 1234, mtime = 5678, is_file = true, is_dir = false } end
end }

local plain = media.inspect({
    path = audio_path,
    duration = 180,
    aid = "auto",
    track_list = {
        { type = "audio", id = 1, selected = true, ["main-selection"] = 0, ["ff-index"] = 0 },
    },
}, fs)
assert(plain.supported, plain.reason)
assert(plain.media_type == "audio", "plain audio must use audio uosc disposition")
assert(plain.track.ff_index == 0 and plain.track.audio_ordinal == 0,
    "plain audio must map its selected stream")

local cover = media.inspect({
    path = audio_path,
    duration = 180,
    aid = 2,
    track_list = {
        { type = "video", id = 1, selected = true, image = true, albumart = true, ["ff-index"] = 0 },
        { type = "audio", id = 2, selected = true, ["main-selection"] = 0, ["ff-index"] = 1 },
    },
}, fs)
assert(cover.supported, cover.reason)
assert(cover.media_type == "audio", "cover art must not turn an audio file into video")
assert(cover.track.ff_index == 1, "cover-art file must map the audio stream, not the image stream")

local no_selection = media.inspect({
    path = audio_path,
    duration = 180,
    aid = "no",
    track_list = {{ type = "audio", id = 1, selected = false, ["ff-index"] = 0 }},
}, fs)
assert(not no_selection.supported and no_selection.reason == "no-audio",
    "aid=no must remain unsupported")

local unknown_duration = media.inspect({
    path = audio_path,
    aid = 1,
    track_list = {{ type = "audio", id = 1, selected = true, ["ff-index"] = 0 }},
}, fs)
assert(not unknown_duration.supported and unknown_duration.reason == "invalid-duration",
    "audio with unknown duration must remain unsupported")

print("PASS media_audio_only")
