--========================================================
-- /xreactor/node/reactor_node.lua
-- Reactor/Turbinen Node: lokale Regelung + Node-Core Runtime
--========================================================
local NodeCore = dofile('/xreactor/node/node_core.lua')

local function merge_thresholds(defaults, overrides)
  if type(overrides) ~= 'table' then return defaults end
  for k,v in pairs(overrides) do defaults[k] = v end
  return defaults
end

local function make_reactor_alarm_watcher(cfg)
  local thresholds = merge_thresholds({
    temp_warn = 950,
    temp_crit = 1100,
    flow_warn = 400,
    flow_crit = 200,
    rpm_warn = 500,
    rpm_crit = 300,
    fuel_warn = 25,
    fuel_crit = 10,
  }, cfg.alarm_thresholds)

  local function read_metrics()
    if type(cfg.read_reactor_metrics) == 'function' then return cfg.read_reactor_metrics() end
    if type(cfg.read_metrics) == 'function' then return cfg.read_metrics('reactor') or cfg.read_metrics() end
    return nil
  end

  local function number_value(x) local n = tonumber(x); if n then return n end end

  return function(ctx)
    local metrics = read_metrics()
    if type(metrics) ~= 'table' then return end

    local temp = number_value(metrics.temperature or metrics.temp)
    if temp then
      if temp >= thresholds.temp_crit then
        ctx.alarm_once('reactor_temp', 'CRITICAL', ('Reaktor-Temperatur hoch: %.1f'):format(temp), { metric = 'temperature', value = temp, threshold = thresholds.temp_crit })
      elseif temp >= thresholds.temp_warn then
        ctx.alarm_once('reactor_temp', 'WARN', ('Reaktor-Temperatur erhöht: %.1f'):format(temp), { metric = 'temperature', value = temp, threshold = thresholds.temp_warn })
      else
        ctx.clear_alarm_flag('reactor_temp')
      end
    end

    local flow = number_value(metrics.coolant_flow or metrics.flow)
    if flow then
      if flow <= thresholds.flow_crit then
        ctx.alarm_once('reactor_flow', 'CRITICAL', ('Kühlmittelfluss niedrig: %.1f'):format(flow), { metric = 'flow', value = flow, threshold = thresholds.flow_crit })
      elseif flow <= thresholds.flow_warn then
        ctx.alarm_once('reactor_flow', 'WARN', ('Kühlmittelfluss abfallend: %.1f'):format(flow), { metric = 'flow', value = flow, threshold = thresholds.flow_warn })
      else
        ctx.clear_alarm_flag('reactor_flow')
      end
    end

    local rpm = number_value(metrics.rpm)
    if rpm then
      if rpm <= thresholds.rpm_crit then
        ctx.alarm_once('reactor_rpm', 'CRITICAL', ('Turbinen-Drehzahl sehr niedrig: %d'):format(rpm), { metric = 'rpm', value = rpm, threshold = thresholds.rpm_crit })
      elseif rpm <= thresholds.rpm_warn then
        ctx.alarm_once('reactor_rpm', 'WARN', ('Turbinen-Drehzahl niedrig: %d'):format(rpm), { metric = 'rpm', value = rpm, threshold = thresholds.rpm_warn })
      else
        ctx.clear_alarm_flag('reactor_rpm')
      end
    end

    local fuel = number_value(metrics.fuel_pct or metrics.fuel)
    if fuel then
      if fuel <= thresholds.fuel_crit then
        ctx.alarm_once('reactor_fuel', 'CRITICAL', ('Brennstoff sehr niedrig: %.1f%%'):format(fuel), { metric = 'fuel_pct', value = fuel, threshold = thresholds.fuel_crit })
      elseif fuel <= thresholds.fuel_warn then
        ctx.alarm_once('reactor_fuel', 'WARN', ('Brennstoff niedrig: %.1f%%'):format(fuel), { metric = 'fuel_pct', value = fuel, threshold = thresholds.fuel_warn })
      else
        ctx.clear_alarm_flag('reactor_fuel')
      end
    end
  end
end

local M = {}

function M.run(opts)
  local cfg = opts or {}
  cfg.identity = cfg.identity or { role='REACTOR' }
  cfg.alarm_watchers = cfg.alarm_watchers or {}
  table.insert(cfg.alarm_watchers, make_reactor_alarm_watcher(cfg))
  local node = NodeCore.create(cfg)
  node:start()
  return node
end

return M
