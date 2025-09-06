
-- Extreme Reactors – Installer (Lua-only, interactive)
if not http then error("HTTP API disabled. Enable http in ComputerCraft config.") end

local function prompt(label, def)
  term.write(label .. (def and (" ["..def.."]") or "") .. ": ")
  local s = read()
  if s=="" and def then return def end
  return s
end

local function fetch(url)
  local h = http.get(url)
  if not h then return nil, "HTTP failed: "..url end
  local s = h.readAll() h.close()
  return s
end

local function save(path, data)
  local dir = fs.getDir(path); if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
  local h = fs.open(path, "w"); if not h then error("cannot write "..path) end
  h.write(data); h.close()
end

print("== Extreme Reactors – Installer ==")
local user   = prompt("GitHub USER", "Dax1")
local repo   = prompt("GitHub REPO", "ExtreamReactor-Controller-V2")
local branch = prompt("GitHub BRANCH", "main")
local base = ("https://raw.githubusercontent.com/%s/%s/%s/"):format(user, repo, branch)

local mani_url = base.."installer/manifest.lua"
print("Lade Manifest: "..mani_url)
local s, err = fetch(mani_url); if not s then error(err) end
local f, perr = load(s, "manifest", "t", {}); if not f then error("Manifest parse error: "..tostring(perr)) end
local mani = f()

local role
while true do
  print("Installations-Typ: [1] Master  [2] Node  [3] Beide  [4] Nur Shared  [Q] Abbruch")
  local k = read()
  if k=="1" then role="master"; break
  elseif k=="2" then role="node"; break
  elseif k=="3" then role="both"; break
  elseif k=="4" then role="shared"; break
  elseif k=="q" or k=="Q" then return end
end

local function install_group(group)
  local list = (mani.files and mani.files[group]) or {}
  for i=1,#list do
    local f = list[i]
    local url = base..f.src
    print("-> "..f.dst)
    local data, e = fetch(url); if not data then error(e) end
    save(f.dst, data)
  end
end

install_group("shared")
if role=="master" then install_group("master")
elseif role=="node" then install_group("node")
elseif role=="both" then install_group("master"); install_group("node")
end

print("Installation abgeschlossen.")
print("Dateien unter /xreactor  |  Master: /xreactor/master  |  Node: /xreactor/node")
