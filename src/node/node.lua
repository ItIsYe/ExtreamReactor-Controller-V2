--========================================================
-- /src/node/node.lua
-- XReactor • Reaktor/Turbinen-Node
--  - Empfängt Master-CMDs (Priorität)
--  - Fallback-Autosteuerung bei Master-Timeout
--  - WASTE_DRAIN lokal am Reaktor-Port (CMD + Auto)
--  - Telemetrie an Master
--========================================================

-----------------------------
-- 1) Config laden
-----------------------------
local CFG = (function()
  local t = {
    auth_token = "xreactor",
    modem_side = "right",
    tick_rate_s = 1.0,
    auto = {
      enable=true, master_timeout_s=20,
      rpm_target=1800, rpm_band=100, flow_step=25,
      inductor_on_min_rpm=500,
      reactor_keep_on=true,
      waste_max_pct=60, waste_batch_amount=4000, waste_cooldown_s=90,
    },
    log = { enabled=false, level="info" },
  }
  local ok,c = pcall(dofile,"/xreactor/config_node.lua")
  if ok and type(c)=="table" then
    for k,v in pairs(c) do
      if k=="auto" and type(v)=="table" then for kk,vv in pairs(v) do t.auto[kk]=vv end
      elseif k=="log" and type(v)=="table" then for kk,vv in pairs(v) do t.log[kk]=vv end
      else t[k]=v end
    end
  end
  return t
end)()

-----------------------------
-- 2) Rednet & Basics
-----------------------------
assert(peripheral.getType(CFG.modem_side)=="modem","Kein Modem an "..tostring(CFG.modem_side))
rednet.open(CFG.modem_side)
local NODE_ID = os.getComputerID()
local function now_s() return os.epoch("utc")/1000 end

local last_master_cmd_ts = now_s()   -- Zeitpunkt der letzten Master-Aktivität
local function master_is_quiet()
  return (now_s() - last_master_cmd_ts) >= (CFG.auto.master_timeout_s or 20)
end

-----------------------------
-- 3) Peripherals finden
-----------------------------
-- Passe diese Typen ggf. an dein Modpack an:
local function pfind(typeName)
  local t = { peripheral.find(typeName) }
  return t
end

-- Versuch 1: Bigger/Extreme Reactors Typen
local REACTORS = pfind("BiggerReactors_Reactor")
local TURBINES = pfind("BiggerReactors_Turbine")

-- Falls nichts gefunden: generische Suche über Namen, die "reactor" / "turbine" enthalten könnten
if #REACTORS==0 then
  for _,name in ipairs(peripheral.getNames()) do
    local tp = peripheral.getType(name) or ""
    if tp:lower():find("reactor") then table.insert(REACTORS, peripheral.wrap(name)) end
  end
end
if #TURBINES==0 then
  for _,name in ipairs(peripheral.getNames()) do
    local tp = peripheral.getType(name) or ""
    if tp:lower():find("turbine") then table.insert(TURBINES, peripheral.wrap(name)) end
  end
end

-----------------------------
-- 4) Adapter-Funktionen
-----------------------------
-- Reaktor
local function reactor_setActive(p, on)
  if p.setActive then return pcall(p.setActive, on)
  elseif p.activate and on then return pcall(p.activate)
  elseif p.scram and (not on) then return pcall(p.scram)
  end
  return false,"no_method"
end

local function reactor_telemetry(p)
  local t = {}
  t.fuel      = (p.getFuelAmount and p.getFuelAmount()) or (p.getFuel and p.getFuel()) or 0
  t.fuel_max  = (p.getFuelAmountMax and p.getFuelAmountMax()) or (p.getFuelCapacity and p.getFuelCapacity()) or 0
  t.waste     = (p.getWasteAmount and p.getWasteAmount()) or (p.getWaste and p.getWaste()) or 0
  t.waste_max = (p.getWasteAmountMax and p.getWasteAmountMax()) or (p.getWasteCapacity and p.getWasteCapacity()) or 0
  t.active    = (p.getActive and p.getActive()) or (p.isActive and p.isActive()) or false
  return t
end

