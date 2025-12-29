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

local function await_election(core, ident)
  local desired = tostring(ident.role or "REACTOR"):upper()
  if desired ~= "MASTER" and desired ~= "MASTER_CANDIDATE" then
    return desired
  end

  local deadline = os.startTimer(15)
  while true do
    local ev = {os.pullEvent()}
    if ev[1] == "node_state_change" then
      local state = ev[3]
      local master_id = core:get_master_id()
      if state == "MASTER" and master_id == os.getComputerID() then
        return "MASTER"
      elseif master_id and master_id ~= os.getComputerID() then
        return "SLAVE"
      end
    elseif ev[1] == "timer" and ev[2] == deadline then
      return desired
    end
  end
end

local function start_node_runtime(ident)
  local NodeCore = dofile('/xreactor/node/node_core.lua')
  return NodeCore.create({ identity = ident })
end

term.setCursorBlink(false)
log("XReactor Launcher gestartet.")
openAnyModem()

local ident = dofile('/xreactor/shared/identity.lua').load_identity()
log(("Identität: role=%s id=%s cluster=%s"):format(ident.role or "?", ident.id or "?", ident.cluster or "?"))

local node = start_node_runtime(ident)

local function run_runtime()
  node:start()
end

local decided_role = nil
local function handle_startup()
  decided_role = await_election(node, ident)
  if decided_role == "MASTER" then
    log("Election gewonnen – starte MASTER-UI")
    node:stop()
    startMASTER()
  else
    log(("Node aktiv als %s (Master=%s)"):format(decided_role or ident.role, tostring(node:get_master_id() or "?")))
    -- Node-Core läuft weiter; UI optional separat startbar
  end
end

parallel.waitForAny(run_runtime, handle_startup)
