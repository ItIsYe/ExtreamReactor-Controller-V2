-- ===== Reactor Node =====
-- Stellt Verbindung zum Master her und sendet Telemetrie
package.path = package.path .. ";/xreactor/?.lua;/xreactor/shared/?.lua;/xreactor/?/init.lua"

local PRO = require("protocol")
local STO = require("storage")

-- ---------- Konfiguration ----------
local CFG_PATH = "/xreactor/config_node.lua"
local CFG = {}
do
  local ok, def = pcall(require, "config_node")
  if ok and type(def) == "table" then for k,v in pairs(def) do CFG[k]=v end end
  local j = STO.load_json and STO.load_json(CFG_PATH, nil)
  if type(j)=="table" then for k,v in pairs(j) do CFG[k]=v end end
end

CFG.master_id   = CFG.master_id   or nil
CFG.floor       = CFG.floor       or 0
CFG.auth_token  = CFG.auth_token  or "changeme"
CFG.modem_side  = CFG.modem_side  or "left"
CFG.telem_rate  = CFG.telem_rate  or 3

-- ---------- Peripherie ----------
if rednet.isOpen() then rednet.close() end
rednet.open(CFG.modem_side)

-- ---------- HELLO ----------
local function hello()
  local msg = {
    type = "HELLO",
    floor = CFG.floor,
    caps = {steam=true, rpm=true, fill=true},
    _auth = CFG.auth_token
  }
  print("Sende HELLO an Master...")
  if CFG.master_id then
    rednet.send(CFG.master_id, msg)
  else
    rednet.broadcast(msg)
  end
end

-- ---------- TELEMETRIE ----------
local function get_telem()
  -- Dummy-Daten – später echte Reactor-Infos
  return {
    type = "TELEM",
    fill = math.random(),
    rpm = math.random(1000,1800),
    steam = math.random(0,2000),
    _auth = CFG.auth_token
  }
end

local function send_telem()
  local msg = get_telem()
  if CFG.master_id then
    rednet.send(CFG.master_id, msg)
  else
    rednet.broadcast(msg)
  end
end

-- ---------- Empfang ----------
local function rx_loop()
  while true do
    local id, msg = rednet.receive(nil, 5)
    if id and type(msg) == "table" then
      if msg._auth ~= CFG.auth_token then
        -- ignorieren
      elseif msg.type == "HELLO_ACK" then
        CFG.master_id = id
        print("Verbunden mit Master #" .. id)
      elseif msg.type == "SETPOINT" then
        -- später für Steuerung nutzbar
        CFG.last_setpoint = msg
      end
    end
  end
end

-- ---------- Hauptschleifen ----------
local function telem_loop()
  while true do
    send_telem()
    sleep(CFG.telem_rate or 3)
  end
end

local function hello_loop()
  while true do
    hello()
    sleep(30) -- alle 30s neu HELLO senden (Reconnect-Sicherheit)
  end
end

-- ---------- Start ----------
print("Starte node...")
hello()
parallel.waitForAny(rx_loop, telem_loop, hello_loop)
