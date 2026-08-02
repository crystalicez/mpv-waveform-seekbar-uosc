local root=assert(arg[1],"source root required")
package.path=root.."/portable_config/scripts/?.lua;"..root.."/portable_config/scripts/?/init.lua;"..package.path
local cache=require("uosc_waveform.cache")
local function pair(key,mtime,raw_size,meta_size)
 return {
  {path="/c/"..key..".bgra",size=raw_size or 100,mtime=mtime},
  {path="/c/"..key..".meta",size=meta_size or 10,mtime=mtime},
 }
end
local entries={}
for _,set in ipairs({pair("aaaaaaaaaaaaaaaa-256x16",10),pair("bbbbbbbbbbbbbbbb-256x16",20),pair("cccccccccccccccc-256x16",30)}) do
 for _,e in ipairs(set) do entries[#entries+1]=e end
end
entries[#entries+1]={path="/c/dddddddddddddddd-256x16.bgra",size=100,mtime=5} -- orphan
local protected={ ["cccccccccccccccc-256x16"]=true }
local groups=cache.cleanup_groups(entries,100,1000,220,protected)
assert(#groups==2,"quota should select oldest complete group and orphan group")
for _,group in ipairs(groups) do
 assert(group.key~="cccccccccccccccc-256x16","protected group must never be selected")
 local has_raw,has_meta=false,false
 for _,path in ipairs(group.paths) do
  if path:match("%.bgra$") then has_raw=true end
  if path:match("%.meta$") then has_meta=true end
 end
 if group.key=="aaaaaaaaaaaaaaaa-256x16" then assert(has_raw and has_meta,"complete cache must delete raw and meta together") end
end
-- Age eviction also works by group and does not return locks/temps.
entries[#entries+1]={path="/c/eeeeeeeeeeeeeeee-256x16.lock",size=1,mtime=1}
entries[#entries+1]={path="/c/eeeeeeeeeeeeeeee-256x16.s.tmp",size=1,mtime=1}
groups=cache.cleanup_groups(entries,1000,500,99999,{})
for _,group in ipairs(groups) do
 for _,path in ipairs(group.paths) do assert(not path:match("%.lock$") and not path:match("%.tmp$")) end
end
print("PASS cache_grouped_cleanup")
