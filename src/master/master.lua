--========================================================
-- XReactor • MASTER
--  - Node-Liste + Steuerung
--  - Matrix-Anzeige
--  - Multi-Monitor (lokal + wired)
--  - AutoScale + manuelle Korrektur
--  - PHASE 1: Fuel-Management (Rednet-FUEL_REQ)
--========================================================

---------------------------
-- 1) Config laden
---------------------------
local CFG = {
  modem_side   = "right",
  auth_token   = "xreactor",
  views = { dashboard=nil, control=nil, config=nil },
  redraw_interval = 0.25,
  telem_timeout_s = 15,
  monitor_wired_side = nil,
  matrix = { enable=true, name=nil, wired_side=nil },
  default_view_scale = {
    dashboard = { autoscale=true, desired_cols=60, correction=0.0, manual=1.0 },
    control   = { autoscale=true, desired_cols=60, correction=0.0, manual=1.0 },
    config    = { autoscale=true, desired_cols=60, correction=0.0, manual=1.0 },
  },
  fuel = {
    enable       = true,
    min_pct      = 20,
    target_pct   = 60,
    request_unit = 4,
    cooldown_s   = 90,
    supplier_tag = "any",
  },
}
do
  local ok,t = pcall(dofile,"/xreactor/config_master.lua")
  if ok and type(t)=="table" then
    for k,v in pairs(t) do
      if k=="views" and type(v)=="table" then CFG.views=v
      elseif k=="matrix" and type(v)=="table" then for kk,vv in pairs(v) do CFG.matrix[kk]=vv end
      elseif k=="default_view_scale" and type(v)=="table" then CFG.default_view_scale=v
      elseif k=="fuel" and type(v)=="table" then for kk,vv in pairs(v) do CFG.fuel[kk]=vv end
      else CFG[k]=v end
    end
  end
end

---------------------------
-- 2) Persistenz / UI-State
---------------------------
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

local UI_STATE = {
  views = { dashboard=CFG.views.dashboard, control=CFG.views.control, config=CFG.views.config },
  view_opts = {
    dashboard = { autoscale=CFG.default_view_scale.dashboard.autoscale, desired_cols=CFG.default_view_scale.dashboard.desired_cols, correction=CFG.default_view_scale.dashboard.correction, manual=CFG.default_view_scale.dashboard.manual },
    control   = { autoscale=CFG.default_view_scale.control.autoscale,   desired_cols=CFG.default_view_scale.control.desired_cols,   correction=CFG.default_view_scale.control.correction,   manual=CFG.default_view_scale.control.manual },
    config    = { autoscale=CFG.default_view_scale.config.autoscale,    desired_cols=CFG.default_view_scale.config.desired_cols,    correction=CFG.default_view_scale.config.correction,    manual=CFG.default_view_scale.config.manual },
  }
}
do
  local ui = load_json(UI_PATH)
  if ui then
    if ui.views then for k,v in pairs(ui.views) do UI_STATE.views[k]=v end end
    if ui.view_opts then
      for k,ov in pairs(ui.view_opts) do
        UI_STATE.view_opts[k] = UI_STATE.view_opts[k] or {}
        for kk,vv in pairs(ov) do UI_STATE.view_opts[k][kk]=vv end
      end
    end
  end
  for k,v in pairs(UI_STATE.views) do CFG.views[k]=v end
end

local function persist_ui()
  save_json(UI_PATH, { views=UI_STATE.views, view_opts=UI_STATE.view_opts })
end

---------------------------
-- 3) Rednet / Grunddaten
---------------------------
assert(peripheral.getType(CFG.modem_side)=="modem", "Kein Modem an "..tostring(CFG.modem_side))
rednet.open(CFG.modem_side)
local MASTER_ID = os.getComputerID()

local nodes = {}  -- [id] = { last=ms, offline=bool, telem=?, caps=? }

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

---------------------------
-- 4) Matrix Reader
---------------------------
local ok_mx, MATRIX = pcall(require, "xreactor.shared.matrix")
if not ok_mx and fs.exists("/xreactor/shared/matrix.lua") then
  MATRIX = dofile("/xreactor/shared/matrix.lua")
end
local matrix_last = nil
local function poll_matrix_once()
  if not (CFG.matrix and CFG.matrix.enable and MATRIX) then matrix_last=nil; return end
  local data = select(1, MATRIX.read({ name=CFG.matrix.name, wired_side=CFG.matrix.wired_side }))
  matrix_last = data or nil
