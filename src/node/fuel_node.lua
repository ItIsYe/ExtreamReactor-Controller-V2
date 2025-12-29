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

local function make_fuel_alarm_watcher(cfg)
  local thresholds = merge_thresholds({
    buffer_warn_pct = 30,
    buffer_crit_pct = 10,
    jammed = true,
  }, cfg.alarm_thresholds)

  local function read_metrics()
    if type(cfg.read_fuel_metrics) == 'function' then return cfg.read_fuel_metrics() end
    if type(cfg.read_metrics) == 'function' then return cfg.read_metrics('fuel') or cfg.read_metrics() end
    return nil
  end

  local function pct_value(v)
    local n = tonumber(v)
    if not n then return nil end
    if n <= 1 then return n * 100 end
    return n
  end

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

local M = {}

function M.run(opts)
  local cfg = opts or {}
  cfg.identity = cfg.identity or { role='FUEL' }
  cfg.alarm_watchers = cfg.alarm_watchers or {}
  table.insert(cfg.alarm_watchers, make_fuel_alarm_watcher(cfg))
  local node = NodeCore.create(cfg)
  node:start()
  return node
end

return M
