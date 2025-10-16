--==========================================================
-- XReactor ◈ MASTER (Leader/Display)  •  mit Detail-Ansicht
-- - empfängt HELLO/TELEM von Nodes (auth-basiert)
-- - sendet HELLO_ACK
-- - zeigt Aggregat + Node-Liste (live)
-- - Klick/Touch auf Node-Zeile öffnet Detailansicht (scrollbar)
-- - optional Ausgabe auf Monitor (auto TextScale)
--==========================================================

-- ---- sichere require + Config ---------------------------------------------
local function try_require(name)
  local ok, mod = pcall(require, name)
  if ok then return mod end
end

local CFG = {
  modem_side       = "right",     -- Modem zum rednet
  monitor_side     = nil,         -- z.B. "bottom" | nil = nur PC
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
    -- einfache Auto-Skalierung
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
local function wwrite(s) T().write(s) end
local function setpos(x,y) T().setCursorPos(x,y) end
local function size() local w,h=T().getSize(); return w,h end

-- ---- Modem/Rednet ---------------------------------------------------------
assert(peripheral.getType(CFG.modem_side)=="modem", "No modem on "..tostring(CFG.modem_side))
rednet.open(CFG.modem_side)
local MASTER_ID = os.getComputerID()

-- ---- Node-Registry ---------------------------------------------------------
local nodes = {}  -- [id] = { last_ms=..., caps={}, telem={reactors={},turbines={},agg={...}}, offline=false }

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

-- ---- Utility ----------------------------------------------------------------
local function fmt(n) if n==nil then return "-" end return tostring(math.floor(n+0.5)) end
local function count_nodes() local c=0 for _ in pairs(nodes) do c=c+1 end return c end

-- ---- UI-State (List & Detail) ----------------------------------------------
local view = "list"        -- "list" | "detail"
local rowmap = {}          -- [y] = node_id (für Klick)
local table_y0 = 0         -- Startzeile der Tabelle (für Mapping)
local selected_id = nil    -- Node in Detailansicht
local detail_scroll = 0    -- Scrolloffset in Detailansicht

-- ---- Zeichnen: Listenansicht ------------------------------------------------
local function draw_list()
  cls()
  wprint(("Master #%d  |  gen %d"):format(MASTER_ID, os.day()*86400 + os.time()))
  local ms = "Modem: "..tostring(CFG.modem_side)
  local mon_s = "Monitor: "..(CFG.monitor_side or "-")
  wprint(ms.."  |  "..mon_s)
  wprint(("Auth: %s  |  Timeout: %ss"):format(CFG.auth_token, CFG.telem_timeout or 15))
  wprint(("Nodes bekannt: %d"):format(count_nodes()))
  wprint("")

  local A = total_agg()
  wprint(("Reaktoren: %d aktiv / %d gesamt | hot %s mB/t | fuel %s/%s mB | energy %s")
    :format(A.reactors.active, A.reactors.count, fmt(A.reactors.hot), fmt(A.reactors.fuel), fmt(A.reactors.fuel_max), fmt(A.reactors.energy)))
  wprint(("Turbinen : %d aktiv / %d gesamt | rpm %s | flow %s/%s | prod %s/t")
    :format(A.turbines.active, A.turbines.count, fmt(A.turbines.rpm), fmt(A.turbines.flow), fmt(A.turbines.flow_max), fmt(A.turbines.prod)))
  wprint("")

  wprint("ID   | age | state    | R(act/total) | T(act/total) | prod/t | rpm | flow/Max")
  local w,_ = size()
  wprint(("─"):rep(w))

  rowmap = {}
  table_y0 = ({T().getCursorPos()})[2]

  -- sortierte Liste
  local list = {}
  for id,n in pairs(nodes) do table.insert(list, {id=id, n=n}) end
  table.sort(list, function(a,b) return a.id<b.id end)

  local y = table_y0
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
    setpos(1,y); wwrite(line)
    rowmap[y] = id
    y = y + 1
  end

  setpos(1,y+1)
  wprint("[F5] Liste bereinigen   [Klick/Touch] Detail öffnen   [Q] Beenden")
end

-- ---- Zeichnen: Detailansicht ------------------------------------------------
local function draw_detail()
  cls()
  if not selected_id or not nodes[selected_id] then
    wprint("Kein Node ausgewählt."); view="list"; return
  end
  local n = nodes[selected_id]
  local ag = n.telem and n.telem.agg
  wprint(("Node #%d  |  age %ds  |  %s"):format(selected_id, age_sec(n.last_ms or 0), n.offline and "OFFLINE" or "online"))
  if ag then
    wprint(("R: act %d/%d  hot %s  fuel %s/%s  energy %s")
      :format(ag.reactors.active or 0, ag.reactors.count or 0, fmt(ag.reactors.hot), fmt(ag.reactors.fuel), fmt(ag.reactors.fuel_max), fmt(ag.reactors.energy)))
    wprint(("T: act %d/%d  rpm %s  flow %s/%s  prod %s/t")
      :format(ag.turbines.active or 0, ag.turbines.count or 0, fmt(ag.turbines.rpm), fmt(ag.turbines.flow), fmt(ag.turbines.flow_max), fmt(ag.turbines.prod)))
  end
  wprint("")

  -- Listen zusammenstellen
  local reactors = (n.telem and n.telem.reactors) or {}
  local turbines = (n.telem and n.telem.turbines) or {}

  local lines = {}
  table.insert(lines, "=== Reaktoren ===")
  for _,r in ipairs(reactors) do
    table.insert(lines, string.format("%-28s | act:%s  hot:%s  fuel:%s/%s  E:%s  T:%s",
      r.name or "reactor", r.active and "on " or "off", fmt(r.hot_mb), fmt(r.fuel), fmt(r.fuel_max), fmt(r.energy), fmt(r.temp)))
  end
  table.insert(lines, "")
  table.insert(lines, "=== Turbinen ===")
  for _,t in ipairs(turbines) do
    table.insert(lines, string.format("%-28s | act:%s  rpm:%s  flow:%s/%s  prod:%s  ind:%s",
      t.name or "turbine", t.active and "on " or "off", fmt(t.rpm), fmt(t.flow), fmt(t.flow_max), fmt(t.prod), tostring(t.inductor)))
  end

  local w,h = size()
  local content_h = h - 3 -- Kopfzeilen bereits geschrieben
  local max_scroll = math.max(0, #lines - content_h)
  if detail_scroll > max_scroll then detail_scroll = max_scroll end
  if detail_scroll < 0 then detail_scroll = 0 end

  for i=1,content_h do
    local idx = i + detail_scroll
    setpos(1, 3+i)
    if idx <= #lines then
      local s = lines[idx]
      if #s > w then s = s:sub(1,w) end
      wwrite(s)
    else
      wwrite((" "):rep(w))
    end
  end

  setpos(1,h); wwrite(("[PgUp/PgDn/MouseWheel] scroll  |  [ESC/←] zurück  |  [Q] beenden"):sub(1,w))
end

-- ---- Haupt-Zeichner --------------------------------------------------------
local function draw()
  if view=="list" then draw_list() else draw_detail() end
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

-- ---- Input: Tastatur / Maus / Monitor-Touch --------------------------------
local function open_detail_by_row(y)
  if view ~= "list" then return end
  if y and rowmap[y] and nodes[rowmap[y]] then
    selected_id = rowmap[y]
    detail_scroll = 0
    view = "detail"
    draw()
  end
end

local function input_loop()
  while true do
    local ev = { os.pullEvent() }
    local e = ev[1]

    if e=="key" then
      local k = ev[2]
      if view=="list" then
        if k==keys.f5 then
          -- Liste "bereinigen": sehr alte Einträge verwerfen
          local keep = {}
          for id,n in pairs(nodes) do
            if n.last_ms and age_sec(n.last_ms)<600 then keep[id]=n end
          end
          nodes = keep
          draw()
        elseif k==keys.q then
          cls(); term.setCursorPos(1,1); print("Master beendet."); return
        end
      else -- detail
        if k==keys.pageUp then detail_scroll = detail_scroll - 5; draw()
        elseif k==keys.pageDown then detail_scroll = detail_scroll + 5; draw()
        elseif k==keys.up then detail_scroll = detail_scroll - 1; draw()
        elseif k==keys.down then detail_scroll = detail_scroll + 1; draw()
        elseif k==keys.left or k==keys.backspace or k==keys.escape then
          view = "list"; selected_id=nil; draw()
        elseif k==keys.q then
          cls(); term.setCursorPos(1,1); print("Master beendet."); return
        end
      end

    elseif e=="mouse_click" then
      local btn, x, y = ev[2], ev[3], ev[4]
      if view=="list" and btn==1 then
        open_detail_by_row(y)
      end

    elseif e=="mouse_scroll" then
      local dir = ev[2] -- -1 hoch, 1 runter
      if view=="detail" then
        detail_scroll = detail_scroll + (dir>0 and 3 or -3); draw()
      end

    elseif e=="monitor_touch" then
      -- ev: "monitor_touch", side, x, y
      local side, x, y = ev[2], ev[3], ev[4]
      if CFG.monitor_side and side==CFG.monitor_side and view=="list" then
        open_detail_by_row(y)
      end
    end
  end
end

-- ---- Startbanner & run -----------------------------------------------------
cls()
wprint(("Master startet...  Modem: %s  |  Monitor: %s"):format(CFG.modem_side, CFG.monitor_side or "-"))
parallel.waitForAny(rx_loop, house_loop, input_loop)
