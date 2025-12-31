--========================================================
-- /xreactor/node/node_core.lua
-- Kernmodul für Nodes: State-Machine, Heartbeat/Timeout, Masterwahl (Prio + ID)
-- Baut auf der gemeinsamen Runtime auf und stellt einheitliche Helper bereit
--========================================================
local Identity = dofile('/xreactor/shared/identity.lua')
local Runtime = dofile('/xreactor/shared/node_runtime.lua')
local StateStore = dofile('/xreactor/shared/local_state_store.lua')

local Core = {}

local function normalize_severity(raw)
  local s = tostring(raw or 'INFO'):upper()
  if s == 'CRIT' then return 'CRITICAL' end
  if s == 'WARNING' then return 'WARN' end
  if s ~= 'WARN' and s ~= 'CRITICAL' then return 'INFO' end
  return s
end

-- Erstellt einen neuen Node-Core auf Basis der gemeinsamen Runtime.
-- cfg.priority wird – falls gesetzt – in die Identity übernommen, um die Wahl-Logik
-- (Priority + Node-ID) zu steuern. Heartbeat, HELLO, Master-Timeout und Wahl laufen
-- innerhalb der Runtime automatisch.
function Core.create(cfg)
  cfg = cfg or {}

  local ident = Identity.load_identity()
  if type(cfg.identity) == 'table' then
    for k,v in pairs(cfg.identity) do ident[k] = v end
  end

  -- Priority auf Identity spiegeln, damit die Election-Logik ein konsistentes Feld nutzt
  if cfg.priority ~= nil then
    cfg.identity = cfg.identity or {}
    if cfg.identity.priority == nil then
      cfg.identity.priority = cfg.priority
    end
  end

  -- Persistenter Zustand: Targets, Limits und Modus inkl. Zeitstempel
  local last_target = {}
  local last_limits = {}
  local last_target_ts = os.epoch('utc')
  local last_mode = 'INIT'
  local last_mode_ts = os.epoch('utc')
  local alarm_history = {}
  local MAX_ALARM_HISTORY = cfg.alarm_history_limit or 100
  local priority_baseline = tonumber(cfg.priority_baseline or 100) or 100
  local node_priority = tonumber((cfg.identity or {}).priority or cfg.priority or ident.priority) or ident.priority

  -- Lokale Zielvorgaben/Policies, die auch ohne Netzwerk weiter gelten
  if type(cfg.default_target) == 'table' then
    for k,v in pairs(cfg.default_target) do last_target[k] = v end
  end
  if type(cfg.default_limits) == 'table' then
    for k,v in pairs(cfg.default_limits) do last_limits[k] = v end
  end

  local function merge_limits(data)
    if type(data) ~= 'table' then return end
    local limits = data.limits or data.limit
    if type(limits) == 'table' then
      for k,v in pairs(limits) do last_limits[k] = v end
    end
  end
  merge_limits(last_target)

  local control_fn   = cfg.control_loop or cfg.local_control
  local user_on_tick = cfg.on_tick
  local user_on_tgt  = cfg.on_target_update
  local alarm_watchers = cfg.alarm_watchers or {}
  local record_alarm
  local build_priority_target

  local runtime
  local state
  local state_store
  local persist_state

  local alarm_flags = {}
  local function trim_alarm_history()
    while #alarm_history > MAX_ALARM_HISTORY do table.remove(alarm_history) end
  end

  local function clamp(v, minv, maxv)
    if v == nil then return nil end
    if minv and v < minv then return minv end
    if maxv and v > maxv then return maxv end
    return v
  end

  local function set_priority(new_priority)
    local p = tonumber(new_priority)
    if not p then return end
    node_priority = p
    cfg.identity = cfg.identity or {}
    cfg.identity.priority = p
    ident.priority = p
    if runtime and runtime.IDENT then runtime.IDENT.priority = p end
  end

  local function shallow_copy(src)
    local dst = {}
    if type(src) == 'table' then for k,v in pairs(src) do dst[k] = v end end
    return dst
  end

  local function apply_priority_to_policy(policy, kind)
    if type(policy) ~= 'table' then return nil end

    local adjusted = shallow_copy(policy)
    adjusted.priority = node_priority

    local baseline = tonumber(policy.priority_baseline or priority_baseline) or priority_baseline
    local factor = node_priority / baseline
    adjusted.priority_factor = factor

    local function reduce_burden(v)
      return clamp((tonumber(v) or 0) / math.max(factor, 0.1), 0, 100)
    end

    local function increase_allocation(v)
      return clamp((tonumber(v) or 0) * math.max(factor, 0), 0, 1e9)
    end

    if kind == 'energy' then
      if adjusted.throttle_pct ~= nil then adjusted.effective_throttle_pct = reduce_burden(adjusted.throttle_pct) end
      if adjusted.shed_pct ~= nil then adjusted.effective_shed_pct = reduce_burden(adjusted.shed_pct) end
      if adjusted.output_limit ~= nil then adjusted.effective_output_limit = increase_allocation(adjusted.output_limit) end
      if adjusted.max_draw ~= nil then adjusted.effective_max_draw = increase_allocation(adjusted.max_draw) end
    elseif kind == 'fuel' then
      if adjusted.reserve_pct ~= nil then adjusted.effective_reserve_pct = clamp((tonumber(adjusted.reserve_pct) or 0) * factor, 0, 100) end
      if adjusted.request_rate ~= nil then adjusted.effective_request_rate = increase_allocation(adjusted.request_rate) end
      if adjusted.refill_rate ~= nil then adjusted.effective_refill_rate = increase_allocation(adjusted.refill_rate) end
    end

    return adjusted
  end

  build_priority_target = function()
    local view = shallow_copy(last_target)
    view.priority = node_priority
    if last_target.energy_policy then view.energy_policy = apply_priority_to_policy(last_target.energy_policy, 'energy') end
    if last_target.fuel_policy then view.fuel_policy = apply_priority_to_policy(last_target.fuel_policy, 'fuel') end
    return view
  end

  local function publish_alarm(severity, message, alarm_id, timestamp, details)
    local ts = timestamp or os.epoch('utc')
    if record_alarm then record_alarm(severity, message, alarm_id, ts, details) end
    return runtime:publish_alarm(severity, message, alarm_id, ts, details)
  end

  local function alarm_once(key, severity, message, details)
    if not key then return publish_alarm(severity, message, nil, nil, details) end
    if alarm_flags[key] == severity then return end
    alarm_flags[key] = severity
    return publish_alarm(severity, message, nil, nil, details)
  end

  local function clear_alarm_flag(key)
    alarm_flags[key] = nil
  end

  local function run_alarm_watchers(trigger, state_name, master_id)
    for _,watcher in ipairs(alarm_watchers) do
      if type(watcher) == 'function' then
        pcall(watcher, {
          trigger = trigger,
          last_target = build_priority_target(),
          runtime = runtime,
          state = state_name,
          master_id = master_id,
          net_ok = runtime.is_network_ok and runtime:is_network_ok(),
          priority = node_priority,
          publish_alarm = publish_alarm,
          alarm_once = alarm_once,
          clear_alarm_flag = clear_alarm_flag,
        })
      end
    end
  end

  local function merge_target(msg)
    if type(msg) ~= 'table' then return end
    local data = msg.data or msg.target or msg
    if type(data) ~= 'table' then return end
    for k,v in pairs(data) do last_target[k] = v end
    merge_limits(data)
    last_target_ts = os.epoch('utc')
    if data.priority ~= nil then set_priority(data.priority) end
    if data.node_priority ~= nil then set_priority(data.node_priority) end
  end

  local function drive_local_control(trigger, from, include_tick_handler)
    local state_name = state and state.get_state and state:get_state() or last_mode
    local master_id = runtime and runtime.get_master_id and runtime:get_master_id()
    local net_ok = runtime and runtime.is_network_ok and runtime:is_network_ok()
    local priority_target = build_priority_target()
    if type(control_fn) == 'function' then
      pcall(control_fn, priority_target, runtime, state_name, master_id, trigger, from, net_ok)
    end
    if include_tick_handler and type(user_on_tick) == 'function' then
      pcall(user_on_tick, runtime, state_name, master_id, priority_target, net_ok)
    end
    run_alarm_watchers(trigger, state_name, master_id)
  end

  -- Halte die letzte Zielvorgabe aktiv und triggere lokale Regelung auch ohne Netzwerk
  cfg.on_target_update = function(runtime, msg, from)
    merge_target(msg)
    drive_local_control('target', from, false)
    if type(user_on_tgt) == 'function' then
      pcall(user_on_tgt, runtime, msg, from, build_priority_target(), runtime.is_network_ok and runtime:is_network_ok())
    end
    persist_state('target_update')
  end

  cfg.on_tick = function(runtime, state, master_id)
    drive_local_control('tick', nil, true)
  end

  state_store = StateStore.create({ identity = ident, path = cfg.state_store_path })

  -- Persist the last targets/limits, mode timestamps, and bounded alarms whenever we touch
  -- control inputs so nodes can reboot into the same operational context offline.
  function persist_state(reason)
    if not state_store then return end
    local snapshot = {
      node_id = (runtime and runtime.IDENT and runtime.IDENT.id) or ident.id,
      role = (runtime and runtime.IDENT and runtime.IDENT.role) or ident.role,
      targets = last_target,
      limits = last_limits,
      target_timestamp = last_target_ts,
      mode = (state and state.get_state and state:get_state()) or last_mode,
      mode_timestamp = last_mode_ts,
      alarms = alarm_history,
      priority = node_priority,
      timestamp = os.epoch('utc'),
      reason = reason,
    }
    pcall(function() state_store:save(snapshot) end)
  end

  record_alarm = function(severity, message, alarm_id, timestamp, details)
    local entry = {
      severity = normalize_severity(severity),
      message = message,
      alarm_id = alarm_id or '?',
      timestamp = timestamp or os.epoch('utc'),
      source = (runtime and runtime.IDENT and runtime.IDENT.id) or ident.id,
      details = details,
    }
    table.insert(alarm_history, 1, entry)
    trim_alarm_history()
    persist_state('alarm_emit')
    return entry
  end

  local function log_persist_warning(reason)
    if not reason then return end
    print(string.format('[node_core] persisted state invalid (%s); using defaults', tostring(reason)))
  end

  -- Attempt to restore a prior snapshot; fall back to defaults on corrupt or mismatched data.
  local persisted, load_err = state_store and state_store:load()
  if load_err then log_persist_warning(load_err) end
  if type(persisted) == 'table' then
    if persisted.targets ~= nil and type(persisted.targets) ~= 'table' then
      log_persist_warning('targets_not_table')
    else
      merge_target({ data = persisted.targets })
    end
    if persisted.limits ~= nil and type(persisted.limits) ~= 'table' then
      log_persist_warning('limits_not_table')
    else
      merge_limits({ limits = persisted.limits })
    end
    if persisted.target_timestamp ~= nil then
      local ts = tonumber(persisted.target_timestamp)
      if ts then last_target_ts = ts else log_persist_warning('target_ts_invalid') end
    end
    if persisted.mode ~= nil then
      if type(persisted.mode) == 'string' then last_mode = persisted.mode else log_persist_warning('mode_invalid') end
    end
    if persisted.mode_timestamp ~= nil then
      local ts = tonumber(persisted.mode_timestamp)
      if ts then last_mode_ts = ts else log_persist_warning('mode_ts_invalid') end
    end
    if persisted.alarms ~= nil then
      if type(persisted.alarms) == 'table' then
        alarm_history = persisted.alarms
      else
        log_persist_warning('alarms_not_table')
      end
    end
    if persisted.priority ~= nil then
      if tonumber(persisted.priority) then set_priority(persisted.priority) else log_persist_warning('priority_invalid') end
    end
  elseif persisted ~= nil then
    log_persist_warning('not_a_table')
  end
  trim_alarm_history()

  -- Replay saved alarms to the dispatcher so operators regain visibility after restarts
  -- without re-triggering control logic.
  local function replay_persisted_alarms()
    if not runtime then return end
    for i = #alarm_history, 1, -1 do
      local a = alarm_history[i]
      if type(a) == 'table' then
        local ts = a.timestamp or a.ts or os.epoch('utc')
        pcall(function()
          runtime:publish_alarm(a.severity, a.message, a.alarm_id, ts, { restored = true, source = a.source or ident.id })
        end)
      end
    end
  end

  cfg.initial_state = cfg.initial_state or last_mode

  local user_on_state_change = cfg.on_state_change
  cfg.on_state_change = function(runtime_self, old, new, reason)
    last_mode = new or last_mode
    last_mode_ts = os.epoch('utc')
    if type(user_on_state_change) == 'function' then
      pcall(user_on_state_change, runtime_self, old, new, reason)
    end
    persist_state('mode_change')
  end

  runtime = Runtime.create(cfg)
  state   = runtime:get_state_machine()
  last_mode = state:get_state() or last_mode
  replay_persisted_alarms()
  drive_local_control('startup_restore', nil, true)
  persist_state('startup')

  local self = {
    runtime = runtime,
    state   = state,
  }

  function self:get_state()
    return state:get_state()
  end

  function self:get_master_id()
    return runtime:get_master_id()
  end

  function self:get_dispatcher()
    if runtime.get_dispatcher then return runtime:get_dispatcher() end
  end

  function self:is_master_candidate()
    return runtime:is_master_candidate()
  end

  function self:publish_telem(data_tbl)
    return runtime:publish_telem(data_tbl)
  end

  function self:publish_alarm(severity, message, alarm_id, timestamp, details)
    return runtime:publish_alarm(severity, message, alarm_id, timestamp, details)
  end

  -- Liefert die letzte bekannte Zielvorgabe/Policy, bleibt aktiv bis überschrieben
  function self:get_last_target()
    return last_target
  end

  function self:get_priority()
    return node_priority
  end

  -- Startet Dispatcher + Eventloop (Heartbeat/HELLO/Timeout/Wahl inklusive)
  function self:start()
    return runtime:start()
  end

  function self:start_event_loop()
    if runtime.run_event_loop then return runtime:run_event_loop() end
  end

  function self:stop()
    if runtime.stop then runtime:stop() end
  end

  return self
end

return Core
