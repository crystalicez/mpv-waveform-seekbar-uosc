local root = assert(arg[1], "source root required")
local input = assert(arg[2], "audio input required")
local duration = assert(tonumber(arg[3]), "duration required")
local width = tonumber(arg[4]) or 512
local sample_rate = tonumber(arg[5]) or 8000
local audio_delay = tonumber(arg[6]) or 0
local timeline_offset = tonumber(arg[7]) or 0
local ff_index = tonumber(arg[8]) or 0
local audio_ordinal = tonumber(arg[9]) or 0
package.path = root .. "/portable_config/scripts/?.lua;" .. root .. "/portable_config/scripts/?/init.lua;" .. package.path
local ffmpeg = require("uosc_waveform.ffmpeg")
local argv = ffmpeg.build_peak_argv("ffmpeg", {
    input_path = input,
    duration = duration,
    source_duration = duration,
    timeline_offset = timeline_offset,
    audio_delay = audio_delay,
    track = { ff_index = ff_index, audio_ordinal = audio_ordinal, external = false },
}, {
    analysis_sample_rate = sample_rate,
    source_width = width,
}, false)
for _, value in ipairs(argv) do io.write(value, "\0") end
