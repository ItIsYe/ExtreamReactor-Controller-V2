-- =========================================================
-- XReactor ◈ NODE
--  - scannt BigReactors (Reaktoren/Turbinen)
--  - HELLO/ACK mit Master über rednet
--  - sendet zyklisch TELEM
--  - empfängt CMDs (Steuerung) + Auto-Kalibrierung Flow
-- =========================================================

-- ── Config laden (mit Defaults)
local CFG = {
  modem_side     = "right",
  monitor_side   = nil,
  telem_interval = 2,
  auth_token     = "xreactor",
}
local ok, user_cfg = pcall(dofile, "/xreactor/config_node.lua")
if ok and type(user_cfg)=="table" then for k,v in pairs(user_cfg) do CFG[k]=v end end

-- ── IO helpers
local mon
local function bind_monitor()
  if CFG.monitor_side and peripheral.isPresent(CFG.monitor_side)
    and peripheral.getType(CFG.monitor_side)=="monitor" then
    mon = peripheral.wrap(CFG.monitor_side)
    pcall(mon.setTextScale, 0.5)
  else mon=nil end
end
bind_monitor()
local function T() return mon or term end
local function cls() local t=T(); t.setBackgroundColor(colors.black); t.setTextColor(colors.white); t.clear(); t.setCursorPos(1,1) end
local function println(s) local t=T(); local x,y=t.getCursorPos(); local w=t.getSize(); if #s>w then s=s:sub(1,w) end; t.write(s); t.setCursorPos(1,y+1) end

-- ── Rednet
assert(peripheral.getType(CFG.modem_side)=="modem", "No modem on "..tostring(CFG.modem_side))
rednet.open(CFG.modem_side)
local MASTER_ID, last_ack = nil, 0
local function now_ms() return os.epoch("utc") end

-- ── Scan Devices
local DEV = {reactors={}, turbines={}}
local function is_reactor(t) return t=="BigReactors-Reactor" end
local function is_turbine(t) return t=="BigReactors-Turbine" end
local function scan_devices()
  DEV.reactors, DEV.turbines = {}, {}
  for _,name in ipairs(peripheral.getNames()) do
    local typ = peripheral.getType(name)
    if is_reactor(typ) then table.insert(DEV.reactors, name)
    elseif is_turbine(typ) then table.insert(DEV.turbines, name) end
  end
end
scan_devices()

-- ── Safe calls
local function safe_call(p, m, ...) if not p or type(p[m])~="function" then return nil end local ok,res=pcall(p[m],...); if ok then return res end return nil end

-- ── Read Telemetry
local function read_reactor(name)
  local p=peripheral.wrap(name); if not p then return nil end
  return {
    name=name,
    active=safe_call(p,"getActive") or false,
    energy=safe_call(p,"getEnergyStored") or 0,
    fuel=safe_call(p,"getFuelAmount") or 0,
    fuel_max=safe_call(p,"getFuelAmountMax") or 0,
    temp=safe_call(p,"getCasingTemperature") or 0,
    hot_mb=safe_call(p,"getHotFluidProducedLastTick") or 0,
  }
end
local function read_turbine(name)
  local p=peripheral.wrap(name); if not p then return nil end
  return {
    name=name,
    active=safe_call(p,"getActive") or false,
    rpm=safe_call(p,"getRotorSpeed") or 0,
    flow=safe_call(p,"getFluidFlowRate") or 0,
    flow_max=safe_call(p,"getFluidFlowRateMax") or 0,
    prod=safe_call(p,"getEnergyProducedLastTick") or 0,
    inductor=safe_call(p,"getInductorEngaged") or false,
    energy=safe_call(p,"getEnergyStored") or 0,
  }
