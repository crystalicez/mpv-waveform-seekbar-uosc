local root = assert(arg[1], "source root required")
package.path = root .. "/portable_config/scripts/?.lua;" .. root .. "/portable_config/scripts/?/init.lua;" .. package.path
local options = require("uosc_waveform.options")

assert(options.defaults().startup_osd == false, "startup OSD must be silent by default")

local normalized, warnings = options.normalize({
    ffmpeg_path = "   ", cache_dir = "", log_level = " DEBUG ", compatibility = "  ",
}, {config_dir=[[C:\Config]], platform="windows"})
assert(normalized.ffmpeg_path == "ffmpeg", "empty ffmpeg path must use the safe default")
assert(normalized.cache_dir == [[c:\Config\cache\uosc-waveform]],
    "empty cache path must not resolve to the current working directory")
assert(normalized.log_level == "debug", "log level should be trimmed and normalized")
assert(normalized.compatibility == "uosc-5.12", "empty compatibility must use the supported adapter")
assert(#warnings >= 2, "invalid empty paths should produce diagnostics")

local fallback = options.normalize({log_level="verbose", opacity=0/0, source_width=math.huge},
    {config_dir="/tmp", platform="other"})
assert(fallback.log_level == "warn", "unknown log levels must fail closed to warn")
assert(fallback.opacity == options.defaults().opacity and fallback.source_width == options.defaults().source_width,
    "NaN/infinite numeric options must not escape normalization")
local uosc = options.parse_key_value_file([[
background_color = #FFFFFF
color = "#abcdef" # explanation
autohide=yes # inline comment
# whole-line comment
]])
assert(uosc.background_color == "#FFFFFF" and uosc.color == "#abcdef",
    "hex color option values must survive comment stripping")
assert(uosc.autohide == "yes", "ordinary comments must still be stripped")
local auto = options.normalize({}, {config_dir="/tmp",platform="other"})
assert(options.choose_waveform_color(auto, uosc, "#000000") == auto.light_color,
    "white uosc background must select dark waveform contrast")
print("PASS options_validation")
