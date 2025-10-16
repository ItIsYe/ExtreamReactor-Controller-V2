--====================================================
-- XReactor Installer / Updater
-- Manifest v2-kompatibel, sicheres Schreiben, Versions-Tracking
-- Erstinstallation überschreibt Configs; spätere Läufe lassen
-- bestehende Configs unverändert (außer force=true).
--====================================================

local DEFAULT_MANIFEST =
  "https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/installer/manifest.lua"

local ROLE_FILE     = "/xreactor/role.txt"
local VERS_FILE     = "/xreactor/.versions.json"

-- -------- utils --------
local function println(s) print(s or "") end

local function ensure_dir(path)
  if not path or path == "" then return end
  if not fs.exists(path) then fs.makeDir(path) end
end

local function write_file(path, data)
  ensure_dir(fs.getDir(path))
  local h = fs.open(path, "wb")
  if not h then error("open_failed: "..path) end
  h.write(data)
  h.close()
end

local function read_all(path)
  if not fs.exists(path) then return nil end
  local h = fs.open(path, "rb"); if not h then return nil end
  local d = h.readAll(); h.close(); return d
end

local function http_fetch(url)
  local ok, res = pcall(function()
    return http.get(url, {["User-Agent"]="XReactor-Installer/3"})
  end)
  if not ok or not res then return nil, "http_get_failed" end
  local body = res.readAll() or ""
  res.close()
  if body == "" then return nil, "empty_body" end
  return body
end

local function load_manifest(url)
  local src, err = http_fetch(url)
  if not src then return nil, "manifest_load_error: "..tostring(err) end
  local chunk, lerr = load(src, "manifest", "t", {})
  if not chunk then return nil, "manifest_compile_error: "..tostring(lerr) end
  local ok, tbl = pcall(chunk)
  if not ok then return nil, "manifest_runtime_error: "..tostring(tbl) end
  if type(tbl) ~= "table" then return nil, "manifest_not_table" end
  return tbl
end

local function ask_role()
  term.setTextColor(colors.white)
  println("Welche Rolle soll dieser Computer haben?")
  println("  1) Master")
  println("  2) Node")
  write("> Auswahl 1/2 [1]: ")
  local ans = read()
  if ans == "2" then return "node" else return "master" end
end

local function get_role()
  if fs.exists(ROLE_FILE) then
    local r = (read_all(ROLE_FILE) or ""):gsub("%s+$","")
    if r == "master" or r == "node" then return r end
  end
  local r = ask_role()
  write_file(ROLE_FILE, r.."\n")
  println("Rolle gespeichert: "..r)
  return r
end

local function load_versions()
  if not fs.exists(VERS_FILE) then return {} end
  local ok, t = pcall(function()
    return textutils.unserializeJSON(read_all(VERS_FILE) or "{}") or {}
  end)
  return ok and t or {}
end

local function save_versions(t)
  write_file(VERS_FILE, textutils.serializeJSON(t))
end

local function should_skip_config(dst, force)
  if force then return false end
  -- Configs NICHT überschreiben, wenn bereits vorhanden (außer force=true)
  if dst:find("/config_") and fs.exists(dst) then return true end
  return false
end

local function need_download(dst, ver, force, versions)
  if force then return true end
  if not fs.exists(dst) then return true end
  if (versions[dst] or "") ~= (ver or "") then return true end
  -- falls leere Datei am Ziel liegt
  if (fs.getSize(dst) or 0) == 0 then return true end
  return false
end

-- -------- main --------
local args = {...}
local manifest_url = args[1] or DEFAULT_MANIFEST

-- Ordner anlegen, bevor irgendwas passiert
ensure_dir("/xreactor")
ensure_dir("/xreactor/shared")

println("XReactor Installer (Manifest v2)")
println("Manifest laden: "..manifest_url)

local M, merr = load_manifest(manifest_url)
if not M then error(merr) end

local role = get_role()

local list = {}
local function enq(group)
  if type(group) ~= "table" then return end
  for _, item in ipairs(group) do table.insert(list, item) end
end

enq(M.shared)
enq(M.installer)
enq(M.autosetup)
if role == "master" then enq(M.master) else enq(M.node) end

local versions = load_versions()
local stats = {new=0, upd=0, skip=0, err=0}

for _, it in ipairs(list) do
  local dst  = it.dst
  local url  = it.url
  local ver  = it.ver or "0"
  local force = it.force and true or false

  if should_skip_config(dst, force) then
    stats.skip = stats.skip + 1
    println("Config existiert, lasse unverändert: "..dst)
  else
    if need_download(dst, ver, force, versions) then
      write("-> "..dst.."  ")
      local data, derr = http_fetch(url)
      if not data then
        stats.err = stats.err + 1
        println("FEHLER: "..tostring(derr))
      else
        local existed = fs.exists(dst)
        write_file(dst, data)
        versions[dst] = ver
        if existed then
          stats.upd = stats.upd + 1
          println("Update ✓  "..(ver or ""))
        else
          stats.new = stats.new + 1
          println("Install ✓ "..(ver or ""))
        end
      end
    else
      stats.skip = stats.skip + 1
      println("Aktuell, übersprungen: "..dst)
    end
  end
end

save_versions(versions)

println("")
println(string.format("Fertig. Neu: %d, Updates: %d, Übersprungen: %d, Fehler: %d",
  stats.new, stats.upd, stats.skip, stats.err))
println("Rolle: "..role.."  |  Manifest "..(M.manifest_version or "?"))

-- Start-Hinweis
if role == "master" then
  println("Start:  lua /xreactor/master.lua")
else
  println("Start:  lua /xreactor/node.lua")
end

println("Hinweis: Config-Dateien werden nur bei Erstinstallation geschrieben.")
println("Tipp: Du kannst eine alternative Manifest-URL als Argument übergeben.")
println("      Beispiel: lua installer/installer.lua https://raw.githubusercontent.com/.../manifest.lua")
