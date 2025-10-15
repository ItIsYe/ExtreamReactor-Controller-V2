-- sequencer.lua — Black-Start & start sequencing (Phase B)
local PRO = require("protocol")

local M = {}

-- Simple sequencing plan:
-- 1) small base steam_target
-- 2) bring turbines online gradually
-- 3) ramp up after short stabilization window
function M.plan_initial_setpoints(cfg)
  local base = math.floor((cfg.steam_max or 2000) * 0.25)
  return { {reactor_id="GLOBAL", reactor_on=true, steam_target=base, rpm_target=cfg.rpm_target or 1800} }
end

function M.plan_ramp_step(cfg, factor)
  local target = math.floor((cfg.steam_max or 2000) * math.max(0.25, math.min(1.0, factor or 0.5)))
  return { {reactor_id="GLOBAL", reactor_on=true, steam_target=target, rpm_target=cfg.rpm_target or 1800} }
end

-- Runs a short sequence on startup (non-blocking driver owns timing)
M.State = { stage="idle", since=0 }

function M.reset() M.State.stage="idle"; M.State.since=os.clock() end

function M.tick(cfg, send_cmd)
  local t = os.clock()
  local stage = M.State.stage
  if stage=="idle" then
    send_cmd(M.plan_initial_setpoints(cfg))
    M.State.stage="stabilize"; M.State.since=t
  elseif stage=="stabilize" then
    if (t - M.State.since) > 10 then
      send_cmd(M.plan_ramp_step(cfg, 0.5))
      M.State.stage="ramp"; M.State.since=t
    end
  elseif stage=="ramp" then
    if (t - M.State.since) > 15 then
      send_cmd(M.plan_ramp_step(cfg, 1.0))
      M.State.stage="done"; M.State.since=t
    end
  else
    -- done: no-op
  end
end

return M
