--========================================================
-- /src/node/node.lua
-- XReactor • Reaktor/Turbinen-Node (AUTODETECT)
--  - Erkennt Reaktoren/Turbinen & deren Methoden automatisch
--  - Master-CMDs haben Priorität
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

local last_master_cmd_ts = now_s()
local function master_is_quiet() return (now_s() - last_master_cmd_ts) >= (CFG.auto.master_timeout_s or 20) end

local function dprint(...)
  if CFG.log and CFG.log.enabled then print("[NODE]", ...) end
end

-----------------------------
-- 3) Autodetect: Peripherals & Methoden
-----------------------------
local function methods_of(pname)
  local ok, m = pcall(peripheral.getMethods, pname)
  if ok and type(m)=="table" then
    local set = {}
    for _,k in ipairs(m) do set[k]=true end
    return set
  end
  return {}
end

local function wrap(name)
  local ok, p = pcall(peripheral.wrap, name)
  if ok and p then return p end
  return nil
end

-- Heuristik: ist „Reaktor“?
local function is_reactor(mset)
  -- typische Signaturen
  return mset.getFuelAmount or mset.getFuelAmountMax or mset.getFuelCapacity
      or mset.getWasteAmount or mset.getWasteCapacity or mset.getWasteAmountMax
      or mset.getActive or mset.setActive or mset.activate or mset.scram
end

-- Heuristik: ist „Turbine“?
local function is_turbine(mset)
  return mset.getRotorSpeed or mset.getRPM or mset.setInductorEngaged or mset.getInductorEngaged
      or mset.setFlowRate or mset.getFlowRate
end

-- Adapter für Reaktor: baut Funktionszeiger je nach vorhandenen Methoden
local function build_reactor_adapter(p, pname, m)
  local A = { name=pname, type="reactor" }

  A.get_active = function()
    if m.getActive then local ok,v=pcall(p.getActive); if ok then return v end end
    if m.isActive then local ok,v=pcall(p.isActive); if ok then return v end end
    return false
  end

  A.set_active = function(on)
    if m.setActive then return pcall(p.setActive, on and true or false) end
    if on and m.activate then return pcall(p.activate) end
    if (not on) and m.scram then return pcall(p.scram) end
    return false,"no_method"
  end

  A.get_fuel = function()
    local f = 0
    if m.getFuelAmount then local ok,v=pcall(p.getFuelAmount); if ok and v then f=v end
    elseif m.getFuel then local ok,v=pcall(p.getFuel); if ok and v then f=v end end
    return f
  end

  A.get_fuel_max = function()
    local mx = 0
    if m.getFuelAmountMax then local ok,v=pcall(p.getFuelAmountMax); if ok and v then mx=v end
    elseif m.getFuelCapacity then local ok,v=pcall(p.getFuelCapacity); if ok and v then mx=v end end
    return mx
  end

  A.get_waste = function()
    local w=0
    if m.getWasteAmount then local ok,v=pcall(p.getWasteAmount); if ok and v then w=v end
    elseif m.getWaste then local ok,v=pcall(p.getWaste); if ok and v then w=v end end
    return w
  end

  A.get_waste_max = function()
    local mx=0
    if m.getWasteAmountMax then local ok,v=pcall(p.getWasteAmountMax); if ok and v then mx=v end
    elseif m.getWasteCapacity then local ok,v=pcall(p.getWasteCapacity); if ok and v then mx=v end end
    return mx
  end

  -- Liste plausibler Drain-Methoden
  local drain_candidates = {
    "ejectWaste","doWasteDrain","dumpWaste","drainWaste","purgeWaste"
  }
  local drain_name = nil
  for _,nm in ipairs(drain_candidates) do if m[nm] then drain_name = nm; break end end

  -- Optional: Port-Enable Toggle
  local has_toggle = (m.setWasteOutputEnabled and m.getWasteOutputEnabled)

  A.waste_drain = function(amount)
    amount = tonumber(amount or 0)
    -- direkte Methode mit/ohne amount
    if drain_name then
      local fn = p[drain_name]
      if amount and amount>0 then
        local ok = select(1, pcall(fn, amount))
        if ok then return true, drain_name end
      else
        local ok = select(1, pcall(fn))
        if ok then return true, drain_name end
      end
    end
    -- Toggle als Fallback
    if has_toggle then
      local ok,on = pcall(p.getWasteOutputEnabled)
      if ok and not on then pcall(p.setWasteOutputEnabled, true) end
      os.sleep(0.2)
      return true, "port_toggle"
    end
    return false, "no_method"
  end

  return A
