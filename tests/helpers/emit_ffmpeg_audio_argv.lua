local root = assert(arg[1], "source root required")
local input = assert(arg[2], "audio input required")
local output = assert(arg[3], "raw output required")
package.path = root .. "/portable_config/scripts/?.lua;" .. root .. "/portable_config/scripts/?/init.lua;" .. package.path
local ffmpeg = require("uosc_waveform.ffmpeg")
local argv = ffmpeg.build_generate_argv("ffmpeg", {
    input_path = input,
    duration = 6,
    source_duration = 6,
    timeline_offset = 0,
    audio_delay = 0,
    track = { ff_index = 0, audio_ordinal = 0, external = false },
}, {
    opacity = 0.38,
    analysis_sample_rate = 8000,
    source_width = 512,
    source_height = 64,
}, output, "#F2F2F2", false)
for _, value in ipairs(argv) do io.write(value, "\0") end
