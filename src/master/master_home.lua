--========================================================
-- /xreactor/master/master_home.lua
-- Master-Startmenü (Touch) mit Topbar + Alarm/Health
--========================================================
local function now_s() return os.epoch("utc")/1000 end

local REQUIRED_MASTER_PATHS = {
  "/xreactor/master/master_core.lua",
  "/xreactor/master/master_model.lua",
  "/xreactor/master/fuel_panel.lua",
  "/xreactor/master/waste_panel.lua",
  "/xreactor/master/overview_panel.lua",
  "/xreactor/master/alarm_panel.lua",
  "/xreactor/shared/protocol.lua",
  "/xreactor/shared/identity.lua",
  "/xreactor/shared/local_state_store.lua",
  "/xreactor/shared/network_dispatcher.lua",
  "/xreactor/shared/node_state_machine.lua",
  "/xreactor/shared/topbar.lua",
}

local function verify_master_dependencies()
  local missing = {}
  for _, path in ipairs(REQUIRED_MASTER_PATHS) do
    if not fs.exists(path) then table.insert(missing, path) end
  end

  if #missing > 0 then
    error("Master startup aborted: missing files -> " .. table.concat(missing, ", "), 0)
  end
end

verify_master_dependencies()

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
local AlarmPanel = dofile("/xreactor/master/alarm_panel.lua")
local CORE = MasterCore.create({auth_token=CFG.auth_token, modem_side=CFG.modem_side, dispatcher=_G.XREACTOR_SHARED_DISPATCHER})
local MODEL = Model.create(CORE:get_dispatcher())
local TOPBAR_CFG = { window_s = 300, health = { timeout_s = 10, warn_s = 20, crit_s = 60, min_nodes = 1 } }

local text_utils = dofile("/xreactor/shared/text.lua")
local sanitizeText = (text_utils and text_utils.sanitizeText) or function(text) return tostring(text or "") end
local function safe_print(text)
  print(sanitizeText(text))
end

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
local function detect_monitors()
  local monitors = {}
  for _, name in ipairs(peripheral.getNames()) do
    if peripheral.getType(name) == "monitor" then
      local mon = peripheral.wrap(name)
      if mon then
        table.insert(monitors, { name = name, peripheral = mon })
      end
    end
  end
  return monitors
end

local function prepare_monitor(mon, name)
  local entry = (UIMAP.monitors or {})[name]
  local scale = entry and entry.scale or (CFG.ui and CFG.ui.text_scale)
  if scale then pcall(mon.setTextScale, tonumber(scale) or 1.0) end
  if mon.setBackgroundColor then pcall(mon.setBackgroundColor, colors.black) end
  if mon.clear then pcall(mon.clear) end
  if mon.setCursorPos then pcall(mon.setCursorPos, 1, 1) end
end

local function allocate_monitors()
  local detected = detect_monitors()
  local role_map = {}
  local unused = {}

  for _, entry in ipairs(detected) do
    prepare_monitor(entry.peripheral, entry.name)
    local cfg = (UIMAP.monitors or {})[entry.name]
    if cfg and cfg.role then
      role_map[cfg.role] = role_map[cfg.role] or {}
      table.insert(role_map[cfg.role], entry)
    else
      table.insert(unused, entry)
    end
  end

  local function take(role)
    if role_map[role] and #role_map[role] > 0 then
      return table.remove(role_map[role], 1)
    end
    if #unused > 0 then
      return table.remove(unused, 1)
    end
    return nil
  end

  return {
    take = take,
    remaining = function()
      local rest = {}
      for _, entries in pairs(role_map) do
        for _, e in ipairs(entries) do table.insert(rest, e) end
      end
      for _, e in ipairs(unused) do table.insert(rest, e) end
      return rest
    end,
  }
end