end

-- Adapter für Turbine
local function build_turbine_adapter(p, pname, m)
  local A = { name=pname, type="turbine" }

  A.get_rpm = function()
    if m.getRotorSpeed then local ok,v=pcall(p.getRotorSpeed); if ok and v then return v end end
    if m.getRPM        then local ok,v=pcall(p.getRPM);        if ok and v then return v end end
    return 0
  end

  A.set_inductor = function(on)
    if m.setInductorEngaged then return pcall(p.setInductorEngaged, on and true or false) end
    return false,"no_method"
  end

  A.get_flow = function()
    if m.getFlowRate then local ok,v=pcall(p.getFlowRate); if ok and v then return v end end
    return nil
  end

  A.set_flow = function(flow)
    if m.setFlowRate then return pcall(p.setFlowRate, math.max(0, math.floor(flow or 0))) end
    return false,"no_method"
  end

  return A
end

-- Scan aller Peripherals → Listen mit Adaptern
local REACTORS, TURBINES = {}, {}
local function autodetect_all()
  REACTORS, TURBINES = {}, {}
  for _,pname in ipairs(peripheral.getNames()) do
    local m = methods_of(pname)
    if next(m) then
      if is_reactor(m) then
        local p = wrap(pname)
        if p then table.insert(REACTORS, build_reactor_adapter(p, pname, m)) end
      elseif is_turbine(m) then
        local p = wrap(pname)
        if p then table.insert(TURBINES, build_turbine_adapter(p, pname, m)) end
      end
    end
  end
  dprint(("Autodetect: %d Reactor(s), %d Turbine(n)"):format(#REACTORS, #TURBINES))
end

autodetect_all()
-- Fallback: erneut scannen nach kurzer Zeit (z. B. wenn Wired-Netz spät kommt)
if #REACTORS==0 and #TURBINES==0 then os.sleep(1.0); autodetect_all() end

-----------------------------
-- 4) Telemetrie
-----------------------------
local function pct(a,b) if not b or b<=0 then return 0 end return (a or 0)/b*100 end

local function collect_telem()
  local telem={ reactors={}, turbines={}, agg={reactors={}, turbines={}} }
  for i,A in ipairs(REACTORS) do
    local r = {
      uid       = ("rx_%d"):format(i),
      fuel      = A.get_fuel(),
      fuel_max  = A.get_fuel_max(),
      waste     = A.get_waste(),
      waste_max = A.get_waste_max(),
      active    = A.get_active() and true or false,
    }
    table.insert(telem.reactors, r)
    telem.agg.reactors.fuel      =(telem.agg.reactors.fuel or 0)+(r.fuel or 0)
    telem.agg.reactors.fuel_max  =(telem.agg.reactors.fuel_max or 0)+(r.fuel_max or 0)
    telem.agg.reactors.waste     =(telem.agg.reactors.waste or 0)+(r.waste or 0)
    telem.agg.reactors.waste_max =(telem.agg.reactors.waste_max or 0)+(r.waste_max or 0)
    telem.agg.reactors.count     =(telem.agg.reactors.count or 0)+1
    telem.agg.reactors.active    =(telem.agg.reactors.active or 0)+((r.active and 1) or 0)
  end
  for i,A in ipairs(TURBINES) do
    local rpm = A.get_rpm()
    telem.turbines[i] = { uid=("tb_%d"):format(i), rpm=rpm }
    telem.agg.turbines.rpm   =(telem.agg.turbines.rpm or 0)+rpm
    telem.agg.turbines.count =(telem.agg.turbines.count or 0)+1
    telem.agg.turbines.active=(telem.agg.turbines.active or 0)+((rpm>10) and 1 or 0)
  end
  return telem
end

-----------------------------
-- 5) Master-CMDs
-----------------------------
local function handle_cmd(msg, from_id)
  last_master_cmd_ts = now_s()

  if msg.target=="reactor" then
    if msg.cmd=="setActive" then
      local ok_any=false
      for _,A in ipairs(REACTORS) do local ok=select(1, A.set_active(msg.value and true or false)); ok_any=ok_any or ok end
      rednet.send(from_id, {type="CMD_ACK", ok=ok_any, msg="reactor setActive", _auth=CFG.auth_token})
      return
    elseif msg.cmd=="WASTE_DRAIN" then
      local amount = tonumber(msg.amount or CFG.auto.waste_batch_amount or 0)
      local ok_any=false; local used="none"
      for _,A in ipairs(REACTORS) do local ok,m=A.waste_drain(amount); ok_any=ok_any or ok; if ok and m then used=m end end
      rednet.send(from_id, {type="CMD_ACK", ok=ok_any, msg="waste_drain:"..tostring(used), _auth=CFG.auth_token})
      return
    end
  elseif msg.target=="turbine" then
    if msg.cmd=="setInductorEngaged" then
      local ok_any=false
      for _,A in ipairs(TURBINES) do local ok=select(1, A.set_inductor and A.set_inductor(msg.value and true or false)); ok_any=ok_any or ok end
      rednet.send(from_id, {type="CMD_ACK", ok=ok_any, msg="turbine inductor", _auth=CFG.auth_token})
      return
    elseif msg.cmd=="autotune" then
      local ok_any=false
      for _,A in ipairs(TURBINES) do
        local rpm = A.get_rpm()
        if A.set_inductor and rpm > (CFG.auto.inductor_on_min_rpm or 500) then
          local ok=select(1, A.set_inductor(true)); ok_any=ok_any or ok
        end
      end
      rednet.send(from_id, {type="CMD_ACK", ok=ok_any, msg="autotune(simple)", _auth=CFG.auth_token})
      return
    end
  end

  rednet.send(from_id, {type="CMD_ACK", ok=false, msg="unknown_cmd", _auth=CFG.auth_token})
