--==========================================================
-- XReactor ◈ MASTER (Leader/Display)
-- - empfängt HELLO/TELEM von Nodes (auth-basiert)
-- - sendet HELLO_ACK
-- - zeigt Aggregat + Node-Liste (live)
-- - optional Ausgabe auf Monitor (auto TextScale)
--==========================================================

-- ---- sichere require + Config ---------------------------------------------
local function try_require(name)
  local ok, mod = pcall(require, name)
  if ok then return mod end
end

local CFG = {
  modem_side       = "right",     -- Modem zum rednet
  monitor_side     = nil,         -- z.B. "left"|"right"|..., nil = nur PC
  auth_token       = "xreactor",  -- muss zu Node passen
  telem_timeout    = 15,          -- s bis Node „offline“
  redraw_interval  = 0.3,         -- s
}
do
  local ok, user = pcall(dofile, "/xreactor/config_master.lua")
  if ok and type(user)=="table" then
    for k,v in pairs(user) do CFG[k]=v end
  end
end

-- ---- I/O Targets (PC / Monitor) -------------------------------------------
local mon = nil
local function bind_monitor()
  if CFG.monitor_side and peripheral.isPresent(CFG.monitor_side)
    and peripheral.getType(CFG.monitor_side)=="monitor" then
    mon = peripheral.wrap(CFG.monitor_side)
    -- Auto-Scale: versuche viel Inhalt lesbar zu halten
    local w,h = mon.getSize()
    if w >= 120 then mon.setTextScale(0.5)
    elseif w >= 60 then mon.setTextScale(0.75)
    else mon.setTextScale(1) end
  else
    mon = nil
  end
end
bind_monitor()

local function T() return mon or term end
local function cls()
  local t=T()
  t.setBackgroundColor(colors.black)
  t.setTextColor(colors.white)
  t.clear(); t.setCursorPos(1,1)
end
local function wprint(s)
  local t=T()
  local x,y=t.getCursorPos()
  local W=t.getSize()
  if #s>W then s=s:sub(1,W) end
  t.write(s); t.setCursorPos(1,y+1)
end

-- ---- Modem/Rednet ---------------------------------------------------------
assert(peripheral.getType(CFG.modem_side)=="modem", "No modem on "..tostring(CFG.modem_side))
rednet.open(CFG.modem_side)
local MASTER_ID = os.getComputerID()

-- ---- Node-Registry ---------------------------------------------------------
local nodes = {}  -- [id] = { last_ms=..., caps={reactors=..,turbines=..}, telem={reactors={},turbines={},agg={...}} }

local function now_ms() return os.epoch("utc") end
local function age_sec(ms) return math.floor((now_ms()-(ms or 0))/1000) end

local function mark_timeouts()
  for id,n in pairs(nodes) do
    local offline = age_sec(n.last_ms or 0) > (CFG.telem_timeout or 15)
    n.offline = offline
  end
end

-- ---- Aggregation über alle Nodes ------------------------------------------
local function total_agg()
  local A = {
    node_cnt=0, node_on=0,
    reactors={count=0,active=0,hot=0,energy=0,fuel=0,fuel_max=0},
    turbines={count=0,active=0,rpm=0,flow=0,flow_max=0,prod=0},
  }
  for _,n in pairs(nodes) do
    A.node_cnt = A.node_cnt + 1
    if not n.offline then A.node_on = A.node_on + 1 end
    local ag = n.telem and n.telem.agg
    if ag then
      A.reactors.count   = A.reactors.count   + (ag.reactors.count or 0)
      A.reactors.active  = A.reactors.active  + (ag.reactors.active or 0)
      A.reactors.hot     = A.reactors.hot     + (ag.reactors.hot or 0)
      A.reactors.energy  = A.reactors.energy  + (ag.reactors.energy or 0)
      A.reactors.fuel    = A.reactors.fuel    + (ag.reactors.fuel or 0)
      A.reactors.fuel_max= A.reactors.fuel_max+ (ag.reactors.fuel_max or 0)

      A.turbines.count   = A.turbines.count   + (ag.turbines.count or 0)
      A.turbines.active  = A.turbines.active  + (ag.turbines.active or 0)
      A.turbines.rpm     = A.turbines.rpm     + (ag.turbines.rpm or 0)
      A.turbines.flow    = A.turbines.flow    + (ag.turbines.flow or 0)
      A.turbines.flow_max= A.turbines.flow_max+ (ag.turbines.flow_max or 0)
      A.turbines.prod    = A.turbines.prod    + (ag.turbines.prod or 0)
    end
  end
  return A
end

-- ---- Drawing ---------------------------------------------------------------
local function fmt(n) if n==nil then return "-" end return tostring(math.floor(n+0.5)) end

