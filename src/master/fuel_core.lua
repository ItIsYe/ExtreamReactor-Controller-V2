-- fuel_core.lua — Master-side fuel management (Phase B)
local PRO = require("protocol")

local M = {}

local last_refuel_ts = {} -- per reactor_id

local function now() return os.epoch("utc") end

local function can_refuel(cfg, rid)
  local last = last_refuel_ts[rid] or 0
  if ((now()-last)/1000) < (cfg.refuel_cooldown or 60) then return false end
  return true
end

-- Decide and issue fuel requests based on telem reactors array
-- telem_reactors: [{reactor_id,fuel,fuel_cap,fuel_pct,...}, ...]
-- send_fn(to_id,msg) will be called for supply dispatch; we broadcast by default
function M.tick(cfg, telem_reactors, send_fn)
  send_fn = send_fn or PRO.broadcast
  if type(telem_reactors)~="table" then return end
  for _,R in ipairs(telem_reactors) do
    local rid = tostring(R.reactor_id or R.name or "?")
    local cap = tonumber(R.fuel_cap or 0) or 0
    local fuel = tonumber(R.fuel or 0) or 0
    local pct = R.fuel_pct
    if cap>0 and pct and cfg.fuel_auto_refill then
      if pct < (cfg.fuel_low_threshold or 0.15) and can_refuel(cfg, rid) then
        local target = math.floor((cfg.fuel_target_threshold or 0.95) * cap + 0.5)
        local need = math.max(0, target - fuel)
        if need > 0 then
          local batch = math.min(need, cfg.max_refuel_batch or 64)
          local msg = PRO.msg_fuel_request(cfg.auth_token, rid, batch, cfg.fuel_item_id, 5)
          send_fn(msg)
          last_refuel_ts[rid] = now()
        end
      end
    end
  end
end

-- handle supply responses (optional; for UI/logging extensions)
function M.on_supply_msg(cfg, msg)
  -- could track stats if desired (left minimal here)
end

return M
