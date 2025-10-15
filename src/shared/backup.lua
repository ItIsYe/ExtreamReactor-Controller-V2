-- backup.lua — config/log snapshots + restore
local M = {}

local function fmt_ts()
  local t = os.date("!*t")
  return string.format("%04d%02d%02d-%02d%02d%02d", t.year, t.month, t.day, t.hour, t.min, t.sec)
end

local function ensure(path) local d=fs.getDir(path); if d~="" and not fs.exists(d) then fs.makeDir(d) end end
local function copy_any(src, dst)
  if fs.isDir(src) then
    if not fs.exists(dst) then fs.makeDir(dst) end
    for _,n in ipairs(fs.list(src)) do copy_any(src.."/"..n, dst.."/"..n) end
  else
    ensure(dst)
    fs.copy(src, dst)
  end
end

local function rmrf(path)
  if fs.exists(path) then
    if fs.isDir(path) then
      for _,n in ipairs(fs.list(path)) do rmrf(path.."/"..n) end
    end
    fs.delete(path)
  end
end

-- Creates backup folder with timestamp and copies relevant dirs/files
function M.snapshot(root, outdir, extra)
  local tag = fmt_ts()
  local target = (outdir or "/xreactor/backups").."/"..tag
  fs.makeDir(target)
  local list = {
    root.."/config_master.lua",
    root.."/config_node.lua",
    root.."/logs",
    root.."/shared",
    root.."/master",
    root.."/node",
  }
  if type(extra)=="table" then for _,p in ipairs(extra) do table.insert(list, p) end end
  for _,p in ipairs(list) do if fs.exists(p) then copy_any(p, target..p) end end
  return target
end

-- Restores a given snapshot dir back to / (only whitelisted paths under root)
function M.restore(root, snapshot_dir)
  assert(fs.exists(snapshot_dir), "snapshot not found")
  local whitelist = { "config_master.lua", "config_node.lua", "logs", "shared", "master", "node" }
  for _,name in ipairs(whitelist) do
    local src = snapshot_dir..root.."/"..name
    local dst = root.."/"..name
    if fs.exists(src) then
      rmrf(dst)
      copy_any(src, dst)
    end
  end
  return true
end

-- returns newest snapshot path or nil
function M.latest(outdir)
  local bdir = outdir or "/xreactor/backups"
  if not fs.exists(bdir) then return nil end
  local latest, best=nil, ""
  for _,n in ipairs(fs.list(bdir)) do
    if n > best then best=n end
  end
  if best~="" then latest = bdir.."/"..best end
  return latest
end

return M