end

-----------------------------
-- 6) Auto-Fallback
-----------------------------
local waste_cd = {}  -- key=uid → last_ts

local function auto_tick()
  if not (CFG.auto and CFG.auto.enable) then return end
  if not master_is_quiet() then return end

  -- a) Reaktor anlassen (optional)
  if CFG.auto.reactor_keep_on then
    for _,A in ipairs(REACTORS) do pcall(A.set_active, true) end
  end

  -- b) Turbinen RPM grob halten
  for _,A in ipairs(TURBINES) do
    local rpm = A.get_rpm()
    local tgt = CFG.auto.rpm_target or 1800
    local band= CFG.auto.rpm_band or 100
    local step= CFG.auto.flow_step or 25

    if A.set_inductor and rpm > (CFG.auto.inductor_on_min_rpm or 500) then pcall(A.set_inductor, true) end
    if A.get_flow and A.set_flow then
      local cur = A.get_flow() or 0
      if rpm < (tgt - band) then pcall(A.set_flow, (cur + step))
      elseif rpm > (tgt + band) then pcall(A.set_flow, math.max(0, cur - step)) end
    end
  end

  -- c) Auto-Waste-DRAIN
  local wmax = CFG.auto.waste_max_pct or 60
  local amt  = CFG.auto.waste_batch_amount or 4000
  local cd_s = CFG.auto.waste_cooldown_s or 90
  for i,A in ipairs(REACTORS) do
    local uid = ("rx_%d"):format(i)
    local f   = A.get_waste and A.get_waste() or 0
    local fm  = A.get_waste_max and A.get_waste_max() or 0
    if fm>0 then
      local wp = (f/fm)*100
      if wp >= wmax and (now_s() - (waste_cd[uid] or 0)) >= cd_s then
        pcall(A.waste_drain, amt)
        waste_cd[uid] = now_s()
      end
    end
  end
end

-----------------------------
-- 7) RX/TX Loops
-----------------------------
local function rx_loop()
  -- HELLO initial (Caps aus Autodetect)
  rednet.broadcast({type="HELLO", caps={reactor=(#REACTORS>0), turbine=(#TURBINES>0)}, _auth=CFG.auth_token})
  while true do
    local id,msg = rednet.receive(0.5)
    if id and type(msg)=="table" and msg._auth==CFG.auth_token then
      if msg.type=="CMD" then
        handle_cmd(msg, id)
      elseif msg.type=="HELLO_ACK" then
        last_master_cmd_ts = now_s()
      end
    end
  end
end

local function tx_loop()
  local t0=0
  while true do
    local now=os.clock()
    if now - t0 >= (CFG.tick_rate_s or 1.0) then
      local telem = collect_telem()
      rednet.broadcast({type="TELEM", telem=telem, _auth=CFG.auth_token})
      t0 = now
    end
    pcall(auto_tick)
    os.sleep(0.05)
  end
end

print(("Node #%d gestartet | Modem:%s | Auto:%s")
  :format(NODE_ID, CFG.modem_side, (CFG.auto.enable and "ON" or "OFF")))
parallel.waitForAny(rx_loop, tx_loop)