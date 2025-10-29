--========================================================
-- XReactor • NODE
-- - Scannt Reaktoren/Turbinen via Wired/remote (per Modem)
-- - Sendet zyklisch TELEM an Master, empfängt CMD/AutoTune
-- - GUI: Node-Dashboard (frei zuweisbarer Monitor, persistiert)
-- Abhängigkeiten: /xreactor/shared/gui.lua, config_node.lua
--========================================================

-- ---------- Config ----------
local CFG = {
  modem_side    = "right",   -- Wireless/Rednet zum Master
  wired_side    = "top",     -- Wired-Modem zu Reaktoren/Turbinen
  monitor_view  = nil,       -- z.B. "monitor_0" (frei konfigurierbar)
  auth_token    = "xreactor",
  telem_interval= 1.0,
  hello_interval= 5.0,
}
do
  local ok,t = pcall(dofile,"/xreactor/config_node.lua")
  if ok and type(t)=="table" then for k,v in pairs(t) do CFG[k]=v end end
end

local UI_PATH = "/xreactor/ui_node.json"
local function load_json(p)
  if not fs.exists(p) then return nil end
  local f = fs.open(p,"r"); local s=f.readAll() or ""; f.close()
  local ok, tbl = pcall(textutils.unserializeJSON, s)
  return ok and tbl or nil
end
local function save_json(p, tbl)
  local s = textutils.serializeJSON(tbl, true)
  fs.makeDir(fs.getDir(p))
  local f = fs.open(p,"w"); f.write(s or "{}"); f.close()
end

do
  local ui = load_json(UI_PATH)
  if ui and ui.monitor_view then CFG.monitor_view = ui.monitor_view end
end

-- ---------- Peripherals ----------
assert(peripheral.getType(CFG.modem_side)=="modem","Kein Wireless-Modem an "..tostring(CFG.modem_side))
rednet.open(CFG.modem_side)

local wired = nil
if CFG.wired_side and peripheral.getType(CFG.wired_side)=="modem" then
  wired = peripheral.wrap(CFG.wired_side)
end

-- ---------- Device Scan ----------
local DEV = {reactors={}, turbines={}}

local function is_reactor(t) return t=="BigReactors-Reactor" or t=="BiggerReactors_Reactor" end
local function is_turbine(t) return t=="BigReactors-Turbine" or t=="BiggerReactors_Turbine" end

local function scan_devices()
  DEV.reactors, DEV.turbines = {}, {}
  if wired and wired.getNamesRemote then
    for _,name in ipairs(wired.getNamesRemote()) do
      local typ = peripheral.getType(name)
      if is_reactor(typ) then table.insert(DEV.reactors, name)
      elseif is_turbine(typ) then table.insert(DEV.turbines, name) end
    end
  else
    -- Fallback: lokale Peripherals durchsuchen
    for _,name in ipairs(peripheral.getNames()) do
      local typ = peripheral.getType(name)
      if is_reactor(typ) then table.insert(DEV.reactors, name)
      elseif is_turbine(typ) then table.insert(DEV.turbines, name) end
    end
  end
end
scan_devices()

-- ---------- Safe peripheral calls ----------
local function pcallm(p, m, ...)
  if not p or type(p[m])~="function" then return nil end
  local ok,res = pcall(p[m], ...)
  if ok then return res end
  return nil
end

-- ---------- Read Telemetry ----------
local function read_reactor(name)
  local p = peripheral.wrap(name); if not p then return nil end
  return {
    name=name,
    active=pcallm(p,"getActive") or false,
    energy=pcallm(p,"getEnergyStored") or 0,
    fuel=pcallm(p,"getFuelAmount") or 0,
    fuel_max=pcallm(p,"getFuelAmountMax") or 0,
    temp=pcallm(p,"getCasingTemperature") or 0,
    hot=pcallm(p,"getHotFluidProducedLastTick") or 0,
  }
end
local function read_turbine(name)
  local p = peripheral.wrap(name); if not p then return nil end
  return {
    name=name,
    active=pcallm(p,"getActive") or false,
    rpm=pcallm(p,"getRotorSpeed") or 0,
    flow=pcallm(p,"getFluidFlowRate") or 0,
    flow_max=pcallm(p,"getFluidFlowRateMax") or 0,
    prod=pcallm(p,"getEnergyProducedLastTick") or 0,
    inductor=pcallm(p,"getInductorEngaged") or false,
    energy=pcallm(p,"getEnergyStored") or 0,
  }
