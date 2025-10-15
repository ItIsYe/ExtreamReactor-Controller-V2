-- master.lua — Phase A: beacon, policy → setpoints, UI skeleton
package.path = package.path .. ";/xreactor/?.lua;/xreactor/shared/?.lua;/xreactor/?/init.lua"

local STO = require("storage")
local POL = require("policy")
local PRO = require("protocol")

local CFG_PATH = "/xreactor/config_master.lua"
local CFG={}
do
  local ok, def=pcall(require,"config_master"); if ok and type(def)=="table" then for k,v in pairs(def) do CFG[k]=v end end
  local j = STO.load_json(CFG_PATH, nil); if type(j)=="table" then for k,v in pairs(j) do CFG[k]=v end end
end

-- comms
assert(peripheral.getType(CFG.modem_side)=="modem", "No modem on "..tostring(CFG.modem_side))
PRO.open(CFG.modem_side)
local MASTER_ID = os.getComputerID()
local MASTER_GEN = math.floor(os.epoch("utc")/1000) % 2147483647 -- simple unique-ish gen per boot

-- monitor (auto-pick largest if none specified)
local function pick_monitor()
  if CFG.monitor_name and peripheral.hasType(CFG.monitor_name,"monitor") then
    return peripheral.wrap(CFG.monitor_name)
  end
  local best, bestArea
  for _,n in ipairs(peripheral.getNames()) do
    if peripheral.hasType(n,"monitor") then
      local m = peripheral.wrap(n)
      local w,h = m.getSize()
      local area = w*h
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

-- util
local function now() return os.epoch("utc") end

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
      end
    end

    -- timeout flags
    for nid,n in pairs(nodes) do
      local age = (now() - (n.last or 0))/1000
      n.offline = age > (CFG.offline_threshold or 30)
    end
  end
end

-- policy + setpoints
local function read_main_soc()
  -- Phase A: try to infer from any TELEM.soc (if provided later), else neutral 0.5
  return 0.5
end

local function compute_reactors_setpoints()
  local soc = read_main_soc()
  local d = POL.decide(soc, LAST_DECISION, CFG)
  LAST_DECISION = {reactor_on=d.reactor_on, turbines_on=d.turbines_on}
  -- Phase A: broadcast one global directive; later split per reactor
  return { {reactor_id="GLOBAL", reactor_on=d.reactor_on, steam_target=d.steam_target, rpm_target=d.target_rpm} }
end

local function push_setpoints_loop()
  while true do
    local rlist = compute_reactors_setpoints()
    local cmd = PRO.msg_command_setpoints(MASTER_GEN, CFG.auth_token, rlist, nil)
    for nid,_ in pairs(nodes) do PRO.send(nid, cmd) end
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

-- UI
local function draw()
  with_mon(function()
    term.setBackgroundColor(colors.black); term.setTextColor(colors.white); term.clear()
    term.setCursorPos(1,1); term.write(("Master #%d gen %d"):format(MASTER_ID, MASTER_GEN))
    term.setCursorPos(1,2); term.write(("Nodes: %d"):format((function() local c=0 for _ in pairs(nodes) do c=c+1 end return c end)()))
    local y=4
    for nid,n in pairs(nodes) do
      local status = n.offline and "OFFLINE" or (n.mode or "-")
      local color = n.offline and colors.red or (n.mode=="LOCAL_CONTROL" and colors.blue or (n.mode=="MASTER_LOSS_GRACE" and colors.orange or colors.green))
      term.setCursorPos(1,y); term.clearLine()
      term.setTextColor(color); term.write(("#%d  %s"):format(nid, status)); term.setTextColor(colors.white)
      if n.telem and n.telem.reactors and n.telem.reactors[1] then
        local R = n.telem.reactors[1]
        term.setCursorPos(18,y); term.write(("R:%s Fuel:%s%% Temp:%s Steam:%s RPM:%s"):format(
          tostring(R.reactor_id or "?"),
          (R.fuel_pct and math.floor(R.fuel_pct*100+0.5) or "-"),
          (R.temp and math.floor(R.temp+0.5) or "-"),
          R.steam_sum or "-", R.rpm_avg or "-"
        ))
      end
      y=y+1
    end
  end)
end

local function draw_loop() while true do draw(); sleep(1) end end

print("Master starting…")
parallel.waitForAny(rx_loop, beacon_loop, push_setpoints_loop, draw_loop)
