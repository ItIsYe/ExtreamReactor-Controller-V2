-- /startup.lua
-- XReactor Launcher (berührt deine Logik nicht, lädt sie nur robust)
local LOG_PATH = "/xreactor/log.txt"

local function ensureDir(path)
  local parts, acc = {}, {}
  for part in string.gmatch(path, "[^/]+") do table.insert(parts, part) end
  if #parts <= 1 then return end
  for i=1,#parts-1 do table.insert(acc, parts[i]) end
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

-- Luapath für require("xreactor.*")
package.path = table.concat({
  "/xreactor/?.lua",
  "/xreactor/?/init.lua",
  "/xreactor/?/?.lua",
  "/?.lua"
}, ";")

local function openAnyModem()
  local any = false
  for _, name in ipairs(peripheral.getNames()) do
    if peripheral.getType(name) == "modem" then
      if not rednet.isOpen(name) then pcall(function() rednet.open(name) end) end
      if rednet.isOpen(name) then
        log("Modem offen: "..name)
        any = true
      end
    end
  end
  if not any then log("WARN: Kein Modem offen. (wired/wireless Modem anschließen & einschalten)") end
end

local function loadIdentity()
  local ok, cfg = pcall(function() return require("xreactor.config_identity") end)
  if not ok or type(cfg) ~= "table" then
    log("Hinweis: /xreactor/config_identity.lua fehlt → nutze REACTOR-Defaults")
    return { role = "REACTOR", id = "01", hostname = "", cluster = "XR-CLUSTER-DEFAULT", token = "xreactor" }
  end
  return cfg
end

local NODE_MODULES = {
  REACTOR   = "xreactor.node.reactor_node",
  ENERGY    = "xreactor.node.energy_node",
  FUEL      = "xreactor.node.fuel_node",
  REPROCESS = "xreactor.node.reprocessing_node",
}

local function startNode(role)
  local key = (role or "REACTOR"):upper()
  local mod_path = NODE_MODULES[key] or NODE_MODULES.REACTOR
  log(("Starte %s-Node (%s)…"):format(key, mod_path))

  local ok, mod = pcall(function() return require(mod_path) end)
  if not ok or not mod then
    log("FEHLER: Node nicht ladbar: "..tostring(mod or ok))
    return
  end

  if type(mod.run) == "function" then
    local ok2, err = pcall(mod.run)
    if not ok2 then log("Node Fehler: "..tostring(err)) end
  else
    local ok2, err = pcall(mod)
    if not ok2 then log("Node Fehler: "..tostring(err)) end
  end
end

local function startMASTER()
  log("Starte MASTER-UI…")
  -- Falls GUI fehlt, liefert unser Shim trotzdem ein GUI-Objekt (siehe gui.lua).
  local ok, mod = pcall(function() return require("xreactor.master.master_home") end)
  if not ok or not mod then
    log("MASTER-UI nicht ladbar: "..tostring(mod or ok))
    return false
  end
  if type(mod.start) == "function" then
    local ok2, err = pcall(mod.start)
    if not ok2 then log("MASTER start()-Fehler: "..tostring(err)); return false end
    return true
  elseif type(mod.run) == "function" then
    local ok2, err = pcall(mod.run)
    if not ok2 then log("MASTER run()-Fehler: "..tostring(err)); return false end
    return true
  else
    local ok2, err = pcall(mod)
    if not ok2 then log("MASTER-Modulexekution Fehler: "..tostring(err)); return false end
    return true
  end
end

term.setCursorBlink(false)
log("XReactor Launcher gestartet.")
openAnyModem()
local ident = loadIdentity()
log(("Identität: role=%s id=%s cluster=%s"):format(ident.role or "?", ident.id or "?", ident.cluster or "?"))

if (ident.role or "REACTOR"):upper() == "MASTER" then
  if not startMASTER() then
    log("MASTER fehlgeschlagen – wechsle in NODE.")
    startNode(ident.role)
  end
else
  startNode(ident.role)
end
