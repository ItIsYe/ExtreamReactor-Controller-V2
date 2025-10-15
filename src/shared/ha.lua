-- ha.lua — High Availability leader election (dual-master)
local M = {}

-- Strategy:
-- - Each master has (id, generation). On boot, generation = timestamp-derived.
-- - Seen other master beacons with higher gen => become STANDBY.
-- - If no leader-beacon within leader_timeout => self-promote (gen += 1) and become LEADER.
-- - Only LEADER pushes setpoints / supply actions.

local S = {
  role = "LEADER",           -- "LEADER" | "STANDBY"
  leader_id = nil,
  leader_gen = 0,
  last_leader_seen = 0,
  leader_timeout = 15,       -- seconds (config override)
}

function M.init(cfg, self_id, self_gen)
  S.role = "LEADER"
  S.leader_id = self_id
  S.leader_gen = self_gen
  S.last_leader_seen = os.clock()
  if cfg and cfg.ha_leader_timeout then S.leader_timeout = cfg.ha_leader_timeout end
end

function M.on_beacon(self_id, self_gen, msg_master_id, msg_gen)
  -- If we see a higher gen than ours, accept that master as leader
  if (msg_gen or 0) > (self_gen or 0) then
    S.role = "STANDBY"
    S.leader_id = msg_master_id
    S.leader_gen = msg_gen
    S.last_leader_seen = os.clock()
  elseif (msg_master_id == S.leader_id) and (msg_gen == S.leader_gen) then
    S.last_leader_seen = os.clock()
  end
end

function M.tick(self_id, self_gen)
  local now = os.clock()
  local elapsed = now - (S.last_leader_seen or 0)
  if S.role=="STANDBY" then
    if elapsed > S.leader_timeout then
      -- self promote
      S.role = "LEADER"
      S.leader_id = self_id
      S.leader_gen = (self_gen or 0) + 1
      S.last_leader_seen = now
      return "PROMOTED", S.leader_gen
    end
  else -- LEADER
    -- if we ourselves are leader, keep last seen fresh
    S.last_leader_seen = now
  end
  return "OK", S.leader_gen
end

function M.should_act()
  return S.role == "LEADER"
end

function M.status()
  return {role=S.role, leader_id=S.leader_id, leader_gen=S.leader_gen, last_seen=S.last_leader_seen, timeout=S.leader_timeout}
end

return M
