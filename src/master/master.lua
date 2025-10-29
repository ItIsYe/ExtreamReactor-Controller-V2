--========================================================
-- XReactor • MASTER  (mit Node-Auswahlliste)
-- - Rednet Master mit 3 GUIs (Dashboard/Control/Config)
-- - Mehrschirm-Support (je Monitor ein View), Speichern der Zuordnung
-- - Telemetrie-Anzeige + Steuerhoheit (CMD an Nodes)
-- - NEU: Node-Liste mit Paging & Klick-Auswahl für Zielbefehle
-- Abhängigkeiten: /xreactor/shared/gui.lua, config_master.lua
--========================================================

-- ---------- Config laden ----------
local CFG = {
  modem_side   = "right",
  auth_token   = "xreactor",
  -- Monitor-Zuordnung (peripheral-Namen; nil = nicht zugewiesen)
  views = {
    dashboard = nil,  -- z.B. "monitor_0"
    control   = nil,  -- z.B. "monitor_1"
    config    = nil,  -- z.B. "monitor_2"
  },
  redraw_interval = 0.25,
  telem_timeout_s = 15,
}
do
  local ok,t = pcall(dofile,"/xreactor/config_master.lua")
  if ok and type(t)=="table" then for k,v in pairs(t) do CFG[k]=v end end
end

-- Persistente UI-Zuordnung
local UI_PATH = "/xreactor/ui_master.json"
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
  if ui and ui.views then
    for k,v in pairs(ui.views) do CFG.views[k]=v end
  end
end

-- ---------- Rednet ----------
assert(peripheral.getType(CFG.modem_side)=="modem", "Kein Modem an "..tostring(CFG.modem_side))
rednet.open(CFG.modem_side)
local MASTER_ID = os.getComputerID()

-- ---------- Datenhaltung ----------
local nodes = {}     -- [id] = {last=ms, offline=bool, caps=?, telem=?}
local function age_sec(ms) return math.floor((os.epoch("utc")-(ms or 0))/1000) end
local function mark_timeouts()
  for id,n in pairs(nodes) do
    n.offline = age_sec(n.last or 0) > CFG.telem_timeout_s
  end
end
local function agg_totals()
  local A = {reactors={count=0,active=0,hot=0,fuel=0,fuel_max=0,energy=0}, turbines={count=0,active=0,rpm=0,flow=0,flow_max=0,prod=0}}
  for _,n in pairs(nodes) do
    local ag = n.telem and n.telem.agg
    if ag then
      for k,v in pairs(ag.reactors or {}) do A.reactors[k]=(A.reactors[k] or 0)+(v or 0) end
      for k,v in pairs(ag.turbines or {}) do A.turbines[k]=(A.turbines[k] or 0)+(v or 0) end
    end
  end
  return A
end

-- ---------- GUI Toolkit ----------
local ok_gui, GUI = pcall(require, "xreactor.shared.gui")
if not ok_gui then GUI = dofile("/xreactor/shared/gui.lua") end

-- Router pro View (damit jeder Monitor eine eigene Ansicht zeigen kann)
local routers = { dashboard = nil, control = nil, config = nil }
-- Globale Navigationsziele (Screens)
local screens = { dashboard = nil, control = nil, config = nil }

-- Auswahlzustand
local selected_node = nil
local broadcast_mode = false

-- Hilfen
local function node_count()
  local c = 0; for _ in pairs(nodes) do c=c+1 end; return c end

local function node_ids_sorted()
  local arr = {}
  for id,_ in pairs(nodes) do table.insert(arr, id) end
  table.sort(arr)
  return arr
end

