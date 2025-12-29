--========================================================
-- /xreactor/master/overview_panel.lua
-- System Overview mit Identity (hostname/role/cluster), KPIs & Filtern
--========================================================
local PROTO = dofile("/xreactor/shared/protocol.lua")
local Dispatcher = dofile("/xreactor/shared/network_dispatcher.lua")
local Model = dofile("/xreactor/master/master_model.lua")
local IDMOD = dofile("/xreactor/shared/identity.lua")
local IDENT  = IDMOD.load_identity()

local CFG=(function()
  local t={ auth_token=IDENT.token or "xreactor", modem_side="right", telem_timeout_s=10, ui={text_scale=nil} }
  if fs.exists("/xreactor/config_overview.lua") then local ok,c=pcall(dofile,"/xreactor/config_overview.lua"); if ok and type(c)=="table" then
    t.auth_token=c.auth_token or t.auth_token; t.modem_side=c.modem_side or t.modem_side; t.telem_timeout_s=tonumber(c.telem_timeout_s or t.telem_timeout_s) or t.telem_timeout_s; if c.ui then t.ui=c.ui end
  end end
  return t
end)()

local DISP = Dispatcher.create({auth_token=CFG.auth_token, modem_side=CFG.modem_side, identity=IDENT})
local MODEL = Model.create(DISP, { telem_timeout_s = CFG.telem_timeout_s })
local function bcast(msg) return DISP:publish(msg) end

local GUI; do local ok,g=pcall(require,"xreactor.shared.gui"); if ok then GUI=g elseif fs.exists("/xreactor/shared/gui.lua") then GUI=dofile("/xreactor/shared/gui.lua") end end
local function load_ui_map() if fs.exists("/xreactor/ui_map.lua") then local ok,t=pcall(dofile,"/xreactor/ui_map.lua"); if ok and type(t)=="table" then return t end end; return {monitors={}, autoscale={enabled=false}} end
local UIMAP=load_ui_map()
local function pick_monitor_for_role(role) local name; for n,cfg in pairs(UIMAP.monitors or {}) do if cfg.role==role then name=n break end end; local mon=name and peripheral.wrap(name) or ({peripheral.find("monitor")})[1]; if not mon then return nil end; local e=(UIMAP.monitors or {})[peripheral.getName(mon)]; local s=e and e.scale or (CFG.ui and CFG.ui.text_scale); if s then pcall(mon.setTextScale, tonumber(s) or 1.0) end; return mon end
local MON=pick_monitor_for_role("system_overview"); if MON and not GUI then pcall(MON.setTextScale, 0.5) end

local Topbar = dofile("/xreactor/shared/topbar.lua")
local TOPBAR_CFG = { window_s = 300, health = { timeout_s = 10, warn_s = 20, crit_s = 60, min_nodes = 1 } }
local TB; local function go_home() shell.run("/xreactor/master/master_home.lua") end

local redraw_pending=false
local function request_redraw(reason)
  if not (GUI and MON) then return end
  if redraw_pending then return end
  redraw_pending=true
  os.queueEvent("ui_redraw", reason or "update")
end
MODEL:subscribe('overview', function() request_redraw('data') end)
MODEL:subscribe('topbar', function() request_redraw('topbar') end)

local function dispatcher_loop()
  DISP:start()
end

local function compute_kpis()
  local total_power=0; local rpm_sum=0; local rpm_cnt=0; local online=0; local offline=0; local fuel_min=nil; local fuel_max=nil
  local now=now_s()
  for _,n in pairs(STATE.nodes) do
    local is_on = (now-(n.last_seen or 0)) <= (CFG.telem_timeout_s or 10)
    if is_on then online=online+1 else offline=offline+1 end
    total_power=total_power+n0(n.power_mrf,0); rpm_sum=rpm_sum+n0(n.rpm,0); rpm_cnt=rpm_cnt+1
    if n.fuel_pct~=nil then fuel_min=(fuel_min==nil) and n.fuel_pct or math.min(fuel_min,n.fuel_pct); fuel_max=(fuel_max==nil) and n.fuel_pct or math.max(fuel_max,n.fuel_pct) end
  end
  return { total_power=total_power, rpm_avg=(rpm_cnt>0) and math.floor(rpm_sum/rpm_cnt+0.5) or 0, online=online, offline=offline, fuel_min=fuel_min, fuel_max=fuel_max }
end

local function role_match(n) if STATE.filter_role=="ALL" then return true end; return (tostring(n.role or "-"):upper()==STATE.filter_role) end
local function nodes_sorted()
  local arr={}; local now=now_s()
  for _,n in pairs(STATE.nodes) do
    local is_on=(now-(n.last_seen or 0)) <= (CFG.telem_timeout_s or 10)
    if ((not STATE.filter_online) or is_on) and role_match(n) then table.insert(arr,n) end
  end
  local s=STATE.sort_by or "POWER"
  table.sort(arr,function(a,b) if s=="RPM" then return n0(a.rpm)>n0(b.rpm) elseif s=="HOST" then return tostring(a.hostname or "")<tostring(b.hostname or "") else return n0(a.power_mrf)>n0(b.power_mrf) end end)
  return arr
