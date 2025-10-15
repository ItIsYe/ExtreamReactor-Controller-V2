-- master.lua — Phase C: Adaptive Ramp + Thermal Band + Logging/Graphs
package.path = package.path .. ";/xreactor/?.lua;/xreactor/shared/?.lua;/xreactor/?/init.lua"

local STO = require("storage")
local POL = require("policy")
local PRO = require("protocol")
local FUEL= require("fuel_core")
local WST = require("waste_core")
local SEQ = require("sequencer")
local PLB = require("playbooks")
local MX  = require("matrix_core")
local LOG = require("logger")

local CFG_PATH = "/xreactor/config_master.lua"
local CFG={}
do
  local ok, def=pcall(require,"config_master"); if ok and type(def)=="table" then for k,v in pairs(def) do CFG[k]=v end end
  local j = STO.load_json(CFG_PATH, nil); if type(j)=="table" then for k,v in pairs(j) do CFG[k]=v end end
end

assert(peripheral.getType(CFG.modem_side)=="modem", "No modem on "..tostring(CFG.modem_side))
PRO.open(CFG.modem_side)
local MASTER_ID = os.getComputerID()
local MASTER_GEN = math.floor(os.epoch("utc")/1000) % 2147483647

-- monitor
local function pick_monitor()
  if CFG.monitor_name and peripheral.hasType(CFG.monitor_name,"monitor") then return peripheral.wrap(CFG.monitor_name) end
  local best, bestArea
  for _,n in ipairs(peripheral.getNames()) do
    if peripheral.hasType(n,"monitor") then
      local m = peripheral.wrap(n); local w,h = m.getSize(); local area = w*h
      if not best or area > bestArea then best, bestArea = m, area end
    end
  end
  return best
end
local MON = pick_monitor()
if MON then pcall(function() MON.setTextScale(CFG.text_scale or 0.5); MON.setBackgroundColor(colors.black); MON.setTextColor(colors.white); MON.clear() end) end
local function with_mon(fn) if MON then local old=term.redirect(MON); fn(); term.redirect(old) end end

-- state
local nodes = {} -- [id] = { last=ms, mode, telem={...}, offline=false }
local LAST_DECISION = {reactor_on=false,turbines_on=false}

-- logging (ring buffers)
local RB = {
  soc   = LOG.new(CFG.log_capacity or 180),
  temp  = LOG.new(CFG.log_capacity or 180),
  rpm   = LOG.new(CFG.log_capacity or 180),
  steam = LOG.new(CFG.log_capacity or 180),
}
local function now_ms() return os.epoch("utc") end
local function now_s() return math.floor(now_ms()/1000) end

-- tx helper
local function broadcast_cmd(reactor_list)
  local cmd = PRO.msg_command_setpoints(MASTER_GEN, CFG.auth_token, reactor_list, nil)
  for nid,_ in pairs(nodes) do PRO.send(nid, cmd) end
end

-- rx
local function rx_loop()
  while true do
    local id, msg = rednet.receive(nil, 1.0)
    if id and type(msg)=="table" and msg._auth == CFG.auth_token then
      if msg.type=="HELLO" then
        nodes[id]=nodes[id] or {}
        nodes[id].last = now_ms()
        nodes[id].mode = nodes[id].mode or "REMOTE_CONTROL"
        PRO.send(id, PRO.msg_hello_ack(MASTER_ID, MASTER_GEN, CFG, CFG.auth_token))
      elseif msg.type=="TELEM" then
        nodes[id]=nodes[id] or {}
        nodes[id].last = now_ms()
        nodes[id].mode = msg.mode
        nodes[id].telem = msg
      elseif msg.type=="FUEL_CONFIRM" or msg.type=="FUEL_DENY" or msg.type=="FUEL_DONE" or
             msg.type=="WASTE_CONFIRM" or msg.type=="WASTE_DENY" or msg.type=="WASTE_DONE" or
             msg.type=="REPROC_CONFIRM" or msg.type=="REPROC_DENY" or msg.type=="REPROC_DONE" then
        FUEL.on_supply_msg(CFG, msg); WST.on_supply_msg(CFG, msg)
      end
    end
    for nid,n in pairs(nodes) do
      local age = (now_ms() - (n.last or 0))/1000
      n.offline = age > (CFG.offline_threshold or 30)
    end
  end
