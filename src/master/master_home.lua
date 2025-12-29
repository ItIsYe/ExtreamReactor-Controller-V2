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

local MasterCore = dofile("/xreactor/master/master_core.lua")
local PROTO = dofile("/xreactor/shared/protocol.lua")
local IDMOD = dofile("/xreactor/shared/identity.lua")
local IDENT  = IDMOD.load_identity()

local Model = dofile("/xreactor/master/master_model.lua")
local FuelPanel = dofile("/xreactor/master/fuel_panel.lua")
local WastePanel = dofile("/xreactor/master/waste_panel.lua")
local OverviewPanel = dofile("/xreactor/master/overview_panel.lua")
local CORE = MasterCore.create({auth_token=CFG.auth_token, modem_side=CFG.modem_side, dispatcher=_G.XREACTOR_SHARED_DISPATCHER})
local MODEL = Model.create(CORE:get_dispatcher())
local TOPBAR_CFG = { window_s = 300, health = { timeout_s = 10, warn_s = 20, crit_s = 60, min_nodes = 1 } }

local function bcast(msg) return CORE:publish(msg) end

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

local function create_home_panel()
  local TB
  local redraw_pending=false
  local router, scr
  local tick=nil

  local function request_redraw(reason)
    if not (GUI and MON) then return end
    if redraw_pending then return end
    redraw_pending=true
    os.queueEvent("ui_redraw", reason or "update")
  end

  MODEL:subscribe('topbar', function() request_redraw('topbar') end)

  local function build_gui()
    if not (GUI and MON) then return end
    router=GUI.mkRouter({monitorName=peripheral.getName(MON)})
    scr=GUI.mkScreen("home","XReactor ▢ Master")

    TB = Topbar.create({title="XReactor ▢ Master", monitor_name=peripheral.getName(MON), window_s=TOPBAR_CFG.window_s, show_clock=true, show_net=true, show_alarm=true, show_health=true})
    TB:mount(GUI, scr)

    local infoA=GUI.mkLabel(4,4,"Panels laufen parallel auf zugewiesenen Monitoren.",{color=colors.lightGray}); scr:add(infoA)
    local infoB=GUI.mkLabel(4,6,"Nutze ui_map.lua, um Rollen→Monitore zu binden.",{color=colors.lightGray}); scr:add(infoB)
    local btnRef  = GUI.mkButton(4,20,10,3,"HELLO", function() bcast({type="HELLO"}) end, colors.gray); scr:add(btnRef)
    local btnQuit = GUI.mkButton(16,20,10,3,"Quit",  function() term.redirect(MON); term.clear(); term.setCursorPos(1,1) end, colors.gray); scr:add(btnQuit)

    router:register(scr); router:show("home")
    scr._redraw=function() TB:update(MODEL:get_topbar_view(TOPBAR_CFG)) end
  end

  local function start()
    if GUI and MON then build_gui() else
      term.clear(); term.setCursorPos(1,1); print("Master UI läuft ohne Monitor (TUI)")
    end
    tick=os.startTimer(1)
    request_redraw("init")
  end

  local function handle_event(ev)
    if ev[1]=="timer" and ev[2]==tick then
      request_redraw("tick"); tick=os.startTimer(1)
    elseif ev[1]=="master_state_change" then
      request_redraw("state")
    elseif ev[1]=="monitor_touch" or ev[1]=="mouse_click" or ev[1]=="mouse_drag" or ev[1]=="term_resize" then
      request_redraw(ev[1])
    elseif ev[1]=="ui_redraw" then
      redraw_pending=false
      if scr and scr._redraw then scr._redraw() end
      if router and router.draw then router:draw() end
    end
  end

  return {start=start, handle_event=handle_event, monitor=MON}
end

local function dispatcher_loop() CORE:start_dispatcher() end

local function start_panels()
  local home_panel = create_home_panel()
  local fuel_panel = FuelPanel.create({monitor=pick_monitor_for_role("fuel_manager")})
  local waste_panel = WastePanel.create({monitor=pick_monitor_for_role("waste_service")})
  local overview_panel = OverviewPanel.create({
    monitor=pick_monitor_for_role("system_overview"),
    on_filter_change = function(k,v) MODEL:set_overview_filter(k,v) end,
    on_refresh = function() CORE:publish(PROTO.make_hello(IDENT)) end,
  })
  local panels = { home_panel, fuel_panel, waste_panel, overview_panel }

  local function topbar_view()
    return MODEL:get_topbar_view(TOPBAR_CFG)
  end

  local function refresh_fuel()
    fuel_panel.set_view({ rows = MODEL:get_fuel_rows(), topbar = topbar_view() })
  end

  local function refresh_waste()
    waste_panel.set_view({ rows = MODEL:get_waste_rows(), topbar = topbar_view() })
  end

  local function refresh_overview()
    overview_panel.set_view({ overview = MODEL:get_overview_view(), topbar = topbar_view() })
  end

  MODEL:subscribe('fuel', refresh_fuel)
  MODEL:subscribe('waste', refresh_waste)
  MODEL:subscribe('overview', refresh_overview)
  MODEL:subscribe('topbar', function()
    refresh_fuel(); refresh_waste(); refresh_overview()
  end)

  CORE:start_timers()
  bcast({type="HELLO"})

  for _,p in ipairs(panels) do if p and p.start then p.start() end end
  refresh_fuel(); refresh_waste(); refresh_overview()

  local ui_tick = os.startTimer(1)

  while true do
    local ev={os.pullEvent()}
    CORE:handle_event(ev)
    if ev[1]=='timer' and ev[2]==ui_tick then
      refresh_fuel(); refresh_waste(); refresh_overview()
      ui_tick=os.startTimer(1)
    end
    for _,p in ipairs(panels) do if p and p.handle_event then p.handle_event(ev) end end
  end
end

print("Master-Startoberfläche ▢ gestartet ("..(GUI and MON and "Monitor" or "TUI")..")")
parallel.waitForAny(dispatcher_loop, start_panels)
