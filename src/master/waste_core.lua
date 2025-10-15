-- waste_core.lua — Master-side waste drain & reprocessing (Phase B)
local PRO = require("protocol")

local M = {}

local last_drain_ts = {} -- per reactor_id

local function now() return os.epoch("utc") end
local function can_drain(cfg, rid)
  local last = last_drain_ts[rid] or 0
  if ((now()-last)/1000) < (cfg.waste_drain_cooldown or 120) then return false end
  return true
end

-- Decide and issue drain requests
function M.tick(cfg, telem_reactors, send_fn)
  send_fn = send_fn or PRO.broadcast
  if type(telem_reactors)~="table" then return end
  for _,R in ipairs(telem_reactors) do
    local rid = tostring(R.reactor_id or R.name or "?")
    local cap = tonumber(R.fuel_cap or 0) or 0
    local waste = tonumber(R.waste or 0) or 0
    local waste_pct = (cap>0) and (waste/cap) or nil
    if cfg.waste_auto_drain and waste_pct and waste_pct >= (cfg.waste_max_threshold or 0.80) then
      if can_drain(cfg, rid) then
        local batch = cfg.waste_drain_batch or 64
        local msg = PRO.msg_waste_drain_request(cfg.auth_token, rid, batch, cfg.waste_item_id, cfg.waste_strategy or "online")
        send_fn(msg)
        last_drain_ts[rid] = now()
      end
    end
  end
end

-- Optional: proactively request reprocessing when waste in ME exists
function M.request_reproc(cfg, amount, send_fn)
  send_fn = send_fn or PRO.broadcast
  if cfg.reproc_enabled then
    local msg = PRO.msg_reproc_request(cfg.auth_token, amount, cfg.waste_item_id, cfg.reproc_out_item_id, cfg.reproc_water_guard)
    send_fn(msg)
  end
end

function M.on_supply_msg(cfg, msg)
  -- extend for UI/logging if wanted
end

return M