end

---------------------------
-- 5) GUI Toolkit
---------------------------
local ok_gui, GUI = pcall(require, "xreactor.shared.gui")
if not ok_gui then GUI = dofile("/xreactor/shared/gui.lua") end

---------------------------
-- 6) Monitor-Suche
---------------------------
local function list_monitors()
  local list = {}
  for _,n in ipairs(peripheral.getNames()) do
    if peripheral.getType(n)=="monitor" then table.insert(list, n) end
  end
  if CFG.monitor_wired_side and peripheral.getType(CFG.monitor_wired_side)=="modem" then
    local wm = peripheral.wrap(CFG.monitor_wired_side)
    if wm and wm.getNamesRemote then
      for _,rn in ipairs(wm.getNamesRemote()) do
        if peripheral.getType(rn)=="monitor" then table.insert(list, rn) end
      end
    end
  end
  table.sort(list)
  return list
end

---------------------------
-- 7) AutoScale
---------------------------
local function round_to_half(x)
  return math.max(0.5, math.min(5.0, math.floor(x*2+0.5)/2))
end

local function suggest_scale_for_monitor(mon, desired_cols)
  local best_s, best_diff = 0.5, math.huge
  for s=0.5,5.0,0.5 do
    pcall(mon.setTextScale, s)
    local w,h = mon.getSize()
    if w then
      local diff = (w >= desired_cols) and (w - desired_cols) or math.huge
      if diff < best_diff then best_diff = diff; best_s = s end
    end
  end
  return best_s
end

local function compute_scale_for_view(view_name)
  local monName = UI_STATE.views[view_name]
  if not monName then return nil end
  local mon = peripheral.wrap(monName)
  if not mon or type(mon.setTextScale)~="function" then return nil end
  local opts = UI_STATE.view_opts[view_name] or {}
  local autoscale  = (opts.autoscale ~= false)
  local desired    = tonumber(opts.desired_cols or 60) or 60
  local correction = tonumber(opts.correction or 0) or 0
  local manual     = tonumber(opts.manual or 1.0) or 1.0
  local s
  if autoscale then
    s = suggest_scale_for_monitor(mon, desired)
    s = round_to_half(s + correction)
  else
    s = round_to_half(manual)
  end
  return s
end

---------------------------
-- 8) Router & Screens
---------------------------
local routers = { dashboard=nil, control=nil, config=nil }
local screens = { dashboard=nil, control=nil, config=nil }

local function mk_router_for(view_name)
  local monName = UI_STATE.views[view_name]
  local scale   = compute_scale_for_view(view_name)
  local r = GUI.mkRouter({monitorName=monName, textScale=scale})
  r:register(screens[view_name])
  r:show(view_name)
  return r
end

local function rebuild_routers()
  routers.dashboard = mk_router_for("dashboard") or GUI.mkRouter({})
  routers.control   = mk_router_for("control")   or GUI.mkRouter({})
  routers.config    = mk_router_for("config")    or GUI.mkRouter({})
  routers.dashboard:register(screens.dashboard); routers.dashboard:show("dashboard")
  routers.control:register(screens.control);     routers.control:show("control")
  routers.config:register(screens.config);       routers.config:show("config")
end

---------------------------
-- 9) Fuel-Management (Phase 1)
---------------------------
-- Telemetrie-Struktur robust lesen:
--  - Bevorzugt pro-Reaktor-Liste: n.telem.reactors = { {uid=..., fuel=..., fuel_max=...}, ... }
--  - Fallback Aggregat: n.telem.agg.reactors.{fuel, fuel_max}
local fuel_state = { last_req = {} } -- key = reactor_uid (oder "node:<id>"), value = last_ts

local function now_s() return os.epoch("utc")/1000 end

local function pct(f, fm)
  if not fm or fm<=0 then return 0 end
  return (f or 0) / fm * 100.0
end

local function floor_to_unit(x, unit)
  if unit<=0 then return math.max(0, math.floor(x)) end
  return math.max(0, math.floor(x / unit) * unit)
end

local function should_cooldown(key)
  local ts = fuel_state.last_req[key] or 0
  return (now_s() - ts) < (CFG.fuel.cooldown_s or 90)
end

local function mark_cooldown(key)
  fuel_state.last_req[key] = now_s()
end

