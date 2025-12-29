--========================================================
-- /xreactor/master/fuel_panel.lua
-- Fuel-Management (GUI-Skeleton): Anzeige/Grundfunktionen + Topbar
--  • Zeigt aggregierte Fuel%-Infos aus TELEM
--  • Stubs für spätere Steuerbefehle (z. B. FUEL_CTRL)
--========================================================
local PROTO = dofile("/xreactor/shared/protocol.lua")
local Dispatcher = dofile("/xreactor/shared/network_dispatcher.lua")

local CFG=(function() local t={ auth_token="xreactor", modem_side="right", ui={text_scale=0.5} }
  if fs.exists("/xreactor/config_fuel.lua") then local ok,c=pcall(dofile,"/xreactor/config_fuel.lua"); if ok and type(c)=="table" then
    t.auth_token=c.auth_token or t.auth_token; t.modem_side=c.modem_side or t.modem_side; if c.ui then t.ui=c.ui end
  end end; return t end)()

local DISP = Dispatcher.create({auth_token=CFG.auth_token, modem_side=CFG.modem_side})

local GUI; do local ok,g=pcall(require,"xreactor.shared.gui"); if ok then GUI=g elseif fs.exists("/xreactor/shared/gui.lua") then GUI=dofile("/xreactor/shared/gui.lua") end end
local function load_ui_map() if fs.exists("/xreactor/ui_map.lua") then local ok,t=pcall(dofile,"/xreactor/ui_map.lua"); if ok and type(t)=="table" then return t end end; return {monitors={}, autoscale={enabled=false}} end
local UIMAP=load_ui_map()
local function pick_monitor_for_role(role) local name; for n,cfg in pairs(UIMAP.monitors or {}) do if cfg.role==role then name=n break end end; local mon=name and peripheral.wrap(name) or ({peripheral.find("monitor")})[1]; if not mon then return nil end; local e=(UIMAP.monitors or {})[peripheral.getName(mon)]; local s=e and e.scale or (CFG.ui and CFG.ui.text_scale); if s then pcall(mon.setTextScale, tonumber(s) or 1.0) end; return mon end
local MON=pick_monitor_for_role("fuel_manager"); if MON and not GUI then pcall(MON.setTextScale, 0.5) end

local Topbar = dofile("/xreactor/shared/topbar.lua")
local TB

-- Zustand
local TELEM = {} -- uid -> {fuel_pct, rpm, power_mrf, last_seen, hostname}

local function on_telem(msg, from_id)
  if type(msg) ~= "table" or type(msg.data) ~= "table" then return end
  local d=msg.data; TELEM[d.uid or ("id:"..tostring(from_id))] = { fuel_pct=d.fuel_pct, rpm=d.rpm, power_mrf=d.power_mrf, last_seen=os.epoch("utc")/1000, hostname=msg.hostname }
end

-- GUI
DISP:subscribe(PROTO.T.TELEM, on_telem)

local function dispatcher_loop()
  DISP:start()
end

local function build_gui()
  if not (GUI and MON) then return nil end
  local router=GUI.mkRouter({monitorName=peripheral.getName(MON)})
  local scr=GUI.mkScreen("fuel","Fuel ▢ Manager")
  TB = Topbar.create({title="Fuel ▢ Manager", auth_token=CFG.auth_token, modem_side=CFG.modem_side, monitor_name=peripheral.getName(MON)}); TB:mount(GUI,scr); TB:attach_dispatcher(DISP)

  local lblA = GUI.mkLabel(2,3,"Fuel Overview",{color=colors.yellow}); scr:add(lblA)
  local list = GUI.mkList(2,5,78,14,{}); scr:add(list)
  local btnHome = GUI.mkButton(2,20,10,3,"Home", function() shell.run("/xreactor/master/master_home.lua") end, colors.lightGray); scr:add(btnHome)

  scr._redraw=function()
    local rows={}
    for uid,d in pairs(TELEM) do
      local fuel = d.fuel_pct and (tostring(d.fuel_pct).."%") or "n/a"
      table.insert(rows, {text=string.format("%-12s Fuel:%-4s RPM:%-5d P:%-7d host:%s", tostring(uid), fuel, tonumber(d.rpm or 0), tonumber(d.power_mrf or 0), tostring(d.hostname or "-")), color=colors.white})
    end
    if #rows==0 then rows={{text="(Noch keine Telemetrie empfangen)", color=colors.gray}} end
    list.props.items=rows; TB:update()
  end

  router:register(scr); router:show("fuel")
  return router, scr
end

local function tui_loop()
  if GUI and MON then return end
  while true do
    term.clear(); term.setCursorPos(1,1)
    print("Fuel ▢ Manager  "..os.date("%H:%M:%S")); print(string.rep("-",78))
    local count=0
    for uid,d in pairs(TELEM) do
      print(string.format("%-12s Fuel:%-4s RPM:%-5d P:%-7d host:%s", tostring(uid), d.fuel_pct and (d.fuel_pct.."%") or "n/a", d.rpm or 0, d.power_mrf or 0, tostring(d.hostname or "-")))
      count=count+1
    end
    if count==0 then print("(Noch keine Telemetrie empfangen)") end
    print(string.rep("-",78)); print("[H] Home  [Q] Quit")
    local e,k=os.pullEvent("key"); if k==keys.q then return elseif k==keys.h then shell.run("/xreactor/master/master_home.lua") end
  end
end

local function gui_loop() if not (GUI and MON) then return end; local router,scr=build_gui(); while true do if scr and scr._redraw then scr._redraw() end; router:draw(); sleep(0.05) end end

print("Fuel Panel ▢ gestartet ("..(GUI and MON and "Monitor" or "TUI")..")")
parallel.waitForAny(dispatcher_loop, gui_loop, tui_loop)