end

-- collect a coarse reactor view + a representative temp/rpm/steam for logging
local function collect_snapshot()
  local reactors_any, temp, rpm, steam = nil, nil, nil, nil
  for _,n in pairs(nodes) do
    if n.telem then
      if n.telem.reactors and #n.telem.reactors>0 then
        reactors_any = reactors_any or n.telem.reactors
        local R = n.telem.reactors[1]
        temp  = temp  or R.temp
        rpm   = rpm   or R.rpm_avg
        steam = steam or R.steam_sum
      end
    end
  end
  return reactors_any, temp, rpm, steam
end

-- policy + adaptive + thermal
local function compute_reactors_setpoints()
  -- SoC aus Nodes aggregieren
  local soc = MX.read_soc_from_nodes(nodes) or 0.5
  -- Trend updaten → adaptiver Faktor
  local trend = MX.update_trend(CFG, soc)
  local adaptF = MX.adapt_factor(CFG)

  -- Basispolicy
  local d = POL.decide(soc, LAST_DECISION, CFG)
  LAST_DECISION = {reactor_on=d.reactor_on, turbines_on=d.turbines_on}

  -- Thermische Korrektur (verwende erste gefundene Reaktor-Temperatur)
  local reactors_any, temp = collect_snapshot()
  local thermF = 1.0
  if reactors_any and reactors_any[1] and reactors_any[1].temp then
    thermF = MX.thermal_correction(CFG, reactors_any[1].temp)
  end

  -- kombiniere Faktoren (klemmen auf sinnvollen Bereich)
  local base = d.steam_target or (CFG.steam_max or 2000)
  local target = math.floor(base * adaptF * thermF + 0.5)
  if target < math.floor((CFG.steam_max or 2000) * (CFG.adapt_min_factor or 0.25)) then
    target = math.floor((CFG.steam_max or 2000) * (CFG.adapt_min_factor or 0.25))
  end
  if target > (CFG.steam_max or 2000) then target = CFG.steam_max or 2000 end

  -- Logging push
  LOG.push(RB.soc,   {t=now_s(), v=soc})
  LOG.push(RB.temp,  {t=now_s(), v=temp})
  LOG.push(RB.rpm,   {t=now_s(), v=reactors_any and reactors_any[1] and reactors_any[1].rpm_avg or nil})
  LOG.push(RB.steam, {t=now_s(), v=target})

  return { {reactor_id="GLOBAL", reactor_on=d.reactor_on, steam_target=target, rpm_target=d.target_rpm} }
end

local function setpoints_driver()
  SEQ.tick(CFG, function(rlist) broadcast_cmd(rlist) end)
  local ov = PLB.evaluate(CFG, nodes)
  if ov and #ov>0 then broadcast_cmd(ov); return end
  local rlist = compute_reactors_setpoints()
  broadcast_cmd(rlist)
end

local function setpoints_loop()
  while true do
    setpoints_driver()
    sleep(CFG.setpoint_interval or 5)
  end
end

local function beacon_loop()
  while true do
    local b = PRO.msg_beacon(MASTER_ID, MASTER_GEN, CFG.auth_token)
    PRO.broadcast(b)
    sleep(CFG.beacon_interval or 5)
  end
end

local function supply_loop()
  while true do
    local reactors_any = nil
    for _,n in pairs(nodes) do
      if n.telem and n.telem.reactors and #n.telem.reactors>0 then reactors_any = n.telem.reactors; break end
    end
    if reactors_any then
      FUEL.tick(CFG, reactors_any, function(msg) PRO.broadcast(msg) end)
      WST.tick(CFG, reactors_any, function(msg) PRO.broadcast(msg) end)
      if CFG.reproc_enabled then WST.request_reproc(CFG, CFG.waste_drain_batch or 64, function(msg) PRO.broadcast(msg) end) end
    end
    sleep(3)
  end
