--========================================================
-- /xreactor/master/alarm_panel.lua
-- Alarmanzeige für aktive Gruppen + Historie (passiv)
--========================================================
local GUI; do local ok,g=pcall(require,"xreactor.shared.gui"); if ok then GUI=g elseif fs.exists("/xreactor/shared/gui.lua") then GUI=dofile("/xreactor/shared/gui.lua") end end
local Topbar = dofile("/xreactor/shared/topbar.lua")
local TOPBAR_CFG = { window_s = 300, health = { timeout_s = 10, warn_s = 20, crit_s = 60, min_nodes = 1 } }

local M = {}

local TEXT_UTILS_PATH = "/xreactor/shared/text.lua"
local function load_text_utils()
  local ok, mod = pcall(dofile, TEXT_UTILS_PATH)
  if not ok or not mod then
    error("Unable to load text utilities from " .. TEXT_UTILS_PATH .. ": " .. tostring(mod))
  end
  if not mod.sanitizeText then
    error("text.lua is missing sanitizeText at " .. TEXT_UTILS_PATH)
  end
  return mod
end

local text_utils = load_text_utils()
local sanitizeText = text_utils.sanitizeText
local function safe_print(text)
  print(sanitizeText(text))
end

local function noop() end

function M.create(opts)
  local cfg = opts or {}
  local mon = cfg.monitor
  local fixed_scale = cfg.text_scale
  local function monitor_name(dev)
    if dev and peripheral and peripheral.getName then
      local ok, name = pcall(peripheral.getName, dev)
      if ok and name then return name end
    end
    return "UNKNOWN"
  end

  local mon_name = monitor_name(mon)

  if GUI and GUI.apply_text_scale then
    GUI.apply_text_scale(mon, { name = mon_name, fixed_scale = fixed_scale })
  elseif mon and not GUI then
    pcall(mon.setTextScale, 0.5)
  end
  local on_home = cfg.on_home or noop
  local on_ack = cfg.on_ack or noop

  local view_state = { alarm = { active = {}, history = {} }, topbar = {} }

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
    router=GUI.mkRouter({monitorName=mon_name})
    scr=GUI.mkScreen("alarm","Alarm ▢ Master")
    TB = Topbar.create({title="Alarm ▢ Master", monitor_name=mon_name, window_s=TOPBAR_CFG.window_s}); TB:mount(GUI,scr)

    local lblActive=GUI.mkLabel(2,3,"Aktive Alarme (Severity ▸ Source)",{color=colors.lightGray}); scr:add(lblActive)
    local lstActive=GUI.mkList(2,4,78,9,{}); scr:add(lstActive)

    local lblHist=GUI.mkLabel(2,14,"Letzte Alarm-Historie",{color=colors.lightGray}); scr:add(lblHist)
    local lstHist=GUI.mkList(2,15,78,7,{}); scr:add(lstHist)

    local btnAck = GUI.mkButton(2,23,12,3,"Quittieren", on_ack, colors.gray); scr:add(btnAck)
    local btnHome= GUI.mkButton(16,23,10,3,"Home", function() on_home() end, colors.lightGray); scr:add(btnHome)

    scr._redraw=function()
      local v = view_state.alarm or {}
      lstActive.props.items = v.active or {}
      lstHist.props.items = v.history or {}
      TB:update(view_state.topbar)
    end

    router:register(scr); router:show("alarm")
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

  local function ensure_alarm_lists(alarm)
    local cleaned = { active = {}, history = {} }
    if type(alarm) ~= 'table' then return cleaned end

    local function append(dst, entry)
      if entry == nil then return end
      if type(entry) == 'table' then
        local e = {
          text = entry.text or (entry.source and tostring(entry.source)) or (entry.alarm and tostring(entry.alarm)) or "UNKNOWN",
          color = entry.color or colors.white,
        }
        table.insert(dst, e)
      else
        table.insert(dst, { text = tostring(entry), color = colors.white })
      end
    end

    for _,item in ipairs(alarm.active or {}) do append(cleaned.active, item) end
    for _,item in ipairs(alarm.history or {}) do append(cleaned.history, item) end
    return cleaned
  end

  local function set_view(view)
    if type(view) ~= 'table' then return end
    view_state.alarm = ensure_alarm_lists(view.alarm or {})
    view_state.topbar = view.topbar or view_state.topbar
    request_redraw('view')
  end

  local function start()
    if GUI and mon then build_gui() else
      term.clear(); term.setCursorPos(1,1)
      safe_print("Alarm ▢ Master (TUI) ready")
    end
    request_redraw('start')
  end

  local function stop()
  end

  return { handle_event = handle_event, start = start, stop = stop, monitor = mon, set_view = set_view }
end

return M
