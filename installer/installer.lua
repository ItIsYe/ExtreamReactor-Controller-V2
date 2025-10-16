-- XReactor Installer (Manifest v2)
-- - arbeitet mit installer/manifest.lua, das eine Tabelle von Zielpfad -> {ver, roles, url, desc} zurückgibt
-- - fragt einmalig Rolle ab (master/node) und speichert sie
-- - lädt nur Dateien, deren roles die eigene Rolle enthalten (oder "all")
-- - vergleicht Versionen als Strings (lexikografisch), lädt nur neuere
-- - überschreibt bestehende config_* NICHT (nur wenn sie fehlen)

local BASE                = "/xreactor"
local LOCAL_STATE_PATH    = BASE.."/.installed_manifest.lua"
local DEFAULT_REMOTE_MAN  = "https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/installer/manifest.lua"

-- ---------- utils ----------
local function ensure_dir_for(path)
  local dir = fs.getDir(path)
  if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
end

local function read_all(fh)
  local s = fh.readAll() or ""
  fh.close()
  return s
end

local function fetch(url)
  local ok, res = pcall(http.get, url, nil, true)
  if not ok or not res then return nil, "http_get_failed" end
  local s = read_all(res)
  if s == "" then return nil, "empty_response" end
  return s
end

local function load_manifest_lua(text)
  local fn, err = load(text, "manifest", "t", {})
  if not fn then return nil, "manifest_load_error: "..tostring(err) end
  local ok, tbl = pcall(fn)
  if not ok or type(tbl) ~= "table" then return nil, "manifest_eval_error" end
  return tbl
end

local function load_local_state()
  if not fs.exists(LOCAL_STATE_PATH) then return { role=nil, files={} } end
  local fh = fs.open(LOCAL_STATE_PATH, "r")
  if not fh then return { role=nil, files={} } end
  local txt = read_all(fh)
  if txt == "" then return { role=nil, files={} } end
  local fn = load(txt, "local_state", "t", {})
  local ok, st = pcall(fn)
  if not ok or type(st)~="table" then return { role=nil, files={} } end
  st.files = st.files or {}
  return st
end

local function save_local_state(st)
  ensure_dir_for(LOCAL_STATE_PATH)
  local fh = fs.open(LOCAL_STATE_PATH, "w")
  if not fh then return false, "open_failed" end
  fh.write("return "..textutils.serialize(st))
  fh.close()
  return true
end

local function ver_gt(a, b)
  if not a and b then return true end  -- remote has version, local none
  if a and not b then return false end -- local has version, remote none (treat as not greater)
  if not a and not b then return true end
  return tostring(a) > tostring(b)     -- simple lexicographic compare (use sortable strings like 2025-10-16-01)
end

local function has_role(entry_roles, role)
  if not entry_roles or #entry_roles==0 then return true end
  for _,r in ipairs(entry_roles) do
    if r=="all" or r==role then return true end
  end
  return false
end

local function ask(prompt, def)
  io.write(prompt)
  if def then io.write(" ["..def.."]") end
  io.write(": ")
  local s = read()
  if s=="" and def then return def end
  return s
end

local function choose_role()
  print("Welche Rolle soll dieser Computer haben?")
  print("  1) Master")
  print("  2) Node")
  local c = ask("Auswahl 1/2", "1")
  if c=="2" then return "node" else return "master" end
end

local function write_file(path, data, overwrite)
  overwrite = overwrite ~= false
  if not overwrite and fs.exists(path) then
    return true, "skipped_exists"
  end
  ensure_dir_for(path)
  local fh = fs.open(path, "w")
  if not fh then return false, "open_failed" end
  fh.write(data)
  fh.close()
  return true
end

local function is_config_path(path)
  return path=="/xreactor/config_master.lua"
      or path=="/xreactor/config_node.lua"
      or path=="/xreactor/config_supply.lua"
      or path:match("/configs?/") ~= nil
end

-- ---------- main ----------
term.setTextColor(colors.white)
print("XReactor Installer (Manifest v2)")
if not http then
  print("Fehler: http API deaktiviert. Bitte im Server-Config HTTP erlauben.")
  return
end

-- Manifest URL (optional Argument 1)
local REMOTE_MAN_URL = ({...})[1] or DEFAULT_REMOTE_MAN
print("Manifest laden: "..REMOTE_MAN_URL)
local man_text, err = fetch(REMOTE_MAN_URL)
if not man_text then
  print("Fehler beim Manifest-Download: "..tostring(err))
  return
end
local MAN, perr = load_manifest_lua(man_text)
if not MAN then
  print("Manifest-Fehler: "..tostring(perr))
  return
end

-- Local state + role
local STATE = load_local_state()
if not STATE.role then
  STATE.role = choose_role()
  save_local_state(STATE)
  print("Rolle gespeichert: "..STATE.role)
else
  print("Gefundene Rolle: "..STATE.role)
end

-- Iterate entries
local installed, updated, skipped = 0, 0, 0
for target, meta in pairs(MAN) do
  -- meta = {ver, roles, url, desc}
  if type(meta)=="table" and meta.url then
    -- Filter by role
    if has_role(meta.roles, STATE.role) or target=="/xreactor/installer.lua" then
      local remote_ver = meta.ver
      local local_ver  = STATE.files[target] and STATE.files[target].ver or nil

      -- Configs: don't overwrite existing
      local want_overwrite = true
      if is_config_path(target) and fs.exists(target) then
        want_overwrite = false
      end

      local need = (not fs.exists(target)) or ver_gt(remote_ver, local_ver)
      if need then
        local data, ferr = fetch(meta.url)
        if not data then
          print("FEHLER: Download fehlgeschlagen: "..target.." ("..tostring(ferr)..")")
        else
          local ok, werr = write_file(target, data, want_overwrite)
          if ok then
            if local_ver then updated = updated + 1 else installed = installed + 1 end
            print(((local_ver and "Updated ") or "Installed ")..target.."  → v"..tostring(remote_ver)
              .. (not want_overwrite and " (bestehende Config beibehalten)" or ""))
            -- Store version (even if config skipped, mark current desired version for future compares)
            STATE.files[target] = { ver = remote_ver }
          else
            print("FEHLER: Schreiben fehlgeschlagen: "..target.." ("..tostring(werr)..")")
          end
        end
      else
        skipped = skipped + 1
      end
    else
      -- role-mismatch → skip silently
    end
  end
end

-- Save state
save_local_state(STATE)

print(("\nFertig. Neu: %d, Updates: %d, Übersprungen: %d"):format(installed, updated, skipped))
print("Rolle: "..STATE.role)
print("Hinweis: Config-Dateien werden nur bei Erstinstallation geschrieben.")
print("Tipp: Du kannst eine alternative Manifest-URL als Argument übergeben.")
print("      Beispiel: lua installer/installer.lua https://raw.githubusercontent.com/.../manifest.lua")
