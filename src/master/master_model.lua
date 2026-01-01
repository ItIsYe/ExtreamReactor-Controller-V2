--========================================================
-- /xreactor/master/master_model.lua
-- Gemeinsames Master-UI Modell: sammelt Daten über Dispatcher
-- und liefert bereits aufbereitete Strings/Zeilen für Panels.
--========================================================
local PROTO = dofile('/xreactor/shared/protocol.lua')
local Identity = dofile('/xreactor/shared/identity.lua')
local StateStore = dofile('/xreactor/shared/local_state_store.lua')

local text_utils = dofile('/xreactor/shared/text.lua')
local sanitizeText = (text_utils and text_utils.sanitizeText) or function(text) return tostring(text or '') end
local function safe_print(text)
  print(sanitizeText(text))
end

local function now_s() return os.epoch('utc')/1000 end
local function n0(x,d) x=tonumber(x); if x==nil then return d or 0 end; return x end
local function normalize_severity(raw)
  local s = tostring(raw or 'INFO'):upper()
  if s == 'CRIT' then return 'CRITICAL' end
  if s == 'WARNING' then return 'WARN' end
  if s ~= 'WARN' and s ~= 'CRITICAL' then return 'INFO' end
  return s
end

local SEV_RANK = { INFO = 1, WARN = 2, CRITICAL = 3 }
local function max_severity(a, b)
  a, b = normalize_severity(a), normalize_severity(b)
  return (SEV_RANK[a] >= SEV_RANK[b]) and a or b
end

local function parse_ts(ts)
  local tnum = tonumber(ts)
  if not tnum then return now_s(), os.date('%H:%M:%S') end
  local sec = (tnum > 1e10) and (tnum/1000) or tnum
  return sec, os.date('%H:%M:%S', sec)
end

local function alarm_key(a)
  return string.format('%s|%s|%s', tostring(a.source or '-'), tostring(a.alarm_id or a.code or '?'), tostring(a.message or ''))
end

local M = {}

