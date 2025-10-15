-- =========================================================
-- XReactor ◈ NODE
--  - scannt BigReactors-Reaktoren & -Turbinen (lokal + wired)
--  - HELLO/ACK mit Master über rednet
--  - sendet zyklisch TELEM mit Telemetrie
--  - zeigt kompakten Status lokal an (Terminal + optional Monitor)
-- =========================================================

-- ── sichere require-Hilfsfunktion
local function try_require(name)
  local ok, mod = pcall(require, name)
  if ok then return mod end
end

-- ── Config laden (mit Defaults)
local CFG = {
  modem_side     = "right",   -- dein Wireless/Wired Modem zum Master
  monitor_side   = nil,       -- z.B. "bottom" (optional)
  telem_interval = 2,         -- Sekunden zwischen Telemetrie-Sendungen
  auth_token     = "xreactor",-- muss zum Master passen
}
local ok, user_cfg = pcall(dofile, "/xreactor/config_node.lua")
if ok and type(user_cfg)=="table" then
  for k,v in pairs(user_cfg) do CFG[k]=v end
end

-- ── Peripherien
local has_colors = term.isColor and term.isColor()
local mon = nil

-- ── Anzeige umschalten
local function bind_monitor()
  if CFG.monitor_side and peripheral.isPresent(CFG.monitor_side)
    and peripheral.getType(CFG.monitor_side)=="monitor" then
    mon = peripheral.wrap(CFG.monitor_side)
    pcall(mon.setTextScale, 0.5)
  else
    mon = nil
  end
end
bind_monitor()

local function w()
  if mon then return mon else return term end
end

local function cls()
  local t = w()
  t.setBackgroundColor(colors.black)
  t.setTextColor(colors.white)
  t.clear()
  t.setCursorPos(1,1)
end

local function print_line(txt)
  local t = w()
  local x,y = t.getCursorPos()
  local width = ({t.getSize()})[1]
  if #txt > width then txt = txt:sub(1,width) end
  t.write(txt)
  t.setCursorPos(1, y+1)
end

-- ── Rednet vorbereiten
assert(peripheral.getType(CFG.modem_side)=="modem", "No modem on "..tostring(CFG.modem_side))
rednet.open(CFG.modem_side)

local MASTER_ID = nil
local last_ack  = 0

-- ── nützliche Hilfen
local function now_ms() return os.epoch("utc") end

local function safe_call(p, method, ...)
  if not p or type(p[method])~="function" then return nil end
  local ok, res = pcall(p[method], ...)
  if ok then return res end
  return nil
end

-- ── Scan: alle Peripherals einsammeln (lokal + über Wired)
local DEV = {reactors={}, turbines={}}

local function is_reactor(typ)  return typ=="BigReactors-Reactor" end
local function is_turbine(typ)  return typ=="BigReactors-Turbine" end

local function scan_devices()
  DEV.reactors, DEV.turbines = {}, {}
  local names = peripheral.getNames()
  for _,name in ipairs(names) do
    local typ = peripheral.getType(name)
    if is_reactor(typ) then table.insert(DEV.reactors, name)
    elseif is_turbine(typ) then table.insert(DEV.turbines, name)
    end
  end
end
scan_devices()

-- ── Telemetrie sammeln (robust, nur vorhandene Methoden)
local function read_reactor(name)
  local p = peripheral.wrap(name); if not p then return nil end
  return {
    name   = name,
    active = safe_call(p,"getActive") or false,
    energy = safe_call(p,"getEnergyStored") or 0,
    fuel   = safe_call(p,"getFuelAmount") or 0,
    fuel_max = safe_call(p,"getFuelAmountMax") or 0,
    temp   = safe_call(p,"getCasingTemperature") or 0,
    hot_mb = safe_call(p,"getHotFluidProducedLastTick") or 0,
  }
end

local function read_turbine(name)
  local p = peripheral.wrap(name); if not p then return nil end
  return {
    name     = name,
    active   = safe_call(p,"getActive") or false,
    rpm      = safe_call(p,"getRotorSpeed") or 0,
    flow     = safe_call(p,"getFluidFlowRate") or 0,
    flow_max = safe_call(p,"getFluidFlowRateMax") or 0,
    prod     = safe_call(p,"getEnergyProducedLastTick") or 0,
    inductor = safe_call(p,"getInductorEngaged") or false,
    energy   = safe_call(p,"getEnergyStored") or 0,
  }
end

