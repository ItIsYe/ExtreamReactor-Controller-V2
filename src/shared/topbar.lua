--========================================================
-- /xreactor/shared/topbar.lua
-- Einheitliche Topbar: Titel, Uhr, Alarm-Badge, NET-Status, HEALTH
--========================================================
local M = {}
local function now_s() return os.epoch("utc")/1000 end
local function try_wrap(name) local ok,p=pcall(peripheral.wrap,name); if ok then return p end; return nil end

function M.create(opts)
  local tb = {
    title      = tostring((opts and opts.title) or "XReactor"),
    auth_token = (opts and opts.auth_token) or "xreactor",
    modem_side = (opts and opts.modem_side) or "right",
    monitor_name = (opts and opts.monitor_name) or nil,
    window_s   = (opts and opts.window_s) or 300,
    show_clock = (opts and opts.show_clock) ~= false,
    show_net   = (opts and opts.show_net)   ~= false,
    show_alarm = (opts and opts.show_alarm) ~= false,
    show_health= (opts and opts.show_health) ~= false,
    health = {
      timeout_s = ((opts and opts.health) and opts.health.timeout_s) or 10,
      warn_s    = ((opts and opts.health) and opts.health.warn_s)    or 20,
      crit_s    = ((opts and opts.health) and opts.health.crit_s)    or 60,
      min_nodes = ((opts and opts.health) and opts.health.min_nodes) or 1,
    },
    _alarm={list={}}, _nodes={ last_any=0, by_uid={} }, _labels={}, _gui=nil, _screen=nil,
    _w=80, _h=25, _rx_running=false,
  }

  local mon = tb.monitor_name and try_wrap(tb.monitor_name) or nil
  if mon and mon.getSize then tb._w, tb._h=mon.getSize() end

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

  function tb:start_rx()
    if self._rx_running then return end
    self._rx_running=true
    parallel.waitForAll(function()
      while self._rx_running do
        local from,msg = rednet.receive(0.2)
        if from and type(msg)=="table" and msg._auth==self.auth_token then
          local ts = now_s()
          if msg.type=="ALARM" then
            table.insert(self._alarm.list, {ts=ts, level=string.upper(tostring(msg.level or "INFO"))})
            local keep={}; for _,a in ipairs(self._alarm.list) do if (ts-a.ts)<=self.window_s then table.insert(keep,a) end end
            self._alarm.list=keep
          end
          if msg.type=="TELEM" or msg.type=="NODE_HELLO" then
            local uid = (msg.data and msg.data.uid) or msg.uid or ("id:"..tostring(from))
            self._nodes.by_uid[tostring(uid)] = ts
            self._nodes.last_any = ts
          end
        end
      end
    end)
  end

  local function compute_badge(tb)
    local ts=now_s(); local total,crit,warn,info=0,0,0,0
    for _,a in ipairs(tb._alarm.list) do
      if (ts-a.ts)<=tb.window_s then
        total=total+1
        if a.level=="CRIT" then crit=crit+1 elseif a.level=="WARN" then warn=warn+1 else info=info+1 end
      end
    end
    return total,crit,warn,info
  end

  local function compute_health(tb)
    if not rednet.isOpen(tb.modem_side or "right") then return "FAIL","Modem" end
    local ts=now_s(); local total,offline,stale_max=0,0,0
    for _,last in pairs(tb._nodes.by_uid) do
      total=total+1; local age=ts-(last or 0); stale_max = math.max(stale_max, age)
      if age>(tb.health.timeout_s or 10) then offline=offline+1 end
    end
    if total<(tb.health.min_nodes or 1) then return "DEG","NoNodes" end
    if stale_max>(tb.health.crit_s or 60) then return "FAIL","Stale>crit" end
    if offline>0 or stale_max>(tb.health.warn_s or 20) then return "DEG","Offline/Slow" end
    return "OK","Healthy"
  end

  function tb:update()
    if self._labels.clock then self._labels.clock.props.text = os.date("%H:%M:%S") end
    if self._labels.net then
      local ok = rednet.isOpen(self.modem_side or "right")
      self._labels.net.props.text  = ok and "[NET:OK]" or "[NET:--]"
      self._labels.net.props.color = ok and colors.green or colors.red
    end
    if self._labels.hlth then
      local lvl = compute_health(self)
      if lvl=="OK" then self._labels.hlth.props.text="[HLTH:OK]"; self._labels.hlth.props.color=colors.green
      elseif lvl=="DEG" then self._labels.hlth.props.text="[HLTH:DEG]"; self._labels.hlth.props.color=colors.orange
      else self._labels.hlth.props.text="[HLTH:FAIL]"; self._labels.hlth.props.color=colors.red end
    end
    if self._labels.badge then
      local total,crit,warn,info = compute_badge(self)
      self._labels.badge.props.text = string.format("[Alarme: %d | C:%d W:%d I:%d]", total, crit, warn, info)
      self._labels.badge.props.color = (crit>0 and colors.red) or (warn>0 and colors.orange) or colors.lightBlue
    end
  end

  return tb
end

return M

