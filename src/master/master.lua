--========================================================
-- XReactor • MASTER  (mit Node-Auswahlliste + Matrix-Anzeige)
--========================================================

-- ---------- Config laden ----------
local CFG = {
  modem_side   = "right",
  auth_token   = "xreactor",
  views = { dashboard=nil, control=nil, config=nil },
  redraw_interval = 0.25,
  telem_timeout_s = 15,
  matrix = { enable=true, name=nil, wired_side=nil },
}
do
  local ok,t = pcall(dofile,"/xreactor/config_master.lua")
  if ok and type(t)=="table" then for k,v in pairs(t) do
    if k=="views" and type(v)=="table" then CFG.views=v
    elseif k=="matrix" and type(v)=="table" then for kk,vv in pairs(v) do CFG.matrix[kk]=vv end
    else CFG[k]=v end
  end end
end

-- Persistente UI-Zuordnung
local UI_PATH = "/xreactor/ui_master.json"
local function load_json(p)
  if not fs.exists(p) then return nil end
  local f=fs.open(p,"r"); local s=f.readAll() or ""; f.close()
  local ok,t = pcall(textutils.unserializeJSON, s)
  return ok and t or nil
end
local function save_json(p, tbl)
  local s=textutils.serializeJSON(tbl, true)
  fs.makeDir(fs.getDir(p))
  local f=fs.open(p,"w"); f.write(s or "{}"); f.close()
end
do
  local ui = load_json(UI_PATH)
  if ui and ui.views then for k,v in pairs(ui.views) do CFG.views[k]=v end end
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

-- ---------- Matrix Reader ----------
local ok_mx, MATRIX = pcall(require, "xreactor.shared.matrix")
if not ok_mx then MATRIX = dofile("/xreactor/shared/matrix.lua") end
local matrix_last = nil
local function poll_matrix_once()
  if not CFG.matrix.enable then matrix_last=nil; return end
  local data, err = MATRIX.read({ name=CFG.matrix.name, wired_side=CFG.matrix.wired_side })
  matrix_last = data or nil
end

-- ---------- GUI Toolkit ----------
local ok_gui, GUI = pcall(require, "xreactor.shared.gui")
if not ok_gui then GUI = dofile("/xreactor/shared/gui.lua") end

-- Router je View
local routers = { dashboard=nil, control=nil, config=nil }
local screens = { dashboard=nil, control=nil, config=nil }

-- Auswahlzustand
local selected_node = nil
local broadcast_mode = false

local function node_count()
  local c=0; for _ in pairs(nodes) do c=c+1 end; return c end
local function node_ids_sorted()
  local arr={}; for id,_ in pairs(nodes) do table.insert(arr, id) end; table.sort(arr); return arr end

-- ---------- GUI: Dashboard ----------
local function build_dashboard_screen()
  local s = GUI.mkScreen("dashboard", "Master ▢ Dashboard")

  -- Linke Infos (Nodes + Turbinen/Produktion)
  local kvR  = GUI.mkKV(2,3,28,"Reaktoren:", colors.cyan)
  local kvT  = GUI.mkKV(2,4,28,"Turbinen:",  colors.cyan)
  local kvP  = GUI.mkKV(2,6,28,"Power/t:",   colors.lime)
  local kvRPM= GUI.mkKV(2,7,28,"RPM∑:",      colors.lime)

  -- Rechte Spalte: Matrix
  local lblM = GUI.mkLabel(32,3,"Induction Matrix", {color=colors.cyan})
  local kvMS = GUI.mkKV(32,4,28,"SoC:", colors.white)
  local kvMI = GUI.mkKV(32,5,28,"In/t:", colors.white)
  local kvMO = GUI.mkKV(32,6,28,"Out/t:", colors.white)
  local barM = GUI.mkBar(32,7,28, colors.lime)

  -- Buttons unten rechts (nur Hinweise, Navigation pro Monitor erfolgt per Monitor-Zuweisung)
  local btnCtl = GUI.mkButton(32,10,13,3,"Kontrolle", function()
    term.setBackgroundColor(colors.black); term.setTextColor(colors.white); term.clear()
    print("Die Control-View zeigt auf dem zugewiesenen Monitor.")
    print("Monitor-Zuweisung in 'Konfiguration' möglich.")
    os.sleep(1)
  end)
  local btnCfg = GUI.mkButton(47,10,13,3,"Konfig", function()
    term.setBackgroundColor(colors.black); term.setTextColor(colors.white); term.clear()
    print("Die Config-View zeigt auf dem zugewiesenen Monitor.")
    print("Monitor-Zuweisung in 'Konfiguration' möglich.")
    os.sleep(1)
  end)

  s:add(kvR); s:add(kvT); s:add(kvP); s:add(kvRPM)
  s:add(lblM); s:add(kvMS); s:add(kvMI); s:add(kvMO); s:add(barM)
  s:add(btnCtl); s:add(btnCfg)

  s.onShow = function()
    local A = agg_totals()
    kvR.props.value   = string.format("%d/%d act", A.reactors.active or 0, A.reactors.count or 0)
    kvT.props.value   = string.format("%d/%d act", A.turbines.active or 0, A.turbines.count or 0)
    kvP.props.value   = string.format("%d kFE", math.floor((A.turbines.prod or 0)/1000))
    kvRPM.props.value = math.floor(A.turbines.rpm or 0)

    if matrix_last then
      local pct = math.floor((matrix_last.soc or 0)*100 + 0.5)
      kvMS.props.value = string.format("%3d%% (%s)", pct, matrix_last.name or "?")
      kvMI.props.value = tostring(matrix_last.inFEt or 0)  .. " FE/t"
      kvMO.props.value = tostring(matrix_last.outFEt or 0) .. " FE/t"
      barM.props.value = matrix_last.soc or 0
    else
      kvMS.props.value = "—"
      kvMI.props.value = "—"
      kvMO.props.value = "—"
      barM.props.value = 0
    end
  end

  return s
