local root = assert(arg[1], "source root required")
package.path = root .. "/portable_config/scripts/?.lua;" .. root .. "/portable_config/scripts/?/init.lua;" .. package.path
local ffmpeg = require("uosc_waveform.ffmpeg")
local opts = { opacity = 0.5, analysis_sample_rate = 8000, source_width = 1000, source_height = 64 }

local function filter(delay, ordinal, timeline_offset)
    local argv = ffmpeg.build_generate_argv("ffmpeg", {
        input_path = "clip.mkv", duration = 10, audio_delay = delay,
        timeline_offset = timeline_offset or 0,
        track = { ff_index = 3, audio_ordinal = 1 },
    }, opts, "out.tmp", "#FFFFFF", ordinal)
    for i, value in ipairs(argv) do if value == "-filter_complex" then return argv[i + 1] end end
end

local base = filter(0, false)
assert(base:find("[0:3]", 1, true), "ff-index must remain preferred")
assert(base:find("aresample=8000:async=1:first_pts=0", 1, true),
    "packet timestamps and leading gaps must be aligned to the media timeline")
assert(not base:find("asetpts=", 1, true), "zero audio delay needs no extra timestamp shift")
local positive = filter(1.5, false)
assert(positive:find("asetpts=PTS+1.5/TB", 1, true), "positive audio-delay must move waveform right")
local negative = filter(-0.75, false)
assert(negative:find("asetpts=PTS-0.75/TB", 1, true), "negative audio-delay must move waveform left")
local offset = filter(0.5, false, 5)
assert(offset:find("asetpts=PTS+5.5/TB", 1, true),
    "non-rebased demuxer start and audio-delay must share the timeline shift")
local fallback = filter(0, true)
assert(fallback:find("[0:a:1]", 1, true), "ordinal retry must select the source-scoped audio ordinal")
assert(ffmpeg.is_stream_mapping_error({ stderr = "Stream specifier ':7' in filtergraph matches no streams." }))
assert(not ffmpeg.is_stream_mapping_error({ stderr = "No such file or directory" }))
print("PASS ffmpeg_timeline_alignment")
