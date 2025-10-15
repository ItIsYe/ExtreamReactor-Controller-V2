-- policy.lua — hysteresis + simple targets (Phase A core)
local M = {}

local DEF = {
  soc_low=0.30, soc_high=0.85, hysteresis=0.03,
  rpm_target=1800, steam_max=2000,
}

local function pick(cfg,k) return (cfg and cfg[k]~=nil) and cfg[k] or DEF[k] end

-- decide global → returns a per-reactor directive template
-- soc: 0..1 or nil ; prev: {reactor_on=?, turbines_on=?}
function M.decide(soc, prev, cfg)
  local low  = pick(cfg,"soc_low")
  local high = pick(cfg,"soc_high")
  local hyst = pick(cfg,"hysteresis")
  local rpm  = pick(cfg,"rpm_target")
  local smax = pick(cfg,"steam_max")

  if soc == nil then
    return { reactor_on=true, turbines_on=true, target_rpm=rpm, steam_target=smax, reason="soc=nil → safe ON" }
  end

  local r_on = prev and prev.reactor_on or false
  local t_on = prev and prev.turbines_on or false

  if soc <= (low - hyst) then
    r_on, t_on = true, true
  elseif soc >= (high + hyst) then
    r_on, t_on = false, false
  end

  return { reactor_on=r_on, turbines_on=t_on, target_rpm=rpm, steam_target=smax,
           reason=("soc=%.2f low=%.2f high=%.2f hyst=%.2f"):format(soc,low,high,hyst) }
end

return M
