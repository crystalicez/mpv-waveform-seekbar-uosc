local root = assert(arg[1], "source root required")
package.path = root .. "/portable_config/scripts/?.lua;" .. root .. "/portable_config/scripts/?/init.lua;" .. package.path
local util = require("uosc_waveform.util")

assert(util.normalize_windows_path([[C:\Media\A\..\B.mkv]]) == [[c:\Media\B.mkv]])
assert(util.normalize_windows_path([[C:folder\..\clip.mkv]]) == [[c:clip.mkv]],
    "drive-relative paths must not be converted to drive-root paths")
assert(util.normalize_windows_path([[\\server\share\folder\..\clip.mkv]]) == [[\\server\share\clip.mkv]])
assert(util.normalize_windows_path([[\\server\share\..\clip.mkv]]) == [[\\server\share\clip.mkv]],
    "UNC normalization must not climb above the share root")
assert(util.normalize_windows_path([[\\?\C:\very\long\..\clip.mkv]]) == [[\\?\c:\very\clip.mkv]])
local key = util.hash64("same identity")
assert(#key == 16 and key:match("^%x+$"), "cache hash must contain 64 bits of hex")
assert(key == util.hash64("same identity"), "cache hash must be deterministic")
assert(key ~= util.hash64("different identity"), "different identities should not share a key in the test set")
print("PASS util_windows_paths")