end

-- ---------- GUI: Control (Node-Liste + Aktionen) ----------
local function build_control_screen()
  local s = GUI.mkScreen("control", "Master ▢ Control")

  local list_x, list_y, list_w, list_h = 2,3,28,12
  local rows = {}
  local page, perPage = 1, 10

  local lblHead = GUI.mkLabel(list_x, list_y-1, "Nodes (klicken zum Auswählen)", {color=colors.cyan})
  s:add(lblHead)

  local btnPrev = GUI.mkButton(list_x, list_y+list_h+1, 8, 3, "◀ Prev", function() page = math.max(1, page-1); s.onShow() end)
  local btnNext = GUI.mkButton(list_x+list_w-8, list_y+list_h+1, 8, 3, "Next ▶", function()
    local total = node_count(); local pages = math.max(1, math.ceil(total / perPage))
    page = math.min(pages, page+1); s.onShow()
  end)
  s:add(btnPrev); s:add(btnNext)

  for i=1,perPage do
    local y = list_y + (i-1)
    local b = GUI.mkButton(list_x, y, list_w, 1, ("—"):rep(list_w), function()
      local idx = (page-1)*perPage + i
      local ids = node_ids_sorted()
      local id  = ids[idx]
      if id then selected_node=id; broadcast_mode=false; s.onShow() end
    end, colors.gray)
    rows[i]=b; s:add(b)
  end

  local ax = 32
  local btnOn  = GUI.mkButton(ax,3,16,3,"Reakt ON", function()
    local payload = {type="CMD", target="reactor", cmd="setActive", value=true,  _auth=CFG.auth_token}
    if broadcast_mode or not selected_node then for id,_ in pairs(nodes) do rednet.send(id, payload) end
    else rednet.send(selected_node, payload) end
  end, colors.lime)

  local btnOff = GUI.mkButton(ax,7,16,3,"Reakt OFF", function()
    local payload = {type="CMD", target="reactor", cmd="setActive", value=false, _auth=CFG.auth_token}
    if broadcast_mode or not selected_node then for id,_ in pairs(nodes) do rednet.send(id, payload) end
    else rednet.send(selected_node, payload) end
  end, colors.red)

  local btnInd = GUI.mkButton(ax,11,16,3,"Inductor", function()
    local payload = {type="CMD", target="turbine", cmd="setInductorEngaged", value=true, _auth=CFG.auth_token}
    if broadcast_mode or not selected_node then for id,_ in pairs(nodes) do rednet.send(id, payload) end
    else rednet.send(selected_node, payload) end
  end, colors.cyan)

  local btnAuto= GUI.mkButton(ax,15,16,3,"AutoTune", function()
    local payload = {type="CMD", target="turbine", cmd="autotune", target_rpm=1800, timeout_s=25, _auth=CFG.auth_token}
    if broadcast_mode or not selected_node then for id,_ in pairs(nodes) do rednet.send(id, payload) end
    else rednet.send(selected_node, payload) end
  end, colors.orange)

  local btnBrc = GUI.mkButton(ax,19,16,3,"Broadcast", function() broadcast_mode=true; selected_node=nil; s.onShow() end, colors.gray)
  local lblSel = GUI.mkLabel(ax, 23, "Ziel: —", {color=colors.white})

  s:add(btnOn); s:add(btnOff); s:add(btnInd); s:add(btnAuto); s:add(btnBrc); s:add(lblSel)

  local function fmt_node_line(id)
    local n = nodes[id] or {}
    local ag = n.telem and n.telem.agg
    local aR,cR = (ag and ag.reactors and ag.reactors.active) or 0, (ag and ag.reactors and ag.reactors.count) or 0
    local aT,cT = (ag and ag.turbines and ag.turbines.active) or 0, (ag and ag.turbines and ag.turbines.count) or 0
    local stat = (n.offline and "OFF") or " ON "
    return string.format("Node #%d  R:%d/%d T:%d/%d [%s]", id, aR,cR,aT,cT, stat)
  end

  s.onShow = function()
    local ids = node_ids_sorted()
    local total = #ids
    local pages = math.max(1, math.ceil(total/perPage))
    if page>pages then page=pages end
    local start = (page-1)*perPage + 1

    for i=1,perPage do
      local idx = start + (i-1)
      local row = rows[i]
      if idx <= total then
        local id = ids[idx]
        row.props.text = fmt_node_line(id)
        local n = nodes[id]
        local bg = n.offline and colors.red or colors.gray
        row.props.color = (selected_node==id and colors.lightBlue) or bg
        row.hidden = false
      else
        row.props.text = ""
        row.hidden = true
      end
    end

    if broadcast_mode or not selected_node then
      lblSel.props.text = "Ziel: Broadcast (alle)"; lblSel.props.color = colors.lightGray
    else
      lblSel.props.text = ("Ziel: Node #%d"):format(selected_node); lblSel.props.color = colors.white
    end
  end

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
  s:add(GUI.mkKV(2,10,36,"Matrix Name:",  colors.cyan))
  s:add(GUI.mkKV(2,11,36,"Matrix Wired:", colors.cyan))

  s:add(GUI.mkButton(2,13,16,3,"Monitore", function()
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

  s:add(GUI.mkButton(20,13,16,3,"Matrix set", function()
    term.setCursorPos(1,1); term.setTextColor(colors.white); term.setBackgroundColor(colors.black); term.clear()
    print("Matrix-Peripheral setzen (leer = auto-detect)")
    write("Name: "); local n = read()
    write("Wired-Side (z.B. left / leer): "); local w = read()
    CFG.matrix.name = (n ~= "" and n) or nil
    CFG.matrix.wired_side = (w ~= "" and w) or nil
    print("Gespeichert. ENTER…"); read()
  end, colors.orange))

  s:add(GUI.mkButton(38,13,12,3,"Zurück", function() end))

  s.onShow = function()
    s.widgets[1].props.value = CFG.modem_side
    s.widgets[2].props.value = CFG.auth_token
    s.widgets[3].props.value = CFG.views.dashboard or "-"
    s.widgets[4].props.value = CFG.views.control   or "-"
    s.widgets[5].props.value = CFG.views.config    or "-"
    s.widgets[6].props.value = CFG.matrix.name or "(auto)"
    s.widgets[7].props.value = CFG.matrix.wired_side or "-"
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
  for _,r in pairs(routers) do if r then r:draw() end end
end

local function house_loop()
  local t0, tm = 0, 0
  while true do
    local now = os.clock()
    if now - tm >= 1.0 then
      poll_matrix_once()
      tm = now
    end
    if now - t0 >= CFG.redraw_interval then
      mark_timeouts()
      if screens.dashboard then pcall(screens.dashboard.onShow, screens.dashboard) end
      if screens.control   then pcall(screens.control.onShow,   screens.control)   end
      if screens.config    then pcall(screens.config.onShow,    screens.config)    end
      draw_all()
      t0 = now
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
      for _,r in pairs(routers) do
        local mon = r and r.monSurf and peripheral.getName(r.monSurf.t)
        if mon and mon==side then r:handleTouch(ev[1], side, x, y) end
      end
    elseif ev[1]=="mouse_click" then
      local btn,x,y=ev[2],ev[3],ev[4]
      for _,r in pairs(routers) do if r then r:handleTouch("mouse_click", btn, x, y) end end
    elseif ev[1]=="key" then
      if ev[2]==keys.q then return end
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

-- Fallbacks auf Terminal, wenn Monitore nicht zugewiesen
if not routers.dashboard then routers.dashboard = GUI.mkRouter({}); routers.dashboard:register(screens.dashboard); routers.dashboard:show("dashboard") end
if not routers.control   then routers.control   = GUI.mkRouter({}); routers.control:register(screens.control);   routers.control:show("control")   end
if not routers.config    then routers.config    = GUI.mkRouter({}); routers.config:register(screens.config);     routers.config:show("config")     end

-- ---------- Start ----------
print(("Master gestartet #%d | Modem:%s | Matrix:%s")
  :format(MASTER_ID, CFG.modem_side, CFG.matrix.name or "(auto)"))
parallel.waitForAny(rx_loop, house_loop, input_loop)