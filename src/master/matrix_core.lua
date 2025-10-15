-- matrix_core.lua — derive a global SoC from TELEM or local peripherals
-- Note: Master hat idR keine wired-Matrix. Wir aggregieren aus Node-TELEM.soc.
local M = {}

function M.read_soc_from_nodes(nodes)
  -- sammle alle gültigen n.telem.soc (falls vorhanden)
  local sum, cnt = 0, 0
  for _,n in pairs(nodes) do
    local t = n.telem
    if t and type(t.soc)=="number" then sum = sum + t.soc; cnt = cnt + 1 end
  end
  if cnt>0 then return math.max(0, math.min(1, sum/cnt)) end
  return nil
end

-- einfacher EMA-Trend für SoC
local Trend = {soc=nil, vel=0}

-- call each cycle (≈ setpoint_interval)
function M.update_trend(cfg, soc)
  if type(soc)~="number" then return Trend end
  if Trend.soc == nil then Trend.soc = soc; Trend.vel = 0; return Trend end
  local alpha = math.max(0, math.min(1, cfg.adapt_smooth or 0.6))
  local ds = soc - Trend.soc
  Trend.soc = Trend.soc + alpha * ds
  Trend.vel = (1-alpha) * Trend.vel + alpha * ds -- „Geschwindigkeit“ (Δsoc/step)
  return Trend
end

-- factor ∈ [adapt_min_factor, adapt_max_factor]
function M.adapt_factor(cfg)
  if not (cfg.adapt_enabled ~= false) then return 1.0 end
  local k   = cfg.adapt_k or 0.6
  local minf= cfg.adapt_min_factor or 0.25
  local maxf= cfg.adapt_max_factor or 1.0
  -- negative vel ⇒ SoC fällt ⇒ mehr Leistung ⇒ Faktor ↑
  -- positive vel ⇒ SoC steigt ⇒ weniger Leistung ⇒ Faktor ↓
  local v = Trend.vel or 0
  local f = 1.0 - (k * v * 5)   -- heuristik: scale vel auf ~sek-gefühl
  if v < 0 then f = 1.0 + (k * (-v) * 5) end
  if f < minf then f=minf elseif f>maxf then f=maxf end
  return f
end

-- Thermische Korrektur (pro Reaktor-Datensatz)
-- returns multiplicative factor applied on steam_target
function M.thermal_correction(cfg, reactor_temp)
  if not (cfg.therm_enabled ~= false) then return 1.0 end
  if type(reactor_temp)~="number" then return 1.0 end
  local t0 = cfg.therm_target or 860
  local band = cfg.therm_band or 40
  local gain = cfg.therm_gain or 0.15
  local lo, hi = t0-band, t0+band
  if reactor_temp > hi then
    local d = reactor_temp - hi
    -- zu heiß → etwas Steam runter
    return math.max(0.5, 1.0 - gain * (d / band))
  elseif reactor_temp < lo then
    local d = lo - reactor_temp
    -- zu kalt → etwas Steam hoch
    return math.min(1.5, 1.0 + gain * (d / band))
  end
  return 1.0
end

return M
