--========================================================
-- /xreactor/node/fuel_node.lua
-- Fuel-Node: nutzt Node-Core für Autonomie + Master-Wahl
--========================================================
local NodeCore = dofile('/xreactor/node/node_core.lua')

local function merge_thresholds(defaults, overrides)
  if type(overrides) ~= 'table' then return defaults end
  for k,v in pairs(overrides) do defaults[k] = v end
  return defaults
end

local function make_metrics_reader(cfg)
  return function()
    if type(cfg.read_fuel_metrics) == 'function' then return cfg.read_fuel_metrics() end
    if type(cfg.read_metrics) == 'function' then return cfg.read_metrics('fuel') or cfg.read_metrics() end
    return nil
  end
end

local function pct_value(v)
  local n = tonumber(v)
  if not n then return nil end
  if n <= 1 then return n * 100 end
  return n
end

local function make_fuel_alarm_watcher(cfg)
  local thresholds = merge_thresholds({
    buffer_warn_pct = 30,
    buffer_crit_pct = 10,
    jammed = true,
  }, cfg.alarm_thresholds)

  local read_metrics = make_metrics_reader(cfg)

  return function(ctx)
    local metrics = read_metrics()
    if type(metrics) ~= 'table' then return end

    local buffer = pct_value(metrics.fuel_buffer_pct or metrics.fuel_pct or metrics.buffer_pct)
    if buffer then
      if buffer <= thresholds.buffer_crit_pct then
        ctx.alarm_once('fuel_buffer', 'CRITICAL', ('Brennstoffpuffer fast leer: %.1f%%'):format(buffer), { metric = 'fuel_buffer_pct', value = buffer, threshold = thresholds.buffer_crit_pct })
      elseif buffer <= thresholds.buffer_warn_pct then
        ctx.alarm_once('fuel_buffer', 'WARN', ('Brennstoffpuffer niedrig: %.1f%%'):format(buffer), { metric = 'fuel_buffer_pct', value = buffer, threshold = thresholds.buffer_warn_pct })
      else
        ctx.clear_alarm_flag('fuel_buffer')
      end
    end

    if thresholds.jammed and metrics.jammed ~= nil then
      if metrics.jammed then
        ctx.alarm_once('fuel_jammed', 'CRITICAL', 'Brennstoffzufuhr blockiert', { metric = 'jammed', value = metrics.jammed })
      else
        ctx.clear_alarm_flag('fuel_jammed')
      end
    end
  end
end

local function make_fuel_pressure_policy(cfg)
  local thresholds = merge_thresholds({
    low_pct = 20,
    high_pct = 90,
    trend_drop_pct = 5,
    trend_rise_pct = 3,
  }, cfg.pressure_thresholds)

  local read_metrics = make_metrics_reader(cfg)
  local last_pressure
  local last_trend
  local last_level
  local pending_pressure
  local pending_trend
  local pending_since
  local stable_window = tonumber(cfg.pressure_stable_sec or 4) or 4

  local function classify_trend(level_pct)
    if not last_level or not level_pct then return 'steady', 0 end
    local delta = level_pct - last_level
    if delta <= -thresholds.trend_drop_pct then return 'falling', delta end
    if delta >= thresholds.trend_rise_pct then return 'rising', delta end
    return 'steady', delta
  end

  local function classify_pressure(level_pct, trend)
    if not level_pct then return nil, 'Keine Brennstoffdaten verfügbar' end
    if level_pct <= thresholds.low_pct then
      return 'LOW', ('Brennstoff niedrig: %.1f%% (%s)'):format(level_pct, trend)
    elseif level_pct >= thresholds.high_pct then
      return 'HIGH', ('Brennstoff fast voll: %.1f%% (%s)'):format(level_pct, trend)
    end

    if trend == 'falling' and level_pct <= (thresholds.low_pct + thresholds.trend_drop_pct) then
      return 'LOW', ('Brennstoff fällt schnell: %.1f%%'):format(level_pct)
    end

    return 'NORMAL', ('Brennstoff im Normalbereich: %.1f%% (%s)'):format(level_pct, trend)
  end

  return function(runtime)
    local metrics = read_metrics()
    if type(metrics) ~= 'table' then return end

    local buffer = pct_value(metrics.fuel_buffer_pct or metrics.fuel_pct or metrics.buffer_pct)
    local reserve = pct_value(metrics.fuel_reserve_pct or metrics.reserve_pct)
    local level = buffer or reserve
    if level and reserve then level = math.min(level, reserve) end

    local trend, delta = classify_trend(level)
    local pressure, rationale = classify_pressure(level, trend)
    last_level = level or last_level

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
      type = 'fuel_pressure',
      pressure = pressure,
      buffer_pct = buffer,
      reserve_pct = reserve,
      level_pct = level,
      trend = trend,
      delta = delta,
      rationale = rationale,
      intent = 'recommendation',
      timestamp = ts,
      source_node_id = source_id,
      suggested_policy = {
        kind = 'fuel',
        pressure = pressure,
        trend = trend,
      },
    }

    if runtime and runtime.publish_telem then
      runtime:publish_telem({
        fuel_pressure = pressure,
        fuel_pressure_trend = trend,
        policy_recommendation = recommendation,
      })
    end
  end
end

local M = {}

function M.run(opts)
  local cfg = opts or {}
  cfg.identity = cfg.identity or { role='FUEL' }
  cfg.alarm_watchers = cfg.alarm_watchers or {}
  table.insert(cfg.alarm_watchers, make_fuel_alarm_watcher(cfg))
  local pressure_policy = make_fuel_pressure_policy(cfg)

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
