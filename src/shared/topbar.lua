--========================================================
-- Einheitliche Topbar: Titel, Uhr, Alarm-Badge, NET-Status, HEALTH
--========================================================
local M = {}

function M.create(opts)
  local tb = {
    title      = tostring((opts and opts.title) or "XReactor"),
    monitor_name = (opts and opts.monitor_name) or nil,
    show_clock = (opts and opts.show_clock) ~= false,
    show_net   = (opts and opts.show_net)   ~= false,
    show_alarm = (opts and opts.show_alarm) ~= false,
    show_health= (opts and opts.show_health) ~= false,
    _labels={}, _gui=nil, _screen=nil,
    _w=80, _h=25,
    _view={ badge={total=0,crit=0,warn=0,info=0}, health={level="--"}, net_ok=false },
  }

  local mon = tb.monitor_name and peripheral.wrap(tb.monitor_name) or nil
  if mon and mon.getSize then tb._w, tb._h = mon.getSize() end

  local function pos_left() return 2,1 end
  local function pos_center() return math.max(2, math.floor(tb._w/2)-5), 1 end
  local function pos_right_badge() return math.max(2, tb._w-34), 1 end
  local function pos_right_health() return math.max(2, tb._w-22), 1 end
  local function pos_right_net() return math.max(2, tb._w-11), 1 end

  function tb:mount(gui, screen)
    self._gui, self._screen = gui, screen
    local GUI = gui
    local lx,ly = pos_left(); self._labels.title = GUI.mkLabel(lx,ly, self.title, {color=colors.cyan}); screen:add(self._labels.title)
    if self.show_clock  then local cx,cy = pos_center(); self._labels.clock = GUI.mkLabel(cx,cy, "--:--:--", {color=colors.lightGray}); screen:add(self._labels.clock) end
    if self.show_alarm  then local bx,by = pos_right_badge(); self._labels.badge = GUI.mkLabel(bx,by, "[Alarme: 0]", {color=colors.lightBlue}); screen:add(self._labels.badge) end
    if self.show_health then local hx,hy = pos_right_health(); self._labels.hlth  = GUI.mkLabel(hx,hy, "[HLTH:--]", {color=colors.red}); screen:add(self._labels.hlth) end
    if self.show_net    then local nx,ny = pos_right_net();    self._labels.net   = GUI.mkLabel(nx,ny, "[NET:--]",  {color=colors.red}); screen:add(self._labels.net) end
  end

  function tb:set_view(view)
    if type(view) ~= "table" then return end
    self._view = view
  end

  function tb:update(view)
    if type(view) == "table" then self:set_view(view) end
    local v = self._view or {}
    if self._labels.clock then self._labels.clock.props.text = v.clock or os.date("%H:%M:%S") end
    if self._labels.net then
      local net_ok = v.net_ok == true
      self._labels.net.props.text  = net_ok and "[NET:OK]" or "[NET:--]"
      self._labels.net.props.color = net_ok and colors.green or colors.red
    end
    if self._labels.hlth then
      local lvl = v.health and v.health.level or "--"
      if lvl=="OK" then self._labels.hlth.props.text="[HLTH:OK]"; self._labels.hlth.props.color=colors.green
      elseif lvl=="DEG" then self._labels.hlth.props.text="[HLTH:DEG]"; self._labels.hlth.props.color=colors.orange
      elseif lvl=="FAIL" then self._labels.hlth.props.text="[HLTH:FAIL]"; self._labels.hlth.props.color=colors.red
      else self._labels.hlth.props.text="[HLTH:--]"; self._labels.hlth.props.color=colors.lightGray end
    end
    if self._labels.badge then
      local b = v.badge or {}
      local total = b.total or 0; local crit = b.crit or 0; local warn = b.warn or 0; local info = b.info or 0
      self._labels.badge.props.text = string.format("[Alarme: %d | C:%d W:%d I:%d]", total, crit, warn, info)
      self._labels.badge.props.color = (crit>0 and colors.red) or (warn>0 and colors.orange) or colors.lightBlue
    end
  end

  return tb
end

return M

