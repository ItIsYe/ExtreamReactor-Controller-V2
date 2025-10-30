--========================================================
-- XReactor • MASTER
--  - Multi-Monitor & Autoscale
--  - Matrix-Anzeige
--  - Fuel-Manager (Phase 1)
--  - Waste-Manager (Phase 2): Drain-Kommandos an Reaktor-Nodes
--========================================================

----------- 1) Config laden ----------
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
  fuel = { enable=true, min_pct=20, target_pct=60, request_unit=4, cooldown_s=90, supplier_tag="any" },
  waste= { enable=true, max_pct=40, cooldown_s=120, batch_amount=4000, tag_receiver="any" },
}
do
  local ok,t = pcall(dofile,"/xreactor/config_master.lua")
  if ok and type(t)=="table" then
    for k,v in pairs(t) do
      if k=="views" and type(v)=="table" then CFG.views=v
      elseif k=="matrix" and type(v)=="table" then for kk,vv in pairs(v) do CFG.matrix[kk]=vv end
      elseif k=="default_view_scale" and type(v)=="table" then CFG.default_view_scale=v
      elseif k=="fuel" and type(v)=="table" then for kk,vv in pairs(v) do CFG.fuel[kk]=vv end
      elseif k=="waste" and type(v)=="table" then for kk,vv in pairs(v) do CFG.waste[kk]=vv end
      else CFG[k]=v end
    end
  end
end

----------- 2) Persistenz UI ----------
local UI_PATH = "/xreactor/ui_master.json"
local function load_json(p) if not fs.exists(p) then return nil end local f=fs.open(p,"r"); local s=f.readAll() or ""; f.close(); local ok,t=pcall(textutils.unserializeJSON,s); return ok and t or nil end
local function save_json(p,tbl) local s=textutils.serializeJSON(tbl,true); fs.makeDir(fs.getDir(p)); local f=fs.open(p,"w"); f.write(s or "{}"); f.close() end

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
    if ui.view_opts then for k,ov in pairs(ui.view_opts) do UI_STATE.view_opts[k]=UI_STATE.view_opts[k] or {}; for kk,vv in pairs(ov) do UI_STATE.view_opts[k][kk]=vv end end end
  end
  for k,v in pairs(UI_STATE.views) do CFG.views[k]=v end
end
local function persist_ui() save_json(UI_PATH,{views=UI_STATE.views, view_opts=UI_STATE.view_opts}) end

----------- 3) Rednet ----------
assert(peripheral.getType(CFG.modem_side)=="modem", "Kein Modem an "..tostring(CFG.modem_side))
rednet.open(CFG.modem_side)
local MASTER_ID = os.getComputerID()

----------- 4) Datenhaltung ----------
local nodes = {}  -- [id]={last, offline, telem, caps}
local function age_sec(ms) return math.floor((os.epoch("utc")-(ms or 0))/1000) end
local function mark_timeouts() for id,n in pairs(nodes) do n.offline = age_sec(n.last or 0) > CFG.telem_timeout_s end end
local function agg_totals()
  local A={reactors={count=0,active=0,fuel=0,fuel_max=0,waste=0,waste_max=0}, turbines={count=0,active=0,rpm=0,prod=0}}
  for _,n in pairs(nodes) do
    local ag=n.telem and n.telem.agg
    if ag then
      for k,v in pairs(ag.reactors or {}) do A.reactors[k]=(A.reactors[k] or 0)+(v or 0) end
      for k,v in pairs(ag.turbines or {}) do A.turbines[k]=(A.turbines[k] or 0)+(v or 0) end
    end
  end
  return A
end

----------- 5) Matrix ----------
local ok_mx, MATRIX = pcall(require,"xreactor.shared.matrix")
if not ok_mx and fs.exists("/xreactor/shared/matrix.lua") then MATRIX=dofile("/xreactor/shared/matrix.lua") end
local matrix_last=nil
local function poll_matrix_once() if not (CFG.matrix and CFG.matrix.enable and MATRIX) then matrix_last=nil; return end local d=select(1, MATRIX.read({name=CFG.matrix.name, wired_side=CFG.matrix.wired_side})); matrix_last=d or nil end

