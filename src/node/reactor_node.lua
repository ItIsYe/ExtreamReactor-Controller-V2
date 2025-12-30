--========================================================
-- /xreactor/node/reactor_node.lua
-- Reactor/Turbinen Node: lokale Regelung + Node-Core Runtime
--========================================================
local PROTO    = dofile('/xreactor/shared/protocol.lua')
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

local function make_pressure_tracker(cfg)
  local pressure = { energy = 'NORMAL', fuel = 'NORMAL' }
  local priority_baseline = tonumber(cfg.priority_baseline or 100) or 100

  local function update_from_telem(msg)
    local data = type(msg.data) == 'table' and msg.data or msg
    local ep = data and data.energy_pressure
    local fp = data and data.fuel_pressure

    if ep then pressure.energy = tostring(ep):upper() end
    if fp then pressure.fuel = tostring(fp):upper() end
  end

  local function clamp(v, minv, maxv)
    if v == nil then return nil end
    if minv and v < minv then return minv end
    if maxv and v > maxv then return maxv end
    return v
  end

  local function adjust_target(target, node_priority)
    local adjusted = {}
    if type(target) == 'table' then for k,v in pairs(target) do adjusted[k] = v end end

    local priority_factor = math.max((tonumber(node_priority) or priority_baseline) / priority_baseline, 0)
    local output_factor = 1

    local function apply_energy_pressure()
      if pressure.energy == 'LOW' then
        output_factor = output_factor + 0.25 * priority_factor
      elseif pressure.energy == 'HIGH' then
        output_factor = output_factor - 0.2
      end
    end

    local function apply_fuel_pressure()
      if pressure.fuel == 'LOW' then
        output_factor = output_factor - 0.3
      elseif pressure.fuel == 'HIGH' then
        output_factor = output_factor + 0.1 * priority_factor
      end
    end

    apply_energy_pressure()
    apply_fuel_pressure()

    output_factor = math.max(output_factor, 0)

    local function copy_policy(policy)
      local p = {}
      if type(policy) == 'table' then for k,v in pairs(policy) do p[k] = v end end
      return p
    end

    if adjusted.energy_policy then
      local pol = copy_policy(adjusted.energy_policy)
      if pol.output_limit ~= nil then pol.pressure_output_limit = math.max(0, (tonumber(pol.output_limit) or 0) * output_factor) end
      if pol.throttle_pct ~= nil then pol.pressure_throttle_pct = clamp((tonumber(pol.throttle_pct) or 0) * output_factor, 0, 100) end
      if pol.max_draw ~= nil then pol.pressure_max_draw = math.max(0, (tonumber(pol.max_draw) or 0) * output_factor) end
      adjusted.energy_policy = pol
    end

    adjusted.pressure = {
      energy = pressure.energy,
      fuel = pressure.fuel,
      priority_factor = priority_factor,
      output_factor = output_factor,
    }

    return adjusted
  end

  local function attach(node)
    local dispatcher = node and node.get_dispatcher and node:get_dispatcher()
    if dispatcher and dispatcher.subscribe then
      dispatcher:subscribe(PROTO.T.TELEM, function(msg)
        update_from_telem(msg)
      end)
    end
  end

  return {
    attach = attach,
    update = update_from_telem,
    adjust = adjust_target,
  }
end

local M = {}

function M.run(opts)
  local cfg = opts or {}
  cfg.identity = cfg.identity or { role='REACTOR' }
  cfg.alarm_watchers = cfg.alarm_watchers or {}
  table.insert(cfg.alarm_watchers, make_reactor_alarm_watcher(cfg))

  local pressure = make_pressure_tracker(cfg)
  local user_control = cfg.control_loop or cfg.local_control

  cfg.control_loop = function(target, runtime, state_name, master_id, trigger, from, net_ok)
    local adjusted = pressure.adjust(target, (runtime and runtime.IDENT and runtime.IDENT.priority) or (target and target.priority))
    if type(user_control) == 'function' then
      return user_control(adjusted, runtime, state_name, master_id, trigger, from, net_ok)
    end
  end

  local node = NodeCore.create(cfg)
  pressure.attach(node)
  node:start()
  return node
end

return M
