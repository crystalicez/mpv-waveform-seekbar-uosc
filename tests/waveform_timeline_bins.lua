local root = assert(arg[1], "source root required")
package.path = root .. "/portable_config/scripts/?.lua;" .. root .. "/portable_config/scripts/?/init.lua;" .. package.path
local waveform = require("uosc_waveform.waveform")

local function metadata(frames)
    local lines = {}
    for index, frame in ipairs(frames) do
        lines[#lines + 1] = string.format("frame:%d pts:%d pts_time:%.9g", index - 1, index - 1, frame[1])
        lines[#lines + 1] = "lavfi.astats.1.Peak_level=" .. tostring(frame[2])
    end
    return table.concat(lines, "\n")
end

-- Fewer frames than pixels: each timestamp interval expands over the media timeline.
local peaks = assert(waveform.parse_peak_metadata(metadata({ {0, -6.0206}, {0.5, 0} }), 1, 8))
for x = 1, 4 do assert(peaks[x] > 0.70 and peaks[x] < 0.71, "first half should use first frame") end
for x = 5, 8 do assert(peaks[x] == 1, "second half should use second frame") end

-- More frames than pixels: all frames touching a pixel are peak-aggregated, not averaged.
peaks = assert(waveform.parse_peak_metadata(metadata({
    {0.00, -20}, {0.10, -1}, {0.20, -30}, {0.30, -40},
    {0.40, -50}, {0.50, -60}, {0.60, -70}, {0.70, -80},
}), 0.8, 2))
local expected_first = math.sqrt(10 ^ (-1 / 20))
assert(math.abs(peaks[1] - expected_first) < 1e-6, "pixel must keep strongest overlapping frame")
assert(peaks[2] > 0 and peaks[2] < peaks[1], "second pixel should contain quieter frames")

-- A late first timestamp leaves the leading seekbar region silent.
peaks = assert(waveform.parse_peak_metadata(metadata({ {0.5, 0} }), 1, 4))
assert(peaks[1] == 0 and peaks[2] == 0, "late audio must leave blank leading bins")
assert(peaks[3] == 1 and peaks[4] == 1, "late audio must begin at its true timestamp")

-- A timestamp at/after duration is valid metadata but contributes no visible pixels.
peaks = assert(waveform.parse_peak_metadata(metadata({ {1.0, 0} }), 1, 4))
for x = 1, 4 do assert(peaks[x] == 0, "out-of-range frame must not wrap onto the timeline") end

print("PASS waveform_timeline_bins")