----------- 6) GUI Toolkit ----------
local ok_gui, GUI = pcall(require,"xreactor.shared.gui")
if not ok_gui then GUI=dofile("/xreactor/shared/gui.lua") end

----------- 7) Monitore finden ----------
local function list_monitors()
  local list={}
  for _,n in ipairs(peripheral.getNames()) do if peripheral.getType(n)=="monitor" then table.insert(list,n) end end
  if CFG.monitor_wired_side and peripheral.getType(CFG.monitor_wired_side)=="modem" then
    local wm=peripheral.wrap(CFG.monitor_wired_side); if wm and wm.getNamesRemote then
      for _,rn in ipairs(wm.getNamesRemote()) do if peripheral.getType(rn)=="monitor" then table.insert(list,rn) end end
    end
  end
  table.sort(list); return list
end

----------- 8) Autoscale ----------
local function round_half(x) return math.max(0.5, math.min(5.0, math.floor(x*2+0.5)/2)) end
local function suggest_scale(mon, cols)
  local best_s, best_diff=0.5, math.huge
  for s=0.5,5.0,0.5 do pcall(mon.setTextScale,s); local w=select(1,mon.getSize()); if w then local d=(w>=cols) and (w-cols) or math.huge; if d<best_diff then best_diff=d; best_s=s end end end
  return best_s
end
local function compute_scale(view)
  local mname=UI_STATE.views[view]; if not mname then return nil end
  local mon=peripheral.wrap(mname); if not mon or not mon.setTextScale then return nil end
  local o=UI_STATE.view_opts[view] or {}; local s
  if (o.autoscale~=false) then s=suggest_scale(mon, tonumber(o.desired_cols or 60) or 60); s=round_half(s+(tonumber(o.correction or 0) or 0))
  else s=round_half(tonumber(o.manual or 1.0) or 1.0) end
  return s
end

----------- 9) Router/Screens ----------
local routers={}; local screens={}
local function mk_router(view) local name=UI_STATE.views[view]; local sc=compute_scale(view); local r=GUI.mkRouter({monitorName=name, textScale=sc}); r:register(screens[view]); r:show(view); return r end
local function rebuild_routers()
  routers.dashboard = mk_router("dashboard") or GUI.mkRouter({})
  routers.control   = mk_router("control")   or GUI.mkRouter({})
  routers.config    = mk_router("config")    or GUI.mkRouter({})
  routers.dashboard:register(screens.dashboard); routers.dashboard:show("dashboard")
  routers.control:register(screens.control);     routers.control:show("control")
  routers.config:register(screens.config);       routers.config:show("config")
end

----------- 10) Fuel-Manager (Phase 1) ----------
local fuel_state={ last_req={} }
local function now_s() return os.epoch("utc")/1000 end
local function pct(a,b) if not b or b<=0 then return 0 end return (a or 0)/b*100 end
local function floor_unit(x,u) if u<=0 then return math.max(0,math.floor(x)) end return math.max(0, math.floor(x/u)*u) end
local function cd_get(t,k) local v=t[k] or 0; return (now_s()-v) end
local function cd_mark(t,k) t[k]=now_s() end

local function fuel_for_node(nid,n)
  if not (CFG.fuel and CFG.fuel.enable) then return end
  local minp=CFG.fuel.min_pct or 20; local targ=math.max(minp, CFG.fuel.target_pct or 60); local unit=math.max(1, CFG.fuel.request_unit or 4)
  local reactors = n.telem and n.telem.reactors
  if type(reactors)=="table" and #reactors>0 then
    for _,r in ipairs(reactors) do
      local uid=r.uid or r.id or tostring(_); local f=tonumber(r.fuel or 0); local fm=tonumber(r.fuel_max or 0)
      if fm and fm>0 and pct(f,fm) < minp then
        local target=math.floor(targ/100*fm); local need=math.max(0, target-(f or 0)); local need_ing=floor_unit(math.floor((need/1000)+0.5), unit)
        local key="rx:"..tostring(uid)
        if need_ing>0 and cd_get(fuel_state.last_req,key) >= (CFG.fuel.cooldown_s or 90) then
          rednet.broadcast({type="FUEL_REQ", supplier_tag=CFG.fuel.supplier_tag or "any", node_id=nid, reactor_uid=uid, need_ingots=need_ing, reason="below_min", _auth=CFG.auth_token})
          cd_mark(fuel_state.last_req,key)
        end
      end
    end
    return
  end
  local ag=n.telem and n.telem.agg
  if ag and ag.reactors then
    local f=tonumber(ag.reactors.fuel or 0); local fm=tonumber(ag.reactors.fuel_max or 0)
    if fm and fm>0 and pct(f,fm) < minp then
      local target=math.floor(targ/100*fm); local need=math.max(0, target-(f or 0)); local need_ing=floor_unit(math.floor((need/1000)+0.5), unit)
      local key="node:"..tostring(nid)
      if need_ing>0 and cd_get(fuel_state.last_req,key) >= (CFG.fuel.cooldown_s or 90) then
        rednet.broadcast({type="FUEL_REQ", supplier_tag=CFG.fuel.supplier_tag or "any", node_id=nid, reactor_uid=nil, need_ingots=need_ing, reason="below_min_agg", _auth=CFG.auth_token})
        cd_mark(fuel_state.last_req,key)
      end
    end
  end
