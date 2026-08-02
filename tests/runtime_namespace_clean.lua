local root = assert(arg[1], "source root required")
local runtime = root .. "/portable_config"
local files = {
    runtime .. "/scripts/uosc-waveform.lua",
    runtime .. "/script-opts/uosc-waveform.conf",
    runtime .. "/scripts/uosc_waveform/cache.lua",
    runtime .. "/scripts/uosc_waveform/controller.lua",
    runtime .. "/scripts/uosc_waveform/ffmpeg.lua",
    runtime .. "/scripts/uosc_waveform/geometry.lua",
    runtime .. "/scripts/uosc_waveform/media.lua",
    runtime .. "/scripts/uosc_waveform/mpv_compat.lua",
    runtime .. "/scripts/uosc_waveform/options.lua",
    runtime .. "/scripts/uosc_waveform/overlay.lua",
    runtime .. "/scripts/uosc_waveform/util.lua",
    runtime .. "/scripts/uosc_waveform/windows_lock.lua",
    runtime .. "/scripts/uosc_waveform/waveform.lua",
}
local forbidden = {
    "waveform" .. "_preview", "waveform" .. "-preview", "Waveform" .. " Preview",
    "show" .. "wavespic",
}
for _, path in ipairs(files) do
    local handle = assert(io.open(path, "rb"), "missing runtime file: " .. path)
    local text = handle:read("*a")
    handle:close()
    for _, needle in ipairs(forbidden) do
        assert(not text:find(needle, 1, true), path .. " contains forbidden old runtime name: " .. needle)
    end
end
print("PASS runtime_namespace_clean")
