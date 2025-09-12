-- Extreme Reactors 3 – Installer (fixed repo)
-- Usage:
--   wget run https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/installer/installer.lua

if not http then
    error("HTTP API disabled. Enable http in ComputerCraft config.")
end

-- Manifest-URL (Repo: ItIsYe)
local mani_url = "https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/installer/manifest.lua"

local function fetch(url)
    local h, err = http.get(url)
    if not h then return nil, err end
    local s = h.readAll()
    h.close()
    return s
end

local function save(path, data)
    local dir = fs.getDir(path)
    if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
    local f = fs.open(path, "w")
    if not f then error("cannot write "..path) end
    f.write(data)
    f.close()
end

-- Manifest laden
print("Manifest laden: "..mani_url)
local s, err = fetch(mani_url)
if not s then error(err) end
local manifest = loadstring(s)()
if not manifest then error("Fehler: Manifest nicht geladen") end

local function install_group(group)
    local list = manifest.files[group] or {}
    if #list == 0 then print("(!) Keine Dateien fuer "..group) end
    for i = 1, #list do
        local it = list[i]
        print("-> "..it.dst)
        local data, e = fetch("https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/"..it.src)
        if not data then error(e) end
        save(it.dst, data)
    end
end

-- Auswahlmenü
print("Installations-Typ: [1] Master  [2] Node  [3] Beide  [4] Nur Shared")
local choice = read()
if choice=="1" then
    install_group("shared"); install_group("master"); install_group("startup")
elseif choice=="2" then
    install_group("shared"); install_group("node"); install_group("startup")
elseif choice=="3" then
    install_group("shared"); install_group("master"); install_group("node"); install_group("startup")
elseif choice=="4" then
    install_group("shared"); install_group("startup")
else
    print("Abbruch."); return
end

print("Installation abgeschlossen.")
print("Master starten: /xreactor/master   |   Node starten: /xreactor/node")