-- Lokales Waste-DRAIN am Reaktor/Waste-Port
local function reactor_waste_drain(p, amount)
  -- Explizite Methoden
  if p.ejectWaste then local ok = select(1, pcall(p.ejectWaste, tonumber(amount or 0))); if ok then return true,"ejectWaste" end end
  if p.doWasteDrain then local ok = select(1, pcall(p.doWasteDrain, tonumber(amount or 0))); if ok then return true,"doWasteDrain" end end
  if p.dumpWaste then local ok = select(1, pcall(p.dumpWaste)); if ok then return true,"dumpWaste" end end
  -- Port toggle (falls es so etwas gibt)
  if p.setWasteOutputEnabled and p.getWasteOutputEnabled then
    local ok,on = pcall(p.getWasteOutputEnabled)
    if ok and not on then pcall(p.setWasteOutputEnabled, true) end
    os.sleep(0.2)
    return true,"port_toggle"
  end
  return false,"no_method"
end

-- Turbine
local function turbine_getRPM(p)
  return (p.getRotorSpeed and p.getRotorSpeed()) or (p.getRPM and p.getRPM()) or 0
end

local function turbine_setInductor(p, on)
  if p.setInductorEngaged then return pcall(p.setInductorEngaged, on) end
  return false,"no_method"
end

local function turbine_setFlow(p, flow)
  -- Manche Implementationen haben setFlowRate; sonst nichts tun.
  if p.setFlowRate then return pcall(p.setFlowRate, math.max(0, math.floor(flow or 0))) end
  return false,"no_method"
end

-----------------------------
-- 5) Telemetrie sammeln
-----------------------------
local function pct(a,b) if not b or b<=0 then return 0 end return (a or 0)/b*100 end

local function collect_telem()
  local telem={ reactors={}, turbines={}, agg={reactors={}, turbines={}} }
  for i,p in ipairs(REACTORS) do
    local r = reactor_telemetry(p); r.uid=("rx_%d"):format(i); table.insert(telem.reactors, r)
    telem.agg.reactors.fuel      =(telem.agg.reactors.fuel or 0)+(r.fuel or 0)
    telem.agg.reactors.fuel_max  =(telem.agg.reactors.fuel_max or 0)+(r.fuel_max or 0)
    telem.agg.reactors.waste     =(telem.agg.reactors.waste or 0)+(r.waste or 0)
    telem.agg.reactors.waste_max =(telem.agg.reactors.waste_max or 0)+(r.waste_max or 0)
    telem.agg.reactors.count     =(telem.agg.reactors.count or 0)+1
    telem.agg.reactors.active    =(telem.agg.reactors.active or 0)+((r.active and 1) or 0)
  end
  for i,p in ipairs(TURBINES) do
    local rpm = turbine_getRPM(p)
    telem.turbines[i] = { uid=("tb_%d"):format(i), rpm=rpm }
    telem.agg.turbines.rpm   =(telem.agg.turbines.rpm or 0)+rpm
    telem.agg.turbines.count =(telem.agg.turbines.count or 0)+1
    telem.agg.turbines.active=(telem.agg.turbines.active or 0)+((rpm>10) and 1 or 0)
  end
  return telem
end

-----------------------------
-- 6) Master-CMDs verarbeiten
-----------------------------
local function handle_cmd(msg, from_id)
  last_master_cmd_ts = now_s()
  if msg.target=="reactor" then
    if msg.cmd=="setActive" then
      local ok_any=false
      for _,p in ipairs(REACTORS) do local ok=select(1,reactor_setActive(p, msg.value and true or false)); ok_any=ok_any or ok end
      rednet.send(from_id, {type="CMD_ACK", ok=ok_any, msg="reactor setActive", _auth=CFG.auth_token})
      return
    elseif msg.cmd=="WASTE_DRAIN" then
      local amount = tonumber(msg.amount or CFG.auto.waste_batch_amount or 0)
      local ok_any=false; local used="none"
      for _,p in ipairs(REACTORS) do local ok,m=reactor_waste_drain(p, amount); ok_any=ok_any or ok; used=m or used end
      rednet.send(from_id, {type="CMD_ACK", ok=ok_any, msg="waste_drain:"..tostring(used), _auth=CFG.auth_token})
      return
    end
  elseif msg.target=="turbine" then
    if msg.cmd=="setInductorEngaged" then
      local ok_any=false
      for _,t in ipairs(TURBINES) do local ok=select(1,turbine_setInductor(t, msg.value and true or false)); ok_any=ok_any or ok end
      rednet.send(from_id, {type="CMD_ACK", ok=ok_any, msg="turbine inductor", _auth=CFG.auth_token})
      return
    elseif msg.cmd=="autotune" then
      -- Platzhalter: einfach Inductor einschalten, falls RPM > min
      local ok_any=false
      for _,t in ipairs(TURBINES) do
        local rpm=turbine_getRPM(t)
        if rpm > (CFG.auto.inductor_on_min_rpm or 500) then local ok=select(1,turbine_setInductor(t,true)); ok_any=ok_any or ok end
      end
      rednet.send(from_id, {type="CMD_ACK", ok=ok_any, msg="autotune(simple)", _auth=CFG.auth_token})
      return
    end
  end
  -- Unbekannt
  rednet.send(from_id, {type="CMD_ACK", ok=false, msg="unknown_cmd", _auth=CFG.auth_token})