end

local function collect_telem()
  local reactors,turbines={},{}
  for _,n in ipairs(DEV.reactors) do local r=read_reactor(n); if r then table.insert(reactors,r) end end
  for _,n in ipairs(DEV.turbines) do local t=read_turbine(n); if t then table.insert(turbines,t) end end
  local agg={reactors={count=#reactors,active=0,hot=0,energy=0,fuel=0,fuel_max=0}, turbines={count=#turbines,active=0,rpm=0,flow=0,flow_max=0,prod=0}}
  for _,r in ipairs(reactors) do
    if r.active then agg.reactors.active=agg.reactors.active+1 end
    agg.reactors.hot=agg.reactors.hot+(r.hot or 0)
    agg.reactors.energy=agg.reactors.energy+(r.energy or 0)
    agg.reactors.fuel=agg.reactors.fuel+(r.fuel or 0)
    agg.reactors.fuel_max=agg.reactors.fuel_max+(r.fuel_max or 0)
  end
  for _,t in ipairs(turbines) do
    if t.active then agg.turbines.active=agg.turbines.active+1 end
    agg.turbines.prod=agg.turbines.prod+(t.prod or 0)
    agg.turbines.rpm=agg.turbines.rpm+(t.rpm or 0)
    agg.turbines.flow=agg.turbines.flow+(t.flow or 0)
    agg.turbines.flow_max=agg.turbines.flow_max+(t.flow_max or 0)
  end
  return reactors,turbines,agg
end

-- ---------- HELLO / TELEM ----------
local MASTER_ID, last_ack = nil, 0
local function hello()
  rednet.broadcast({type="HELLO", caps={reactor=true,turbine=true}, _auth=CFG.auth_token})
end
local function expect_ack(timeout)
  local id,msg = rednet.receive(timeout or 2)
  if id and type(msg)=="table" and msg.type=="HELLO_ACK" and msg._auth==CFG.auth_token then
    MASTER_ID = id; last_ack = os.epoch("utc"); return true
  end
  return false
end
local function send_telem()
  if not MASTER_ID then return end
  local reactors,turbines,agg = collect_telem()
  rednet.send(MASTER_ID, {type="TELEM", telem={reactors=reactors,turbines=turbines,agg=agg}, _auth=CFG.auth_token})
end

-- ---------- CMD Handling ----------
local function cmd_ack(to, ok, msg, extra)
  local payload = {type="CMD_ACK", ok=ok, msg=msg, _auth=CFG.auth_token}
  if extra then for k,v in pairs(extra) do payload[k]=v end end
  if to then rednet.send(to, payload) else rednet.broadcast(payload) end
end

local function autotune_turbine(name, target_rpm, timeout_s)
  target_rpm = target_rpm or 1800
  timeout_s  = timeout_s or 25
  local p = peripheral.wrap(name); if not p then return false, "not found" end
  local cur = pcallm(p,"getFluidFlowRateMax") or 1000
  local best, best_err = cur, math.huge
  local step = 400
  local t0 = os.clock()
  while os.clock() - t0 < timeout_s do
    pcallm(p,"setFluidFlowRateMax", math.max(0, math.floor(cur)))
    os.sleep(1.2)
    local rpm = pcallm(p,"getRotorSpeed") or 0
    local err = math.abs((target_rpm) - rpm)
    if err < best_err then best_err, best = err, cur end
    if err <= 15 then break end
    if rpm < target_rpm then cur = cur + step else cur = math.max(0, cur - step) end
    step = math.max(25, math.floor(step*0.55))
  end
  pcallm(p,"setFluidFlowRateMax", math.max(0, math.floor(best)))
  return true, ("flow_max="..math.floor(best).." err="..math.floor(best_err))
end

local function handle_cmd(id, msg)
  if msg._auth ~= CFG.auth_token then return end
  local target, name, cmd, value = msg.target, msg.name, msg.cmd, msg.value
  if target=="reactor" then
    -- Wenn name nil: alle Reaktoren
    local list = (name and {name}) or DEV.reactors
    for _,n in ipairs(list) do
      local p=peripheral.wrap(n); if p then pcallm(p,cmd,value) end
    end
    cmd_ack(id,true,"reactor "..(cmd or "?"))
  elseif target=="turbine" then
    if cmd=="autotune" then
      local ok,info = autotune_turbine(name or DEV.turbines[1], tonumber(msg.target_rpm) or 1800, tonumber(msg.timeout_s) or 25)
      cmd_ack(id, ok, info or "")
      return
    end
    local list = (name and {name}) or DEV.turbines
    for _,n in ipairs(list) do
      local p=peripheral.wrap(n); if p then pcallm(p,cmd,value) end
    end
    cmd_ack(id,true,"turbine "..(cmd or "?"))
  end
end

-- ---------- GUI ----------
local ok_gui, GUI = pcall(require,"xreactor.shared.gui")
if not ok_gui then GUI = dofile("/xreactor/shared/gui.lua") end

local screen_node = (function()
  local s = GUI.mkScreen("node","Node ▢ Übersicht")
  local kvR = GUI.mkKV(2,3,30,"Reaktoren:", colors.cyan)
  local kvT = GUI.mkKV(2,4,30,"Turbinen:",  colors.cyan)
  local kvRPM=GUI.mkKV(2,6,30,"RPM∑:",     colors.lime)
  local kvSTM=GUI.mkKV(2,7,30,"Steam∑:",   colors.lime)
  local kvP  =GUI.mkKV(2,8,30,"Power/t:",  colors.lime)
  local bar  =GUI.mkBar(2,10,30, colors.lime)
  local btnM =GUI.mkButton(34,3,16,3,"Mon zuweisen", function()
    term.setBackgroundColor(colors.black); term.setTextColor(colors.white); term.clear()
    print("Monitor-Name eingeben (z.B. monitor_0). Leer = entfernen.")
    write("> "); local m = read()
    if m=="" then CFG.monitor_view=nil else CFG.monitor_view=m end
    save_json(UI_PATH, {monitor_view=CFG.monitor_view})
    print("Gespeichert. ENTER…"); read()
  end, colors.cyan)
  s:add(kvR); s:add(kvT); s:add(kvRPM); s:add(kvSTM); s:add(kvP); s:add(bar); s:add(btnM)
  s.onShow = function()
    local _,_,A = collect_telem()
    kvR.props.value = string.format("%d/%d act", A.reactors.active or 0, A.reactors.count or 0)
    kvT.props.value = string.format("%d/%d act", A.turbines.active or 0, A.turbines.count or 0)
    kvRPM.props.value = math.floor(A.turbines.rpm or 0)
    kvSTM.props.value = math.floor(A.turbines.flow or 0).." mB/t"
    kvP.props.value   = math.floor(A.turbines.prod or 0).." RF/t"
    bar.props.value   = math.min(1, (A.turbines.prod or 0)/200000) -- Demo-Skala
  end
  return s
end)()

local router = (function()
  local r = GUI.mkRouter({monitorName=CFG.monitor_view, textScale=0.5})
  r:register(screen_node)
  r:show("node")
  return r
end)()

if not router.monSurf then
  -- Kein Monitor zugewiesen: zeige im Terminal
  router = GUI.mkRouter({})
  router:register(screen_node)
  router:show("node")
end

-- ---------- Loops ----------
local function rx_loop()
  while true do
    local id,msg = rednet.receive(1)
    if id and type(msg)=="table" and msg._auth==CFG.auth_token then
      if msg.type=="HELLO_ACK" then
        MASTER_ID=id; last_ack=os.epoch("utc")
      elseif msg.type=="CMD" then
        handle_cmd(id,msg)
      end
    end
  end
end

local function core_loop()
  hello(); expect_ack(2)
  local t_hello=0; local t_telem=0
  while true do
    if os.clock()-t_hello >= CFG.hello_interval then hello(); expect_ack(2); t_hello=os.clock() end
    if os.clock()-t_telem >= CFG.telem_interval then send_telem(); t_telem=os.clock() end
    os.sleep(0.05)
  end
end

local function ui_loop()
  local t0=0
  while true do
    if os.clock()-t0 >= 0.25 then
      router:draw()
      t0=os.clock()
    end
    local e = {os.pullEventTimeout(0.05)}
    if e[1]=="monitor_touch" then
      local side,x,y=e[2],e[3],e[4]
      if router and router.monSurf and peripheral.getName(router.monSurf.t)==side then
        router:handleTouch(e[1], side, x, y)
      end
    elseif e[1]=="mouse_click" then
      router:handleTouch("mouse_click", e[2], e[3], e[4])
    end
  end
end

print(("Node gestartet | Modem:%s  Wired:%s  Monitor:%s")
  :format(CFG.modem_side, CFG.wired_side or "-", CFG.monitor_view or "-"))

parallel.waitForAny(rx_loop, core_loop, ui_loop)