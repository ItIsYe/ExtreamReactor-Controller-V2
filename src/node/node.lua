-- node.lua — Phase A: telem + local control + basic safety + UI skeleton
package.path = package.path .. ";/xreactor/?.lua;/xreactor/shared/?.lua;/xreactor/?/init.lua"

local STO = require("storage")
local DEV = require("devices")
local PRO = require("protocol")
local POL = require("policy")

local CFG_PATH = "/xreactor/config_node.lua"
local CFG = {}
do
  local ok, def = pcall(require,"config_node")
  if ok and type(def)=="table" then for k,v in pairs(def) do CFG[k]=v end end
  local j = STO.load_json(CFG_PATH, nil); if type(j)=="table" then for k,v in pairs(j) do CFG[k]=v end end
end

-- open comms
assert(peripheral.getType(CFG.modem_comm)=="modem", "No modem on "..tostring(CFG.modem_comm))
PRO.open(CFG.modem_comm)

-- wired must be present (enabled in-world)
assert(peripheral.getType(CFG.wired_side)=="modem", "No wired modem on "..tostring(CFG.wired_side))

-- monitor (optional)
local MON
if peripheral.hasType(CFG.monitor_side, "monitor") then
  MON = peripheral.wrap(CFG.monitor_side)
  pcall(function() MON.setTextScale(0.5); MON.setBackgroundColor(colors.black); MON.setTextColor(colors.white); MON.clear() end)
end
local function with_mon(fn) if MON then local old=term.redirect(MON); fn(); term.redirect(old) end end

-- discover
DEV.discover()

-- state
local master_id=nil
local master_generation=0
local last_master_seen=os.clock()
local mode="REMOTE_CONTROL" -- REMOTE_CONTROL | MASTER_LOSS_GRACE | LOCAL_CONTROL
local grace_deadline=nil
local LAST_DECISION={reactor_on=false,turbines_on=false}

-- apply setpoints (best effort per all detected reactors/turbines)
local function apply_setpoints(dec)
  -- reactors
  for _,R in ipairs(DEV.get_state().reactors) do
    DEV.reactor_set_active(R.dev, dec.reactor_on)
  end
  -- turbines → production = inductor engaged when ON
  for _,T in ipairs(DEV.get_state().turbines) do
    DEV.turbine_set_inductor(T.dev, dec.turbines_on)
  end
end

-- telemetry build (reactor-centric aggregates)
local function make_telem()
  local reactors = {}
  for _,r in ipairs(DEV.read_reactors()) do
    table.insert(reactors, {
      reactor_id = r.name,
      temp = r.temp, fuel=r.fuel, fuel_cap=r.fuel_cap, fuel_pct=r.fuel_pct,
      waste=r.waste, burn_rate=r.burn_rate,
      -- aggregate turbines assigned to this reactor if mapping exists:
      rpm_avg=0, steam_sum=0, turbine_count=0,
    })
  end

  local rpm, steam, tcnt = DEV.read_turbines()
  -- (Phase A: simple totals, later per-reactor mapping distribution)
  if #reactors==0 then
    reactors = { {reactor_id="UNKNOWN", temp=nil, fuel=nil, fuel_cap=nil, fuel_pct=nil, waste=nil, burn_rate=nil,
                  rpm_avg=math.floor(rpm+0.5), steam_sum=math.floor(steam+0.5), turbine_count=tcnt } }
  else
    -- put totals into first reactor as coarse view (Phase A)
    reactors[1].rpm_avg = math.floor(rpm+0.5)
    reactors[1].steam_sum= math.floor(steam+0.5)
    reactors[1].turbine_count = tcnt
  end

  return {
    type="TELEM",
    mode=mode,
    reactors=reactors,
    ts=os.epoch("utc"),
    _auth=CFG.auth_token,
  }
end

-- local policy (when LOCAL_CONTROL)
local function local_policy_tick()
  -- best-effort SoC (battery/matrix if present locally)
  local soc = DEV.read_soc()
  local d = POL.decide(soc, LAST_DECISION, { -- use defaults for Phase A
    soc_low=0.30, soc_high=0.85, hysteresis=0.03, rpm_target=1800, steam_max=2000
  })
  LAST_DECISION = {reactor_on=d.reactor_on, turbines_on=d.turbines_on}
  apply_setpoints(d)
