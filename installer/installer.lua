--========================================================
-- ExtreamReactor Controller V2 — Installer/Updater
-- Datei: installer/installer.lua
-- Nutzung:
--   dofile("installer/installer.lua")
--   -- optional: dofile("installer/installer.lua", "<eigene-manifest-url>")
--========================================================

local function println(...) print(...) end
local function warnln(...) print("\31"..table.concat({...}," ")) end -- gelb
local function errln(...)  print("\30"..table.concat({...}," ")) end -- rot

local function ensure_http()
  if not http then error("http API nicht verfügbar (CC-Konfig: http.enable=true).") end
end

local function fetch(url)
  ensure_http()
  local h, err = http.get(url, { ["Cache-Control"]="no-cache"})
  if not h then return nil, ("HTTP-Fehler: "..tostring(err or "?")) end
  local body = h.readAll(); h.close(); return body
end

local function load_lua_from_url(url)
  local body, e = fetch(url); if not body then return nil, e end
  local fn, err = loadstring(body, "@"..url); if not fn then return nil, "loadstring: "..tostring(err) end
  local ok, mod = pcall(fn); if not ok then return nil, "exec: "..tostring(mod) end
  return mod
end

local function ensure_dir_for(path)
  local cur=""
  for part in string.gmatch(path, "[^/]+") do
    local next_ = cur=="" and ("/"..part) or (cur.."/"..part)
    if next_ ~= path then if not fs.exists(next_) then fs.makeDir(next_) end end
    cur = next_
  end
end

local function read_file(path)
  if not fs.exists(path) then return nil end
  local h = fs.open(path,"r"); if not h then return nil end
  local d = h.readAll(); h.close(); return d
end

local function write_file(path, data)
  ensure_dir_for(path)
  local h = fs.open(path,"w"); if not h then return false,"fs.open fail" end
  h.write(data or ""); h.close(); return true
end

local function update_file(url, dst)
  local remote, e = fetch(url)
  if not remote then return false,("Download fehlgeschlagen: "..e) end
  local local_data = read_file(dst)
  if local_data == remote then return "same" end
  local ok, err = write_file(dst, remote)
  if not ok then return false, ("Schreibfehler: "..tostring(err)) end
  return "updated"
end

--============================ main =========================
local arg_manifest_url = ({...})[1]
local MANIFEST_URL = arg_manifest_url or "https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/installer/manifest.lua"

println("== ExtreamReactor Installer ==")
println("Manifest: "..MANIFEST_URL)

local manifest, e = load_lua_from_url(MANIFEST_URL)
if not manifest then errln("Manifest laden fehlgeschlagen: "..tostring(e)); return end
if type(manifest)~="table" or type(manifest.files)~="table" then errln("Ungültiges Manifest."); return end

println(("Version: %s  (Stand: %s)"):format(tostring(manifest.version or "?"), tostring(manifest.created_at or "?")))
local base = manifest.base_url or ""

local total, changed, same, failed = 0,0,0,0
for _,f in ipairs(manifest.files) do
  local src, dst = tostring(f.src or ""), tostring(f.dst or "")
  if src=="" or dst=="" then warnln("Überspringe ungültigen Eintrag"); else
    total = total + 1
    local url = (base:sub(-1)=="/") and (base..src) or (base.."/"..src)
    println(string.format("[%d] %s -> %s", total, src, dst))
    local ok, msg = update_file(url, dst)
    if ok=="same" then same = same + 1; println("   • bereits aktuell")
    elseif ok=="updated" then changed = changed + 1; println("   • aktualisiert")
    elseif ok==false then failed = failed + 1; errln("   • FEHLER: "..tostring(msg))
    else failed = failed + 1; errln("   • Unbekannter Status") end
  end
end

println(""); println("== Zusammenfassung ==")
println(string.format("Dateien: %d  aktualisiert: %d  unverändert: %d  Fehler: %d", total, changed, same, failed))
println(failed==0 and "Status: OK" or "Status: WARN/FAIL – bitte Log prüfen")
println(""); println("Start: dofile('/xreactor/master/master_home.lua')")