end
local function collect_telem()
  local reactors,turbines={},{}
  for _,n in ipairs(DEV.reactors) do local r=read_reactor(n); if r then table.insert(reactors,r) end end
  for _,n in ipairs(DEV.turbines) do local t=read_turbine(n); if t then table.insert(turbines,t) end end
  local agg={reactors={count=#reactors,active=0,hot=0,energy=0,fuel=0,fuel_max=0}, turbines={count=#turbines,active=0,rpm=0,flow=0,flow_max=0,prod=0}}
  for _,r in ipairs(reactors) do
    agg.reactors.hot=agg.reactors.hot+(r.hot_mb or 0)
    agg.reactors.energy=agg.reactors.energy+(r.energy or 0)
    agg.reactors.fuel=agg.reactors.fuel+(r.fuel or 0)
    agg.reactors.fuel_max=agg.reactors.fuel_max+(r.fuel_max or 0)
    if r.active then agg.reactors.active=agg.reactors.active+1 end
  end
  for _,t in ipairs(turbines) do
    agg.turbines.prod=agg.turbines.prod+(t.prod or 0)
    agg.turbines.rpm=agg.turbines.rpm+(t.rpm or 0)
    agg.turbines.flow=agg.turbines.flow+(t.flow or 0)
    agg.turbines.flow_max=agg.turbines.flow_max+(t.flow_max or 0)
    if t.active then agg.turbines.active=agg.turbines.active+1 end
  end
  return reactors,turbines,agg
end

-- ── HELLO / ACK / TELEM
local function say_hello() rednet.broadcast({type="HELLO", caps={reactor=true,turbine=true}, _auth=CFG.auth_token}) end
local function expect_ack(timeout)
  local id,msg=rednet.receive(timeout or 2)
  if id and type(msg)=="table" and msg.type=="HELLO_ACK" and msg._auth==CFG.auth_token then MASTER_ID=id; last_ack=now_ms(); return true end
  return false
end
local function send_telem()
  if not MASTER_ID then return end
  local reactors,turbines,agg = collect_telem()
  rednet.send(MASTER_ID, {type="TELEM", caps={reactors=#DEV.reactors,turbines=#DEV.turbines}, telem={reactors=reactors,turbines=turbines,agg=agg}, _auth=CFG.auth_token})
end

-- ── CMD Handling (Whitelist)
local ALLOWED = {
  reactor = { setActive = true },
  turbine = { setInductorEngaged = true, setFluidFlowRateMax = true },
}

local function cmd_ack(to, ok, msg, extra)
  local payload = {type="CMD_ACK", ok=ok, msg=msg, _auth=CFG.auth_token}
  if extra then for k,v in pairs(extra) do payload[k]=v end end
  if to then rednet.send(to, payload) else rednet.broadcast(payload) end
end

-- Auto-Tune Flow für Turbine: bringe RPM nahe target_rpm (z. B. 1800)
local function autotune_turbine(name, target_rpm, timeout_s)
  target_rpm = target_rpm or 1800
  timeout_s = timeout_s or 25
  local p = peripheral.wrap(name); if not p then return false, "not found" end
  local cur = safe_call(p,"getFluidFlowRateMax") or 1000
  local best = cur
  local best_err = math.huge
  local step = 400
  local t0 = os.clock()
  while os.clock() - t0 < timeout_s do
    safe_call(p,"setFluidFlowRateMax", math.max(0, math.floor(cur)))
    os.sleep(1.2) -- settle
    local rpm = safe_call(p,"getRotorSpeed") or 0
    local err = math.abs(target_rpm - rpm)
    if err < best_err then best_err, best = err, cur end
    if err <= 15 then break end
    -- Richtungsanpassung
    if rpm < target_rpm then
      cur = cur + step
    else
      cur = math.max(0, cur - step)
    end
    step = math.max(25, math.floor(step * 0.55))
  end
  safe_call(p,"setFluidFlowRateMax", math.max(0, math.floor(best)))
  return true, ("flow_max="..tostring(math.floor(best))..", err="..tostring(math.floor(best_err)))
end

local function handle_cmd(id, msg)
  if msg._auth ~= CFG.auth_token then return end
  local target, name, cmd, value = msg.target, msg.name, msg.cmd, msg.value
  if target=="reactor" then
    if not (ALLOWED.reactor[cmd]) then cmd_ack(id,false,"not allowed"); return end
    local p = peripheral.wrap(name)
    if not p then cmd_ack(id,false,"reactor not found"); return end
    local ok = safe_call(p, cmd, value)
    cmd_ack(id, ok~=nil, ok and "OK" or "call failed", {name=name, cmd=cmd, value=value})
  elseif target=="turbine" then
    if cmd=="autotune" then
      local ok,info = autotune_turbine(name, tonumber(msg.target_rpm) or 1800, tonumber(msg.timeout_s) or 25)
      cmd_ack(id, ok, info or "", {name=name, cmd="autotune"})
      return
    end
    if not (ALLOWED.turbine[cmd]) then cmd_ack(id,false,"not allowed"); return end
    local p = peripheral.wrap(name)
    if not p then cmd_ack(id,false,"turbine not found"); return end
    local ok = safe_call(p, cmd, value)
    cmd_ack(id, ok~=nil, ok and "OK" or "call failed", {name=name, cmd=cmd, value=value})
  end
end

-- ── Loops
local function rx_loop()
  while true do
    local id,msg = rednet.receive(1)
    if id and type(msg)=="table" then
      if msg._auth==CFG.auth_token and msg.type=="HELLO_ACK" then MASTER_ID=id; last_ack=now_ms()
      elseif msg._auth==CFG.auth_token and msg.type=="CMD" then handle_cmd(id,msg) end
    end
  end
end

local function core_loop()
  say_hello(); expect_ack(2); cls()
  println(("Node online | Modem:%s  Monitor:%s"):format(CFG.modem_side, CFG.monitor_side or "-"))
  local t_last=0
  while true do
    if not MASTER_ID or (now_ms()-last_ack) > 15000 then say_hello(); expect_ack(2) end
    if os.clock()-t_last >= (CFG.telem_interval or 2) then send_telem(); t_last=os.clock() end
    os.sleep(0.1)
  end
end

local function keys_loop()
  while true do
    local e,k = os.pullEvent("key")
    if k==keys.f5 then scan_devices()
    elseif k==keys.q or k==keys.escape then cls(); print("Node beendet."); return end
  end
end

-- ── Run
cls(); println("Starte node…")
parallel.waitForAny(rx_loop, core_loop, keys_loop)
