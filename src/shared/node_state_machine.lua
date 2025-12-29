--========================================================
-- /xreactor/shared/node_state_machine.lua
-- Vereinheitlichte Node-Statemachine (INIT/AUTO/LOST_MASTER/EMERGENCY/MASTER)
--========================================================
local SM = {}

local VALID = {
  INIT=true, AUTO=true, LOST_MASTER=true, EMERGENCY=true, MASTER=true,
}

local function now_s() return os.epoch("utc")/1000 end

function SM.create(opts)
  local cfg = opts or {}
  local self = {
    state = "INIT",
    master_timeout_s = tonumber(cfg.master_timeout_s or 10) or 10,
    on_change = cfg.on_change,
    _last_master = now_s(),
  }

  local function change(new_state, reason)
    new_state = tostring(new_state or ""):upper()
    if (not VALID[new_state]) or new_state==self.state then return end
    local prev = self.state
    self.state = new_state
    if type(self.on_change)=="function" then
      pcall(self.on_change, prev, new_state, reason)
    end
  end

  function self:get_state() return self.state end

  function self:mark_master_seen()
    self._last_master = now_s()
    if self.state=="INIT" or self.state=="LOST_MASTER" then
      change("AUTO", "master_seen")
    end
  end

  function self:tick()
    local age = now_s() - (self._last_master or 0)
    if age > self.master_timeout_s and self.state ~= "MASTER" and self.state ~= "EMERGENCY" then
      change("LOST_MASTER", "master_timeout")
    end
  end

  function self:trigger_emergency(reason)
    change("EMERGENCY", reason or "fault")
  end

  function self:assume_master(reason)
    change("MASTER", reason or "elected")
  end

  function self:enter_auto(reason)
    change("AUTO", reason or "master_present")
  end

  function self:reset(reason)
    change("INIT", reason or "reset")
  end

  return self
end

return SM
