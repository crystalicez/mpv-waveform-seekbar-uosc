local root = assert(arg[1], "source root required")
package.path = table.concat({
    root .. "/portable_config/scripts/?.lua",
    root .. "/portable_config/scripts/?/init.lua",
    package.path,
}, ";")

local ffmpeg = require("uosc_waveform.ffmpeg")
local opts = {
    opacity = 0.5,
    analysis_sample_rate = 8000,
    source_width = 256,
    source_height = 32,
}

local function filter_for(track)
    local argv = ffmpeg.build_peak_argv("ffmpeg", {
        input_path = [[C:\Media\multi.mkv]],
        duration = 120.25,
        track = track,
    }, opts, false)
    for index, value in ipairs(argv) do
        if value == "-filter_complex" then return argv[index + 1] end
    end
    error("missing filter graph")
end

local indexed = filter_for({ ff_index = 3, audio_ordinal = 1 })
assert(indexed:find("[0:3]", 1, true), "ff-index must be the preferred FFmpeg selector")
assert(indexed:find("apad=whole_dur=120.25", 1, true), "short tracks must be padded to the mpv timeline duration")
assert(indexed:find("atrim=duration=120.25", 1, true), "long tracks must be trimmed to the mpv timeline duration")

local fallback = filter_for({ ff_index = nil, audio_ordinal = 1 })
assert(fallback:find("[0:a:1]", 1, true), "audio ordinal must be used only when ff-index is unavailable")

print("PASS ffmpeg_multi_audio")