end

local function fuel_manager_tick() if not (CFG.fuel and CFG.fuel.enable) then return end for nid,n in pairs(nodes) do if not n.offline then pcall(fuel_for_node,nid,n) end end end

----------- 11) Waste-Manager (Phase 2) ----------
local waste_state={ last_cmd={} }
local function waste_for_node(nid,n)
  if not (CFG.waste and CFG.waste.enable) then return end
  local maxp=CFG.waste.max_pct or 40
  local reactors = n.telem and n.telem.reactors
  if type(reactors)=="table" and #reactors>0 then
    for _,r in ipairs(reactors) do
      local uid=r.uid or r.id or tostring(_); local w=tonumber(r.waste or 0); local wm=tonumber(r.waste_max or 0)
      if wm and wm>0 then
        local pw=pct(w,wm)
        local key="wx:"..tostring(uid)
        if pw>=maxp and cd_get(waste_state.last_cmd,key) >= (CFG.waste.cooldown_s or 120) then
          rednet.send(nid, {type="CMD", target="reactor", cmd="WASTE_DRAIN", reactor_uid=uid, amount=CFG.waste.batch_amount or 4000, _auth=CFG.auth_token})
          cd_mark(waste_state.last_cmd,key)
        end
      end
    end
    return
  end
  local ag=n.telem and n.telem.agg
  if ag and ag.reactors then
    local w=tonumber(ag.reactors.waste or 0); local wm=tonumber(ag.reactors.waste_max or 0)
    local key="node:"..tostring(nid)
    if wm and wm>0 and pct(w,wm)>=maxp and cd_get(waste_state.last_cmd,key) >= (CFG.waste.cooldown_s or 120) then
      rednet.send(nid, {type="CMD", target="reactor", cmd="WASTE_DRAIN", reactor_uid=nil, amount=CFG.waste.batch_amount or 4000, _auth=CFG.auth_token})
      cd_mark(waste_state.last_cmd,key)
    end
  end
end
local function waste_manager_tick() if not (CFG.waste and CFG.waste.enable) then return end for nid,n in pairs(nodes) do if not n.offline then pcall(waste_for_node,nid,n) end end end

----------- 12) Screens (Dashboard/Control/Config) ----------
local selected_node=nil; local broadcast_mode=false
local function node_ids_sorted() local t={}; for id,_ in pairs(nodes) do table.insert(t,id) end table.sort(t); return t end
local function node_count() local c=0; for _ in pairs(nodes) do c=c+1 end return c end

