local root = assert(arg[1], "source root required")
package.path = root .. "/portable_config/scripts/?.lua;" .. root .. "/portable_config/scripts/?/init.lua;" .. package.path
local waveform = require("uosc_waveform.waveform")

local width, height = 4, 8
local raw, err = waveform.render_bgra({ 0, 0.25, 0.5, 1 }, width, height, "#804020", 0.5)
assert(raw and not err, tostring(err))
assert(#raw == width * height * 4, "BGRA output must have exact fixed size")

local function pixel(x, y)
    local offset = ((y * width + x) * 4) + 1
    return { raw:byte(offset, offset + 3) }
end
local function same(a, b)
    return a[1] == b[1] and a[2] == b[2] and a[3] == b[3] and a[4] == b[4]
end

for x = 0, width - 1 do
    for y = 0, height - 1 do
        assert(same(pixel(x, y), pixel(x, height - 1 - y)), "bitmap must be vertically symmetric")
    end
end
for y = 0, height - 1 do
    assert(same(pixel(0, y), {0, 0, 0, 0}), "silence must remain fully transparent")
end
local full = pixel(3, 0)
assert(same(full, {16, 32, 64, 128}), "colored pixels must use premultiplied BGRA")

local bad, reason = waveform.render_bgra({}, width, height, "#FFFFFF", 1)
assert(bad == nil and reason == "peak-count-mismatch", "renderer must reject wrong peak count")

-- Production-size output and release of the large returned string.
collectgarbage("collect")
local baseline = collectgarbage("count")
local peaks = {}
for x = 1, 4096 do peaks[x] = (x % 101) / 100 end
local production = assert(waveform.render_bgra(peaks, 4096, 128, "#FFFFFF", 0.42))
assert(#production == 4096 * 128 * 4, "production bitmap must be exactly 2 MiB")
production, peaks = nil, nil
collectgarbage("collect")
local after = collectgarbage("count")
assert(after <= baseline + 128, string.format("renderer should release temporary heap: baseline=%.2f after=%.2f", baseline, after))

print("PASS waveform_bitmap_render")