local function draw()
  cls()
  wprint(("Master #%d  |  gen %d"):format(MASTER_ID, os.day()*86400 + os.time()))
  local ms = "Modem: "..tostring(CFG.modem_side)
  local mon_s = "Monitor: "..(CFG.monitor_side or "-")
  wprint(ms.."  |  "..mon_s)
  wprint(("Auth: %s  |  Timeout: %ss"):format(CFG.auth_token, CFG.telem_timeout or 15))
  wprint(("Nodes bekannt: %d"):format((function() local c=0 for _ in pairs(nodes) do c=c+1 end return c end)()))
  wprint("")

  local A = total_agg()
  wprint(("Reaktoren: %d aktiv / %d gesamt | hot %s mB/t | fuel %s/%s mB | energy %s")
    :format(A.reactors.active, A.reactors.count, fmt(A.reactors.hot), fmt(A.reactors.fuel), fmt(A.reactors.fuel_max), fmt(A.reactors.energy)))
  wprint(("Turbinen : %d aktiv / %d gesamt | rpm %s | flow %s/%s | prod %s/t")
    :format(A.turbines.active, A.turbines.count, fmt(A.turbines.rpm), fmt(A.turbines.flow), fmt(A.turbines.flow_max), fmt(A.turbines.prod)))
  wprint("")

  wprint("ID   | age | state    | R(act/total) | T(act/total) | prod/t | rpm | flow/Max")
  wprint(("─"):rep(({T().getSize()})[1]))
  -- sortierte Liste (stabile Reihenfolge)
  local list = {}
  for id,n in pairs(nodes) do table.insert(list, {id=id, n=n}) end
  table.sort(list, function(a,b) return a.id<b.id end)

  for _,e in ipairs(list) do
    local id, n = e.id, e.n
    local ag = n.telem and n.telem.agg
    local R,Tb = {0,0},{0,0}
    local prod,rpm,flow,flowm = 0,0,0,0
    if ag then
      R={ag.reactors.active or 0, ag.reactors.count or 0}
      Tb={ag.turbines.active or 0, ag.turbines.count or 0}
      prod=ag.turbines.prod or 0; rpm=ag.turbines.rpm or 0
      flow=ag.turbines.flow or 0; flowm=ag.turbines.flow_max or 0
    end
    local state = n.offline and "OFFLINE" or "online "
    local line = string.format("#%-3d | %3ds | %-7s | %2d/%-2d      | %2d/%-2d      | %5s | %4s | %4s/%-4s",
      id, age_sec(n.last_ms or 0), state, R[1],R[2], Tb[1],Tb[2], fmt(prod), fmt(rpm), fmt(flow), fmt(flowm))
    wprint(line)
  end

  wprint("")
  wprint("[F5] Neuscan Nodes (leere löschen)   [Q] Beenden")
end

-- ---- Networking ------------------------------------------------------------
local function send_ack(id)
  rednet.send(id, {type="HELLO_ACK", _auth=CFG.auth_token, master_id=MASTER_ID})
end

local function rx_loop()
  while true do
    local id, msg = rednet.receive(1)
    if id and type(msg)=="table" and msg._auth==CFG.auth_token then
      if msg.type=="HELLO" then
        -- Node registrieren / Caps merken
        nodes[id] = nodes[id] or {}
        nodes[id].caps = msg.caps or nodes[id].caps or {}
        nodes[id].last_ms = now_ms()
        nodes[id].offline = false
        send_ack(id)
      elseif msg.type=="TELEM" then
        nodes[id] = nodes[id] or {}
        nodes[id].caps  = msg.caps or nodes[id].caps or {}
        nodes[id].telem = msg.telem or nodes[id].telem
        nodes[id].last_ms = now_ms()
        nodes[id].offline = false
      end
    end
  end
end

-- ---- UI/Housekeeping -------------------------------------------------------
local function house_loop()
  local last = 0
  while true do
    if os.clock() - last >= (CFG.redraw_interval or 0.3) then
      mark_timeouts()
      draw()
      last = os.clock()
    end
    os.sleep(0.05)
  end
end

local function keys_loop()
  while true do
    local e, k = os.pullEvent("key")
    if k==keys.f5 then
      -- „Neuscan“ = veraltete/nie gehörte löschen (optional)
      local keep = {}
      for id,n in pairs(nodes) do
        if n.last_ms and age_sec(n.last_ms)<600 then keep[id]=n end
      end
      nodes = keep
      draw()
    elseif k==keys.q or k==keys.escape then
      cls(); term.setCursorPos(1,1); print("Master beendet."); return
    end
  end
end

-- ---- Startbanner & run -----------------------------------------------------
cls()
wprint(("Master startet...  Modem: %s  |  Monitor: %s"):format(CFG.modem_side, CFG.monitor_side or "-"))
parallel.waitForAny(rx_loop, house_loop, keys_loop)
