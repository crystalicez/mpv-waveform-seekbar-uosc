local root = assert(arg[1], "source root required")
package.path = root .. "/portable_config/scripts/?.lua;" .. root .. "/portable_config/scripts/?/init.lua;" .. package.path
local media = require("uosc_waveform.media")

local source = "/tmp/call.m4a"
local fs = { info = function(path)
    if path == source then return { size = 1234, mtime = 5678, is_file = true, is_dir = false } end
end }

local via_lavfi = media.inspect({
    path = source,
    duration = 420,
    aid = "no",
    lavfi_complex = "[aid1] asplit [ao],showcqt [vo]",
    current_audio = { type = "audio", id = 1, ["ff-index"] = 0 },
    track_list = {
        { type = "audio", id = 1, selected = true, ["ff-index"] = 0 },
    },
}, fs)
assert(via_lavfi.supported, via_lavfi.reason)
assert(via_lavfi.track.id == 1, "lavfi-selected current audio track must be used even when aid reports no")
assert(via_lavfi.track.ff_index == 0, "lavfi-selected audio ff-index must be preserved")

local explicit_no = media.inspect({
    path = source,
    duration = 420,
    aid = "no",
    lavfi_complex = "",
    track_list = {
        { type = "audio", id = 1, selected = false, ["ff-index"] = 0 },
    },
}, fs)
assert(not explicit_no.supported and explicit_no.reason == "no-audio",
    "aid=no without a lavfi-selected current audio track must remain unsupported")

print("PASS media_lavfi_audio")
