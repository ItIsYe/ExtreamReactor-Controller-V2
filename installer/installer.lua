-- installer.lua — XReactor A–D Installer & Updater (role-aware, versioned)
-- Lädt ein Manifest von GitHub, vergleicht Versionen und installiert/updated nur nötige Dateien.
-- Erstinstallation: fragt Rolle ab, legt Ordner an und erstellt ein Startup (falls noch nicht vorhanden).
-- Update: lässt vorhandene config_*.lua unberührt (nur wenn nicht vorhanden, werden Templates gelegt).

local BASE = "/xreactor"
local LOCAL_MAN_PATH = BASE.."/.installed_manifest.lua"

-- >>> URL zu DEINEM Manifest im Repo (raw):
local REMOTE_MAN_URL =
  "https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/installer/manifest.lua"

-- ------------- helpers -------------
local function ensure_dir(path)
  local dir = fs.getDir(path)
  if dir and dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
end

local function fetch(url)
  local ok, res = pcall(http.get, url, nil, true)
  if not ok or not res then return nil, "http_get_failed" end
  local s = res.readAll() or ""
  res.close()
  if #s == 0 then return nil, "empty_response" end
  return s
end

local function parse_manifest_lua(s)
  -- erwartet: 'return { ... }'
  local fn, err = load(s, "manifest", "t", {})
  if not fn then return nil, "manifest_load_error: "..tostring(err) end
  local ok, tbl = pcall(fn)
  if not ok or type(tbl) ~= "table" then return nil, "manifest_eval_error" end
  return tbl
end

local function load_local_manifest()
  if not fs.exists(LOCAL_MAN_PATH) then return nil end
  local f = fs.open(LOCAL_MAN_PATH, "r")
  if not f then return nil end
  local s = f.readAll() or ""
  f.close()
  if s == "" then return nil end
  return parse_manifest_lua(s)
end

local function save_local_manifest(tbl)
  ensure_dir(LOCAL_MAN_PATH)
  local f = fs.open(LOCAL_MAN_PATH, "w")
  if not f then return false, "open_failed" end
  f.write("return "..textutils.serialize(tbl))
  f.close()
  return true
end

local function write_file(path, data, overwrite)
  overwrite = overwrite ~= false
  if (not overwrite) and fs.exists(path) then
    return true, "skipped_exists"
  end
  ensure_dir(path)
  local f = fs.open(path, "w")
  if not f then return false, "open_failed" end
  f.write(data)
  f.close()
  return true
end

local function ver_gt(a, b)
  if not a and b then return true end
  if a and not b then return false end
  if not a and not b then return false end
  -- String-Lex-Vergleich (Manifest-Versionen sollten chronologisch sortierbare Strings sein)
  return tostring(a) > tostring(b)
end

local function ask(prompt, def)
  term.setTextColor(colors.white)
  io.write(prompt)
  if def then io.write(" ["..def.."]") end
  io.write(": ")
  local s = read()
  if s == "" and def then return def end
  return s
end

local function pick_role()
  print("Welche Rolle soll dieser Computer haben?")
  print("  1) Master")
  print("  2) Node")
  print("  3) Supply (ME/RS)")
  local choice = ask("Auswahl 1/2/3", "1")
  if choice == "2" then return "node"
  elseif choice == "3" then return "supply"
  else return "master" end
end

local function create_startup(role, exe)
  if fs.exists("startup") then
    -- belasse existierendes Startup
    return
  end
  local line = ('shell.run("%s")'):format(exe)
  local ok, err = write_file("startup", line, true)
  if ok then print("Startup erstellt → "..exe) else print("Startup NICHT erstellt: "..tostring(err)) end
end

-- ------------- main -------------
print("XReactor Installer/Updater — lädt Manifest…")
if not http then
  print("Fehler: http API ist deaktiviert. Bitte auf dem Server erlauben (enableCommandBlock? / enableAPI?).")
  return
end

local remoteText, err = fetch(REMOTE_MAN_URL)
if not remoteText then
  print("Fehler beim Laden des Manifests: "..tostring(err))
  return
end

local REMOTE_MAN, perr = parse_manifest_lua(remoteText)
if not REMOTE_MAN then
  print("Manifest-Parsefehler: "..tostring(perr))
  return
end

-- Rolle bestimmen (aus lokalem Manifest, sonst abfragen)
local role = nil
local LOCAL_MAN = load_local_manifest()
if LOCAL_MAN and LOCAL_MAN.installed_role then
  role = LOCAL_MAN.installed_role
  print("Gefundene installierte Rolle: "..role)
else
  role = pick_role()
end