local monitor_allocator = allocate_monitors()
local function pick_monitor_for_role(role)
  local entry = monitor_allocator.take(role)
  return entry and entry.peripheral or nil
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
      term.clear(); term.setCursorPos(1,1); safe_print("Master UI läuft ohne Monitor (TUI)")
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
  local fuel_mon = pick_monitor_for_role("fuel_manager")
  local waste_mon = pick_monitor_for_role("waste_service")
  local alarm_mon = pick_monitor_for_role("alarm_center")
  local overview_mon = pick_monitor_for_role("system_overview")

  local fuel_panel = fuel_mon and FuelPanel.create({monitor=fuel_mon}) or nil
  local waste_panel = waste_mon and WastePanel.create({monitor=waste_mon}) or nil
  local alarm_panel = AlarmPanel.create({
    monitor=alarm_mon,
    on_home = function() shell.run("/xreactor/master/master_home.lua") end,
    on_ack = function() MODEL:ack_alarms() end,
  })
  local overview_panel = overview_mon and OverviewPanel.create({
    monitor=overview_mon,
    on_filter_change = function(k,v) MODEL:set_overview_filter(k,v) end,
    on_refresh = function() CORE:publish(PROTO.make_hello(IDENT)) end,
  }) or nil
  local function placeholder_panel(entry)
    if not entry or not entry.peripheral then return nil end
    local mon = entry.peripheral
    local label = "Monitor " .. (entry.name or "?")

    local function draw_placeholder()
      pcall(mon.setBackgroundColor, colors.black)
      pcall(mon.setTextColor, colors.lightGray)
      pcall(mon.clear)
      pcall(mon.setCursorPos, 2, 2)
      pcall(mon.write, "XReactor ▢ No panel assigned")
      pcall(mon.setCursorPos, 2, 4)
      pcall(mon.write, label)
    end

    return {
      monitor = mon,
      start = draw_placeholder,
      handle_event = function(ev)
        if ev[1] == "monitor_touch" and ev[2] == entry.name then draw_placeholder() end
      end,
    }
  end

  local placeholder_panels = {}
  for _, entry in ipairs(monitor_allocator.remaining()) do
    table.insert(placeholder_panels, placeholder_panel(entry))
  end

  local panels = { home_panel, fuel_panel, waste_panel, alarm_panel, overview_panel }
  for _, p in ipairs(placeholder_panels) do table.insert(panels, p) end

  local function topbar_view()
    return MODEL:get_topbar_view(TOPBAR_CFG)
  end

  local function refresh_fuel()
    if fuel_panel and fuel_panel.set_view then
      fuel_panel.set_view({ rows = MODEL:get_fuel_rows(), topbar = topbar_view() })
    end
  end

  local function refresh_waste()
    if waste_panel and waste_panel.set_view then
      waste_panel.set_view({ rows = MODEL:get_waste_rows(), topbar = topbar_view() })
    end
  end

  local function refresh_alarm()
    if alarm_panel and alarm_panel.set_view then
      alarm_panel.set_view({ alarm = MODEL:get_alarm_view(), topbar = topbar_view() })
    end
  end

  local function refresh_overview()
    if overview_panel and overview_panel.set_view then
      overview_panel.set_view({ overview = MODEL:get_overview_view(), topbar = topbar_view() })
    end
  end

  MODEL:subscribe('fuel', refresh_fuel)
  MODEL:subscribe('waste', refresh_waste)
  MODEL:subscribe('alarm', refresh_alarm)
  MODEL:subscribe('overview', refresh_overview)
  MODEL:subscribe('topbar', function()
    refresh_fuel(); refresh_waste(); refresh_alarm(); refresh_overview()
  end)

  CORE:start_timers()
  bcast({type="HELLO"})

  for _,p in ipairs(panels) do if p and p.start then p.start() end end
  refresh_fuel(); refresh_waste(); refresh_alarm(); refresh_overview()

  local ui_tick = os.startTimer(1)

  while true do
    local ev={os.pullEvent()}
    CORE:handle_event(ev)
    if ev[1]=='timer' and ev[2]==ui_tick then
      refresh_fuel(); refresh_waste(); refresh_overview()
      refresh_alarm()
      ui_tick=os.startTimer(1)
    end
    for _,p in ipairs(panels) do if p and p.handle_event then p.handle_event(ev) end end
  end
end

safe_print("Master-Startoberfläche ▢ gestartet ("..(GUI and MON and "Monitor" or "TUI")..")")
parallel.waitForAny(dispatcher_loop, start_panels)