-- ---------- GUI: Dashboard ----------
local function build_dashboard_screen()
  local s = GUI.mkScreen("dashboard", "Master ▢ Dashboard")
  local kvR = GUI.mkKV(2,3,28,"Reaktoren:", colors.cyan)
  local kvT = GUI.mkKV(2,4,28,"Turbinen:",  colors.cyan)
  local kvP = GUI.mkKV(2,6,28,"Power/t:",  colors.lime)
  local kvRPM=GUI.mkKV(2,7,28,"RPM∑:",     colors.lime)
  local bar  = GUI.mkBar(2,9,28, colors.lime) -- Matrix SoC (optional)

  s:add(kvR); s:add(kvT); s:add(kvP); s:add(kvRPM); s:add(bar)

  s:add(GUI.mkButton(32,3,16,3,"Kontrolle", function()
    -- keine direkte Navigation: jede View hat ihren Router
    -- Tipp im Terminal ausgeben
    term.setCursorPos(1,1); term.setTextColor(colors.white); term.setBackgroundColor(colors.black)
    print("Kontroll-View ist auf zugewiesenem Monitor sichtbar.")
  end))
  s.addConf = GUI.mkButton(32,7,16,3,"Konfig", function()
    term.setCursorPos(1,1); term.setTextColor(colors.white); term.setBackgroundColor(colors.black)
    print("Konfig-View ist auf zugewiesenem Monitor sichtbar.")
  end)
  s:add(s.addConf)

  s.onShow = function()
    local A = agg_totals()
    kvR.props.value = string.format("%d/%d act", A.reactors.active or 0, A.reactors.count or 0)
    kvT.props.value = string.format("%d/%d act", A.turbines.active or 0, A.turbines.count or 0)
    kvP.props.value = string.format("%d kFE", math.floor((A.turbines.prod or 0)/1000))
    kvRPM.props.value = math.floor(A.turbines.rpm or 0)
    bar.props.value = 0  -- Matrix SoC später befüllen
  end
  return s
end

-- ---------- GUI: Control (mit Node-Liste) ----------
local function build_control_screen()
  local s = GUI.mkScreen("control", "Master ▢ Control")

  -- Linke Spalte: Node-Liste
  local list_x, list_y, list_w, list_h = 2,3,28,12
  local rows = {}      -- 10 klickbare Reihen
  local page = 1
  local perPage = 10

  local lblHead = GUI.mkLabel(list_x, list_y-1, "Nodes (klicken zum Auswählen)", {color=colors.cyan})
  s:add(lblHead)

  -- Navigationsbuttons für Liste
  local btnPrev = GUI.mkButton(list_x, list_y+list_h+1, 8, 3, "◀ Prev", function()
    page = math.max(1, page-1); s.onShow()
  end)
  local btnNext = GUI.mkButton(list_x+list_w-8, list_y+list_h+1, 8, 3, "Next ▶", function()
    local total = node_count()
    local pages = math.max(1, math.ceil(total / perPage))
    page = math.min(pages, page+1); s.onShow()
  end)
  s:add(btnPrev); s:add(btnNext)

  -- Erzeuge 10 klickbare Reihen (Buttons)
  for i=1,perPage do
    local y = list_y + (i-1)
    local b = GUI.mkButton(list_x, y, list_w, 1, ("—"):rep(list_w), function(wg)
      local idx = (page-1)*perPage + i
      local ids = node_ids_sorted()
      local id  = ids[idx]
      if id then
        selected_node = id
        broadcast_mode = false
        s.onShow()
      end
    end, colors.gray)
    -- Als "Label-Button": optisch Zeile, aber klickbar
    rows[i] = b; s:add(b)
  end

  -- Rechte Spalte: Aktionen
  local ax = 32
  local btnOn  = GUI.mkButton(ax,3,16,3,"Reakt ON", function()
    if broadcast_mode or not selected_node then
      for id,_ in pairs(nodes) do
        rednet.send(id, {type="CMD", target="reactor", cmd="setActive", value=true, _auth=CFG.auth_token})
      end
    else
      rednet.send(selected_node, {type="CMD", target="reactor", cmd="setActive", value=true, _auth=CFG.auth_token})
    end
  end, colors.lime)

  local btnOff = GUI.mkButton(ax,7,16,3,"Reakt OFF", function()
    if broadcast_mode or not selected_node then
      for id,_ in pairs(nodes) do
        rednet.send(id, {type="CMD", target="reactor", cmd="setActive", value=false, _auth=CFG.auth_token})
      end
    else
      rednet.send(selected_node, {type="CMD", target="reactor", cmd="setActive", value=false, _auth=CFG.auth_token})
    end
  end, colors.red)

  local btnInd = GUI.mkButton(ax,11,16,3,"Inductor", function()
    if broadcast_mode or not selected_node then
      for id,_ in pairs(nodes) do
        rednet.send(id, {type="CMD", target="turbine", cmd="setInductorEngaged", value=true, _auth=CFG.auth_token})
      end
    else
      rednet.send(selected_node, {type="CMD", target="turbine", cmd="setInductorEngaged", value=true, _auth=CFG.auth_token})
    end
  end, colors.cyan)

  local btnAuto= GUI.mkButton(ax,15,16,3,"AutoTune", function()
    local payload = {type="CMD", target="turbine", cmd="autotune", target_rpm=1800, timeout_s=25, _auth=CFG.auth_token}
    if broadcast_mode or not selected_node then
      for id,_ in pairs(nodes) do rednet.send(id, payload) end
    else
      rednet.send(selected_node, payload)
    end
  end, colors.orange)

  local btnBrc = GUI.mkButton(ax,19,16,3,"Broadcast", function()
    broadcast_mode = true
    selected_node = nil
    s.onShow()
  end, colors.gray)

  s:add(btnOn); s:add(btnOff); s:add(btnInd); s:add(btnAuto); s:add(btnBrc)

  -- Statuszeile rechts
  local lblSel = GUI.mkLabel(ax, 23, "Ziel: —", {color=colors.white}); s:add(lblSel)

  -- Render/Refresh Logik
  local function fmt_node_line(id)
    local n = nodes[id] or {}
    local ag = n.telem and n.telem.agg
    local activeR, countR = (ag and ag.reactors and ag.reactors.active) or 0, (ag and ag.reactors and ag.reactors.count) or 0
    local activeT, countT = (ag and ag.turbines and ag.turbines.active) or 0, (ag and ag.turbines and ag.turbines.count) or 0
    local stat = (n.offline and "OFF") or " ON "
    local name = string.format("Node #%d  R:%d/%d T:%d/%d  [%s]", id, activeR, countR, activeT, countT, stat)
    return name
  end

  s.onShow = function()
    -- Node-Liste auf Seite 'page' befüllen
    local ids = node_ids_sorted()
    local total = #ids
    local pages = math.max(1, math.ceil(total/perPage))
    if page>pages then page = pages end
    local start = (page-1)*perPage + 1
    for i=1,perPage do
      local idx = start + (i-1)
      local row = rows[i]
      if idx <= total then
        local id = ids[idx]
        local txt = fmt_node_line(id)
        -- Farbgebung
        local n = nodes[id]
        local bg = n.offline and colors.red or colors.gray
        row.props.text = txt
        row.props.color = (selected_node==id and colors.lightBlue) or bg
        row.hidden = false
      else
        row.props.text = ""
        row.hidden = true
      end
    end

    if broadcast_mode or not selected_node then
      lblSel.props.text = "Ziel: Broadcast (alle)"
      lblSel.props.color = colors.lightGray
    else
      lblSel.props.text = ("Ziel: Node #%d"):format(selected_node)
      lblSel.props.color = colors.white
    end
  end

  s.onEvent = function() return false end
  return s
