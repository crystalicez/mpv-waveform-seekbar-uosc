local root = assert(arg[1], "source root required")
package.path = root .. "/portable_config/scripts/?.lua;" .. root .. "/portable_config/scripts/?/init.lua;" .. package.path
local cache = require("uosc_waveform.cache")

local files = { temp = "TEMP", raw = "GOOD" }
local removed = {}
local fs = {
    size = function(path) return files[path] and #files[path] or nil end,
    exists = function(path) return files[path] ~= nil end,
    remove = function(path) removed[#removed + 1] = path; files[path] = nil; return true end,
    rename = function(src, dst) files[dst] = files[src]; files[src] = nil; return true end,
}
local ok, reason = cache.publish(fs, "temp", "raw", 4)
assert(ok == false and reason == "destination-exists", "valid peer cache must win")
assert(files.raw == "GOOD", "publish must never delete a complete peer cache")
assert(files.temp == nil, "losing temporary file must be removed")

files = { temp = "TEMP" }
fs.rename = function(src, dst)
    files[dst] = "PEER"
    return false, "destination appeared"
end
ok, reason = cache.publish(fs, "temp", "raw", 4)
assert(ok == false and reason == "destination-exists", "rename race must adopt peer winner")
assert(files.raw == "PEER", "peer output must remain intact")
assert(files.temp == nil, "temporary file must be removed after a rename race")

-- Cleanup must be scoped to files owned by this script. A custom cache_dir
-- can point at a directory containing unrelated .tmp/.lock/.bgra files.
local stale = cache.stale_auxiliary_candidates({
    { path = "deadbeef-4096x128.session.tmp", mtime = 10 },
    { path = "0123456789abcdef-4096x128.lock", mtime = 20 },
    { path = "c.bgra", mtime = 1 },
    { path = "notes.tmp", mtime = 1 },
    { path = "active.tmp", mtime = 1 },
}, 100, 50, { ["active.tmp"] = true })
assert(#stale == 1 and stale[1] == "deadbeef-4096x128.session.tmp",
    "cleanup must not unlink a lock based only on file age")

local locked = cache.stale_auxiliary_candidates({
    { path = "aaaaaaaaaaaaaaaa-256x16.lock", mtime = 1 },
    { path = "aaaaaaaaaaaaaaaa-256x16.session.tmp", mtime = 1 },
    { path = "bbbbbbbbbbbbbbbb-256x16.session.tmp", mtime = 1 },
}, 1000, 10, {})
assert(#locked == 1 and locked[1] == "bbbbbbbbbbbbbbbb-256x16.session.tmp",
    "active or stale peer locks must protect their session temporary files")
local cleanup = cache.cleanup_candidates({
    { path = "deadbeef-4096x128.bgra", size = 4, mtime = 1 },
    { path = "0123456789abcdef-4096x128.meta", size = 1, mtime = 1 },
    { path = "family-video.bgra", size = 999, mtime = 1 },
    { path = "README.txt", size = 999, mtime = 1 },
}, 100, 50, 10000)
assert(#cleanup == 2, "cache cleanup must ignore unrelated files in a custom directory")
assert(cleanup[1] == "0123456789abcdef-4096x128.meta"
    and cleanup[2] == "deadbeef-4096x128.bgra",
    "only recognized waveform payloads may be expired")
local unknown_time = cache.cleanup_candidates({
    { path = "deadbeef-4096x128.bgra", size = 4, mtime = 0 },
}, 100000, 1, 10000)
assert(#unknown_time == 0, "unknown mtimes must not be treated as ancient cache files")

-- An invalid destination that appears during publication is not safe to delete:
-- another process can replace it between validation and removal. Leave it for
-- the controller's pre-generation stale cleanup instead.
files = { temp = "TEMP", raw = "BAD" }
removed = {}
fs.rename = function() return false, "destination exists" end
ok, reason = cache.publish(fs, "temp", "raw", 4)
assert(ok == false and reason:match("rename%-failed"), "invalid destination must fail safely")
assert(files.raw == "BAD", "publication must not delete a raced destination")
assert(files.temp == "TEMP", "unresolved rename failure must preserve its valid session temp")
local base_info = {
    source_path="clip", source_size=1, source_mtime=2,
    input_path="clip", input_size=1, input_mtime=2,
    duration=10, source_duration=10, edition=0, demuxer_start_time=0,
    rebase_start_time=true, timeline_offset=0, audio_delay=0,
    track={id=1,ff_index=0,audio_ordinal=0,external=false},
}
local opts={source_width=4096,source_height=128,opacity=0.38,waveform_color="#FFFFFF",analysis_sample_rate=8000}
local identity_a=cache.identity(base_info,opts)
local shifted={}
for k,v in pairs(base_info) do shifted[k]=v end
shifted.rebase_start_time=false; shifted.timeline_offset=5; shifted.duration=15
local identity_b=cache.identity(shifted,opts)
assert(identity_a ~= identity_b, "timeline rebasing must invalidate the waveform cache")
assert(cache.paths("cache",identity_a,"a").key ~= cache.paths("cache",identity_b,"a").key,
    "different timeline mappings must not collide at the cache-path layer")
print("PASS cache_publish_race")