local function build_dashboard_screen()
  local s=GUI.mkScreen("dashboard","Master ▢ Dashboard")
  local kvR=GUI.mkKV(2,3,28,"Reaktoren:",colors.cyan)
  local kvT=GUI.mkKV(2,4,28,"Turbinen:",colors.cyan)
  local kvP=GUI.mkKV(2,6,28,"Power/t:",colors.lime)
  local kvRPM=GUI.mkKV(2,7,28,"RPM∑:",colors.lime)

  local lblM=GUI.mkLabel(32,3,"Induction Matrix",{color=colors.cyan})
  local kvMS=GUI.mkKV(32,4,28,"SoC:",colors.white)
  local kvMI=GUI.mkKV(32,5,28,"In/t:",colors.white)
  local kvMO=GUI.mkKV(32,6,28,"Out/t:",colors.white)
  local barM=GUI.mkBar(32,7,28,colors.lime)

  local lblF=GUI.mkLabel(32,10,"Fuel-Manager",{color=colors.cyan})
  local kvFE=GUI.mkKV(32,11,28,"Status:",colors.white)

  local lblW=GUI.mkLabel(32,13,"Waste-Manager",{color=colors.cyan})
  local kvWE=GUI.mkKV(32,14,28,"Status:",colors.white)
  local kvWL=GUI.mkKV(32,15,28,"Max%:",colors.white)
  local kvWB=GUI.mkKV(32,16,28,"Batch:",colors.white)

  s:add(kvR); s:add(kvT); s:add(kvP); s:add(kvRPM)
  s:add(lblM); s:add(kvMS); s:add(kvMI); s:add(kvMO); s:add(barM)
  s:add(lblF); s:add(kvFE); s:add(lblW); s:add(kvWE); s:add(kvWL); s:add(kvWB)

  s.onShow=function()
    local A=agg_totals()
    kvR.props.value=string.format("%d/%d act",A.reactors.active or 0,A.reactors.count or 0)
    kvT.props.value=string.format("%d/%d act",A.turbines.active or 0,A.turbines.count or 0)
    kvP.props.value=string.format("%d kFE",math.floor((A.turbines.prod or 0)/1000))
    kvRPM.props.value=math.floor(A.turbines.rpm or 0)

    if matrix_last then
      local p=math.floor((matrix_last.soc or 0)*100+0.5)
      kvMS.props.value=string.format("%3d%% (%s)",p,matrix_last.name or "?")
      kvMI.props.value=tostring(matrix_last.inFEt or 0).." FE/t"
      kvMO.props.value=tostring(matrix_last.outFEt or 0).." FE/t"
      barM.props.value=matrix_last.soc or 0
    else kvMS.props.value,kvMI.props.value,kvMO.props.value="—","—","—"; barM.props.value=0 end

    kvFE.props.value = CFG.fuel.enable and "AN" or "AUS"
    kvWE.props.value = CFG.waste.enable and "AN" or "AUS"
    kvWL.props.value = tostring(CFG.waste.max_pct or 40)
    kvWB.props.value = tostring(CFG.waste.batch_amount or 4000).." mB"
  end
  return s
end

