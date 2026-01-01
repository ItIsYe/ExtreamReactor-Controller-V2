--========================================================
-- /xreactor/master/overview_panel.lua
-- System Overview mit Identity (hostname/role/cluster), KPIs & Filtern
--========================================================
local GUI; do local ok,g=pcall(require,"xreactor.shared.gui"); if ok then GUI=g elseif fs.exists("/xreactor/shared/gui.lua") then GUI=dofile("/xreactor/shared/gui.lua") end end
local Topbar = dofile("/xreactor/shared/topbar.lua")
local TOPBAR_CFG = { window_s = 300, health = { timeout_s = 10, warn_s = 20, crit_s = 60, min_nodes = 1 } }

local M = {}

local text_utils = dofile("/xreactor/shared/text.lua")
local sanitizeText = (text_utils and text_utils.sanitizeText) or function(text) return tostring(text or "") end
local function safe_print(text)
  print(sanitizeText(text))
end

local function noop() end

function M.create(opts)
  local cfg = opts or {}
  local mon = assert(cfg.monitor, "monitor required")
  if mon and not GUI then pcall(mon.setTextScale, 0.5) end
  local on_home = cfg.on_home or noop
  local on_filter_change = cfg.on_filter_change or noop
  local on_refresh = cfg.on_refresh or noop
  local view_state = {
    overview = {
      filters = { sort_by = 'POWER', filter_online = true, filter_role = 'ALL' },
      rows = {},
      policy_rows = {},
      priority_rows = {},
      kpi_power_text = '',
      kpi_rpm_text = '',
      kpi_online_text = '',
      kpi_fuel_text = '',
    },
    topbar = {},
  }

  local redraw_pending=false
  local router, scr
  local TB

  local function request_redraw(reason)
    if not (GUI and mon) then return end
    if redraw_pending then return end
    redraw_pending=true
    os.queueEvent("ui_redraw", reason or "update")
  end

  local function build_gui()
    if not (GUI and mon) then return nil end
    router=GUI.mkRouter({monitorName=peripheral.getName(mon)})
    scr=GUI.mkScreen("ovw","System ▢ Overview")
    TB = Topbar.create({title="System ▢ Overview", monitor_name=peripheral.getName(mon), window_s=TOPBAR_CFG.window_s}); TB:mount(GUI,scr)

    local kpiA=GUI.mkLabel(2,3,"Power: - RF/t",{color=colors.green}); scr:add(kpiA)
    local kpiB=GUI.mkLabel(26,3,"Ø RPM: -",{color=colors.lightBlue}); scr:add(kpiB)
    local kpiC=GUI.mkLabel(44,3,"Online: - / -",{color=colors.orange}); scr:add(kpiC)
    local kpiD=GUI.mkLabel(64,3,"Fuel%: - .. -",{color=colors.yellow}); scr:add(kpiD)

    local lst=GUI.mkList(2,5,78,10,{}); scr:add(lst)
    local lblPolicy=GUI.mkLabel(2,14,"Policies & Prioritäten",{color=colors.lightGray}); scr:add(lblPolicy)
    local lstPolicy=GUI.mkList(2,15,78,5,{}); scr:add(lstPolicy)

    local function set_sort(v) on_filter_change('sort_by', v) end
    local function set_filter_online(v) on_filter_change('filter_online', v=="ONLINE") end
    local function set_filter_role(v) on_filter_change('filter_role', v) end

    local btnSort=GUI.mkSelector(2,20,18,{"POWER","RPM","HOST"},"POWER",set_sort); scr:add(btnSort)
    local btnFilt=GUI.mkSelector(22,20,14,{"ONLINE","ALLE"},"ONLINE",set_filter_online); scr:add(btnFilt)
    local btnRole=GUI.mkSelector(38,20,18,{"ALL","MASTER","REACTOR","FUEL","WASTE","AUX"},"ALL",set_filter_role); scr:add(btnRole)
    local btnRef =GUI.mkButton(58,20,10,3,"Refresh", on_refresh, colors.gray); scr:add(btnRef)
    local btnHome=GUI.mkButton(70,20,10,3,"Home",    function() on_home() end, colors.lightGray); scr:add(btnHome)

    scr._redraw=function()
      local v = view_state.overview
      kpiA.props.text = v.kpi_power_text or ''
      kpiB.props.text = v.kpi_rpm_text or ''
      kpiC.props.text = v.kpi_online_text or ''
      kpiD.props.text = v.kpi_fuel_text or ''
      lst.props.items = v.rows or {}
      lstPolicy.props.items = v.policy_rows or {}
      if btnSort.props and v.filters then btnSort.props.value = v.filters.sort_by end
      if btnFilt.props and v.filters then btnFilt.props.value = v.filters.filter_online and "ONLINE" or "ALLE" end
      if btnRole.props and v.filters then btnRole.props.value = v.filters.filter_role end
      TB:update(view_state.topbar)
    end

    router:register(scr); router:show("ovw")
  end

  local function handle_event(ev)
    if ev[1]=='monitor_touch' or ev[1]=='mouse_click' or ev[1]=='mouse_drag' or ev[1]=='term_resize' then
      request_redraw(ev[1])
      if router and router.handleEvent then router:handleEvent(ev) end
    elseif ev[1]=='ui_redraw' then
      redraw_pending=false
      if scr and scr._redraw then scr._redraw() end
      if router and router.draw then router:draw() end
    end
  end

  local function set_view(view)
    view_state.overview = view.overview or view_state.overview
    view_state.topbar = view.topbar or view_state.topbar
    request_redraw('view')
  end

  local function start()
    if GUI and mon then build_gui() else
      term.clear(); term.setCursorPos(1,1)
      safe_print("System ▢ Overview (TUI) ready")
    end
    request_redraw('start')
  end

  local function stop()
  end

  return { handle_event = handle_event, start = start, stop = stop, monitor = mon, set_view = set_view }
end

return M
