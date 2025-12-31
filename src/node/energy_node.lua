--========================================================
-- /xreactor/node/energy_node.lua
-- Energy-Node: nutzt Node-Core für Telemetrie + Master-Integration
--========================================================
local NodeCore = dofile('/xreactor/node/node_core.lua')

local function merge_thresholds(defaults, overrides)
  if type(overrides) ~= 'table' then return defaults end
  for k,v in pairs(overrides) do defaults[k] = v end
  return defaults
end

local function make_metrics_reader(cfg)
  return function()
    if type(cfg.read_energy_metrics) == 'function' then return cfg.read_energy_metrics() end
    if type(cfg.read_metrics) == 'function' then return cfg.read_metrics('energy') or cfg.read_metrics() end
    return nil
  end
end

local function pct_value(v)
  local n = tonumber(v)
  if not n then return nil end
  if n <= 1 then return n * 100 end
  return n
end

local function make_energy_alarm_watcher(cfg)
  local thresholds = merge_thresholds({
    buffer_warn_pct = 30,
    buffer_crit_pct = 10,
    input_warn = 50000,
  }, cfg.alarm_thresholds)

  local read_metrics = make_metrics_reader(cfg)

  return function(ctx)
    local metrics = read_metrics()
    if type(metrics) ~= 'table' then return end

    local buffer = pct_value(metrics.buffer_pct or metrics.buffer_fill)
    if buffer then
      if buffer <= thresholds.buffer_crit_pct then
        ctx.alarm_once('energy_buffer', 'CRITICAL', ('Energiespeicher fast leer: %.1f%%'):format(buffer), { metric = 'buffer_pct', value = buffer, threshold = thresholds.buffer_crit_pct })
      elseif buffer <= thresholds.buffer_warn_pct then
        ctx.alarm_once('energy_buffer', 'WARN', ('Energiespeicher niedrig: %.1f%%'):format(buffer), { metric = 'buffer_pct', value = buffer, threshold = thresholds.buffer_warn_pct })
      else
        ctx.clear_alarm_flag('energy_buffer')
      end
    end

    local input = tonumber(metrics.input_mrf or metrics.input or metrics.generation)
    if input and input <= thresholds.input_warn then
      ctx.alarm_once('energy_input', 'WARN', ('Leistungsaufnahme niedrig: %d'):format(input), { metric = 'input', value = input, threshold = thresholds.input_warn })
    elseif input then
      ctx.clear_alarm_flag('energy_input')
    end
  end
end

local function make_energy_pressure_policy(cfg)
  local thresholds = merge_thresholds({
    low_pct = 15,
    high_pct = 90,
    trend_drop_pct = 5,
    trend_rise_pct = 3,
  }, cfg.pressure_thresholds)

  local read_metrics = make_metrics_reader(cfg)
  local last_pressure
  local last_trend
  local last_buffer
  local pending_pressure
  local pending_trend
  local pending_since
  local stable_window = tonumber(cfg.pressure_stable_sec or 4) or 4

  local function classify_trend(buffer_pct)
    if not last_buffer or not buffer_pct then return 'steady', 0 end
    local delta = buffer_pct - last_buffer
    if delta <= -thresholds.trend_drop_pct then return 'falling', delta end
    if delta >= thresholds.trend_rise_pct then return 'rising', delta end
    return 'steady', delta
  end

  local function classify_pressure(buffer_pct, trend)
    if not buffer_pct then return nil, 'Keine Energiedaten verfügbar' end
    if buffer_pct <= thresholds.low_pct then
      return 'LOW', ('Energiespeicher kritisch niedrig: %.1f%% (%s)'):format(buffer_pct, trend)
    elseif buffer_pct >= thresholds.high_pct then
      return 'HIGH', ('Energiespeicher fast voll: %.1f%% (%s)'):format(buffer_pct, trend)
    end

    if trend == 'falling' and buffer_pct <= (thresholds.low_pct + thresholds.trend_drop_pct) then
      return 'LOW', ('Energiespeicher fällt schnell: %.1f%%'):format(buffer_pct)
    end

    return 'NORMAL', ('Energiespeicher im Normalbereich: %.1f%% (%s)'):format(buffer_pct, trend)
  end

  return function(runtime)
    local metrics = read_metrics()
    if type(metrics) ~= 'table' then return end

    local buffer = pct_value(metrics.buffer_pct or metrics.buffer_fill)
    local trend, delta = classify_trend(buffer)
    local pressure, rationale = classify_pressure(buffer, trend)
    last_buffer = buffer or last_buffer

    if not pressure then return end
    local now = os.clock()

    if pressure == last_pressure and trend == last_trend then
      pending_pressure, pending_trend, pending_since = nil, nil, nil
      return
    end

    if pressure ~= 'LOW' then
      if pending_pressure ~= pressure or pending_trend ~= trend then
        pending_pressure, pending_trend, pending_since = pressure, trend, now
        return
      end

      if pending_since and (now - pending_since) < stable_window then
        return
      end
    end

    last_pressure = pressure
    last_trend = trend
    pending_pressure, pending_trend, pending_since = nil, nil, nil

    local ts = os.epoch('utc')
    local source_id = runtime and runtime.IDENT and runtime.IDENT.id or os.getComputerID()

    local recommendation = {
      type = 'energy_pressure',
      pressure = pressure,
      buffer_pct = buffer,
      trend = trend,
      delta = delta,
      rationale = rationale,
      intent = 'recommendation',
      timestamp = ts,
      source_node_id = source_id,
      suggested_policy = {
        kind = 'energy',
        pressure = pressure,
        trend = trend,
      },
    }

    if runtime and runtime.publish_telem then
      runtime:publish_telem({
        energy_pressure = pressure,
        energy_pressure_trend = trend,
        policy_recommendation = recommendation,
      })
    end
  end
end

local M = {}

function M.run(opts)
  local cfg = opts or {}
  cfg.identity = cfg.identity or { role='ENERGY' }
  cfg.alarm_watchers = cfg.alarm_watchers or {}
  table.insert(cfg.alarm_watchers, make_energy_alarm_watcher(cfg))

  local pressure_policy = make_energy_pressure_policy(cfg)
  local user_on_tick = cfg.on_tick
  cfg.on_tick = function(runtime, state_name, master_id, target, net_ok)
    if type(user_on_tick) == 'function' then
      pcall(user_on_tick, runtime, state_name, master_id, target, net_ok)
    end
    if pressure_policy then pcall(pressure_policy, runtime) end
  end

  local node = NodeCore.create(cfg)
  node:start()
  return node
end

return M
