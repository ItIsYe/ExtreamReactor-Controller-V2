--========================================================
-- /xreactor/master/master_home.lua
-- Master-Startmenü (Touch) mit Topbar + Alarm/Health
--========================================================
local function now_s() return os.epoch("utc")/1000 end

-- Basiskonfig (Modem/Auth kann via config_master.lua überschrieben werden)
local CFG=(function()
  local t={ auth_token="xreactor", modem_side="right", ui={text_scale=0.5} }
  if fs.exists("/xreactor/config_master.lua") then
    local ok,c=pcall(dofile,"/xreactor/config_master.lua"); if ok and type(c)=="table" then
      t.auth_token=c.auth_token or t.auth_token; t.modem_side=c.modem_side or t.modem_side; if c.ui then t.ui=c.ui end
    end
  end
  return t
end)()

assert(peripheral.getType(CFG.modem_side)=="modem","Kein Modem an "..tostring(CFG.modem_side))
if not rednet.isOpen(CFG.modem_side) then rednet.open(CFG.modem_side) end

local function tagged(msg) msg._auth=CFG.auth_token; return msg end
local function bcast(msg) rednet.broadcast(tagged(msg)) end

-- GUI-Toolkit laden
local GUI; do
  local ok,g=pcall(require,"xreactor.shared.gui")
  if ok then GUI=g elseif fs.exists("/xreactor/shared/gui.lua") then GUI=dofile("/xreactor/shared/gui.lua") end
end

-- Monitor nach Rolle auswählen
local function load_ui_map()
  if fs.exists("/xreactor/ui_map.lua") then local ok,t=pcall(dofile,"/xreactor/ui_map.lua"); if ok and type(t)=="table" then return t end end
  return {monitors={}, autoscale={enabled=false}}
end
local UIMAP=load_ui_map()
local function pick_monitor_for_role(role)
  local name=nil; for n,cfg in pairs(UIMAP.monitors or {}) do if cfg.role==role then name=n break end end
  local mon = name and peripheral.wrap(name) or ({peripheral.find("monitor")})[1]
  if not mon then return nil end
  local entry=(UIMAP.monitors or {})[peripheral.getName(mon)]
  local scale= entry and entry.scale or (CFG.ui and CFG.ui.text_scale); if scale then pcall(mon.setTextScale, tonumber(scale) or 1.0) end
  return mon
end

local MON=pick_monitor_for_role("master_home")
if MON and not GUI then pcall(MON.setTextScale, 0.5) end

local Topbar = dofile("/xreactor/shared/topbar.lua")
local TB

-- Aktionen
local function open_alarm_center() shell.run("/xreactor/master/alarm_center.lua") end
local function open_fuel_panel()   shell.run("/xreactor/master/fuel_panel.lua")   end
local function open_waste_panel()  shell.run("/xreactor/master/waste_panel.lua")  end
local function open_overview()     shell.run("/xreactor/master/overview_panel.lua") end

-- GUI
local function build_gui()
  if not (GUI and MON) then return nil end
  local router=GUI.mkRouter({monitorName=peripheral.getName(MON)})
  local scr=GUI.mkScreen("home","XReactor ▢ Master")

  TB = Topbar.create({title="XReactor ▢ Master", auth_token=CFG.auth_token, modem_side=CFG.modem_side, monitor_name=peripheral.getName(MON), window_s=300, show_clock=true, show_net=true, show_alarm=true, show_health=true})
  TB:mount(GUI, scr); TB:start_rx()

  local btnFuel  = GUI.mkButton(4,4,22,7,"Fuel ▢ Manager",  open_fuel_panel, colors.green);  scr:add(btnFuel)
  local btnWaste = GUI.mkButton(30,4,22,7,"Waste ▢ Panel",  open_waste_panel, colors.orange); scr:add(btnWaste)
  local btnAlarm = GUI.mkButton(56,4,22,7,"Alarm ▢ Center", open_alarm_center, colors.red);   scr:add(btnAlarm)
  local btnOvw   = GUI.mkButton(4,12,22,7,"System ▢ Overview", open_overview, colors.cyan);   scr:add(btnOvw)

  local info=GUI.mkLabel(4,20,"Tippe auf eine Kachel, um das Panel zu öffnen.",{color=colors.lightGray}); scr:add(info)
  local btnRef  = GUI.mkButton(56,20,10,3,"HELLO", function() bcast({type="HELLO"}) end, colors.gray); scr:add(btnRef)
  local btnQuit = GUI.mkButton(68,20,10,3,"Quit",  function() term.redirect(MON); term.clear(); term.setCursorPos(1,1) end, colors.gray); scr:add(btnQuit)

  router:register(scr); router:show("home")
  scr._redraw=function() TB:update() end
  return router, scr
end

-- TUI Fallback (falls kein GUI/Monitor)
local function tui_loop()
  if GUI and MON then return end
  while true do
    term.clear(); term.setCursorPos(1,1)
    print("XReactor ▢ Master  "..os.date("%H:%M:%S"))
    print(string.rep("-", 48))
    print(" [F] Fuel-Manager   [W] Waste-Panel")
    print(" [A] Alarm-Center   [O] System-Overview")
    print(" [R] Broadcast HELLO  [Q] Quit")
    local e,k=os.pullEvent("key")
    if k==keys.q then return
    elseif k==keys.f then open_fuel_panel()
    elseif k==keys.w then open_waste_panel()
    elseif k==keys.a then open_alarm_center()
    elseif k==keys.o then open_overview()
    elseif k==keys.r then bcast({type="HELLO"}) end
  end
end

local function gui_loop()
  if not (GUI and MON) then return end
  local router, scr = build_gui()
  while true do if scr and scr._redraw then scr._redraw() end; router:draw(); sleep(0.05) end
end

print("Master-Startoberfläche ▢ gestartet ("..(GUI and MON and "Monitor" or "TUI")..")")
bcast({type="HELLO"})
parallel.waitForAny(gui_loop, tui_loop)
