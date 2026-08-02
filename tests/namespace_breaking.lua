local root = assert(arg[1], "source root required")
local function exists(path)
    local f = io.open(path, "rb")
    if f then f:close(); return true end
    return false
end

assert(exists(root .. "/portable_config/scripts/uosc-waveform.lua"),
    "new entry script must be named uosc-waveform.lua")
assert(exists(root .. "/portable_config/scripts/uosc_waveform/controller.lua"),
    "new module directory must be uosc_waveform")
assert(exists(root .. "/portable_config/script-opts/uosc-waveform.conf"),
    "new options file must be uosc-waveform.conf")
assert(not exists(root .. "/portable_config/scripts/waveform-preview.lua"),
    "old entry script must not ship")
assert(not exists(root .. "/portable_config/scripts/waveform_preview/controller.lua"),
    "old module directory must not ship")
assert(not exists(root .. "/portable_config/script-opts/waveform-preview.conf"),
    "old options file must not ship")

print("PASS namespace_breaking")