local function build_control_screen()
  local s=GUI.mkScreen("control","Master ▢ Control")
  local list_x,list_y,list_w,list_h=2,3,28,12
  local rows={}; local page,perPage=1,10
  local lbl=GUI.mkLabel(list_x,list_y-1,"Nodes (klicken zum Auswählen)",{color=colors.cyan}); s:add(lbl)
  local btnPrev=GUI.mkButton(list_x,list_y+list_h+1,8,3,"◀ Prev",function() page=math.max(1,page-1); s.onShow() end)
  local btnNext=GUI.mkButton(list_x+list_w-8,list_y+list_h+1,8,3,"Next ▶",function() local total=node_count(); local pages=math.max(1,math.ceil(total/perPage)); page=math.min(pages,page+1); s.onShow() end)
  s:add(btnPrev); s:add(btnNext)
  for i=1,perPage do local y=list_y+(i-1); local b=GUI.mkButton(list_x,y,list_w,1,("—"):rep(list_w),function() local idx=(page-1)*perPage+i; local ids=node_ids_sorted(); local id=ids[idx]; if id then selected_node=id; broadcast_mode=false; s.onShow() end end, colors.gray); rows[i]=b; s:add(b) end
  local ax=32
  local btnOn=GUI.mkButton(ax,3,16,3,"Reakt ON",function() local p={type="CMD",target="reactor",cmd="setActive",value=true,_auth=CFG.auth_token}; if broadcast_mode or not selected_node then for id,_ in pairs(nodes) do rednet.send(id,p) end else rednet.send(selected_node,p) end end, colors.lime)
  local btnOff=GUI.mkButton(ax,7,16,3,"Reakt OFF",function() local p={type="CMD",target="reactor",cmd="setActive",value=false,_auth=CFG.auth_token}; if broadcast_mode or not selected_node then for id,_ in pairs(nodes) do rednet.send(id,p) end else rednet.send(selected_node,p) end end, colors.red)
  local btnDrain=GUI.mkButton(ax,11,16,3,"Waste DRAIN",function() local p={type="CMD",target="reactor",cmd="WASTE_DRAIN", amount=CFG.waste.batch_amount,_auth=CFG.auth_token}; if broadcast_mode or not selected_node then for id,_ in pairs(nodes) do rednet.send(id,p) end else rednet.send(selected_node,p) end end, colors.orange)
  local btnBrc=GUI.mkButton(ax,15,16,3,"Broadcast",function() broadcast_mode=true; selected_node=nil; s.onShow() end, colors.gray)
  local lblSel=GUI.mkLabel(ax,19,"Ziel: —",{color=colors.white})
  s:add(btnOn); s:add(btnOff); s:add(btnDrain); s:add(btnBrc); s:add(lblSel)

  local function rowtxt(id) local n=nodes[id] or {}; local ag=n.telem and n.telem.agg; local aR,cR=(ag and ag.reactors and ag.reactors.active) or 0, (ag and ag.reactors and ag.reactors.count) or 0; local aT,cT=(ag and ag.turbines and ag.turbines.active) or 0, (ag and ag.turbines and ag.turbines.count) or 0; local stat=(n.offline and "OFF") or " ON "; return string.format("Node #%d  R:%d/%d T:%d/%d [%s]",id,aR,cR,aT,cT,stat) end
  s.onShow=function()
    local ids=node_ids_sorted(); local total=#ids; local pages=math.max(1,math.ceil(total/perPage)); if page>pages then page=pages end
    local start=(page-1)*perPage+1
    for i=1,perPage do local idx=start+(i-1); local row=rows[i]; if idx<=total then local id=ids[idx]; row.props.text=rowtxt(id); local n=nodes[id]; row.props.color=(selected_node==id and colors.lightBlue) or (n.offline and colors.red or colors.gray); row.hidden=false else row.props.text=""; row.hidden=true end end
    if broadcast_mode or not selected_node then lblSel.props.text="Ziel: Broadcast (alle)"; lblSel.props.color=colors.lightGray else lblSel.props.text=("Ziel: Node #%d"):format(selected_node); lblSel.props.color=colors.white end
  end
  return s
end

