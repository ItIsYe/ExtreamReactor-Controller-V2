-- master.lua — Phase B: integrates fuel/waste cores, sequencer, playbooks
package.path = package.path .. ";/xreactor/?.lua;/xreactor/shared/?.lua;/xreactor/?/init.lua"

local STO = require("storage")
local POL = require("policy")
local PRO = require("protocol")
local FUEL= require("fuel_core")
local WST = require("waste_core")
local SEQ = require("sequencer")
local PLB = require("playbooks")

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
local function now() return os.epoch("utc") end

-- tx helpers
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
        nodes[id].last = now()
        nodes[id].mode = nodes[id].mode or "REMOTE_CONTROL"
        PRO.send(id, PRO.msg_hello_ack(MASTER_ID, MASTER_GEN, CFG, CFG.auth_token))
      elseif msg.type=="TELEM" then
        nodes[id]=nodes[id] or {}
        nodes[id].last = now()
        nodes[id].mode = msg.mode
        nodes[id].telem = msg
      elseif msg.type=="FUEL_CONFIRM" or msg.type=="FUEL_DENY" or msg.type=="FUEL_DONE" or
             msg.type=="WASTE_CONFIRM" or msg.type=="WASTE_DENY" or msg.type=="WASTE_DONE" or
             msg.type=="REPROC_CONFIRM" or msg.type=="REPROC_DENY" or msg.type=="REPROC_DONE" then
        -- supply feedback (optional tracking)
        FUEL.on_supply_msg(CFG, msg); WST.on_supply_msg(CFG, msg)
      end
    end
    -- timeouts
    for nid,n in pairs(nodes) do
      local age = (now() - (n.last or 0))/1000
      n.offline = age > (CFG.offline_threshold or 30)
    end
  end
end

-- policy + setpoints
local function read_main_soc()
  -- (Phase B: still neutral 0.5; Matrix integration comes in Phase C)
  return 0.5
end

local function compute_reactors_setpoints()
  local soc = read_main_soc()
  local d = POL.decide(soc, LAST_DECISION, CFG)
  LAST_DECISION = {reactor_on=d.reactor_on, turbines_on=d.turbines_on}
  return { {reactor_id="GLOBAL", reactor_on=d.reactor_on, steam_target=d.steam_target, rpm_target=d.target_rpm} }
end

local function setpoints_driver()
  -- sequencing tick (on startup it steps through staged plan)
  SEQ.tick(CFG, function(rlist) broadcast_cmd(rlist) end)

  -- safety playbooks (may produce override)
  local ov = PLB.evaluate(CFG, nodes)
  if ov and #ov>0 then broadcast_cmd(ov); return end

  -- normal policy-driven setpoints
  local rlist = compute_reactors_setpoints()
  broadcast_cmd(rlist)
end

local function setpoints_loop()
  while true do
    setpoints_driver()
    sleep(CFG.setpoint_interval or 5)
  end
end

-- beacon
local function beacon_loop()
  while true do
    local b = PRO.msg_beacon(MASTER_ID, MASTER_GEN, CFG.auth_token)
    PRO.broadcast(b)
    sleep(CFG.beacon_interval or 5)
  end
end

-- fuel+waste scan
local function supply_loop()
  while true do
    -- collect a merged reactor view across nodes (Phase B coarse: first node with data)
    local reactors_any = nil
    for _,n in pairs(nodes) do
      if n.telem and n.telem.reactors and #n.telem.reactors>0 then reactors_any = n.telem.reactors; break end
    end

    if reactors_any then
      -- Fuel manager
      FUEL.tick(CFG, reactors_any, function(msg)
        if CFG.fuel_request_type=="rednet" then PRO.broadcast(msg) else PRO.broadcast(msg) end
      end)

      -- Waste manager
      WST.tick(CFG, reactors_any, function(msg) PRO.broadcast(msg) end)
      -- Optionally also push a reproc request opportunistically
      if CFG.reproc_enabled then WST.request_reproc(CFG, CFG.waste_drain_batch or 64, function(msg) PRO.broadcast(msg) end) end
    end
    sleep(3)
  end
end

-- UI
local function draw()
  with_mon(function()
    term.setBackgroundColor(colors.black); term.setTextColor(colors.white); term.clear()
    term.setCursorPos(1,1); term.write(("Master #%d gen %d"):format(MASTER_ID, MASTER_GEN))
    local y=3
    for nid,n in pairs(nodes) do
      local status = n.offline and "OFFLINE" or (n.mode or "-")
      local color = n.offline and colors.red or (n.mode=="LOCAL_CONTROL" and colors.blue or (n.mode=="MASTER_LOSS_GRACE" and colors.orange or colors.green))
      term.setCursorPos(1,y); term.setTextColor(color); term.write(("#%d  %s"):format(nid, status)); term.setTextColor(colors.white)

      if n.telem and n.telem.reactors and n.telem.reactors[1] then
        local R = n.telem.reactors[1]
        term.setCursorPos(18,y); term.write(("R:%s Fuel:%s%% Waste:%s%% Temp:%s Steam:%s RPM:%s"):format(
          tostring(R.reactor_id or "?"),
          (R.fuel_pct and math.floor(R.fuel_pct*100+0.5) or "-"),
          (R.waste_pct and math.floor(R.waste_pct*100+0.5) or "-"),
          (R.temp and math.floor(R.temp+0.5) or "-"),
          R.steam_sum or "-", R.rpm_avg or "-"
        ))
      end
      y=y+1
    end
  end)
end

local function draw_loop() while true do draw(); sleep(1) end end

print("Master Phase B starting…")
SEQ.reset()
parallel.waitForAny(rx_loop, beacon_loop, setpoints_loop, supply_loop, draw_loop)
