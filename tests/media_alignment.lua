local root = assert(arg[1], "source root required")
package.path = root .. "/portable_config/scripts/?.lua;" .. root .. "/portable_config/scripts/?/init.lua;" .. package.path
local media = require("uosc_waveform.media")

local posix = "/tmp/clip.mkv"
local fs = { info = function(path)
    if path == posix then return { size = 10, mtime = 20, is_file = true, is_dir = false } end
end }
local info = media.inspect({
    path = posix, duration = 12, aid = "2", audio_delay = 1.25,
    track_list = {
        { type = "video", id = 1, selected = true, albumart = false },
        { type = "audio", id = 2, selected = true, ["ff-index"] = "3" },
    },
}, fs)
assert(info.supported, info.reason)
assert(info.input_path == posix, "POSIX paths must not be converted to backslashes")
assert(info.track.ff_index == 3, "numeric native/string ff-index values must be accepted")
assert(info.audio_delay == 1.25, "audio-delay must enter media identity")
assert(info.media_type == "video", "selected real video track must preserve video persistency semantics")

local empty_stream_name = media.inspect({
    path = posix,
    stream_open_filename = "",
    duration = 20,
    aid = 1,
    track_list = {{type="audio", id=1, selected=true, ["ff-index"]="1"}},
}, fs)
assert(empty_stream_name.supported and empty_stream_name.source_path:lower() == posix:lower(),
    "empty stream-open-filename must fall back to the valid path property")

local malformed_tracks = media.inspect({
    path = posix,
    duration = 20,
    aid = 1,
    track_list = "not-a-table",
}, fs)
assert(not malformed_tracks.supported and malformed_tracks.reason == "no-audio",
    "malformed track-list must fail closed instead of crashing the script")

local disabled_video = media.inspect({
    path = posix, duration = 12, aid = 2,
    track_list = {
        {type="video", id=1, selected=false, albumart=false},
        {type="audio", id=2, selected=true, ["ff-index"]=1},
    },
}, fs)
assert(disabled_video.media_type == "video",
    "media disposition must match uosc even when vid=no leaves a real video track unselected")

local cover_only = media.inspect({
    path = posix, duration = 12, aid = 2,
    track_list = {
        {type="video", id=1, selected=true, image=true, albumart=true},
        {type="audio", id=2, selected=true, ["ff-index"]=1},
    },
}, fs)
assert(cover_only.media_type == "audio", "cover art must not force video persistency")

local unrebase = media.inspect({
    path = posix, duration = 12, aid = 2, demuxer_start_time = 5,
    rebase_start_time = false, audio_delay = 0.5,
    track_list = {{type="audio", id=2, selected=true, ["ff-index"]=1}},
}, fs)
assert(unrebase.supported, unrebase.reason)
assert(unrebase.source_duration == 12 and unrebase.duration == 17,
    "non-rebased start time must extend the canvas exactly like uosc")
assert(unrebase.timeline_offset == 5,
    "non-rebased waveform must preserve leading demuxer timeline space")

local rebased = media.inspect({
    path = posix, duration = 12, aid = 2, demuxer_start_time = 5,
    rebase_start_time = true,
    track_list = {{type="audio", id=2, selected=true, ["ff-index"]=1}},
}, fs)
assert(rebased.duration == 12 and rebased.timeline_offset == 0,
    "default rebasing must keep the waveform canvas starting at zero")

print("PASS media_alignment")