function M.create(dispatcher, opts)
  local cfg = opts or {}
  local timeout_s = cfg.telem_timeout_s or 10
  local alarm_cfg = cfg.alarms or {}
  local escalation_cfg = alarm_cfg.escalation or {}
  local suppression_window_s = alarm_cfg.suppression_window_s or 30
  local alarm_history_limit = alarm_cfg.history_limit or 200
  local esc_info_to_warn_s = escalation_cfg.info_to_warn_s or 120
  local esc_warn_to_crit_s = escalation_cfg.warn_to_crit_s or 120

  local state = {
    nodes = {},
    alarm_history = {},
    alarm_groups = {},
    active_alarms = {},
    policies = {},
    overview_filters = { sort_by = 'POWER', filter_online = true, filter_role = 'ALL' },
  }

  local listeners = { overview = {}, fuel = {}, waste = {}, alarm = {}, topbar = {} }

  local ident = Identity.load_identity()
  local alarm_store = StateStore.create({ identity = ident, path = '/xreactor/state/master_alarm_state.lua' })

  local function trim_alarm_history()
    while #state.alarm_history > alarm_history_limit do table.remove(state.alarm_history) end
  end

  -- Persist active groups and recent history so the master UI can survive restarts without
  -- replaying control actions.
  local function persist_alarm_state(reason)
    if not alarm_store then return end
    local snapshot = {
      active_alarms = state.active_alarms,
      alarm_history = state.alarm_history,
      timestamp = os.epoch('utc'),
      reason = reason,
    }
    pcall(function() alarm_store:save(snapshot) end)
  end

  local function notify(kind)
    for _,cb in ipairs(listeners[kind] or {}) do
      pcall(cb, kind)
    end
  end

  local function effective_severity(entry, ref_now)
    local now = ref_now or now_s()
    local base = normalize_severity(entry.base_severity or entry.severity or 'INFO')
    if base == 'CRITICAL' then return base end
    local age = math.max(0, now - (entry.first_ts or now))
    local sev = base
    if sev == 'INFO' and age >= esc_info_to_warn_s then
      sev = 'WARN'
      age = age - esc_info_to_warn_s
    end
    if (sev == 'WARN' or base == 'WARN') and age >= esc_warn_to_crit_s then
      sev = 'CRITICAL'
    end
    return sev
  end

  local function rebuild_alarm_groups(ref_now)
    local now = ref_now or now_s()
    state.alarm_groups = {}
    for _,entry in pairs(state.active_alarms) do
      local source = tostring(entry.source or '-')
      local sev = effective_severity(entry, now)
      local groups = state.alarm_groups
      local g = groups[source]
      if not g then g = { source = source, severities = {} }; groups[source] = g end
      local se = g.severities[sev]
      if not se then se = { severity = sev, count = 0, latest_ts = 0, latest_ts_txt = '', latest_id = '', latest_message = '', acked = true } end
      local cnt = entry.count or 1
      se.count = se.count + cnt
      se.acked = se.acked and (entry.acked or false)
      if (entry.last_ts or 0) >= (se.latest_ts or 0) then
        se.latest_ts = entry.last_ts or 0
        se.latest_ts_txt = entry.last_ts_txt or ''
        se.latest_id = entry.last_alarm_id or entry.alarm_id or entry.code or '?'
        se.latest_message = entry.message or entry.latest_message or ''
      end
      g.severities[sev] = se
    end
  end

  local function log_persist_warning(reason)
    if not reason then return end
    safe_print(string.format('[master_model] persisted alarm state invalid (%s); using defaults', tostring(reason)))
  end

  -- Reload persisted alarm view data on startup; warn and default if the snapshot is corrupt.
  local persisted, load_err = alarm_store and alarm_store:load()
  if load_err then log_persist_warning(load_err) end
  if type(persisted) == 'table' then
    if persisted.active_alarms ~= nil and type(persisted.active_alarms) ~= 'table' then
      log_persist_warning('active_alarms_not_table')
    else
      state.active_alarms = persisted.active_alarms or state.active_alarms
    end
    if persisted.alarm_history ~= nil and type(persisted.alarm_history) ~= 'table' then
      log_persist_warning('alarm_history_not_table')
    else
      state.alarm_history = persisted.alarm_history or state.alarm_history
    end
    trim_alarm_history()
    rebuild_alarm_groups(now_s())
    notify('alarm'); notify('topbar')
  elseif persisted ~= nil then
    log_persist_warning('not_a_table')
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
      n = { uid = uid or k, rednet_id = id or 0, hostname = '-', role = '-', cluster = '-', priority = nil, rpm = 0, power_mrf = 0, flow = 0, fuel_pct = nil, last_seen = 0, state = '-' }
      state.nodes[k] = n
    end
    return n
  end

  local function record_policy(rec, source, ts_s, ts_txt)
    if type(rec) ~= 'table' then return end
    local pol = rec.suggested_policy or rec.policy or rec
    local kind = tostring((pol and pol.kind) or rec.kind or rec.type or 'GENERAL'):upper()
    local pressure = tostring((pol and pol.pressure) or rec.pressure or rec.level or 'UNKNOWN'):upper()
    state.policies[kind] = {
      kind = kind,
      pressure = pressure,
      source = source or '-',
      rationale = rec.rationale or rec.reason,
      intent = rec.intent,
      ts_s = ts_s,
      ts = ts_txt,
    }
  end

  local function on_telem(msg, from_id)
    if type(msg) ~= 'table' or type(msg.data) ~= 'table' then return end
    local d = msg.data
    local n = ensure_node(d.uid, from_id)
    n.rednet_id = from_id
    n.hostname = msg.hostname or n.hostname
    n.role = (msg.role and tostring(msg.role):upper()) or n.role
    n.cluster = msg.cluster or n.cluster
    n.priority = tonumber(msg.priority or d.priority or d.node_priority or n.priority)
    n.rpm = n0(d.rpm, n.rpm)
    n.power_mrf = n0(d.power_mrf, n.power_mrf)
    n.flow = n0(d.flow, n.flow)
    n.fuel_pct = tonumber(d.fuel_pct or n.fuel_pct)
    n.last_seen = now_s()

    if type(d.policy_recommendation) == 'table' then
      local ts_s, ts_txt = parse_ts(d.policy_recommendation.timestamp or d.policy_recommendation.ts or msg.timestamp or msg.ts)
      record_policy(d.policy_recommendation, n.hostname or n.uid, ts_s, ts_txt)
    end
    notify('overview'); notify('fuel'); notify('waste'); notify('topbar')
  end

  local function on_hello(msg, from_id)
    local n = ensure_node(msg.uid, from_id)
    n.rednet_id = from_id
    n.hostname = msg.hostname or n.hostname
    n.role = (msg.role and tostring(msg.role):upper()) or n.role
    n.cluster = msg.cluster or n.cluster
    n.priority = tonumber(msg.priority or n.priority)
    n.last_seen = now_s()
    notify('overview'); notify('fuel'); notify('waste'); notify('topbar')
  end

  local function on_state(msg, from_id)
    local n = ensure_node(msg.uid, from_id)
    n.rednet_id = from_id
    n.hostname = msg.hostname or n.hostname
    n.role = (msg.role and tostring(msg.role):upper()) or n.role
    n.cluster = msg.cluster or n.cluster
    n.priority = tonumber(msg.priority or (msg.data and msg.data.priority) or n.priority)
    n.state = tostring(msg.state or n.state or '-')
    n.last_seen = now_s()
    notify('overview'); notify('topbar')
  end

  local function push_alarm(a)
    local ts_s = a.ts_s or now_s()
    local key = alarm_key(a)
    local entry = state.active_alarms[key]
    local suppressed = false
    if entry then
      local same_msg = tostring(entry.message or '') == tostring(a.message or '')
      local same_sev = normalize_severity(entry.base_severity or entry.severity) == normalize_severity(a.severity)
      local recent = (ts_s - (entry.last_ts or 0)) <= suppression_window_s
      suppressed = same_msg and same_sev and recent

      entry.count = (entry.count or 0) + 1
      entry.last_ts = ts_s
      entry.last_ts_txt = a.ts or os.date('%H:%M:%S', ts_s)
      entry.last_alarm_id = a.alarm_id or a.code or entry.last_alarm_id or '?'
      entry.base_severity = max_severity(entry.base_severity or entry.severity, a.severity)
      entry.message = a.message or entry.message
      if not suppressed and entry.acked then entry.acked = false; entry.ack_ts = nil end
    else
      entry = {
        first_ts = ts_s,
        last_ts = ts_s,
        last_ts_txt = a.ts or os.date('%H:%M:%S', ts_s),
        base_severity = a.severity,
        message = a.message,
        source = a.source,
        alarm_id = a.alarm_id or a.code,
        last_alarm_id = a.alarm_id or a.code,
        code = a.code,
        count = 1,
        acked = false,
      }
      state.active_alarms[key] = entry
    end

    if not suppressed then
      local history_entry = {
        ts = a.ts or os.date('%H:%M:%S', ts_s),
        ts_s = ts_s,
        severity = effective_severity(entry, ts_s),
        base_severity = entry.base_severity,
        message = a.message,
        source = a.source,
        alarm_id = a.alarm_id or a.code,
        code = a.code,
        acked = entry.acked or false,
        count = entry.count,
      }
      table.insert(state.alarm_history, 1, history_entry)
      trim_alarm_history()
    end

    rebuild_alarm_groups(ts_s)
    notify('alarm'); notify('topbar')
    persist_alarm_state('alarm_push')
  end

  local function on_alarm(msg)
    if type(msg) ~= 'table' then return end
    local severity = normalize_severity(msg.severity or msg.level)
    local ts_s, ts_txt = parse_ts(msg.timestamp or msg.ts)
    push_alarm({
      ts = ts_txt,
      ts_s = ts_s,
      severity = severity,
      message = msg.message or msg.msg or msg.text or msg.code or '',
      source = msg.source_node_id or msg.node or msg.uid or '-',
      alarm_id = msg.alarm_id or msg.uid or '?',
      code = msg.code,
    })
  end

  dispatcher:subscribe(PROTO.T.TELEM, on_telem)
  dispatcher:subscribe(PROTO.T.NODE_HELLO, on_hello)
  dispatcher:subscribe(PROTO.T.NODE_STATE, on_state)
  dispatcher:subscribe('ALARM', on_alarm)

  function state:get_topbar_view(opts_tb)
    local cfg_tb = opts_tb or {}
    local window_s = cfg_tb.window_s or 300
    local health_cfg = cfg_tb.health or {}
    local now = now_s()

    local badge = { total = 0, crit = 0, warn = 0, info = 0 }
    for _,entry in pairs(state.active_alarms) do
      if not entry.acked then
        local age = now - (entry.last_ts or now)
        if age <= window_s then
          local sev = effective_severity(entry, now)
          badge.total = badge.total + 1
          if sev == 'CRITICAL' then badge.crit = badge.crit + 1
          elseif sev == 'WARN' then badge.warn = badge.warn + 1
          else badge.info = badge.info + 1 end
        end
      end
    end

    local health = { level = '--' }
    local timeout_s = health_cfg.timeout_s or 10
    local warn_s = health_cfg.warn_s or 20
    local crit_s = health_cfg.crit_s or 60
    local min_nodes = health_cfg.min_nodes or 1
    local total, offline, stale_max = 0, 0, 0
    for _,n in pairs(state.nodes) do
      total = total + 1
      local age = now - (n.last_seen or 0)
      stale_max = math.max(stale_max, age)
      if age > timeout_s then offline = offline + 1 end
    end
    if total < min_nodes then health = { level = 'DEG', reason = 'NoNodes' }
    elseif stale_max > crit_s then health = { level = 'FAIL', reason = 'Stale>crit' }
    elseif offline > 0 or stale_max > warn_s then health = { level = 'DEG', reason = 'Offline/Slow' }
    else health = { level = 'OK', reason = 'Healthy' } end

    local net_ok = (dispatcher.is_online and dispatcher:is_online()) or false

    return {
      clock = os.date('%H:%M:%S'),
      badge = badge,
      health = health,
      net_ok = net_ok,
    }
  end

  function state:get_overview_view()
    local kpi = { total_power = 0, rpm_sum = 0, rpm_cnt = 0, online = 0, offline = 0, fuel_min = nil, fuel_max = nil }
    local rows = {}
    local policy_rows = {}
    local priority_rows = {}
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
          priority = n.priority,
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
        local prio = r.priority and tostring(r.priority) or '-'
        local line = string.format('%-14s %-7s %-8s Prio:%-4s  P:%-6d RPM:%-5d Flow:%-5d Fuel:%-4s  %2ss  %s',
          tostring(r.hostname or '-'), tostring(r.role or '-'), tostring(r.cluster or '-'), prio, r.power, r.rpm, r.flow, r.fuel, r.age, tostring(r.state or '-'))
        table.insert(list_rows, { text = line, color = r.online and colors.white or colors.lightGray })
      end
    end

    local pol_list = {}
    for _,rec in pairs(state.policies or {}) do table.insert(pol_list, rec) end
    table.sort(pol_list, function(a,b) return (a.ts_s or 0) > (b.ts_s or 0) end)
    for _,rec in ipairs(pol_list) do
      local color = (rec.pressure == 'LOW' and colors.orange) or (rec.pressure == 'HIGH' and colors.lightBlue) or colors.white
      local line = string.format('%s ▢ %-7s %s (%s)', rec.ts or '--:--:--', rec.kind or '-', rec.pressure or '-', rec.source or '-')
      if rec.rationale then line = line .. ' ▢ ' .. tostring(rec.rationale) end
      table.insert(policy_rows, { text = line, color = color })
    end
    if #policy_rows == 0 then policy_rows = { { text = '(Keine Policy-Empfehlungen empfangen)', color = colors.gray } } end

    for _,n in pairs(state.nodes) do
      if n.priority then
        table.insert(priority_rows, { priority = n.priority, hostname = n.hostname, role = n.role, cluster = n.cluster })
      end
    end
    table.sort(priority_rows, function(a,b)
      local pa, pb = tonumber(a.priority) or -1, tonumber(b.priority) or -1
      if pa == pb then return tostring(a.hostname or '') < tostring(b.hostname or '') end
      return pa > pb
    end)
    local pr_rows = {}
    for _,p in ipairs(priority_rows) do
      local line = string.format('Prio:%-4s %-14s %-6s %-8s', tostring(p.priority), tostring(p.hostname or '-'), tostring(p.role or '-'), tostring(p.cluster or '-'))
      table.insert(pr_rows, { text = line, color = colors.white })
    end
    priority_rows = pr_rows
    if #priority_rows == 0 then priority_rows = { { text = '(Keine Prioritäten gemeldet)', color = colors.lightGray } } end

    local combined_policy_rows = { { text = '▢ Policy-Empfehlungen', color = colors.lightGray } }
    for _,r in ipairs(policy_rows) do table.insert(combined_policy_rows, r) end
    table.insert(combined_policy_rows, { text = '▢ Node-Prioritäten', color = colors.lightGray })
    for _,r in ipairs(priority_rows) do table.insert(combined_policy_rows, r) end

    return {
      filters = f,
      kpi_power_text = string.format('Power: %d RF/t', math.floor(kpi.total_power + 0.5)),
      kpi_rpm_text = string.format('\226\136\157 RPM: %d', (kpi.rpm_cnt > 0) and math.floor(kpi.rpm_sum / kpi.rpm_cnt + 0.5) or 0),
      kpi_online_text = string.format('Online: %d / %d', kpi.online, kpi.online + kpi.offline),
      kpi_fuel_text = (kpi.fuel_min and kpi.fuel_max) and string.format('Fuel%%: %d .. %d', kpi.fuel_min, kpi.fuel_max) or 'Fuel%: n/a',
      rows = list_rows,
      policy_rows = combined_policy_rows,
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

  function state:get_alarm_groups()
    local rows = {}
    local now = now_s()
    local severities = { 'CRITICAL', 'WARN', 'INFO' }
    rebuild_alarm_groups(now)
    for _,sev in ipairs(severities) do
      local per_src = {}
      for _,entry in pairs(state.alarm_groups) do
        local se = entry.severities[sev]
        if se and se.count and se.count > 0 then
          table.insert(per_src, {
            source = entry.source,
            severity = sev,
            count = se.count,
            latest_ts = se.latest_ts or 0,
            latest_ts_txt = se.latest_ts_txt or '',
            latest_message = se.latest_message or '',
            latest_id = se.latest_id or '?',
            acked = se.acked,
          })
        end
      end
      table.sort(per_src, function(a,b)
        if a.latest_ts == b.latest_ts then return tostring(a.source or '') < tostring(b.source or '') end
        return a.latest_ts > b.latest_ts
      end)
      for _,g in ipairs(per_src) do
        local color = (g.severity=='CRITICAL' and colors.red) or (g.severity=='WARN' and colors.orange) or colors.white
        if g.acked then color = colors.lightGray end
        local age = math.floor(math.max(0, now - g.latest_ts))
        local ack_tag = g.acked and ' ACK' or ''
        local line = string.format('%s [%s%s] %-8s x%-3d %-10s %s (age:%ss)', g.latest_ts_txt, g.severity, ack_tag, g.latest_id, g.count, g.source or '-', g.latest_message, age)
        table.insert(rows, { text = line, color = color })
      end
    end
    if #rows == 0 then rows = { { text = '(Keine Alarme)', color = colors.lightGray } } end
    return rows
  end

  function state:get_alarm_rows()
    local rows = {}
    local grouped = state:get_alarm_groups()
    local history = state:get_alarm_history_rows()
    table.insert(rows, { text = '▢ Grouped (Severity ▸ Source)', color = colors.lightGray })
    for _,r in ipairs(grouped) do table.insert(rows, r) end
    table.insert(rows, { text = '▢ Recent history', color = colors.lightGray })
    for _,r in ipairs(history) do table.insert(rows, r) end
    return rows
  end

  function state:get_alarm_history_rows()
    local rows = {}
    for _,a in ipairs(state.alarm_history) do
      local color = (a.severity=='CRITICAL' and colors.red) or (a.severity=='WARN' and colors.orange) or colors.white
      if a.acked then color = colors.lightGray end
      local ack_tag = a.acked and ' ACK' or ''
      local line = string.format('%s [%s%s] %s %-8s %s', a.ts, a.severity, ack_tag, a.alarm_id or a.code or '?', a.source or '-', a.message or '')
      table.insert(rows, { text = line, color = color })
    end
    if #rows == 0 then rows = { { text = '(Keine Alarme)', color = colors.lightGray } } end
    return rows
  end

  function state:get_alarm_view()
    return {
      active = state:get_alarm_groups(),
      history = state:get_alarm_history_rows(),
    }
  end

  function state:ack_alarms()
    local now = now_s()
    for _,entry in pairs(state.active_alarms) do
      entry.acked = true
      entry.ack_ts = now
    end
    for _,h in ipairs(state.alarm_history) do
      h.acked = true
      h.ack_ts = now
    end
    rebuild_alarm_groups(now)
    notify('alarm'); notify('topbar')
    persist_alarm_state('ack')
  end

  function state:subscribe(kind, cb)
    dispatcher:__subscribe(kind, cb)
  end

  return state
end

return M