local function send_fuel_req(payload, target_node)
  -- target_node optional; wir broadcasten standardmäßig (Supplier entscheidet)
  if target_node then
    rednet.send(target_node, payload)
  else
    -- Broadcast an alle (Supplier filtern per type/supplier_tag/_auth)
    for id,_ in pairs(nodes) do rednet.send(id, payload) end
    -- Zusätzlich globaler Broadcast-Kanal (optional): nicht nötig, Rednet braucht IDs
  end
end

local function handle_fuel_for_node(nid, n)
  if not (CFG.fuel and CFG.fuel.enable) then return end
  local min_pct    = CFG.fuel.min_pct or 20
  local target_pct = math.max(min_pct, CFG.fuel.target_pct or 60)
  local unit       = math.max(1, CFG.fuel.request_unit or 4)

  -- 1) Pro-Reaktor detailliert
  local reactors = n.telem and n.telem.reactors
  if type(reactors)=="table" and #reactors>0 then
    for _,r in ipairs(reactors) do
      local uid, f, fm = r.uid or r.id or tostring(_), tonumber(r.fuel or 0), tonumber(r.fuel_max or 0)
      local p = pct(f,fm)
      if p < min_pct and fm>0 then
        local target = math.floor(target_pct/100 * fm)
        local need   = math.max(0, target - f)  -- Einheiten wie in Telemetry (mB/FE?), wir sprechen in "Ingots"
        -- Schätzen: 1 Ingot ≈ 1000 mB (je nach Mod-Setup; hier rein logisch in "Ingots" anfordern)
        local need_ing = math.floor((need/1000) + 0.5)
        need_ing = floor_to_unit(need_ing, unit)
        local key = "rx:"..tostring(uid)
        if need_ing>0 and not should_cooldown(key) then
          send_fuel_req({
            type="FUEL_REQ",
            supplier_tag = CFG.fuel.supplier_tag or "any",
            node_id = nid,
            reactor_uid = uid,
            need_ingots = need_ing,
            reason = "below_min",
            _auth = CFG.auth_token
          })
          mark_cooldown(key)
        end
      end
    end
    return
  end

  -- 2) Fallback Aggregat (keine Einzelreaktor-Daten verfügbar)
  local ag = n.telem and n.telem.agg
  if ag and ag.reactors then
    local f, fm = tonumber(ag.reactors.fuel or 0), tonumber(ag.reactors.fuel_max or 0)
    local p = pct(f,fm)
    if p < min_pct and fm>0 then
      local target = math.floor(target_pct/100 * fm)
      local need   = math.max(0, target - f)
      local need_ing = math.floor((need/1000) + 0.5)
      need_ing = floor_to_unit(need_ing, unit)
      local key = "node:"..tostring(nid)
      if need_ing>0 and not should_cooldown(key) then
        send_fuel_req({
          type="FUEL_REQ",
          supplier_tag = CFG.fuel.supplier_tag or "any",
          node_id = nid,
          reactor_uid = nil,
          need_ingots = need_ing,
          reason = "below_min_agg",
          _auth = CFG.auth_token
        })
        mark_cooldown(key)
      end
    end
  end
end

local function fuel_manager_tick()
  if not (CFG.fuel and CFG.fuel.enable) then return end
  for nid,n in pairs(nodes) do
    if not n.offline then
      pcall(handle_fuel_for_node, nid, n)
    end
  end
end

---------------------------
-- 10) Screens
---------------------------
local selected_node = nil
local broadcast_mode = false

local function node_count() local c=0; for _ in pairs(nodes) do c=c+1 end; return c end
local function node_ids_sorted() local arr={}; for id,_ in pairs(nodes) do table.insert(arr, id) end; table.sort(arr); return arr end