end

-- ---------- GUI: Config ----------
local function build_config_screen()
  local s = GUI.mkScreen("config", "Master ▢ Konfiguration")
  s:add(GUI.mkKV(2,3,36,"Modem:", colors.cyan))
  s:add(GUI.mkKV(2,4,36,"Auth:",  colors.cyan))
  s:add(GUI.mkKV(2,6,36,"Mon Dashboard:", colors.white))
  s:add(GUI.mkKV(2,7,36,"Mon Control:",   colors.white))
  s:add(GUI.mkKV(2,8,36,"Mon Config:",    colors.white))
  s:add(GUI.mkButton(2,11,16,3,"Monitore", function()
    term.setCursorPos(1,1); term.setTextColor(colors.white); term.setBackgroundColor(colors.black); term.clear()
    print("Monitore zuweisen (leer lassen zum Überspringen)")
    local mons = { peripheral.find("monitor") }
    print("Gefundene Monitore: "..#mons)
    write("Dashboard Monitor-Name: "); local d = read()
    write("Control   Monitor-Name: "); local c = read()
    write("Config    Monitor-Name: "); local g = read()
    if d~="" then CFG.views.dashboard = d end
    if c~="" then CFG.views.control   = c end
    if g~="" then CFG.views.config    = g end
    save_json(UI_PATH, {views=CFG.views})
    print("Gespeichert. ENTER…"); read()
  end, colors.cyan))
  s:add(GUI.mkButton(20,11,12,3,"Zurück", function() end))

  s.onShow = function()
    s.widgets[1].props.value = CFG.modem_side
    s.widgets[2].props.value = CFG.auth_token
    s.widgets[3].props.value = CFG.views.dashboard or "-"
    s.widgets[4].props.value = CFG.views.control   or "-"
    s.widgets[5].props.value = CFG.views.config    or "-"
  end
  return s
end

-- ---------- Router je View ----------
local function mk_router_for(view_name)
  local monName = CFG.views[view_name]
  local r = GUI.mkRouter({monitorName=monName, textScale=0.5})
  r:register(screens[view_name])
  r:show(view_name)
  return r
end

-- ---------- Netzwerk-Loop ----------
local ui_msg, ui_msg_ts = "", 0

local function rx_loop()
  while true do
    local id,msg = rednet.receive(1)
    if id and type(msg)=="table" and msg._auth==CFG.auth_token then
      if msg.type=="HELLO" then
        nodes[id]=nodes[id] or {}
        nodes[id].caps = msg.caps or nodes[id].caps or {}
        nodes[id].last = os.epoch("utc"); nodes[id].offline=false
        rednet.send(id, {type="HELLO_ACK", master=MASTER_ID, _auth=CFG.auth_token})
      elseif msg.type=="TELEM" then
        nodes[id]=nodes[id] or {}
        nodes[id].telem = msg.telem or nodes[id].telem
        nodes[id].last  = os.epoch("utc"); nodes[id].offline=false
      elseif msg.type=="CMD_ACK" then
        ui_msg = (msg.ok and "OK: " or "ERR: ")..(msg.msg or "")
        ui_msg_ts=os.clock()
      end
    end
  end
end

-- ---------- Render-Loop ----------
local function draw_all()
  for name,r in pairs(routers) do if r then r:draw() end end
end
local function house_loop()
  local t0=0
  while true do
    if os.clock()-t0 >= CFG.redraw_interval then
      mark_timeouts()
      -- Refresh-Screens (onShow aktualisiert Labels/Zeilen)
      if screens.dashboard then pcall(screens.dashboard.onShow, screens.dashboard) end
      if screens.control   then pcall(screens.control.onShow,   screens.control)   end
      if screens.config    then pcall(screens.config.onShow,    screens.config)    end
      draw_all()
      t0=os.clock()
    end
    os.sleep(0.05)
  end
end

-- ---------- Input-Loop ----------
local function input_loop()
  while true do
    local ev={os.pullEvent()}
    if ev[1]=="monitor_touch" then
      local side,x,y=ev[2],ev[3],ev[4]
      for name,r in pairs(routers) do
        local mon = r and r.monSurf and peripheral.getName(r.monSurf.t)
        if mon and mon==side then
          r:handleTouch(ev[1], side, x, y)
        end
      end
    elseif ev[1]=="mouse_click" then
      local btn,x,y=ev[2],ev[3],ev[4]
      for _,r in pairs(routers) do
        if r then r:handleTouch("mouse_click", btn, x, y) end
      end
    elseif ev[1]=="key" then
      local k=ev[2]
      if k==keys.q then return end
    end
  end
end

-- ---------- Init ----------
screens.dashboard = build_dashboard_screen()
screens.control   = build_control_screen()
screens.config    = build_config_screen()

routers.dashboard = mk_router_for("dashboard")
routers.control   = mk_router_for("control")
routers.config    = mk_router_for("config")

-- Fallbacks auf Terminal, falls Monitore (noch) nicht zugewiesen sind
if not routers.dashboard then
  routers.dashboard = GUI.mkRouter({})
  routers.dashboard:register(screens.dashboard)
  routers.dashboard:show("dashboard")
end
if not routers.control then
  routers.control = GUI.mkRouter({})
  routers.control:register(screens.control)
  routers.control:show("control")
end
if not routers.config then
  routers.config = GUI.mkRouter({})
  routers.config:register(screens.config)
  routers.config:show("config")
end

-- ---------- Start ----------
print(("Master gestartet #%d | Modem:%s"):format(MASTER_ID, CFG.modem_side))
parallel.waitForAny(rx_loop, house_loop, input_loop)