end

local function build_gui()
  if not (GUI and MON) then return nil end
  local router=GUI.mkRouter({monitorName=peripheral.getName(MON)})
  local scr=GUI.mkScreen("ovw","System ▢ Overview")
  TB = Topbar.create({title="System ▢ Overview", monitor_name=peripheral.getName(MON), window_s=TOPBAR_CFG.window_s}); TB:mount(GUI,scr)

  local kpiA=GUI.mkLabel(2,3,"Power: - RF/t",{color=colors.green}); scr:add(kpiA)
  local kpiB=GUI.mkLabel(26,3,"Ø RPM: -",{color=colors.lightBlue}); scr:add(kpiB)
  local kpiC=GUI.mkLabel(44,3,"Online: - / -",{color=colors.orange}); scr:add(kpiC)
  local kpiD=GUI.mkLabel(64,3,"Fuel%: - .. -",{color=colors.yellow}); scr:add(kpiD)

  local lst=GUI.mkList(2,5,78,14,{}); scr:add(lst)

  local btnSort=GUI.mkSelector(2,20,18,{"POWER","RPM","HOST"},"POWER",function(v) MODEL:set_overview_filter('sort_by', v) end); scr:add(btnSort)
  local btnFilt=GUI.mkSelector(22,20,14,{"ONLINE","ALLE"},"ONLINE",function(v) MODEL:set_overview_filter('filter_online', v=="ONLINE") end); scr:add(btnFilt)
  local btnRole=GUI.mkSelector(38,20,18,{"ALL","MASTER","REACTOR","FUEL","WASTE","AUX"},"ALL",function(v) MODEL:set_overview_filter('filter_role', v) end); scr:add(btnRole)
  local btnRef =GUI.mkButton(58,20,10,3,"Refresh", function() bcast(PROTO.make_hello(IDENT)) end, colors.gray); scr:add(btnRef)
  local btnHome=GUI.mkButton(70,20,10,3,"Home",    function() go_home() end, colors.lightGray); scr:add(btnHome)

  scr._redraw=function()
    local v = MODEL:get_overview_view()
    kpiA.props.text = v.kpi_power_text
    kpiB.props.text = v.kpi_rpm_text
    kpiC.props.text = v.kpi_online_text
    kpiD.props.text = v.kpi_fuel_text
    lst.props.items = v.rows
    TB:update(MODEL:get_topbar_view(TOPBAR_CFG))
  end

  router:register(scr); router:show("ovw")
  return router, scr
end

local function tui_loop()
  if GUI and MON then return end
  local function bhello() bcast(PROTO.make_hello(IDENT)) end
  while true do
    term.clear(); term.setCursorPos(1,1)
    local v = MODEL:get_overview_view()
    print("System ▢ Overview (TUI)  "..os.date("%H:%M:%S"))
    print(string.rep("-",78))
    print(string.format("%s   %s   %s   %s", v.kpi_power_text, v.kpi_rpm_text, v.kpi_online_text, v.kpi_fuel_text))
    print(string.rep("-",78))
    for _,row in ipairs(v.rows) do
      print(row.text)
    end
    print(string.rep("-",78))
    print("[S] POWER/RPM/HOST  [F] ONLINE/ALLE  [L] Role-Filter  [R] Refresh  [H] Home  [Q] Quit")
    local e,kb=os.pullEvent("key")
    if kb==keys.q then return
    elseif kb==keys.r then bhello()
    elseif kb==keys.h then go_home()
    elseif kb==keys.s then
      local current = v.filters.sort_by
      local nexts = (current=="POWER") and "RPM" or (current=="RPM" and "HOST" or "POWER")
      MODEL:set_overview_filter('sort_by', nexts)
    elseif kb==keys.f then MODEL:set_overview_filter('filter_online', not v.filters.filter_online)
    elseif kb==keys.l then local order={"ALL","MASTER","REACTOR","FUEL","WASTE","AUX"}; local i=1; for ii,val in ipairs(order) do if val==v.filters.filter_role then i=ii break end end; MODEL:set_overview_filter('filter_role', order[i%#order+1]) end
  end
end

local function gui_loop()
  if not (GUI and MON) then return end
  local router,scr=build_gui()

  request_redraw("init")
  local tick=os.startTimer(1)
  while true do
    local ev={os.pullEvent()}
    if ev[1]=="timer" and ev[2]==tick then
      request_redraw("tick"); tick=os.startTimer(1)
    elseif ev[1]=="monitor_touch" or ev[1]=="mouse_click" or ev[1]=="mouse_drag" or ev[1]=="term_resize" then
      request_redraw(ev[1])
    elseif ev[1]=="ui_redraw" then
      redraw_pending=false
      if scr and scr._redraw then scr._redraw() end
      if router and router.draw then router:draw() end
    end
  end
end

print("System Overview ▢ gestartet ("..(GUI and MON and "Monitor" or "TUI")..")")
bcast(PROTO.make_hello(IDENT))
parallel.waitForAny(dispatcher_loop, gui_loop, tui_loop)
