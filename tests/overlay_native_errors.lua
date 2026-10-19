local root = assert(arg[1], "source root required")
package.path = root .. "/portable_config/scripts/?.lua;" .. root .. "/portable_config/scripts/?/init.lua;" .. package.path
local overlay = require("uosc_waveform.overlay")
local calls, removed = 0, 0
local mp = {
    command_native = function(command)
        local name = command._name or command.name
        if name == "overlay-remove" then removed = removed + 1; return {} end
        assert(name == "overlay-add")
        calls = calls + 1
        if calls == 1 then return nil, "synthetic mpv API failure" end
        if calls == 2 then error("synthetic exception") end
        if calls == 3 then return false end
        return {} -- mpv returns a (usually empty) table on success
    end,
}
local renderer = overlay.new(mp, { overlay_id = 63 })
local rect = { x = 0, y = 30, width = 256, height = 20 }
for i = 1, 3 do
    assert(not renderer:show("/tmp/bitmap.bgra", 256, 16, rect), "failed overlay-add must not report success")
    assert(not renderer:is_visible() and renderer:last_signature() == nil, "failure must not cache overlay signature")
end
assert(renderer:show("/tmp/bitmap.bgra", 256, 16, rect), "later successful overlay-add must retry")
assert(renderer:is_visible())
assert(renderer:show("/tmp/bitmap.bgra", 256, 16, rect))
assert(calls == 4, "identical successful overlay must not be re-added")
renderer:hide()
assert(removed == 1 and not renderer:is_visible())
print("PASS overlay_native_errors")
