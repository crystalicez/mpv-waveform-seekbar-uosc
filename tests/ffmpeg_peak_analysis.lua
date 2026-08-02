local root = assert(arg[1], "source root required")
package.path = root .. "/portable_config/scripts/?.lua;" .. root .. "/portable_config/scripts/?/init.lua;" .. package.path
local ffmpeg = require("uosc_waveform.ffmpeg")

local opts = {
    analysis_sample_rate = 8000,
    source_width = 4096,
    source_height = 128,
}
local media = {
    input_path = [[C:\Media\long.m4a]],
    duration = 120.25,
    audio_delay = 0.5,
    timeline_offset = 5,
    track = { ff_index = 3, audio_ordinal = 1 },
}
local argv = ffmpeg.build_peak_argv("ffmpeg", media, opts, false)
local filter
for index, value in ipairs(argv) do
    if value == "-filter_complex" then filter = argv[index + 1] end
end
assert(filter, "peak analyzer must use a filter graph")
assert(filter:find("[0:3]", 1, true), "ff-index must remain the preferred stream selector")
assert(filter:find("asetpts=PTS+5.5/TB", 1, true), "timeline offset and audio delay must remain aligned")
assert(filter:find("aformat=channel_layouts=mono", 1, true), "analysis must be mono")
assert(filter:find("aresample=8000:async=1:first_pts=0", 1, true), "PTS gaps must remain preserved")
assert(filter:find("apad=whole_dur=120.25", 1, true), "short tracks must be padded")
assert(filter:find("atrim=duration=120.25", 1, true), "long tracks must be cropped")
local samples_per_frame = math.ceil(8000 * 120.25 / 4096)
assert(filter:find("asetnsamples=n=" .. samples_per_frame .. ":p=1", 1, true),
    "analysis must bound output frames to approximately source_width")
assert(filter:find("astats=metadata=1:reset=1:measure_perchannel=Peak_level:measure_overall=none", 1, true),
    "analysis must emit per-frame peak metadata")
assert(filter:find("ametadata=print:key=lavfi.astats.1.Peak_level:file=-", 1, true),
    "peak metadata must be captured on stdout")
assert(not filter:find("showwavespic", 1, true), "high-RAM showwavespic must be removed from the new path")
assert(not filter:find("format=bgra", 1, true), "FFmpeg must no longer render the bitmap")

local joined = table.concat(argv, "\n")
assert(not joined:find("rawvideo", 1, true), "peak analysis must not emit rawvideo")
assert(joined:find("-f\nnull\n-", 1, false), "analyzed audio must be consumed by the null muxer")

local fallback = ffmpeg.build_peak_argv("ffmpeg", media, opts, true)
local fallback_filter
for index, value in ipairs(fallback) do
    if value == "-filter_complex" then fallback_filter = fallback[index + 1] end
end
assert(fallback_filter:find("[0:a:1]", 1, true), "ordinal retry must remain available")

assert(ffmpeg.is_feature_unsupported({ stderr = "No such filter: 'astats'" }))
assert(ffmpeg.is_feature_unsupported({ stderr = "Error applying option 'reset' to filter 'astats': Option not found" }))
assert(ffmpeg.is_feature_unsupported({ error_string = "No such filter: asetnsamples" }))
assert(not ffmpeg.is_feature_unsupported({ stderr = "Stream specifier ':7' matches no streams" }))

print("PASS ffmpeg_peak_analysis")

local captured
local callback_result
local mock_mpv={
 command_native_async=function(command,callback)
  captured=command
  callback(true,{status=0,stdout="",stderr=""},nil)
  return 1
 end,
}
ffmpeg.start(mock_mpv,{"ffmpeg","-version"},function(result) callback_result=result end)
local fields=captured
assert(type(fields)=="table")
assert(fields.capture_size and fields.capture_size<=8*1024*1024,
 "captured FFmpeg output must have an explicit bounded size")
assert(fields.playback_only==false and fields.capture_stdout==true and fields.capture_stderr==true)
assert(callback_result and callback_result.status==0)
print("PASS ffmpeg_capture_budget")
