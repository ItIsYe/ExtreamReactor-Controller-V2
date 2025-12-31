--========================================================
-- /xreactor/node/reprocessing_node.lua
-- Reprocessing-Node: nutzt Node-Core für Autonomie + Wahl
--========================================================
local NodeCore = dofile('/xreactor/node/node_core.lua')

local function merge_thresholds(defaults, overrides)
  if type(overrides) ~= 'table' then return defaults end
  for k,v in pairs(overrides) do defaults[k] = v end
  return defaults
end

local function make_reprocess_alarm_watcher(cfg)
  local thresholds = merge_thresholds({
    waste_warn_pct = 70,
    waste_crit_pct = 90,
    offline_severity = 'WARN',
  }, cfg.alarm_thresholds)

  local function read_metrics()
    if type(cfg.read_reprocess_metrics) == 'function' then return cfg.read_reprocess_metrics() end
    if type(cfg.read_metrics) == 'function' then return cfg.read_metrics('reprocess') or cfg.read_metrics() end
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

    local waste = pct_value(metrics.waste_buffer_pct or metrics.waste_pct or metrics.buffer_pct)
    if waste then
      if waste >= thresholds.waste_crit_pct then
        ctx.alarm_once('reproc_waste', 'CRITICAL', ('Abfallpuffer fast voll: %.1f%%'):format(waste), { metric = 'waste_buffer_pct', value = waste, threshold = thresholds.waste_crit_pct })
      elseif waste >= thresholds.waste_warn_pct then
        ctx.alarm_once('reproc_waste', 'WARN', ('Abfallpuffer hoch: %.1f%%'):format(waste), { metric = 'waste_buffer_pct', value = waste, threshold = thresholds.waste_warn_pct })
      else
        ctx.clear_alarm_flag('reproc_waste')
      end
    end

    if metrics.online ~= nil then
      if not metrics.online then
        ctx.alarm_once('reproc_offline', thresholds.offline_severity or 'WARN', 'Reprocessing offline', { metric = 'online', value = metrics.online })
      else
        ctx.clear_alarm_flag('reproc_offline')
      end
    end
  end
end

local M = {}

function M.run(opts)
  local cfg = opts or {}
  cfg.identity = cfg.identity or { role='REPROCESS' }
  cfg.alarm_watchers = cfg.alarm_watchers or {}
  table.insert(cfg.alarm_watchers, make_reprocess_alarm_watcher(cfg))
  local node = NodeCore.create(cfg)
  node:start()
  return node
end

return M