local function collect_telem()
  local reactors, turbines = {}, {}
  for _,n in ipairs(DEV.reactors) do
    local t = read_reactor(n); if t then table.insert(reactors, t) end
  end
  for _,n in ipairs(DEV.turbines) do
    local t = read_turbine(n); if t then table.insert(turbines, t) end
  end

  -- Aggregate
  local agg = {
    reactors = {count=#reactors, hot=0, energy=0, fuel=0, fuel_max=0, active=0},
    turbines = {count=#turbines, prod=0, rpm=0, flow=0, flow_max=0, active=0},
  }
  for _,r in ipairs(reactors) do
    agg.reactors.hot      = agg.reactors.hot + (r.hot_mb or 0)
    agg.reactors.energy   = agg.reactors.energy + (r.energy or 0)
    agg.reactors.fuel     = agg.reactors.fuel + (r.fuel or 0)
    agg.reactors.fuel_max = agg.reactors.fuel_max + (r.fuel_max or 0)
    if r.active then agg.reactors.active = agg.reactors.active + 1 end
  end
  for _,t in ipairs(turbines) do
    agg.turbines.prod     = agg.turbines.prod + (t.prod or 0)
    agg.turbines.rpm      = agg.turbines.rpm + (t.rpm or 0)
    agg.turbines.flow     = agg.turbines.flow + (t.flow or 0)
    agg.turbines.flow_max = agg.turbines.flow_max + (t.flow_max or 0)
    if t.active then agg.turbines.active = agg.turbines.active + 1 end
  end

  return reactors, turbines, agg
end

-- ── HELLO/ACK – Master finden
local function say_hello()
  rednet.broadcast({type="HELLO", caps={reactor=true,turbine=true}, _auth=CFG.auth_token})
end

local function expect_ack(timeout)
  local t = timeout or 2
  local id, msg = rednet.receive(t)
  if id and type(msg)=="table" and msg.type=="HELLO_ACK" and msg._auth==CFG.auth_token then
    MASTER_ID = id
    last_ack = now_ms()
    return true
  end
  return false
end

-- ── Senden/Empfangen
local function send_telem()
  if not MASTER_ID then return end
  local reactors, turbines, agg = collect_telem()
  local payload = {
    type="TELEM",
    caps={reactors=#DEV.reactors, turbines=#DEV.turbines},
    telem={reactors=reactors, turbines=turbines, agg=agg},
    _auth=CFG.auth_token,
  }
  rednet.send(MASTER_ID, payload)
end

-- ── Anzeige
local function draw()
  cls()
  print_line(("XReactor Node  |  Modem: %s"):format(CFG.modem_side))
  print_line(("Master: %s"):format(MASTER_ID and ("#"..MASTER_ID) or "…suche…"))
  print_line("")
  print_line(("Reaktoren: %d  |  Turbinen: %d"):format(#DEV.reactors, #DEV.turbines))

  local _,_,agg = collect_telem()
  print_line(("R: active %d/%d  hot %d mB/t  fuel %.0f/%.0f mB  energy %.0f")
    :format(agg.reactors.active, agg.reactors.count, agg.reactors.hot, agg.reactors.fuel, agg.reactors.fuel_max, agg.reactors.energy))
  print_line(("T: active %d/%d  rpm %.0f  flow %.0f/%.0f  prod %.0f/t")
    :format(agg.turbines.active, agg.turbines.count, agg.turbines.rpm, agg.turbines.flow, agg.turbines.flow_max, agg.turbines.prod))

  print_line("")
  print_line("[F5] Rescan  |  [Q] Quit")
end

-- ── Event-Loop
local function rx_loop()
  while true do
    local id, msg = rednet.receive(1)
    if id and type(msg)=="table" and msg._auth==CFG.auth_token then
      if msg.type=="HELLO_ACK" then
        MASTER_ID = id
        last_ack = now_ms()
      end
    end
  end
end

local function core_loop()
  -- initial hello
  say_hello()
  expect_ack(2)
  draw()

  local t_last = 0
  while true do
    -- Verbindungs-Health: regelmäßig HELLO falls ACK alt
    if not MASTER_ID or (now_ms()-last_ack) > 15000 then
      say_hello()
      expect_ack(2)
    end

    -- zyklische Telemetrie
    local t = os.clock()
    if t - t_last >= (CFG.telem_interval or 2) then
      send_telem()
      draw()
      t_last = t
    end

    -- leichte Pause
    os.sleep(0.1)
  end
end

local function keys_loop()
  while true do
    local e, k = os.pullEvent("key")
    if k == keys.f5 then
      scan_devices()
      draw()
    elseif k == keys.q or k == keys.escape then
      cls()
      term.setCursorPos(1,1)
      print("Node beendet.")
      return
    end
  end
end

-- ── Startbanner
cls()
print_line("Starte node...")
print_line(("Modem: %s  |  Monitor: %s")
  :format(CFG.modem_side, CFG.monitor_side or "-"))

-- ── paralleler Betrieb
parallel.waitForAny(rx_loop, core_loop, keys_loop)
