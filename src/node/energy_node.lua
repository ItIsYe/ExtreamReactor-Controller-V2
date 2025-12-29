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

local function make_energy_alarm_watcher(cfg)
  local thresholds = merge_thresholds({
    buffer_warn_pct = 30,
    buffer_crit_pct = 10,
    input_warn = 50000,
  }, cfg.alarm_thresholds)

  local function read_metrics()
    if type(cfg.read_energy_metrics) == 'function' then return cfg.read_energy_metrics() end
    if type(cfg.read_metrics) == 'function' then return cfg.read_metrics('energy') or cfg.read_metrics() end
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

local M = {}

function M.run(opts)
  local cfg = opts or {}
  cfg.identity = cfg.identity or { role='ENERGY' }
  cfg.alarm_watchers = cfg.alarm_watchers or {}
  table.insert(cfg.alarm_watchers, make_energy_alarm_watcher(cfg))
  local node = NodeCore.create(cfg)
  node:start()
  return node
end

return M
