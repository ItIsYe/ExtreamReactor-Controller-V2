--========================================================
-- /xreactor/master/overview_panel.lua
-- System Overview mit Identity (hostname/role/cluster), KPIs & Filtern
--========================================================
local function now_s() return os.epoch("utc")/1000 end
local function n0(x,d) x=tonumber(x); if x==nil then return d or 0 end; return x end
local function age_s(ts) local a=now_s()-(ts or 0); if a<0 then a=0 end; return math.floor(a) end

local PROTO = dofile("/xreactor/shared/protocol.lua")
local IDMOD = dofile("/xreactor/shared/identity.lua")
local IDENT  = IDMOD.load_identity()

local CFG=(function()
  local t={ auth_token=IDENT.token or "xreactor", modem_side="right", telem_timeout_s=10, ui={text_scale=nil} }
  if fs.exists("/xreactor/config_overview.lua") then local ok,c=pcall(dofile,"/xreactor/config_overview.lua"); if ok and type(c)=="table" then
    t.auth_token=c.auth_token or t.auth_token; t.modem_side=c.modem_side or t.modem_side; t.telem_timeout_s=tonumber(c.telem_timeout_s or t.telem_timeout_s) or t.telem_timeout_s; if c.ui then t.ui=c.ui end
  end end
  return t
end)()

assert(peripheral.getType(CFG.modem_side)=="modem","Kein Modem an "..tostring(CFG.modem_side))
if not rednet.isOpen(CFG.modem_side) then rednet.open(CFG.modem_side) end
local function bcast(msg) msg=PROTO.tag(msg, CFG.auth_token); return rednet.broadcast(msg) end

local GUI; do local ok,g=pcall(require,"xreactor.shared.gui"); if ok then GUI=g elseif fs.exists("/xreactor/shared/gui.lua") then GUI=dofile("/xreactor/shared/gui.lua") end end
local function load_ui_map() if fs.exists("/xreactor/ui_map.lua") then local ok,t=pcall(dofile,"/xreactor/ui_map.lua"); if ok and type(t)=="table" then return t end end; return {monitors={}, autoscale={enabled=false}} end
local UIMAP=load_ui_map()
local function pick_monitor_for_role(role) local name; for n,cfg in pairs(UIMAP.monitors or {}) do if cfg.role==role then name=n break end end; local mon=name and peripheral.wrap(name) or ({peripheral.find("monitor")})[1]; if not mon then return nil end; local e=(UIMAP.monitors or {})[peripheral.getName(mon)]; local s=e and e.scale or (CFG.ui and CFG.ui.text_scale); if s then pcall(mon.setTextScale, tonumber(s) or 1.0) end; return mon end
local MON=pick_monitor_for_role("system_overview"); if MON and not GUI then pcall(MON.setTextScale, 0.5) end

local Topbar = dofile("/xreactor/shared/topbar.lua")
local TB; local function go_home() shell.run("/xreactor/master/master_home.lua") end

local STATE = { nodes={}, sort_by="POWER", filter_online=true, filter_role="ALL" }
local function key_for(uid, id) if uid and tostring(uid)~="" then return tostring(uid) end; return "id:"..tostring(id or "?") end
local function ensure_node(uid, id) local k=key_for(uid,id); local n=STATE.nodes[k]; if not n then n={ uid=uid or k, rednet_id=id or 0, hostname="-", role="-", cluster="-", rpm=0, power_mrf=0, flow=0, fuel_pct=nil, last_seen=0, state="-" } STATE.nodes[k]=n end; return n end

