--========================================================
-- /xreactor/master/master_model.lua
-- Gemeinsames Master-UI Modell: sammelt Daten über Dispatcher
-- und liefert bereits aufbereitete Strings/Zeilen für Panels.
--========================================================
local PROTO = dofile('/xreactor/shared/protocol.lua')

local function now_s() return os.epoch('utc')/1000 end
local function n0(x,d) x=tonumber(x); if x==nil then return d or 0 end; return x end

local M = {}

function M.create(dispatcher, opts)
  local cfg = opts or {}
  local timeout_s = cfg.telem_timeout_s or 10

  local state = {
    nodes = {},
    alarms = {},
    overview_filters = { sort_by = 'POWER', filter_online = true, filter_role = 'ALL' },
  }

  local listeners = { overview = {}, fuel = {}, waste = {}, alarm = {} }

  local function notify(kind)
    for _,cb in ipairs(listeners[kind] or {}) do
      pcall(cb, kind)
    end
  end

  function dispatcher:__subscribe(kind, cb)
    table.insert(listeners[kind], cb)
  end

  local function key_for(uid, id)
    if uid and tostring(uid) ~= '' then return tostring(uid) end
    return 'id:' .. tostring(id or '?')
  end

  local function ensure_node(uid, id)
    local k = key_for(uid, id)
    local n = state.nodes[k]
    if not n then
      n = { uid = uid or k, rednet_id = id or 0, hostname = '-', role = '-', cluster = '-', rpm = 0, power_mrf = 0, flow = 0, fuel_pct = nil, last_seen = 0, state = '-' }
      state.nodes[k] = n
    end
    return n
  end

  local function on_telem(msg, from_id)
    if type(msg) ~= 'table' or type(msg.data) ~= 'table' then return end
    local d = msg.data
    local n = ensure_node(d.uid, from_id)
    n.rednet_id = from_id
    n.hostname = msg.hostname or n.hostname
    n.role = (msg.role and tostring(msg.role):upper()) or n.role
    n.cluster = msg.cluster or n.cluster
    n.rpm = n0(d.rpm, n.rpm)
    n.power_mrf = n0(d.power_mrf, n.power_mrf)
    n.flow = n0(d.flow, n.flow)
    n.fuel_pct = tonumber(d.fuel_pct or n.fuel_pct)
    n.last_seen = now_s()
    notify('overview'); notify('fuel'); notify('waste')
  end

  local function on_hello(msg, from_id)
    local n = ensure_node(msg.uid, from_id)
    n.rednet_id = from_id
    n.hostname = msg.hostname or n.hostname
    n.role = (msg.role and tostring(msg.role):upper()) or n.role
    n.cluster = msg.cluster or n.cluster
    n.last_seen = now_s()
    notify('overview'); notify('fuel'); notify('waste')
  end

  local function on_state(msg, from_id)
    local n = ensure_node(msg.uid, from_id)
    n.rednet_id = from_id
    n.hostname = msg.hostname or n.hostname
    n.role = (msg.role and tostring(msg.role):upper()) or n.role
    n.cluster = msg.cluster or n.cluster
    n.state = tostring(msg.state or n.state or '-')
    n.last_seen = now_s()
    notify('overview')
  end

  local function push_alarm(a)
    table.insert(state.alarms, 1, a)
    if #state.alarms > 100 then table.remove(state.alarms) end
    notify('alarm')
  end

  local function on_alarm(msg)
    if type(msg) ~= 'table' then return end
    push_alarm({ ts = os.date('%H:%M:%S'), level = string.upper(msg.level or 'INFO'), code = msg.code or '?', msg = msg.msg or '', node = msg.node or '-', uid = msg.uid or '-' })
  end

  dispatcher:subscribe(PROTO.T.TELEM, on_telem)
  dispatcher:subscribe(PROTO.T.NODE_HELLO, on_hello)
  dispatcher:subscribe(PROTO.T.NODE_STATE, on_state)
  dispatcher:subscribe('ALARM', on_alarm)

  function state:get_overview_view()
    local kpi = { total_power = 0, rpm_sum = 0, rpm_cnt = 0, online = 0, offline = 0, fuel_min = nil, fuel_max = nil }
    local rows = {}
    local now = now_s()
    local f = state.overview_filters
    for _,n in pairs(state.nodes) do
      local age = now - (n.last_seen or 0)
      local is_on = age <= timeout_s
      if is_on then kpi.online = kpi.online + 1 else kpi.offline = kpi.offline + 1 end
      if (not f.filter_online or is_on) and (f.filter_role == 'ALL' or tostring(n.role or '-'):upper() == f.filter_role) then
        kpi.total_power = kpi.total_power + n0(n.power_mrf, 0)
        kpi.rpm_sum = kpi.rpm_sum + n0(n.rpm, 0)
        kpi.rpm_cnt = kpi.rpm_cnt + 1
        if n.fuel_pct ~= nil then
          kpi.fuel_min = (kpi.fuel_min == nil) and n.fuel_pct or math.min(kpi.fuel_min, n.fuel_pct)
          kpi.fuel_max = (kpi.fuel_max == nil) and n.fuel_pct or math.max(kpi.fuel_max, n.fuel_pct)
        end
        table.insert(rows, {
          hostname = n.hostname,
          role = n.role,
          cluster = n.cluster,
          power = n0(n.power_mrf),
          rpm = n0(n.rpm),
          flow = n0(n.flow),
          fuel = n.fuel_pct and (tostring(n.fuel_pct)..'%') or 'n/a',
          age = math.floor(math.max(0, age)),
          state = tostring(n.state or '-'),
          online = is_on,
        })
      end
    end
    table.sort(rows, function(a,b)
      if f.sort_by == 'RPM' then return a.rpm > b.rpm
      elseif f.sort_by == 'HOST' then return tostring(a.hostname or '') < tostring(b.hostname or '')
      else return a.power > b.power end
    end)
    local list_rows = {}
    if #rows == 0 then
      list_rows = { { text = '(Noch keine TELEM gesehen – Refresh oder kurz warten)', color = colors.gray } }
    else
      for _,r in ipairs(rows) do
        local line = string.format('%-16s %-7s %-8s  P:%-6d RPM:%-5d Flow:%-5d Fuel:%-4s  %2ss  %s',
          tostring(r.hostname or '-'), tostring(r.role or '-'), tostring(r.cluster or '-'), r.power, r.rpm, r.flow, r.fuel, r.age, tostring(r.state or '-'))
        table.insert(list_rows, { text = line, color = r.online and colors.white or colors.lightGray })
      end
    end

    return {
      filters = f,
      kpi_power_text = string.format('Power: %d RF/t', math.floor(kpi.total_power + 0.5)),
      kpi_rpm_text = string.format('\226\136\157 RPM: %d', (kpi.rpm_cnt > 0) and math.floor(kpi.rpm_sum / kpi.rpm_cnt + 0.5) or 0),
      kpi_online_text = string.format('Online: %d / %d', kpi.online, kpi.online + kpi.offline),
      kpi_fuel_text = (kpi.fuel_min and kpi.fuel_max) and string.format('Fuel%%: %d .. %d', kpi.fuel_min, kpi.fuel_max) or 'Fuel%: n/a',
      rows = list_rows,
    }
  end

  function state:set_overview_filter(key, value)
    state.overview_filters[key] = value
    notify('overview')
  end

  function state:get_fuel_rows()
    local rows = {}
    for uid,n in pairs(state.nodes) do
      local fuel = n.fuel_pct and (tostring(n.fuel_pct)..'%') or 'n/a'
      table.insert(rows, { text = string.format('%-12s Fuel:%-4s RPM:%-5d P:%-7d host:%s', tostring(uid), fuel, n0(n.rpm), n0(n.power_mrf), tostring(n.hostname or '-')), color = colors.white })
    end
    if #rows == 0 then rows = { { text = '(Noch keine Telemetrie empfangen)', color = colors.gray } } end
    return rows
  end

  function state:get_waste_rows()
    local rows = {}
    for uid,n in pairs(state.nodes) do
      table.insert(rows, { text = string.format('%-12s host:%-12s info:%s', tostring(uid), tostring(n.hostname or '-'), string.format('RPM:%d P:%d', n0(n.rpm), n0(n.power_mrf))), color = colors.white })
    end
    if #rows == 0 then rows = { { text = '(Noch keine Daten)', color = colors.gray } } end
    return rows
  end

  function state:get_alarm_rows()
    local rows = {}
    for _,a in ipairs(state.alarms) do
      local color = (a.level=='CRIT' and colors.red) or (a.level=='WARN' and colors.orange) or colors.white
      local line = string.format('%s [%s] %s %-8s %s', a.ts, a.level, a.code, a.node or '-', a.msg or '')
      table.insert(rows, { text = line, color = color })
    end
    if #rows == 0 then rows = { { text = '(Keine Alarme)', color = colors.lightGray } } end
    return rows
  end

  function state:ack_alarms()
    state.alarms = {}
    notify('alarm')
  end

  function state:subscribe(kind, cb)
    dispatcher:__subscribe(kind, cb)
  end

  return state
end

return M