end

-- UI skeleton
local function draw()
  with_mon(function()
    term.setBackgroundColor(colors.black); term.setTextColor(colors.white); term.clear()
    local w,h = term.getSize()
    term.setCursorPos(1,1); term.write((CFG.node_title or "Node").." | "..mode)
    term.setCursorPos(1,2); term.write("Master: "..(master_id and ("#"..master_id.." gen "..master_generation) or "search…"))

    local reactors = DEV.read_reactors()
    local y=4
    if #reactors==0 then
      term.setCursorPos(1,y); term.write("No reactor detected (wired top?)")
      return
    end
    for _,r in ipairs(reactors) do
      local fuel_pct = (r.fuel_cap and r.fuel_cap>0) and (r.fuel/r.fuel_cap) or 0
      term.setCursorPos(1,y);   term.write(string.format("%s  T:%s  Fuel:%s/%s  Waste:%s",
        r.name, r.temp and math.floor(r.temp+0.5).."C" or "-", r.fuel or "-", r.fuel_cap or "-", r.waste or "-"))
      y=y+1
      local bw = math.max(10, w-12)
      term.setCursorPos(1,y); term.write("Fuel: ")
      term.setBackgroundColor(colors.gray); term.write(string.rep(" ", bw))
      local filled = math.floor(bw*math.max(0, math.min(1, fuel_pct)) + 0.5)
      term.setCursorPos(8,y); term.setBackgroundColor(colors.green); if filled>0 then term.write(string.rep(" ", filled)) end
      term.setBackgroundColor(colors.black); term.write(string.format(" %3d%%", math.floor(fuel_pct*100+0.5)))
      y=y+2
    end
  end)
end

-- loops
local function rx_loop()
  while true do
    local id, msg = rednet.receive(nil, 1.0)
    if id and type(msg)=="table" and msg._auth == CFG.auth_token then
      if msg.type=="HELLO_ACK" then
        master_id = msg.master_id; master_generation = msg.master_generation; last_master_seen=os.clock()
      elseif msg.type=="BEACON" then
        if msg.master_generation >= master_generation then
          master_id = msg.master_id; master_generation = msg.master_generation; last_master_seen=os.clock()
        end
      elseif msg.type=="COMMAND" and msg.action=="SETPOINTS" then
        if (msg.master_generation or 0) >= master_generation then
          master_generation = msg.master_generation; last_master_seen=os.clock()
          -- Phase A: translate single global decision to on/off for all hardware
          local any = msg.reactors and msg.reactors[1]
          if any then
            LAST_DECISION = {reactor_on = any.reactor_on, turbines_on = (any.reactor_on==true)}
            apply_setpoints({reactor_on=any.reactor_on, turbines_on=(any.reactor_on==true)})
          end
        end
      elseif msg.type=="DISCOVER" then
        DEV.discover()
      end
    end
  end
end

local function hello_loop()
  while true do
    PRO.broadcast(PRO.msg_hello(CFG))
    sleep(20)
  end
end

local function telem_loop()
  while true do
    local t = make_telem()
    if master_id then PRO.send(master_id, t) else PRO.broadcast(t) end
    sleep(CFG.update or 2)
  end
end

local function mode_loop()
  local timeout = 10
  while true do
    local since = os.clock() - last_master_seen
    if since <= timeout then
      if mode ~= "REMOTE_CONTROL" then mode="REMOTE_CONTROL" end
      grace_deadline = nil
    else
      if mode=="REMOTE_CONTROL" then
        mode="MASTER_LOSS_GRACE"; grace_deadline = os.clock() + (CFG.grace_duration or 90)
      elseif mode=="MASTER_LOSS_GRACE" then
        if os.clock() >= (grace_deadline or 0) then mode="LOCAL_CONTROL" end
      elseif mode=="LOCAL_CONTROL" then
        local_policy_tick()
      end
    end
    sleep(0.5)
  end
end

local function draw_loop() while true do draw(); sleep(1) end end

print("Node starting…")
DEV.discover()
parallel.waitForAny(rx_loop, hello_loop, telem_loop, mode_loop, draw_loop)
