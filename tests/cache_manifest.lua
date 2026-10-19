local root=assert(arg[1],"source root required")
package.path=root.."/portable_config/scripts/?.lua;"..root.."/portable_config/scripts/?/init.lua;"..package.path
local cache=require("uosc_waveform.cache")
local identity="cache-format=6\nsource-width=256\nsource-height=16\ninput=x"
local paths=cache.paths("/cache",identity,"session")
local files={}
local operations={}
local fs={
 size=function(p) return files[p] and #files[p] or nil end,
 exists=function(p) return files[p]~=nil end,
 read=function(p) return files[p] end,
 write=function(p,c) operations[#operations+1]="write:"..p;files[p]=c;return true end,
 rename=function(a,b) operations[#operations+1]="rename:"..a..">"..b;if files[b] then return false,"exists" end;files[b]=files[a];files[a]=nil;return true end,
 remove=function(p) operations[#operations+1]="remove:"..p;files[p]=nil;return true end,
}
local expected=256*16*4
local ok,reason=cache.validate_entry(fs,paths,expected)
assert(not ok and reason=="missing-raw")
files[paths.raw]=string.rep("R",expected)
ok,reason=cache.validate_entry(fs,paths,expected)
assert(not ok and reason=="missing-meta","raw-only entry must be incomplete")
files[paths.raw]=nil
files[paths.meta]="cache-format=6\nkey="..paths.key.."\nsize="..expected.."\n"
ok,reason=cache.validate_entry(fs,paths,expected)
assert(not ok and reason=="missing-raw","meta-only entry must be incomplete")

local temp=paths.temp
files[paths.meta]=nil
files[temp]=string.rep("R",expected)
local published,publish_reason,fallback=cache.publish_entry(fs,paths,temp,expected,{created=123,width=256,height=16})
assert(published and not publish_reason and not fallback,"complete entry should publish")
ok,reason=cache.validate_entry(fs,paths,expected)
assert(ok and reason==nil,"published entry must validate")
assert(operations[#operations]:find(paths.meta,1,true),"meta rename must be the final commit operation")

files[paths.meta]=files[paths.meta]:gsub("key=[^\r\n]+","key=wrong")
ok,reason=cache.validate_entry(fs,paths,expected)
assert(not ok and reason=="meta-key-mismatch")
files[paths.meta]=cache.manifest_content(paths,expected,{created=123,width=256,height=16})
files[paths.raw]=files[paths.raw].."x"
ok,reason=cache.validate_entry(fs,paths,expected)
assert(not ok and reason=="invalid-size")

-- A complete peer winner must never be overwritten.
files[paths.raw]=string.rep("P",expected)
files[paths.meta]=cache.manifest_content(paths,expected,{created=200,width=256,height=16})
files[temp]=string.rep("T",expected)
published,publish_reason=cache.publish_entry(fs,paths,temp,expected,{created=201,width=256,height=16})
assert(not published and publish_reason=="destination-exists")
assert(files[paths.raw]:sub(1,1)=="P" and files[temp]==nil,"peer entry must win and loser temp must be removed")

-- If raw publishes but meta commit fails, canonical raw is a usable session fallback but not a cache hit.
files[paths.raw],files[paths.meta]=nil,nil
files[temp]=string.rep("F",expected)
fs.rename=function(a,b)
 operations[#operations+1]="rename:"..a..">"..b
 if b==paths.meta then return false,"meta busy" end
 files[b]=files[a];files[a]=nil;return true
end
published,publish_reason,fallback=cache.publish_entry(fs,paths,temp,expected,{created=300,width=256,height=16})
assert(not published and publish_reason:find("meta-publish-failed",1,true) and fallback==paths.raw)
ok,reason=cache.validate_entry(fs,paths,expected)
assert(not ok and reason=="missing-meta")
assert(#files[paths.raw]==expected,"uncommitted canonical raw remains available to current session")
-- On POSIX the no-replace publisher must be preferred over normal rename.
-- Simulate a peer making a complete entry between preflight and atomic link.
files[paths.raw], files[paths.meta] = nil, nil
files[temp] = string.rep("T", expected)
local old_rename = fs.rename
fs.rename = function() error("ordinary rename must not be called when no-replace is supplied") end
local attempts = 0
fs.rename_noreplace = function(a, b)
    attempts = attempts + 1
    assert(b == paths.raw)
    files[paths.raw] = string.rep("P", expected)
    files[paths.meta] = cache.manifest_content(paths, expected, {created=400,width=256,height=16})
    return false, "exists"
end
published,publish_reason=cache.publish_entry(fs,paths,temp,expected,{created=500,width=256,height=16})
assert(not published and publish_reason=="destination-exists", "no-replace must adopt completed peer")
assert(attempts==1 and files[paths.raw]:sub(1,1)=="P" and files[temp]==nil,
    "failed link must preserve peer bytes and discard only our temp")
fs.rename, fs.rename_noreplace = function(a, b)
    operations[#operations+1]="rename:"..a..">"..b
    if files[b] then return false, "exists" end
    files[b]=files[a]; files[a]=nil
    return true
end, nil
old_rename = fs.rename

-- Recover an interrupted producer that linked a complete bitmap, then died
-- before committing the manifest. Do not replace the orphan's raw bytes.
files[paths.raw] = string.rep("R", expected)
files[paths.meta] = nil
files[temp] = string.rep("R", expected)
fs.rename_noreplace = function(a, b)
    if b == paths.raw then return false, "exists" end
    return old_rename(a, b)
end
published,publish_reason=cache.publish_entry(fs,paths,temp,expected,{created=600,width=256,height=16})
assert(published and publish_reason==nil, "complete orphan raw should gain a manifest")
assert(files[paths.raw]:sub(1,1) == "R" and files[temp] == nil,
    "orphan recovery must preserve peer raw and clean up our temp")
assert(cache.validate_entry(fs,paths,expected), "orphan recovery must commit a reusable cache hit")

-- Two orphan recovery attempts can race to commit the same manifest; the
-- losing instance must adopt the peer winner and remove its own temporary.
files[paths.meta] = nil
files[temp] = string.rep("R", expected)
fs.rename_noreplace = function(a, b)
    if b == paths.raw then return false, "exists" end
    files[paths.meta] = cache.manifest_content(paths, expected,
        {created=700,width=256,height=16})
    return false, "exists"
end
published,publish_reason=cache.publish_entry(fs,paths,temp,expected,{created=701,width=256,height=16})
assert(not published and publish_reason=="destination-exists", "peer manifest must win")
assert(files[temp]==nil and cache.validate_entry(fs,paths,expected),
    "loser must clean up its temp and retain valid winner")
fs.rename_noreplace = nil

print("PASS cache_manifest")
