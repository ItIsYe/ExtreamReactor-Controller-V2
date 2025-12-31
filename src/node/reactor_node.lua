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
  local output_factor = 1
  local ramp_up_rate = tonumber(cfg.pressure_ramp_up_per_sec or 0.25) or 0.25
  local ramp_down_rate = tonumber(cfg.pressure_ramp_down_per_sec or 0.35) or 0.35
  local target_blend = tonumber(cfg.pressure_target_blend or 0.35) or 0.35
  local deadband = tonumber(cfg.pressure_deadband or 0.02) or 0.02
  local min_factor = tonumber(cfg.pressure_min_output_factor or 0.2) or 0.2
  local max_factor = tonumber(cfg.pressure_max_output_factor or 1.5) or 1.5
  local priority_relief_scale = tonumber(cfg.priority_relief_scale or 1.35) or 1.35
  local stable_window = tonumber(cfg.pressure_stable_sec or 3) or 3
  local last_desired = output_factor
  local last_update_time = os.clock()
  local pressure_weight = {
    energy_low    = tonumber(cfg.energy_pressure_raise or 0.3) or 0.3,
    energy_high   = tonumber(cfg.energy_pressure_relief or 0.2) or 0.2,
    fuel_low      = tonumber(cfg.fuel_pressure_conserve or 0.25) or 0.25,
    fuel_high     = tonumber(cfg.fuel_pressure_opportunity or 0.1) or 0.1,
  }

  local pending = {
    energy = nil,
    fuel = nil,
  }

  local function stabilize(kind, new_pressure, new_trend)
    if not new_pressure then return end

    local now = os.clock()
    local current = pressure[kind]

    if new_pressure == current then
      if new_trend then pressure[kind .. '_trend'] = new_trend end
      pending[kind] = nil
      return
    end

    if new_pressure == 'LOW' then
      pressure[kind] = new_pressure
      if new_trend then pressure[kind .. '_trend'] = new_trend end
      pending[kind] = nil
      return
    end

    local candidate = pending[kind]
    if not candidate or candidate.value ~= new_pressure or candidate.trend ~= new_trend then
      pending[kind] = { value = new_pressure, trend = new_trend, since = now }
      return
    end

    if (now - candidate.since) >= stable_window then
      pressure[kind] = new_pressure
      if new_trend then pressure[kind .. '_trend'] = new_trend end
      pending[kind] = nil
    end
  end

  local function update_from_telem(msg)
    local data = type(msg.data) == 'table' and msg.data or msg
    local ep = data and data.energy_pressure
    local fp = data and data.fuel_pressure
    local rec = data and data.policy_recommendation
    local suggested = rec and rec.suggested_policy

    local ep_trend = data and data.energy_pressure_trend and tostring(data.energy_pressure_trend):lower()
    local fp_trend = data and data.fuel_pressure_trend and tostring(data.fuel_pressure_trend):lower()

    if ep then stabilize('energy', tostring(ep):upper(), ep_trend) end
    if fp then stabilize('fuel', tostring(fp):upper(), fp_trend) end

    if type(suggested) == 'table' then
      if suggested.kind == 'energy' then
        pressure.energy_policy = suggested
      elseif suggested.kind == 'fuel' then
        pressure.fuel_policy = suggested
      end
    end
  end

  local function clamp(v, minv, maxv)
    if v == nil then return nil end
    if minv and v < minv then return minv end
    if maxv and v > maxv then return maxv end
    return v
  end

  local function ramp_towards(target_value)
    if output_factor == nil then output_factor = target_value end

    local now = os.clock()
    local dt = math.max(now - (last_update_time or now), 0)
    last_update_time = now

    local delta = target_value - output_factor
    if math.abs(delta) <= deadband then return output_factor end

    local rate = delta > 0 and ramp_up_rate or ramp_down_rate
    local max_delta = rate * dt

    if math.abs(delta) <= max_delta then return target_value end
    if delta > 0 then
      return output_factor + max_delta
    else
      return output_factor - max_delta
    end
  end

  local function adjust_target(target, node_priority)
    local adjusted = {}
    if type(target) == 'table' then for k,v in pairs(target) do adjusted[k] = v end end

    local priority_factor = math.max((tonumber(node_priority) or priority_baseline) / priority_baseline, 0)
    -- Lower priority (<1.0) should shed load earlier/more aggressively than higher priority (>1.0)
    local relief_scale = (1 / math.max(priority_factor, 0.1)) * priority_relief_scale
    local desired_factor = 1

    local function apply_energy_pressure()
      if pressure.energy == 'LOW' then
        desired_factor = desired_factor + pressure_weight.energy_low * priority_factor
      elseif pressure.energy == 'HIGH' then
        desired_factor = desired_factor - pressure_weight.energy_high * relief_scale
      end
    end

    local function apply_fuel_pressure()
      if pressure.fuel == 'LOW' then
        desired_factor = desired_factor - pressure_weight.fuel_low * relief_scale
      elseif pressure.fuel == 'HIGH' then
        desired_factor = desired_factor + pressure_weight.fuel_high * priority_factor
      end
    end

    apply_energy_pressure()
    apply_fuel_pressure()

    desired_factor = clamp(desired_factor, min_factor, max_factor)

    -- dampen oscillation from noisy pressure changes before ramping
    if last_desired then
      desired_factor = last_desired + (desired_factor - last_desired) * target_blend
    end
    last_desired = desired_factor

    output_factor = ramp_towards(desired_factor)

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
      desired_output_factor = desired_factor,
      output_factor = output_factor,
      energy_trend = pressure.energy_trend,
      fuel_trend = pressure.fuel_trend,
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