-- Auth-Token (optional) einmalig setzen?
-- Wenn config bereits existiert, NICHT überschreiben.
local function maybe_seed_configs(role)
  if role == "master" then
    if not fs.exists(BASE.."/config_master.lua") then
      local url = REMOTE_MAN.files["/xreactor/config_master.lua"].url
      local txt = fetch(url)
      if txt then write_file(BASE.."/config_master.lua", txt, false) end
      print("config_master.lua (neu) angelegt.")
      -- optional: Token setzen
      local tok = ask("Auth-Token für Master setzen (leer = 'changeme')", "changeme")
      if tok ~= "" then
        -- quick replace
        local s = fetch(url) or ""
        s = s:gsub('auth_token%s*=%s*"[^"]*"', 'auth_token = "'..tok..'"')
        write_file(BASE.."/config_master.lua", s, true)
      end
    else
      print("config_master.lua existiert, lasse unverändert.")
    end
  elseif role == "node" then
    if not fs.exists(BASE.."/config_node.lua") then
      local url = REMOTE_MAN.files["/xreactor/config_node.lua"].url
      local txt = fetch(url)
      if txt then write_file(BASE.."/config_node.lua", txt, false) end
      print("config_node.lua (neu) angelegt.")
      local tok = ask("Auth-Token für Node setzen (leer = 'changeme')", "changeme")
      if tok ~= "" then
        local s = fetch(url) or ""
        s = s:gsub('auth_token%s*=%s*"[^"]*"', 'auth_token = "'..tok..'"')
        write_file(BASE.."/config_node.lua", s, true)
      end
    else
      print("config_node.lua existiert, lasse unverändert.")
    end
  elseif role == "supply" then
    if not fs.exists(BASE.."/config_supply.lua") then
      local url = REMOTE_MAN.files["/xreactor/config_supply.lua"].url
      local txt = fetch(url)
      if txt then write_file(BASE.."/config_supply.lua", txt, false) end
      print("config_supply.lua (neu) angelegt.")
      local tok = ask("Auth-Token für Supply setzen (leer = 'changeme')", "changeme")
      if tok ~= "" then
        local s = fetch(url) or ""
        s = s:gsub('auth_token%s*=%s*"[^"]*"', 'auth_token = "'..tok..'"')
        write_file(BASE.."/config_supply.lua", s, true)
      end
    else
      print("config_supply.lua existiert, lasse unverändert.")
    end
  end
end

-- Liste relevanter Dateien für diese Rolle aus Manifest bauen
local function files_for_role(man)
  local list = {}
  for path, meta in pairs(man.files or {}) do
    local roles = meta.roles or {"all"}
    local match = false
    for _,r in ipairs(roles) do if r=="all" or r==role then match=true end end
    if match then list[path] = meta end
  end
  return list
end

local ROLE_FILES = files_for_role(REMOTE_MAN)
local LOCAL_VER = (LOCAL_MAN and LOCAL_MAN.files) or {}

-- Install/Update
local updated, skipped, installed = 0,0,0
for path, meta in pairs(ROLE_FILES) do
  local remote_ver = meta.ver
  local local_ver  = LOCAL_VER[path] and LOCAL_VER[path].ver or nil

  local need = (not fs.exists(path)) or ver_gt(remote_ver, local_ver)
  if need then
    local data, ferr = fetch(meta.url)
    if not data then
      print("FEHLER: konnte nicht laden: "..path.." ("..tostring(ferr)..")")
    else
      local ok, werr = write_file(path, data, true)
      if ok then
        if fs.exists(path) then
          if local_ver then updated=updated+1 else installed=installed+1 end
          print(((local_ver and "Updated ") or "Installed ")..path.."  → v"..tostring(remote_ver))
        end
      else
        print("FEHLER: konnte nicht schreiben: "..path.." ("..tostring(werr)..")")
      end
    end
  else
    skipped = skipped + 1
  end
end

-- Configs ggf. neu anlegen (ohne vorhandenes zu überschreiben) + optional Token setzen
maybe_seed_configs(role)

-- Startup: nur erstellen, wenn noch keins vorhanden
local exe = REMOTE_MAN.startup[role]
if exe then create_startup(role, exe) end

-- Neues lokales Manifest speichern (nur die tatsächlich installierten Role-Dateien + Versionen)
local NEW_LOCAL = { installed_role = role, manifest_version = REMOTE_MAN.version, files = {} }
for path, meta in pairs(ROLE_FILES) do
  NEW_LOCAL.files[path] = { ver = meta.ver }
end
save_local_manifest(NEW_LOCAL)

print("Fertig. Neu: "..installed..", Updates: "..updated..", Übersprungen: "..skipped)
print("Rolle: "..role.." | Manifest v"..tostring(REMOTE_MAN.version))
