-- devices.lua — discovery + safe getters for reactors/turbines/battery/matrix
local M = {}

local state = { reactors={}, turbines={}, battery=nil, matrices={} }

local function has(t, fn) return type(t)=="table" and type(t[fn])=="function" end
local function safe(obj, fn, ...)
  if not has(obj, fn) then return nil end
  local ok, res = pcall(obj[fn], ...)
  if ok then return res end
  return nil
end

local function lower_type(name)
  local tp = peripheral.getType(name) or ""
  return string.lower(tp)
end

function M.discover()
  state = { reactors={}, turbines={}, battery=nil, matrices={} }
  for _,p in ipairs(peripheral.getNames()) do
    local lt = lower_type(p)

    if lt:find("reactor") then
      local r = peripheral.wrap(p)
      if r and (has(r,"getActive") or has(r,"getFuelAmount") or has(r,"getEnergyStored")) then
        table.insert(state.reactors, {name=p, dev=r})
      end

    elseif lt:find("turbine") then
      local t = peripheral.wrap(p)
      if t and (has(t,"getRotorSpeed") or has(t,"getEnergyProducedLastTick")) then
        table.insert(state.turbines, {name=p, dev=t})
      end

    elseif lt:find("induction") or lt:find("matrix") then
      local m = peripheral.wrap(p)
      if m and (has(m,"getEnergy") or has(m,"getEnergyStored")) then
        table.insert(state.matrices, {name=p, dev=m})
      end

    else
      -- generic battery/energy cell
      local b = peripheral.wrap(p)
      if b and (has(b,"getEnergyStored") or has(b,"getEnergy") or has(b,"getStored")) then
        state.battery = state.battery or {name=p, dev=b}
      end
    end
  end
  return state
end

-- battery/matrix SoC (best effort)
function M.read_soc()
  -- prefer matrix if present
  if state.matrices[1] then
    local m = state.matrices[1].dev
    local stored = safe(m,"getEnergy") or safe(m,"getEnergyStored")
    local cap    = safe(m,"getMaxEnergy") or safe(m,"getEnergyCapacity")
    if type(stored)=="number" and type(cap)=="number" and cap>0 then return math.max(0, math.min(1, stored/cap)) end
  end
  if state.battery then
    local b = state.battery.dev
    local s = safe(b,"getEnergyStored") or safe(b,"getEnergy") or safe(b,"getStored")
    local c = safe(b,"getEnergyCapacity") or safe(b,"getMaxEnergyStored") or safe(b,"getCapacity")
    if type(s)=="number" and type(c)=="number" and c>0 then return math.max(0, math.min(1, s/c)) end
  end
  return nil
end

-- aggregate turbines
function M.read_turbines(turbine_list)
  local list = turbine_list or state.turbines
  local rpm_sum, rpm_cnt, steam_sum = 0, 0, 0
  for _,t in ipairs(list) do
    local d = t.dev
    local rpm = safe(d,"getRotorSpeed")
    if type(rpm)=="number" then rpm_sum = rpm_sum + rpm; rpm_cnt = rpm_cnt + 1 end
    local flow = safe(d,"getFluidFlowRate") or safe(d,"getSteamFlowRate") or safe(d,"getFlowRate")
    if type(flow)=="number" then steam_sum = steam_sum + flow end
  end
  return (rpm_cnt>0 and (rpm_sum/rpm_cnt) or 0), steam_sum, #list
end

-- read reactor core info (first param may be a reactor dev)
local function read_reactor_core(r)
  if not r then return nil end
  return {
    active = (safe(r,"getActive")==true),
    temp   = safe(r,"getCasingTemperature") or safe(r,"getTemperature"),
    fuel   = safe(r,"getFuelAmount") or safe(r,"getFuel") or 0,
    fuel_cap = safe(r,"getFuelAmountMax") or safe(r,"getFuelCapacity") or 0,
    waste  = safe(r,"getWasteAmount") or 0,
    burn   = safe(r,"getBurnedFuelLastTick") or 0,
  }
end

function M.read_reactors()
  local out = {}
  for _,R in ipairs(state.reactors) do
    local core = read_reactor_core(R.dev) or {}
    table.insert(out, {
      name=R.name,
      active=core.active, temp=core.temp, fuel=core.fuel, fuel_cap=core.fuel_cap,
      waste=core.waste, burn_rate=core.burn, fuel_pct=(core.fuel_cap and core.fuel_cap>0) and (core.fuel/core.fuel_cap) or nil,
    })
  end
  return out
end

function M.get_state() return state end

-- basic control primitives (best effort)
function M.reactor_set_active(rdev, on)
  if rdev and has(rdev,"setActive") then pcall(rdev.setActive, on) end
end

function M.turbine_set_inductor(tdev, engaged)
  if tdev and has(tdev,"setInductorEngaged") then pcall(tdev.setInductorEngaged, engaged) end
end

return M
