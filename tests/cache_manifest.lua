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
print("PASS cache_manifest")