-- Dashboard
local function build_dashboard_screen()
  local s = GUI.mkScreen("dashboard", "Master ▢ Dashboard")
  local kvR  = GUI.mkKV(2,3,28,"Reaktoren:", colors.cyan)
  local kvT  = GUI.mkKV(2,4,28,"Turbinen:",  colors.cyan)
  local kvP  = GUI.mkKV(2,6,28,"Power/t:",   colors.lime)
  local kvRPM= GUI.mkKV(2,7,28,"RPM∑:",      colors.lime)

  local lblM = GUI.mkLabel(32,3,"Induction Matrix", {color=colors.cyan})
  local kvMS = GUI.mkKV(32,4,28,"SoC:", colors.white)
  local kvMI = GUI.mkKV(32,5,28,"In/t:", colors.white)
  local kvMO = GUI.mkKV(32,6,28,"Out/t:", colors.white)
  local barM = GUI.mkBar(32,7,28, colors.lime)

  local lblF = GUI.mkLabel(32,10,"Fuel-Manager", {color=colors.cyan})
  local kvFE = GUI.mkKV(32,11,28,"Status:", colors.white)
  local kvFT = GUI.mkKV(32,12,28,"Ziel %:", colors.white)
  local kvFM = GUI.mkKV(32,13,28,"Min  %:", colors.white)
  local btnFT = GUI.mkButton(32,15,13,3,"Toggle", function()
    CFG.fuel.enable = not CFG.fuel.enable
  end, colors.orange)

  s:add(kvR); s:add(kvT); s:add(kvP); s:add(kvRPM)
  s:add(lblM); s:add(kvMS); s:add(kvMI); s:add(kvMO); s:add(barM)
  s:add(lblF); s:add(kvFE); s:add(kvFT); s:add(kvFM); s:add(btnFT)

  s.onShow = function()
    local A = agg_totals()
    kvR.props.value   = string.format("%d/%d act", A.reactors.active or 0, A.reactors.count or 0)
    kvT.props.value   = string.format("%d/%d act", A.turbines.active or 0, A.turbines.count or 0)
    kvP.props.value   = string.format("%d kFE", math.floor((A.turbines.prod or 0)/1000))
    kvRPM.props.value = math.floor(A.turbines.rpm or 0)

    if matrix_last then
      local pctv = math.floor((matrix_last.soc or 0)*100 + 0.5)
      kvMS.props.value = string.format("%3d%% (%s)", pctv, matrix_last.name or "?")
      kvMI.props.value = tostring(matrix_last.inFEt or 0)  .. " FE/t"
      kvMO.props.value = tostring(matrix_last.outFEt or 0) .. " FE/t"
      barM.props.value = matrix_last.soc or 0
    else
      kvMS.props.value, kvMI.props.value, kvMO.props.value = "—", "—", "—"
      barM.props.value = 0
    end

    kvFE.props.value = CFG.fuel.enable and "AN" or "AUS"
    kvFT.props.value = tostring(CFG.fuel.target_pct or 60)
    kvFM.props.value = tostring(CFG.fuel.min_pct or 20)
  end

  return s
end