local function build_config_screen()
  local s=GUI.mkScreen("config","Master ▢ Konfiguration")
  s:add(GUI.mkKV(2,3,36,"Modem:",colors.cyan))
  s:add(GUI.mkKV(2,4,36,"Auth:", colors.cyan))
  s:add(GUI.mkKV(2,6,36,"Mon Dashboard:",colors.white))
  s:add(GUI.mkKV(2,7,36,"Mon Control:",  colors.white))
  s:add(GUI.mkKV(2,8,36,"Mon Config:",   colors.white))
  s:add(GUI.mkKV(2,10,36,"Matrix Name:", colors.cyan))
  s:add(GUI.mkKV(2,11,36,"Matrix Wired:",colors.cyan))
  s:add(GUI.mkKV(2,13,36,"Mon-Wired-Side:",colors.cyan))
  s:add(GUI.mkKV(2,15,36,"Fuel:",colors.cyan))
  s:add(GUI.mkKV(2,16,36,"Waste:",colors.cyan))

  s:add(GUI.mkButton(39,3,20,3,"Monitore",function()
    term.setCursorPos(1,1); term.setTextColor(colors.white); term.setBackgroundColor(colors.black); term.clear()
    print("Monitore zuweisen"); local mons=list_monitors(); if #mons==0 then print("Keine Monitore gefunden.") else print("Gefundene Monitore:") for i,n in ipairs(mons) do print(("[%2d] %s"):format(i,n)) end end
    local function pick(label,cur) print(label.." (Index/Name, leer=skip)"); if cur then print("Aktuell: "..tostring(cur)) end; write("> "); local v=read(); if v=="" then return cur end local i=tonumber(v); if i and mons[i] then return mons[i] end return v end
    UI_STATE.views.dashboard=pick("Dashboard",UI_STATE.views.dashboard)
    UI_STATE.views.control  =pick("Control",UI_STATE.views.control)
    UI_STATE.views.config   =pick("Config",UI_STATE.views.config)
    persist_ui(); rebuild_routers()
  end, colors.cyan))

  s:add(GUI.mkButton(39,7,20,3,"Mon-Wired set",function()
    term.setCursorPos(1,1); term.setTextColor(colors.white); term.setBackgroundColor(colors.black); term.clear()
    print("Wired-Modem-Seite (leer=entfernen)"); print("Aktuell: "..tostring(CFG.monitor_wired_side or "-")); write("> "); local w=read(); CFG.monitor_wired_side=(w~="" and w) or nil
  end, colors.orange))

  s:add(GUI.mkButton(39,11,20,3,"Scale Setup",function()
    term.setCursorPos(1,1); term.setTextColor(colors.white); term.setBackgroundColor(colors.black); term.clear()
    local function one(view) local o=UI_STATE.view_opts[view]; print("View: "..view); print("  Autoscale "..(o.autoscale and "ON" or "OFF").." (y/n/leer)"); write("> "); local a=read(); if a=="y" or a=="Y" then o.autoscale=true elseif a=="n" or a=="N" then o.autoscale=false end
      if o.autoscale then print("  desired_cols ("..o.desired_cols..")"); write("> "); local d=read(); if d~="" then o.desired_cols=tonumber(d) or o.desired_cols end
        print("  correction ("..o.correction..")"); write("> "); local c=read(); if c~="" then o.correction=tonumber(c) or o.correction end
      else print("  manual ("..o.manual..")"); write("> "); local m=read(); if m~="" then o.manual=tonumber(m) or o.manual end end
      print("")
    end
    one("dashboard"); one("control"); one("config"); persist_ui(); rebuild_routers()
  end, colors.green))

  s:add(GUI.mkButton(39,15,20,3,"Fuel Setup",function()
    term.setCursorPos(1,1); term.setTextColor(colors.white); term.setBackgroundColor(colors.black); term.clear()
    print("Fuel-Management"); print("Aktiv (y/n) aktuell: "..(CFG.fuel.enable and "y" or "n")); write("> "); local a=read(); if a=="y" or a=="Y" then CFG.fuel.enable=true elseif a=="n" or a=="N" then CFG.fuel.enable=false end
    print("Min% ("..CFG.fuel.min_pct..")"); write("> "); local mn=read(); if mn~="" then CFG.fuel.min_pct=tonumber(mn) or CFG.fuel.min_pct end
    print("Ziel% ("..CFG.fuel.target_pct..")"); write("> "); local tg=read(); if tg~="" then CFG.fuel.target_pct=tonumber(tg) or CFG.fuel.target_pct end
    print("Unit Ingots ("..CFG.fuel.request_unit..")"); write("> "); local un=read(); if un~="" then CFG.fuel.request_unit=math.max(1,tonumber(un) or CFG.fuel.request_unit) end
    print("Cooldown s ("..CFG.fuel.cooldown_s..")"); write("> "); local cd=read(); if cd~="" then CFG.fuel.cooldown_s=math.max(10,tonumber(cd) or CFG.fuel.cooldown_s) end
    print("Supplier-Tag ("..(CFG.fuel.supplier_tag or "any")..")"); write("> "); local st=read(); if st~="" then CFG.fuel.supplier_tag=st end
    print("ENTER…"); read()
  end, colors.orange))

  s:add(GUI.mkButton(39,19,20,3,"Waste Setup",function()
    term.setCursorPos(1,1); term.setTextColor(colors.white); term.setBackgroundColor(colors.black); term.clear()
    print("Waste-Management (Drain über Nodes)")
    print("Aktiv (y/n) aktuell: "..(CFG.waste.enable and "y" or "n")); write("> "); local a=read(); if a=="y" or a=="Y" then CFG.waste.enable=true elseif a=="n" or a=="N" then CFG.waste.enable=false end
    print("Max% ("..CFG.waste.max_pct..")"); write("> "); local mp=read(); if mp~="" then CFG.waste.max_pct=tonumber(mp) or CFG.waste.max_pct end
    print("Cooldown s ("..CFG.waste.cooldown_s..")"); write("> "); local cd=read(); if cd~="" then CFG.waste.cooldown_s=math.max(10,tonumber(cd) or CFG.waste.cooldown_s) end
    print("Batch mB ("..CFG.waste.batch_amount..")"); write("> "); local ba=read(); if ba~="" then CFG.waste.batch_amount=math.max(0,tonumber(ba) or CFG.waste.batch_amount) end
    print("Receiver-Tag ("..(CFG.waste.tag_receiver or "any")..")"); write("> "); local tr=read(); if tr~="" then CFG.waste.tag_receiver=tr end
    print("ENTER…"); read()
  end, colors.orange))

  s:add(GUI.mkButton(2,23,12,3,"Zurück",function() end))

  s.onShow=function()
    s.widgets[1].props.value=CFG.modem_side
    s.widgets[2].props.value=CFG.auth_token
    s.widgets[3].props.value=UI_STATE.views.dashboard or "-"
    s.widgets[4].props.value=UI_STATE.views.control or "-"
    s.widgets[5].props.value=UI_STATE.views.config or "-"
    s.widgets[6].props.value=(CFG.matrix and CFG.matrix.name) or "(auto)"
    s.widgets[7].props.value=(CFG.matrix and CFG.matrix.wired_side) or "-"
    s.widgets[8].props.value=CFG.monitor_wired_side or "-"
    s.widgets[9].props.value = (CFG.fuel.enable and "Fuel: AN" or "Fuel: AUS").." / "..(CFG.waste.enable and "Waste: AN" or "Waste: AUS")
    s.widgets[10].props.value= "—"
  end
  return s
