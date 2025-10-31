--========================================================
-- XReactor Controller V2
-- Datei: /startup.lua
-- Beschreibung:
--   Universelles Autostart-Skript für alle Rollen (MASTER, REACTOR, FUEL, WASTE, AUX)
--   Erkennt die Identität des Computers aus /xreactor/config_identity.lua
--   Öffnet automatisch alle Modems
--   Startet die passende Node- oder Master-Anwendung
--========================================================

--==================== Hilfsfunktionen ====================
local function safe_require(path)
  if fs.exists(path) then
    local ok, mod = pcall(dofile, path)
    if ok then return mod end
    print("Fehler beim Laden von " .. path .. ": " .. tostring(mod))
  end
  return nil
end

-- Lade optionale Shared-Module
local LOG   = safe_require("/xreactor/shared/log.lua")
local PROTO = safe_require("/xreactor/shared/protocol.lua") or {
  AUTH_TOKEN_DEFAULT = "xreactor",
  T = { HELLO = "HELLO", NODE_HELLO = "NODE_HELLO" },
  tag = function(m, a) m._auth = a; return m end
}
local IDENTM = safe_require("/xreactor/shared/identity.lua")

local function log_info(msg)  if LOG and LOG.info  then LOG.info(msg)  end end
local function log_warn(msg)  if LOG and LOG.warn  then LOG.warn(msg)  end end
local function log_error(msg) if LOG and LOG.error then LOG.error(msg) end end

--==================== 1) Identität laden ==================
-- Lädt oder erstellt automatisch die Identität (Hostname, Role, Cluster)
local IDENT = {
  role = "MASTER",
  id = "01",
  hostname = "XR-MASTER-01",
  cluster = "XR-CLUSTER-ALPHA",
  token = PROTO.AUTH_TOKEN_DEFAULT
}
if IDENTM and IDENTM.load_identity then
  local ok, res = pcall(IDENTM.load_identity)
  if ok and type(res) == "table" then IDENT = res end
end

-- Computerlabel setzen
pcall(os.setComputerLabel, IDENT.hostname or "XR-UNDEF")

--==================== 2) Modems öffnen ====================
-- Öffnet alle Modems automatisch (wired + wireless)
local function open_all_modems()
  local opened = {}
  for _, name in ipairs(peripheral.getNames()) do
    if peripheral.getType(name) == "modem" then
      if not rednet.isOpen(name) then pcall(rednet.open, name) end
      if rednet.isOpen(name) then table.insert(opened, name) end
    end
  end
  -- Fallback: Standardseiten prüfen
  if #opened == 0 then
    for _, side in ipairs({"right","left","top","bottom","front","back"}) do
      if peripheral.getType(side) == "modem" then
        if not rednet.isOpen(side) then pcall(rednet.open, side) end
        if rednet.isOpen(side) then table.insert(opened, side) end
      end
    end
  end
  return opened
end

local opened_modems = open_all_modems()
if #opened_modems == 0 then
  log_warn("Kein Modem geöffnet – Netzwerk eingeschränkt!")
end

--==================== 3) Netzwerk-Setup ===================
-- Broadcast-Helfer mit Authentifizierung
local function bcast(msg)
  local token = IDENT.token or PROTO.AUTH_TOKEN_DEFAULT
  msg = PROTO.tag(msg, token)
  pcall(rednet.broadcast, msg)
end

-- Falls Node: beim Master anmelden
if tostring(IDENT.role):upper() ~= "MASTER" then
  bcast({ type = PROTO.T.NODE_HELLO, hostname = IDENT.hostname, role = IDENT.role, cluster = IDENT.cluster })
end

--==================== 4) Startpfade definieren ==============
local ROLE = tostring(IDENT.role or "MASTER"):upper()
local ROLE_TO_PATH = {
  MASTER  = "/xreactor/master/master_home.lua",
  REACTOR = "/xreactor/node/reactor_node.lua",
  FUEL    = "/xreactor/node/fuel_node.lua",
  WASTE   = "/xreactor/node/waste_node.lua",
  AUX     = "/xreactor/node/aux_node.lua",
}
local path = ROLE_TO_PATH[ROLE] or ROLE_TO_PATH["AUX"]

--==================== 5) Fallback-Node ======================
-- Wird aufgerufen, falls die Node-Datei fehlt oder fehlerhaft ist
local function run_fallback_node()
  log_warn("Fallback-Node gestartet (kein spezifisches Programm gefunden).")
  term.clear(); term.setCursorPos(1,1)
  print(("XReactor Node Fallback [%s / %s]"):format(IDENT.hostname or "?", ROLE))
  print("Kein spezifisches Node-Programm gefunden.")
  print("Erwarte Befehle und sende Heartbeats ...")

  local last_hello = 0
  while true do
    local t = os.clock()
    if t - last_hello > 5 then
      last_hello = t
      bcast({ type = PROTO.T.NODE_HELLO, hostname = IDENT.hostname, role = ROLE, cluster = IDENT.cluster })
    end
    rednet.receive(0.5)
  end
end

--==================== 6) Hauptstart =========================
log_info(("Startup: role=%s host=%s cluster=%s"):format(ROLE, IDENT.hostname, IDENT.cluster))
if fs.exists(path) then
  local ok, err = pcall(function() shell.run(path) end)
  if not ok then
    log_error("Startfehler: " .. tostring(err))
    term.clear(); term.setCursorPos(1,1)
    print("Startfehler in " .. path)
    print(tostring(err))
    print("\nÖffne Fallback ...")
    sleep(2)
    run_fallback_node()
  end
else
  if ROLE == "MASTER" then
    term.clear(); term.setCursorPos(1,1)
    print("XReactor MASTER - Start")
    print("Pfad nicht gefunden: " .. path)
    print("Bitte Installer ausführen:")
    print("  dofile('installer/installer.lua')")
    log_error("Master-Pfad fehlt: " .. path)
  else
    run_fallback_node()
  end
end