local function rx_loop()
  while true do
    local id,msg=rednet.receive(0.5)
    if id and type(msg)=="table" and PROTO.is_auth(msg, CFG.auth_token) then
      if msg.type==PROTO.T.TELEM and type(msg.data)=="table" then
        local d=msg.data; local n=ensure_node(d.uid, id)
        n.rednet_id=id; n.hostname=msg.hostname or n.hostname; n.role=(msg.role and tostring(msg.role):upper()) or n.role; n.cluster=msg.cluster or n.cluster
        n.rpm=n0(d.rpm,n.rpm); n.power_mrf=n0(d.power_mrf,n.power_mrf); n.flow=n0(d.flow,n.flow); n.fuel_pct=tonumber(d.fuel_pct or n.fuel_pct); n.last_seen=now_s()
      elseif msg.type==PROTO.T.NODE_HELLO then
        local n=ensure_node(msg.uid, id); n.rednet_id=id; n.hostname=msg.hostname or n.hostname; n.role=(msg.role and tostring(msg.role):upper()) or n.role; n.cluster=msg.cluster or n.cluster; n.last_seen=now_s()
      elseif msg.type==PROTO.T.NODE_STATE then
        local n=ensure_node(msg.uid, id); n.rednet_id=id; n.hostname=msg.hostname or n.hostname; n.role=(msg.role and tostring(msg.role):upper()) or n.role; n.cluster=msg.cluster or n.cluster; n.state=tostring(msg.state or n.state or "-"); n.last_seen=now_s()
      end
    end
  end
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
  TB = Topbar.create({title="System ▢ Overview", auth_token=CFG.auth_token, modem_side=CFG.modem_side, monitor_name=peripheral.getName(MON), window_s=300}); TB:mount(GUI,scr); TB:start_rx()

  local kpiA=GUI.mkLabel(2,3,"Power: - RF/t",{color=colors.green}); scr:add(kpiA)
  local kpiB=GUI.mkLabel(26,3,"Ø RPM: -",{color=colors.lightBlue}); scr:add(kpiB)
  local kpiC=GUI.mkLabel(44,3,"Online: - / -",{color=colors.orange}); scr:add(kpiC)
  local kpiD=GUI.mkLabel(64,3,"Fuel%: - .. -",{color=colors.yellow}); scr:add(kpiD)

  local lst=GUI.mkList(2,5,78,14,{}); scr:add(lst)

  local btnSort=GUI.mkSelector(2,20,18,{"POWER","RPM","HOST"},"POWER",function(v) STATE.sort_by=v end); scr:add(btnSort)
  local btnFilt=GUI.mkSelector(22,20,14,{"ONLINE","ALLE"},"ONLINE",function(v) STATE.filter_online=(v=="ONLINE") end); scr:add(btnFilt)
  local btnRole=GUI.mkSelector(38,20,18,{"ALL","MASTER","REACTOR","FUEL","WASTE","AUX"},"ALL",function(v) STATE.filter_role=v end); scr:add(btnRole)
  local btnRef =GUI.mkButton(58,20,10,3,"Refresh", function() bcast(PROTO.make_hello(IDENT)) end, colors.gray); scr:add(btnRef)
  local btnHome=GUI.mkButton(70,20,10,3,"Home",    function() go_home() end, colors.lightGray); scr:add(btnHome)

  scr._redraw=function()
    local k=compute_kpis()
    kpiA.props.text=("Power: %d RF/t"):format(math.floor(k.total_power+0.5))
    kpiB.props.text=("Ø RPM: %d"):format(k.rpm_avg or 0)
    kpiC.props.text=("Online: %d / %d"):format(k.online or 0, (k.online or 0)+(k.offline or 0))
    kpiD.props.text=(k.fuel_min and k.fuel_max) and ("Fuel%%: %d .. %d"):format(k.fuel_min,k.fuel_max) or "Fuel%: n/a"

    local rows={}
    local arr=nodes_sorted()
    if #arr==0 then rows={{text="(Noch keine TELEM gesehen – Refresh oder kurz warten)", color=colors.gray}}
    else
      for _,n in ipairs(arr) do
        local age=age_s(n.last_seen or 0); local online = age <= (CFG.telem_timeout_s or 10)
        local fuel = n.fuel_pct and (tostring(n.fuel_pct).."%") or "n/a"
        local line=string.format("%-16s %-7s %-8s  P:%-6d RPM:%-5d Flow:%-5d Fuel:%-4s  %2ss  %s",
          tostring(n.hostname or "-"), tostring(n.role or "-"), tostring(n.cluster or "-"),
          n0(n.power_mrf), n0(n.rpm), n0(n.flow), fuel, age, tostring(n.state or "-"))
        table.insert(rows, {text=line, color=online and colors.white or colors.lightGray})
      end
    end
    lst.props.items=rows
    TB:update()
  end

  router:register(scr); router:show("ovw")
  return router, scr
end

local function tui_loop()
  if GUI and MON then return end
  local function bhello() bcast(PROTO.make_hello(IDENT)) end
  while true do
    term.clear(); term.setCursorPos(1,1)
    local k=compute_kpis()
    print("System ▢ Overview (TUI)  "..os.date("%H:%M:%S"))
    print(string.rep("-",78))
    local fuel = (k.fuel_min and k.fuel_max) and (tostring(k.fuel_min)..".."..tostring(k.fuel_max)) or "n/a"
    print(("Power: %d RF/t   ØRPM: %d   Online: %d/%d   Fuel%%: %s   RoleFilter: %s"):format(
      math.floor(k.total_power+0.5), k.rpm_avg, k.online or 0, (k.online or 0)+(k.offline or 0), fuel, STATE.filter_role))
    print(string.rep("-",78))
    for _,n in ipairs(nodes_sorted()) do
      local age=age_s(n.last_seen or 0); local online=age <= (CFG.telem_timeout_s or 10)
      local f = n.fuel_pct and (tostring(n.fuel_pct).."%") or "n/a"
      print(string.format("%-16s %-7s %-8s  P:%-6d RPM:%-5d Flow:%-5d Fuel:%-4s  %2ss  %s %s",
        tostring(n.hostname or "-"), tostring(n.role or "-"), tostring(n.cluster or "-"),
        n0(n.power_mrf), n0(n.rpm), n0(n.flow), f, age, tostring(n.state or "-"), online and "" or "(OFF)"))
    end
    print(string.rep("-",78))
    print("[S] POWER/RPM/HOST  [F] ONLINE/ALLE  [L] Role-Filter  [R] Refresh  [H] Home  [Q] Quit")
    local e,kb=os.pullEvent("key")
    if kb==keys.q then return
    elseif kb==keys.r then bhello()
    elseif kb==keys.h then go_home()
    elseif kb==keys.s then STATE.sort_by = (STATE.sort_by=="POWER") and "RPM" or (STATE.sort_by=="RPM" and "HOST" or "POWER")
    elseif kb==keys.f then STATE.filter_online = not STATE.filter_online
    elseif kb==keys.l then local order={"ALL","MASTER","REACTOR","FUEL","WASTE","AUX"}; local i=1; for ii,v in ipairs(order) do if v==STATE.filter_role then i=ii break end end; STATE.filter_role = order[i%#order+1] end
  end
end

local function gui_loop()
  if not (GUI and MON) then return end
  local router,scr=build_gui()
  while true do if scr and scr._redraw then scr._redraw() end; router:draw(); sleep(0.05) end
end

print("System Overview ▢ gestartet ("..(GUI and MON and "Monitor" or "TUI")..")")
bcast(PROTO.make_hello(IDENT))
parallel.waitForAny(rx_loop, gui_loop, tui_loop)