end

-- UI: Overview + Mini-Graphs (SOC/Temp/Steam)
local function draw_graph(x, y, w, h, rb, vmin, vmax, label)
  local oldbg, oldfg = term.getBackgroundColor(), term.getTextColor()
  term.setBackgroundColor(colors.gray)
  for yy=0,h-1 do term.setCursorPos(x, y+yy); term.write(string.rep(" ", w)) end
  term.setBackgroundColor(oldbg)
  local pts = {}
  for row in LOG.iter(rb) do
    if row and type(row.v)=="number" then table.insert(pts, row.v) end
  end
  if #pts>0 then
    vmin = vmin or math.huge; vmax = vmax or -math.huge
    for _,v in ipairs(pts) do if v<vmin then vmin=v end; if v>vmax then vmax=v end end
    if vmin==vmax then vmax=vmax+1 end
    local step = math.max(1, math.floor(#pts / w))
    local xi, idx = 0, 1
    while idx <= #pts and xi < w do
      local v = pts[idx]
      local norm = (v - vmin) / (vmax - vmin)
      local hh = math.max(1, math.floor(norm * (h-1) + 0.5))
      for yy=0,hh-1 do
        term.setCursorPos(x+xi, y + (h-1-yy))
        term.setBackgroundColor(colors.green)
        term.write(" ")
      end
      xi = xi + 1
      idx = idx + step
    end
  end
  term.setBackgroundColor(oldbg); term.setTextColor(colors.white)
  term.setCursorPos(x, y-1); term.write(label or "")
end

local function draw()
  with_mon(function()
    term.setBackgroundColor(colors.black); term.setTextColor(colors.white); term.clear()
    term.setCursorPos(1,1); term.write(("Master #%d gen %d"):format(MASTER_ID, MASTER_GEN))
    term.setCursorPos(1,2); term.write(("Nodes: %d"):format((function() local c=0 for _ in pairs(nodes) do c=c+1 end return c end)()))

    local y=4
    for nid,n in pairs(nodes) do
      local status = n.offline and "OFFLINE" or (n.mode or "-")
      local color = n.offline and colors.red or (n.mode=="LOCAL_CONTROL" and colors.blue or (n.mode=="MASTER_LOSS_GRACE" and colors.orange or colors.green))
      term.setCursorPos(1,y); term.setTextColor(color); term.write(("#%d  %s"):format(nid, status)); term.setTextColor(colors.white)
      if n.telem and n.telem.reactors and n.telem.reactors[1] then
        local R = n.telem.reactors[1]
        term.setCursorPos(18,y); term.write(("R:%s Fuel:%s%% Waste:%s%% Temp:%s Steam~: %s"):format(
          tostring(R.reactor_id or "?"),
          (R.fuel_pct and math.floor(R.fuel_pct*100+0.5) or "-"),
          (R.waste_pct and math.floor(R.waste_pct*100+0.5) or "-"),
          (R.temp and math.floor(R.temp+0.5) or "-"),
          R.steam_sum or "-"
        ))
      end
      y=y+1
    end

    -- Mini-Graphs rechts/unten
    local W,H = term.getSize()
    local gw, gh = math.floor(W*0.48), math.floor(H*0.28)
    local gx = W - gw + 1
    draw_graph(gx, 4, gw, gh, RB.soc, 0, 1, "SoC")
    draw_graph(gx, 6+gh, gw, gh, RB.temp, nil, nil, "Temp")
    draw_graph(gx, 8+gh*2, gw, gh, RB.steam, nil, nil, "Steam tgt")

    -- optional: persist logs gelegentlich
    if (now_s() % 30) == 0 then
      LOG.flush(CFG.log_path or "/xreactor/logs/master_timeseries.json", {
        soc=RB.soc, temp=RB.temp, rpm=RB.rpm, steam=RB.steam
      })
    end
  end)
end

local function draw_loop() while true do draw(); sleep(1) end end

print("Master Phase C starting…")
SEQ.reset()
parallel.waitForAny(rx_loop, beacon_loop, setpoints_loop, supply_loop, draw_loop)