-- Control
local function build_control_screen()
  local s = GUI.mkScreen("control", "Master ▢ Control")
  local list_x, list_y, list_w, list_h = 2,3,28,12
  local rows = {}; local page, perPage = 1, 10
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
    local payload = {type="CMD", target="reactor", cmd="setActive", value=true, _auth=CFG.auth_token}
    if broadcast_mode or not selected_node then for id,_ in pairs(nodes) do rednet.send(id, payload) end else rednet.send(selected_node, payload) end
  end, colors.lime)
  local btnOff = GUI.mkButton(ax,7,16,3,"Reakt OFF", function()
    local payload = {type="CMD", target="reactor", cmd="setActive", value=false, _auth=CFG.auth_token}
    if broadcast_mode or not selected_node then for id,_ in pairs(nodes) do rednet.send(id, payload) end else rednet.send(selected_node, payload) end
  end, colors.red)
  local btnInd = GUI.mkButton(ax,11,16,3,"Inductor", function()
    local payload = {type="CMD", target="turbine", cmd="setInductorEngaged", value=true, _auth=CFG.auth_token}
    if broadcast_mode or not selected_node then for id,_ in pairs(nodes) do rednet.send(id, payload) end else rednet.send(selected_node, payload) end
  end, colors.cyan)
  local btnAuto= GUI.mkButton(ax,15,16,3,"AutoTune", function()
    local payload = {type="CMD", target="turbine", cmd="autotune", target_rpm=1800, timeout_s=25, _auth=CFG.auth_token}
    if broadcast_mode or not selected_node then for id,_ in pairs(nodes) do rednet.send(id, payload) end else rednet.send(selected_node, payload) end
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

-- Config (+ Monitore, Scale & Fuel)
local function build_config_screen()
  local s = GUI.mkScreen("config", "Master ▢ Konfiguration")
  s:add(GUI.mkKV(2,3,36,"Modem:", colors.cyan))
  s:add(GUI.mkKV(2,4,36,"Auth:",  colors.cyan))
  s:add(GUI.mkKV(2,6,36,"Mon Dashboard:", colors.white))
  s:add(GUI.mkKV(2,7,36,"Mon Control:",   colors.white))
  s:add(GUI.mkKV(2,8,36,"Mon Config:",    colors.white))
  s:add(GUI.mkKV(2,10,36,"Matrix Name:",  colors.cyan))
  s:add(GUI.mkKV(2,11,36,"Matrix Wired:", colors.cyan))
  s:add(GUI.mkKV(2,13,36,"Mon-Wired-Side:", colors.cyan))

  s:add(GUI.mkKV(2,15,36,"Scale Dashboard:", colors.white))
  s:add(GUI.mkKV(2,16,36,"Scale Control:",   colors.white))
  s:add(GUI.mkKV(2,17,36,"Scale Config:",    colors.white))

  -- Fuel-Settings
  s:add(GUI.mkKV(2,19,36,"Fuel: Status:", colors.cyan))
  s:add(GUI.mkKV(2,20,36,"Fuel: Min%:",   colors.white))
  s:add(GUI.mkKV(2,21,36,"Fuel: Ziel%:",  colors.white))
  s:add(GUI.mkKV(2,22,36,"Fuel: Unit:",   colors.white))
  s:add(GUI.mkKV(2,23,36,"Fuel: Cooldown:", colors.white))

  s:add(GUI.mkButton(39,3,20,3,"Monitore", function()
    term.setCursorPos(1,1); term.setTextColor(colors.white); term.setBackgroundColor(colors.black); term.clear()
    print("Monitore zuweisen")
    print("-----------------")
    local mons = list_monitors()
    if #mons==0 then print("Keine Monitore gefunden.") else
      print("Gefundene Monitore:"); for i,name in ipairs(mons) do print(("[%2d] %s"):format(i,name)) end
    end
    local function pick(label, cur)
      print(label.." (Index oder Name; leer=skip)")
      if cur then print("Aktuell: "..tostring(cur)) end
      write("> "); local v=read()
      if v=="" then return cur end
      local idx=tonumber(v); if idx and mons[idx] then return mons[idx] end
      return v
    end
    UI_STATE.views.dashboard = pick("Dashboard", UI_STATE.views.dashboard)
    UI_STATE.views.control   = pick("Control",   UI_STATE.views.control)
    UI_STATE.views.config    = pick("Config",    UI_STATE.views.config)
    persist_ui(); rebuild_routers()
  end, colors.cyan))

  s:add(GUI.mkButton(39,7,20,3,"Mon-Wired set", function()
    term.setCursorPos(1,1); term.setTextColor(colors.white); term.setBackgroundColor(colors.black); term.clear()
    print("Wired-Modem-Seite für Monitor-Scan setzen (leer=entfernen)")
    print("Aktuell: "..tostring(CFG.monitor_wired_side or "-"))
    write("> "); local w=read()
    CFG.monitor_wired_side = (w~="" and w) or nil
  end, colors.orange))

  s.add_scale = GUI.mkButton(39,11,20,3,"Scale Setup", function()
    term.setCursorPos(1,1); term.setTextColor(colors.white); term.setBackgroundColor(colors.black); term.clear()
    local function setup_one(view)
      local opts = UI_STATE.view_opts[view]
      print(("View: %s"):format(view))
      print(("  Autoscale (aktuell: %s) y/n/leer"):format(opts.autoscale and "ON" or "OFF"))
      write("> "); local a=read(); if a=="y" or a=="Y" then opts.autoscale=true elseif a=="n" or a=="N" then opts.autoscale=false end
      if opts.autoscale then
        print(("  desired_cols (aktuell: %d)"):format(opts.desired_cols)); write("> "); local d=read(); if d~="" then opts.desired_cols=tonumber(d) or opts.desired_cols end
        print(("  correction   (aktuell: %.1f)"):format(opts.correction)); write("> "); local c=read(); if c~="" then opts.correction=tonumber(c) or opts.correction end
      else
        print(("  manual scale (aktuell: %.1f)"):format(opts.manual)); write("> "); local m=read(); if m~="" then opts.manual=tonumber(m) or opts.manual end
      end
      print("")
    end
    setup_one("dashboard"); setup_one("control"); setup_one("config")
    persist_ui(); rebuild_routers()
  end, colors.green)
  s:add(s.add_scale)

  -- Fuel Setup
  s:add(GUI.mkButton(39,15,20,3,"Fuel Setup", function()
    term.setCursorPos(1,1); term.setTextColor(colors.white); term.setBackgroundColor(colors.black); term.clear()
    print("Fuel-Management Einstellungen")
    print(("Aktiv (y/n) aktuell: %s"):format(CFG.fuel.enable and "y" or "n"))
    write("> "); local a=read(); if a=="y" or a=="Y" then CFG.fuel.enable=true elseif a=="n" or a=="N" then CFG.fuel.enable=false end
    print(("Min%% (aktuell: %d)"):format(CFG.fuel.min_pct)); write("> "); local mn=read(); if mn~="" then CFG.fuel.min_pct=tonumber(mn) or CFG.fuel.min_pct end
    print(("Ziel%% (aktuell: %d)"):format(CFG.fuel.target_pct)); write("> "); local tg=read(); if tg~="" then CFG.fuel.target_pct=tonumber(tg) or CFG.fuel.target_pct end
    print(("Unit Ingots (aktuell: %d)"):format(CFG.fuel.request_unit)); write("> "); local un=read(); if un~="" then CFG.fuel.request_unit=math.max(1, tonumber(un) or CFG.fuel.request_unit) end
    print(("Cooldown s (aktuell: %d)"):format(CFG.fuel.cooldown_s)); write("> "); local cd=read(); if cd~="" then CFG.fuel.cooldown_s=math.max(10, tonumber(cd) or CFG.fuel.cooldown_s) end
    print(("Supplier-Tag (aktuell: %s)"):format(CFG.fuel.supplier_tag or "any")); write("> "); local st=read(); if st~="" then CFG.fuel.supplier_tag=st end
    print("Gespeichert. ENTER…"); read()
  end, colors.orange))

  s:add(GUI.mkButton(2,25,12,3,"Zurück", function() end))

  s.onShow = function()
    s.widgets[1].props.value  = CFG.modem_side
    s.widgets[2].props.value  = CFG.auth_token
    s.widgets[3].props.value  = UI_STATE.views.dashboard or "-"
    s.widgets[4].props.value  = UI_STATE.views.control   or "-"
    s.widgets[5].props.value  = UI_STATE.views.config    or "-"
    s.widgets[6].props.value  = (CFG.matrix and CFG.matrix.name) or "(auto)"
    s.widgets[7].props.value  = (CFG.matrix and CFG.matrix.wired_side) or "-"
    s.widgets[8].props.value  = CFG.monitor_wired_side or "-"

    local sd = compute_scale_for_view("dashboard") or "-"
    local sc = compute_scale_for_view("control")   or "-"
    local sg = compute_scale_for_view("config")    or "-"
    s.widgets[9].props.value  = tostring(sd)
    s.widgets[10].props.value = tostring(sc)
    s.widgets[11].props.value = tostring(sg)

    -- Fuel-Anzeige
    s.widgets[12].props.value = CFG.fuel.enable and "AN" or "AUS"
    s.widgets[13].props.value = tostring(CFG.fuel.min_pct)
    s.widgets[14].props.value = tostring(CFG.fuel.target_pct)
    s.widgets[15].props.value = tostring(CFG.fuel.request_unit).." ing"
    s.widgets[16].props.value = tostring(CFG.fuel.cooldown_s).." s"
  end
  return s
end

---------------------------
-- 11) Netzwerk & Loops
---------------------------
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
        -- optional: UI-Toast
      end
    end
  end
end

local function draw_all() for _,r in pairs(routers) do if r then r:draw() end end end

local function house_loop()
  local t0, tm, tf = 0, 0, 0
  while true do
    local now = os.clock()
    if now - tm >= 1.0 then poll_matrix_once(); tm = now end
    if now - tf >= 2.0 then pcall(fuel_manager_tick); tf = now end
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

---------------------------
-- 12) Init & Start
---------------------------
local function init_screens()
  screens.dashboard = build_dashboard_screen()
  screens.control   = build_control_screen()
  screens.config    = build_config_screen()
end

init_screens()
rebuild_routers()

print(("Master gestartet #%d | Modem:%s | Mon-Wired:%s | Matrix:%s | Fuel: %s")
  :format(MASTER_ID, CFG.modem_side, CFG.monitor_wired_side or "-", (CFG.matrix and CFG.matrix.name) or "(auto)", CFG.fuel.enable and "AN" or "AUS"))

parallel.waitForAny(rx_loop, house_loop, input_loop)