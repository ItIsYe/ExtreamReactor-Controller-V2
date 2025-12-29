--========================================================
-- /xreactor/shared/network_dispatcher.lua
-- Zentraler rednet-Dispatcher: genau ein receive-Loop, Auth, Rollenfilter
--========================================================
local PROTO = dofile("/xreactor/shared/protocol.lua")

local M = {}

local function tbl_copy(t) local r={}; for k,v in pairs(t or {}) do r[k]=v end; return r end

local function ensure_modem(side)
  if side and peripheral.getType(side)=="modem" then
    if not rednet.isOpen(side) then pcall(rednet.open, side) end
    return rednet.isOpen(side)
  end
  for _,n in ipairs(peripheral.getNames()) do
    if peripheral.getType(n)=="modem" then
      if not rednet.isOpen(n) then pcall(rednet.open,n) end
      if rednet.isOpen(n) then return true end
    end
  end
  return false
end

function M.create(opts)
  local cfg = opts or {}
  local self = {
    auth_token   = cfg.auth_token or PROTO.AUTH_TOKEN_DEFAULT,
    modem_side   = cfg.modem_side,
    identity     = tbl_copy(cfg.identity or {}),
    receive_wait = cfg.receive_wait or 0.2,
    _subs        = {},
    _running     = false,
  }

  ensure_modem(self.modem_side)

  local function emit(type_name, handler, from_id, msg)
    local ok, err = pcall(handler, msg, from_id)
    if not ok then
      print("[dispatcher] handler error for "..tostring(type_name)..": "..tostring(err))
    end
  end

  local function matches_role(sub_roles, msg_role)
    if not sub_roles or #sub_roles==0 then return true end
    local mr = msg_role and tostring(msg_role):upper() or ""; local want={}
    for _,r in ipairs(sub_roles) do want[tostring(r):upper()]=true end
    return want[mr]==true
  end

  function self:subscribe(type_name, handler, opts_sub)
    assert(type(type_name)=="string", "type_name muss string sein")
    assert(type(handler)=="function", "handler muss function sein")
    local entry = {cb=handler, roles=nil}
    if opts_sub and opts_sub.roles then
      entry.roles = {}
      for _,r in ipairs(opts_sub.roles) do table.insert(entry.roles, r) end
    end
    self._subs[type_name] = self._subs[type_name] or {}
    table.insert(self._subs[type_name], entry)
  end

  function self:publish(msg, target)
    if type(msg) ~= "table" then return false end
    if not msg.type then return false end
    ensure_modem(self.modem_side)
    local tagged = PROTO.tag(PROTO.attach_identity(msg, self.identity), self.auth_token)
    if target then
      return pcall(rednet.send, target, tagged)
    else
      return pcall(rednet.broadcast, tagged)
    end
  end

  function self:publish_type(type_name, data_tbl, target)
    if type(type_name) ~= "string" then return false end
    return self:publish({ type = type_name, data = data_tbl or {} }, target)
  end

  function self:start()
    if self._running then return end
    self._running = true

    local function safe_receive(timeout)
      local ok, from, msg = pcall(rednet.receive, timeout)
      if not ok then
        ensure_modem(self.modem_side)
        return nil, nil, msg
      end
      return from, msg
    end

    parallel.waitForAny(function()
      while self._running do
        local from, msg = safe_receive(self.receive_wait)
        if from and type(msg)=="table" and PROTO.is_auth(msg, self.auth_token) and msg.type then
          local subs = self._subs[msg.type] or {}
          for _,s in ipairs(subs) do
            if matches_role(s.roles, msg.role) then emit(msg.type, s.cb, from, msg) end
          end
        end
      end
    end, function()
      os.pullEvent("dispatcher_stop")
      self._running=false
    end)
  end

  function self:stop()
    self._running=false
    os.queueEvent("dispatcher_stop")
  end

  return self
end

return M
