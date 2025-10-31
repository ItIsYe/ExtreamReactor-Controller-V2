-- /startup.lua
-- XReactor Controller – robuster Launcher (keine Logik-Änderungen deiner Module)
-- Versucht MASTER-UI zu starten, fällt bei Fehlern automatisch auf AUX/Text zurück.
-- Öffnet Modems automatisch.

local LOG_PATH = "/xreactor/log.txt"

local function ensureDir(path)
  local ps, acc = {}, {}
  for part in string.gmatch(path, "[^/]+") do table.insert(ps, part) end
  if #ps <= 1 then return end
  for i=1,#ps-1 do table.insert(acc, ps[i]) end
  local dir = "/"..table.concat(acc, "/")
  if not fs.exists(dir) then fs.makeDir(dir) end
end

local function log(msg)
  local line = string.format("[%s] %s", textutils.formatTime(os.time(), true), tostring(msg))
  print(line)
  pcall(function()
    ensureDir(LOG_PATH)
    local h = fs.open(LOG_PATH, "a")
    h.writeLine(line)
    h.close()
  end)
end

-- Luapath: erlaube require("xreactor.*")
package.path = table.concat({
  "/xreactor/?.lua",
  "/xreactor/?/init.lua",
  "/xreactor/?/?.lua",
  "/?.lua"
}, ";")

-- Rednet/Modem auto-open
local function openAnyModem()
  local opened = false
  for _, side in ipairs(peripheral.getNames()) do
    if peripheral.getType(side) == "modem" then
      local m = peripheral.wrap(side)
      if m and m.isWireless then
        -- egal ob wired/wireless: rednet.open braucht die Seite
      end
      if not rednet.isOpen(side) then
        pcall(function() rednet.open(side) end)
      end
      if rednet.isOpen(side) then
        log("Modem offen auf Seite: "..side)
        opened = true
      end
    end
  end
  if not opened then
    log("WARN: Kein Modem offen. Bitte ein (wired/wireless) Modem anschließen & aktivieren.")
  end
end

-- Config laden (Rolle/Cluster/Token)
local function loadIdentity()
  local ok, cfg = pcall(function() return require("xreactor.config_identity") end)
  if not ok or type(cfg) ~= "table" then
    log("Hinweis: /xreactor/config_identity.lua nicht gefunden – default AUX")
    return { role="AUX", id="01", hostname="", cluster="XR-CLUSTER-DEFAULT", token="xreactor" }
  end
  return cfg
end

-- Fallback: AUX-Node (Textmodus) starten
local function startAUX()
  log("Starte AUX-Node (Textmodus/Fallback)…")
  local ok, mod = pcall(function() return require("xreactor.node.aux_node") end)
  if not ok or not mod then
    log("FEHLER: AUX-Node konnte nicht geladen werden: "..tostring(mod or ok))
    log("Bitte prüfe, ob /xreactor/node/aux_node.lua vorhanden ist.")
    return
  end
  if type(mod.run) == "function" then
    local ok2, err = pcall(mod.run)
    if not ok2 then
      log("AUX-Node Laufzeitfehler: "..tostring(err))
    end
  else
    -- falls Modul ohne .run, einfach ausführen
    local ok3, err3 = pcall(mod)
    if not ok3 then log("AUX-Node Fehler: "..tostring(err3)) end
  end
end

-- MASTER-UI starten (falls GUI/Monitor verfügbar)
local function startMASTER()
  log("Starte MASTER-UI…")
  -- Optional: GUI-Stub zulassen, wenn gui.lua fehlt (master_home darf existieren)
  local ok, mod = pcall(function() return require("xreactor.master.master_home") end)
  if not ok or not mod then
    log("MASTER-UI nicht ladbar: "..tostring(mod or ok))
    return false
  end

  -- Manche Module exportieren start()/run() oder sind einfach ausführbar:
  if type(mod.start) == "function" then
    local ok2, err = pcall(mod.start)
    if not ok2 then
      log("MASTER start()-Fehler: "..tostring(err))
      return false
    end
    return true
  elseif type(mod.run) == "function" then
    local ok2, err = pcall(mod.run)
    if not ok2 then
      log("MASTER run()-Fehler: "..tostring(err))
      return false
    end
    return true
  else
    local ok2, err = pcall(mod)
    if not ok2 then
      log("MASTER-Modulexekution Fehler: "..tostring(err))
      return false
    end
    return true
  end
end

-- MAIN
term.setCursorBlink(false)
log("XReactor Launcher gestartet.")
openAnyModem()
local ident = loadIdentity()
log(("Identität: role=%s id=%s cluster=%s"):format(ident.role or "?", ident.id or "?", ident.cluster or "?"))

if (ident.role or "AUX"):upper() == "MASTER" then
  local okMaster = startMASTER()
  if not okMaster then
    log("MASTER fehlgeschlagen – wechsle in AUX-Fallback.")
    startAUX()
  end
else
  startAUX()
end
