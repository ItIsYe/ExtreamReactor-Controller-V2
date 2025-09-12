-- ===== Master Controller =====
-- Suchpfad erweitern, damit require() Module in /xreactor und /xreactor/shared gefunden werden
package.path = package.path .. ";/xreactor/?.lua;/xreactor/shared/?.lua;/xreactor/?/init.lua"

local GUI = require("gui")
local STO = require("storage")
local P   = require("protocol")

-- Pfad für die Config
local CFG_PATH = "/xreactor/config_master.lua"

-- Globale Tabellen
local CFG  = {}
local nodes = {}
local page_idx = 1
local scr = term.current()

-- === Dummy-Funktionen (Platzhalter, später implementieren) ===
local function read_main_soc()
  -- TODO: hier später den tatsächlichen Speicherstand auslesen
  return 0.5  -- 50% als Standardwert
end

local function soc_to_steam_target(soc)
  -- TODO: hier später aus SoC den Steam-Bedarf berechnen
  return 0
end

local function distribute(total)
  -- TODO: Verteilung auf die Nodes implementieren
end

local function apply_ramp()
  -- TODO: Rampensteuerung implementieren
end

local function push_setpoints()
  -- TODO: Sollwerte an Nodes senden
end

local function draw()
  -- TODO: Ausgabe auf Monitor/Terminal
  term.setCursorPos(1,1)
  term.clear()
  print("Master online – Monitoring aktiv")
  print("Nodes verbunden: "..tostring(#nodes))
end

-- === Konfigurations-Dialog ===
local function do_config()
  local CFG_DEF = require("config_master")
  CFG = CFG or {}
  for k,v in pairs(CFG_DEF or {}) do if CFG[k] == nil then CFG[k] = v end end

  local spec = {
    {key="distribute",          label="Verteilung",              type="text"},
    {key="page_interval",       label="Page Intervall (s)",      type="number"},
    {key="rows_per_page",       label="Rows/Page",               type="number"},
    {key="ramp_enabled",        label="Ramp enabled",            type="toggle"},
    {key="ramp_step",           label="Ramp Step (mB/t)",        type="number"},
    {key="ramp_interval",       label="Ramp Interval (s)",       type="number"},
    {key="ramp_floor_offset",   label="Ramp Offset/Etage (s)",   type="number"},
    {key="alarm_sound",         label="Alarm Sound",             type="toggle"},
    {key="alarm_rpm_low",       label="Alarm RPM low",           type="number"},
    {key="alarm_rpm_high",      label="Alarm RPM high",          type="number"},
    {key="alarm_floor_soc_low", label="Alarm Floor SoC low",     type="number"},
    {key="main_storages",       label="Hauptspeicher (Komma)",   type="list"},
  }

  local work = {}; for k,v in pairs(CFG) do work[k] = v end
  local res, data = GUI.form("Master Konfiguration", spec, work)

  if res == "save" and type(data) == "table" then
    for k,v in pairs(data) do CFG[k] = v end
    if STO and STO.save_json and CFG_PATH then
      STO.save_json(CFG_PATH, CFG)
    end
    if rednet.isOpen() then rednet.close() end
    if CFG.modem_side then rednet.open(CFG.modem_side) end
  end
end

-- === RX-Loop (Empfang von Nodes) ===
local function rx_loop()
  while true do
    local id, msg = P.recv(1)
    if id and msg then
      if msg._auth ~= CFG.auth_token then
        -- falscher Token -> ignorieren
      else
        if msg.type=="HELLO" then
          nodes[id]=nodes[id] or {}
          nodes[id].floor = msg.floor
          nodes[id].caps = msg.caps or {}
          nodes[id].last = os.epoch("utc")
          nodes[id].ramp = {cur=0, next=os.clock() + (CFG.ramp_floor_offset*(msg.floor or 0))}
          P.send(id, {type="HELLO_ACK", master_id=os.getComputerID(), cfg={rpm_target=CFG.rpm_target}}, CFG.auth_token)

        elseif msg.type=="TELEM" then
          nodes[id]=nodes[id] or {}
          nodes[id].telem = msg
          nodes[id].last = os.epoch("utc")
        end
      end
    end

    -- Timeouts markieren
    for nid,n in pairs(nodes) do
      if (os.epoch("utc")-(n.last or 0))/1000 > (CFG.telem_timeout or 10) then
        n.offline = true
      else
        n.offline = false
      end
    end
  end
end

-- === Kontroll-Loop ===
local function ctrl_loop()
  while true do
    local soc = read_main_soc() or CFG.soc_target
    local total = soc_to_steam_target(soc)
    distribute(total)
    apply_ramp()
    push_setpoints()
    draw()
    sleep(CFG.setpoint_interval or 5)
  end
end

-- === Tastatursteuerung / Menü ===
local function key_loop()
  while true do
    local e,k = os.pullEvent("key")
    if k == keys.f1 then
      do_config()
    elseif k == keys.pageup then
      page_idx = math.max(1, page_idx-1)
    elseif k == keys.pagedown then
      page_idx = page_idx + 1
    elseif k == keys.q or k == keys.escape then
      term.redirect(scr); term.clear(); term.setCursorPos(1,1)
      return
    end
  end
end

-- === Haupt-Parallel-Start ===
parallel.waitForAny(
  rx_loop,
  ctrl_loop,
  key_loop
)
