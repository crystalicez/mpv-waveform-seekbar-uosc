local root = assert(arg[1], "source root required")
package.path = root .. "/portable_config/scripts/?.lua;" .. root .. "/portable_config/scripts/?/init.lua;" .. package.path
local waveform = require("uosc_waveform.waveform")

local function assert_close(actual, expected, epsilon, message)
    assert(math.abs(actual - expected) <= (epsilon or 1e-6),
        string.format("%s: expected %.9f got %.9f", message or "value", expected, actual))
end

local text = table.concat({
    "frame:0    pts:0       pts_time:0",
    "lavfi.astats.1.Peak_level=-inf",
    "frame:1    pts:200     pts_time:0.25",
    "lavfi.astats.1.Peak_level=-12.0412",
    "frame:2    pts:400     pts_time:0.5",
    "lavfi.astats.1.Peak_level=0",
    "frame:3    pts:600     pts_time:0.75",
    "lavfi.astats.1.Peak_level=-6.0206",
}, "\r\n")

local peaks, err = waveform.parse_peak_metadata(text, 1, 4)
assert(peaks and not err, tostring(err))
assert(#peaks == 4, "parser must return exactly width bins")
assert_close(peaks[1], 0, 1e-6, "-inf maps to silence")
assert_close(peaks[2], math.sqrt(0.25), 1e-5, "-12.0412 dB maps with sqrt scaling")
assert_close(peaks[3], 1, 1e-6, "0 dB maps to full scale")
assert_close(peaks[4], math.sqrt(0.5), 1e-5, "-6.0206 dB maps with sqrt scaling")

local invalid_cases = {
    { "", "empty-output" },
    { "frame:0 pts:0 pts_time:oops\nlavfi.astats.1.Peak_level=-1", "malformed-pts-time" },
    { "frame:0 pts:0 pts_time:0\n", "missing-peak-level" },
    { "frame:0 pts:0 pts_time:0\nlavfi.astats.1.Peak_level=nan", "invalid-peak-level" },
    { "frame:0 pts:0 pts_time:0\nlavfi.astats.1.Peak_level=inf", "invalid-peak-level" },
    { table.concat({
        "frame:0 pts:10 pts_time:0.5",
        "lavfi.astats.1.Peak_level=-1",
        "frame:1 pts:0 pts_time:0.25",
        "lavfi.astats.1.Peak_level=-1",
    }, "\n"), "non-monotonic-pts" },
}
for _, case in ipairs(invalid_cases) do
    local value, reason = waveform.parse_peak_metadata(case[1], 1, 4)
    assert(value == nil and reason == case[2],
        string.format("expected %s, got value=%s reason=%s", case[2], tostring(value), tostring(reason)))
end

print("PASS waveform_peak_parser")