end

-----------------------------
-- 7) Fallback-Autosteuerung
-----------------------------
local waste_cooldown = {}  -- key="rx_i" → ts

local function auto_loop_tick()
  if not (CFG.auto and CFG.auto.enable) then return end
  if not master_is_quiet() then return end

  -- a) Reaktor anlassen (optional)
  if CFG.auto.reactor_keep_on then
    for _,p in ipairs(REACTORS) do pcall(reactor_setActive, p, true) end
  end

  -- b) Turbinen RPM halten (rudimentär)
  for _,t in ipairs(TURBINES) do
    local rpm = turbine_getRPM(t)
    local tgt = CFG.auto.rpm_target or 1800
    local band= CFG.auto.rpm_band   or 100
    local step= CFG.auto.flow_step  or 25

    -- Inductor bei genug RPM an
    if rpm > (CFG.auto.inductor_on_min_rpm or 500) then pcall(turbine_setInductor, t, true) end

    -- Wenn API Flow-Rate kann: grob justieren
    if t.getFlowRate and t.setFlowRate then
      local cur = t.getFlowRate()
      if rpm < (tgt - band) then pcall(turbine_setFlow, t, (cur or 0) + step)
      elseif rpm > (tgt + band) then pcall(turbine_setFlow, t, math.max(0, (cur or 0) - step)) end
    end
  end

  -- c) Auto-WASTE-DRAIN
  local waste_max = CFG.auto.waste_max_pct or 60
  local amount    = CFG.auto.waste_batch_amount or 4000
  local cd        = CFG.auto.waste_cooldown_s or 90
  for i,p in ipairs(REACTORS) do
    local r = reactor_telemetry(p)
    local uid = ("rx_%d"):format(i)
    local last = waste_cooldown[uid] or 0
    if r.waste_max and r.waste_max > 0 then
      local w_pct = pct(r.waste, r.waste_max)
      if w_pct >= waste_max and (now_s() - last) >= cd then
        pcall(reactor_waste_drain, p, amount)
        waste_cooldown[uid] = now_s()
      end
    end
  end
end

-----------------------------
-- 8) RX/TX Loops
-----------------------------
local function rx_loop()
  -- HELLO initial
  rednet.broadcast({type="HELLO", caps={reactor=(#REACTORS>0), turbine=(#TURBINES>0)}, _auth=CFG.auth_token})
  while true do
    local id,msg = rednet.receive(0.5)
    if id and type(msg)=="table" and msg._auth==CFG.auth_token then
      if msg.type=="CMD" then
        handle_cmd(msg, id)
      elseif msg.type=="HELLO_ACK" then
        last_master_cmd_ts = now_s() -- lebenszeichen
      end
    end
  end
end

local function tx_loop()
  local t0 = 0
  while true do
    local now=os.clock()
    if now - t0 >= (CFG.tick_rate_s or 1.0) then
      local telem = collect_telem()
      rednet.broadcast({type="TELEM", telem=telem, _auth=CFG.auth_token})
      t0 = now
    end
    -- Fallback-Auto
    pcall(auto_loop_tick)
    os.sleep(0.05)
  end
end

print(("Node #%d gestartet | Modem:%s | Auto:%s")
  :format(NODE_ID, CFG.modem_side, (CFG.auto.enable and "ON" or "OFF")))
parallel.waitForAny(rx_loop, tx_loop)