end

----------- 13) Netzwerk/Loops ----------
local function rx_loop()
  while true do
    local id,msg = rednet.receive(1)
    if id and type(msg)=="table" and msg._auth==CFG.auth_token then
      if msg.type=="HELLO" then
        nodes[id]=nodes[id] or {}; nodes[id].caps = msg.caps or nodes[id].caps or {}; nodes[id].last=os.epoch("utc"); nodes[id].offline=false
        rednet.send(id, {type="HELLO_ACK", master=MASTER_ID, _auth=CFG.auth_token})
      elseif msg.type=="TELEM" then
        nodes[id]=nodes[id] or {}; nodes[id].telem = msg.telem or nodes[id].telem; nodes[id].last=os.epoch("utc"); nodes[id].offline=false
      elseif msg.type=="CMD_ACK" then
        -- optional: Status-Toast
      end
    end
  end
end

local function draw_all() for _,r in pairs(routers) do if r then r:draw() end end end

local function house_loop()
  local t0,tm,tf,tw=0,0,0,0
  while true do
    local now=os.clock()
    if now-tm>=1.0 then pcall(poll_matrix_once); tm=now end
    if now-tf>=2.0 then pcall(fuel_manager_tick); tf=now end
    if now-tw>=2.0 then pcall(waste_manager_tick); tw=now end
    if now-t0>=CFG.redraw_interval then
      mark_timeouts()
      if screens.dashboard then pcall(screens.dashboard.onShow, screens.dashboard) end
      if screens.control   then pcall(screens.control.onShow,   screens.control)   end
      if screens.config    then pcall(screens.config.onShow,    screens.config)    end
      draw_all(); t0=now
    end
    os.sleep(0.05)
  end
end

local function input_loop()
  while true do
    local ev={os.pullEvent()}
    if ev[1]=="monitor_touch" then local side,x,y=ev[2],ev[3],ev[4]; for _,r in pairs(routers) do local mon=r and r.monSurf and peripheral.getName(r.monSurf.t); if mon and mon==side then r:handleTouch(ev[1],side,x,y) end end
    elseif ev[1]=="mouse_click" then local btn,x,y=ev[2],ev[3],ev[4]; for _,r in pairs(routers) do if r then r:handleTouch("mouse_click",btn,x,y) end end
    elseif ev[1]=="key" then if ev[2]==keys.q then return end end
  end
end

----------- 14) Init/Start ----------
local function build_all() screens.dashboard=build_dashboard_screen(); screens.control=build_control_screen(); screens.config=build_config_screen() end
build_all(); rebuild_routers()
print(("Master #%d | Modem:%s | Waste:%s | Fuel:%s"):format(MASTER_ID, CFG.modem_side, CFG.waste.enable and "ON" or "OFF", CFG.fuel.enable and "ON" or "OFF"))
parallel.waitForAny(rx_loop, house_loop, input_loop)