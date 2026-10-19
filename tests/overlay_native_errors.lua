local root = assert(arg[1], "source root required")
package.path = root .. "/portable_config/scripts/?.lua;" .. root .. "/portable_config/scripts/?/init.lua;" .. package.path
local overlay = require("uosc_waveform.overlay")
local calls, removed, fail_next_remove = 0, 0, false
local mp = {
    command_native = function(command)
        local name = command._name or command.name
        if name == "overlay-remove" then
            if fail_next_remove then
                fail_next_remove = false
                return nil, "synthetic removal failure"
            end
            removed = removed + 1
            return {}
        end
        assert(name == "overlay-add")
        calls = calls + 1
        if calls == 1 then return nil, "synthetic mpv API failure" end
        if calls == 2 then error("synthetic exception") end
        if calls == 3 then return false end
        if calls == 4 then return nil end -- applied side effect but returned no payload
        return {} -- normal success with a result table
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
assert(removed == 1 and not renderer:is_visible(),
    "nil/no-error overlay-add must be tracked and subsequently removed on autohide")
assert(renderer:show("/tmp/bitmap.bgra", 256, 16, rect),
    "normal result-table success must still work")
assert(calls == 5)
renderer:hide()
assert(removed == 2 and not renderer:is_visible())
assert(renderer:show("/tmp/bitmap.bgra", 256, 16, rect))
fail_next_remove = true
assert(not renderer:hide(), "failed overlay-remove should report failure")
assert(renderer:is_visible(), "failed removal must preserve visibility for retry")
assert(renderer:hide(), "retry must remove the waveform")
assert(removed == 3 and not renderer:is_visible())

-- A failing native result does not prove no bitmap was drawn before the
-- error. Autohide should clean up that uncertain overlay exactly once.
local uncertain_removes = 0
local uncertain = overlay.new({
    command_native = function(command)
        local name = command._name or command.name
        if name == "overlay-add" then return nil, "backend error after drawing" end
        assert(name == "overlay-remove")
        uncertain_removes = uncertain_removes + 1
        return {}
    end,
}, { overlay_id = 62 })
assert(not uncertain:show("/tmp/bitmap.bgra", 256, 16, rect))
assert(not uncertain:is_visible())
assert(uncertain:hide() and uncertain_removes == 1,
    "autohide must remove a possibly-drawn overlay even after add returned an error")
assert(uncertain:hide() and uncertain_removes == 1,
    "successful cleanup must not spam overlay-remove on every idle refresh")

print("PASS overlay_native_errors")
