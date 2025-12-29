--========================================================
-- /xreactor/master/waste_panel.lua
-- Waste-Management (GUI-Skeleton) mit Topbar
--========================================================
local GUI; do local ok,g=pcall(require,"xreactor.shared.gui"); if ok then GUI=g elseif fs.exists("/xreactor/shared/gui.lua") then GUI=dofile("/xreactor/shared/gui.lua") end end
local Topbar = dofile("/xreactor/shared/topbar.lua")

local M = {}

local function noop() end

function M.create(opts)
  local cfg = opts or {}
  local mon = assert(cfg.monitor, "monitor required")
  if mon and not GUI then pcall(mon.setTextScale, 0.5) end
  local on_home = cfg.on_home or noop
  local view_state = { rows = {}, topbar = {} }

  local TB
  local redraw_pending=false
  local router, scr

  local function request_redraw(reason)
    if not (GUI and mon) then return end
    if redraw_pending then return end
    redraw_pending=true
    os.queueEvent("ui_redraw", reason or "update")
  end

  local function build_gui()
    if not (GUI and mon) then return nil end
    router=GUI.mkRouter({monitorName=peripheral.getName(mon)})
    scr=GUI.mkScreen("waste","Waste ▢ Panel")
    TB = Topbar.create({title="Waste ▢ Panel", monitor_name=peripheral.getName(mon)}); TB:mount(GUI,scr)

    local list=GUI.mkList(2,3,78,16,{}); scr:add(list)
    local btnHome=GUI.mkButton(2,20,10,3,"Home", on_home, colors.lightGray); scr:add(btnHome)

    scr._redraw=function()
      list.props.items = view_state.rows
      TB:update(view_state.topbar)
    end

    router:register(scr); router:show("waste")
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
    view_state.rows = view.rows or view_state.rows
    view_state.topbar = view.topbar or view_state.topbar
    request_redraw('view')
  end

  local function start()
    if GUI and mon then build_gui() else
      term.clear(); term.setCursorPos(1,1)
      print("Waste ▢ Panel (TUI) ready")
    end
    request_redraw('start')
  end

  local function stop()
  end

  return { handle_event = handle_event, start = start, stop = stop, monitor = mon, set_view = set_view }
end

return M
