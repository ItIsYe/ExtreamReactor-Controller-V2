-- /startup  – Robuster Boot-Launcher für XReactor
local INSTALLER_URL = "https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/installer/installer.lua"
local ROLE_FILE     = "/xreactor/role.txt"

local function log(msg)
  term.setTextColor(colors.white)
  print("[startup] "..(msg or ""))
end

local function rexists(p) return fs.exists(p) and not fs.isDir(p) end
local function ensure_dir(d) if not fs.exists(d) then fs.makeDir(d) end end

local function run_safely(cmd, ...)
  local ok, err = pcall(function() shell.run(cmd, ...) end)
  return ok, err
end

local function role()
  if not rexists(ROLE_FILE) then return nil end
  local h = fs.open(ROLE_FILE, "r"); if not h then return nil end
  local s = (h.readAll() or ""):gsub("%s+$",""); h.close()
  if s == "master" or s == "node" then return s end
  return nil
end

local function program_for(r)
  if r == "master" then return "/xreactor/master.lua" end
  if r == "node"   then return "/xreactor/node.lua"   end
  return nil
end

local function fetch_installer_once()
  ensure_dir("/xreactor")
  if not rexists("/xreactor/installer.lua") then
    log("Hole Installer...")
    local ok, err = run_safely("wget", INSTALLER_URL, "/xreactor/installer.lua")
    if not ok then log("WGET fehlgeschlagen: "..tostring(err)) end
  end
end

local function install_or_update(manifest_url)
  fetch_installer_once()
  log("Starte Installer...")
  if manifest_url then
    run_safely("lua", "/xreactor/installer.lua", manifest_url)
  else
    run_safely("lua", "/xreactor/installer.lua")
  end
end

-- ===== Boot-Sequenz =====
term.setTextColor(colors.yellow)
print("XReactor Boot...")

-- 1) Sicherstellen, dass Basis-Struktur existiert
ensure_dir("/xreactor"); ensure_dir("/xreactor/shared")

-- 2) Rolle + Programm prüfen
local r = role()
if not r then
  log("Keine Rolle gefunden – führe Installer aus.")
  install_or_update()
  r = role()
end

local prog = program_for(r)
if not (prog and rexists(prog)) then
  log("Programm fehlt/alt – führe Installer aus.")
  install_or_update()
end

-- 3) Programm erneut prüfen und starten
prog = program_for(role())
if prog and rexists(prog) then
  log("Starte "..prog.." (Rolle: "..(role() or "?")..")")
  sleep(0)  -- Yield
  shell.run("lua", prog)
else
  term.setTextColor(colors.red)
  print("[startup] FEHLER: Konnte Zielprogramm nicht finden.")
  print("[startup] Bitte Installer manuell ausführen:")
  print("  lua /xreactor/installer.lua")
end
