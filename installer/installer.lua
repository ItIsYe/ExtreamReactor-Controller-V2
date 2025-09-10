
-- Extreme Reactors – Installer (fixed repo)
-- Usage:
--   wget run https://raw.githubusercontent.com/Dax1/ExtreamReactor-Controller-V2/main/installer/installer_fixed.lua

if not http then error("HTTP API disabled. Enable http in ComputerCraft config.") end

local function fetch(url)
  local h = http.get(url); if not h then return nil, "HTTP failed: "..url end
  local s = h.readAll(); h.close(); return s
end

local function save(path, data)
  local dir = fs.getDir(path); if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
  local h = fs.open(path, "w"); if not h then error("cannot write "..path) end
  h.write(data); h.close()
end

local base = "https://raw.githubusercontent.com/Dax1/ExtreamReactor-Controller-V2/main/"
local mani_url = base.."installer/manifest.lua"
print("Manifest: "..mani_url)
local s, err = fetch(mani_url); if not s then error(err) end
local f, perr = load(s, "manifest", "t", {}); if not f then error("Manifest parse error: "..tostring(perr)) end
local mani = f()

local function install_group(group)
  local list = (mani.files and mani.files[group]) or {}
  for i=1,#list do
    local f = list[i]; local url = base..f.src
    print("-> "..f.dst)
    local data, e = fetch(url); if not data then error(e) end
    save(f.dst, data)
  end
end

print("Installations-Typ: [1] Master  [2] Node  [3] Beide  [4] Nur Shared")
local choice = read()
if choice=="1" then
  install_group("shared"); install_group("master")
elseif choice=="2" then
  install_group("shared"); install_group("node")
elseif choice=="3" then
  install_group("shared"); install_group("master"); install_group("node")
elseif choice=="4" then
  install_group("shared")
else
  print("Abbruch."); return
end

print("Installation abgeschlossen.")
print("Master starten: /xreactor/master   |   Node starten: /xreactor/node")
