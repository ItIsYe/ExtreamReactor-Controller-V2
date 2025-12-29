-- /xreactor/master/master_core.lua
-- Master-Runtime mit Election/Heartbeat und MASTER↔SLAVE Wechsel
-- Verteilte Architektur: wireless = nur Kommunikation, wired = nur Hardware,
-- Nodes bleiben autonom, Master ist optional und darf ausfallen
--========================================================
local PROTO      = dofile('/xreactor/shared/protocol.lua')
local IDENTM     = dofile('/xreactor/shared/identity.lua')
local Dispatcher = dofile('/xreactor/shared/network_dispatcher.lua')
local NodeState  = dofile('/xreactor/shared/node_state_machine.lua')

local function now_s() return os.epoch('utc')/1000 end

local M = {}

function M.create(opts)
  local cfg = opts or {}
  local ident = IDENTM.load_identity()
  if type(cfg.identity) == 'table' then
    for k,v in pairs(cfg.identity) do ident[k] = v end
  end
  ident.role = ident.role or 'MASTER'

  local is_candidate = cfg.is_candidate
  if is_candidate == nil then
    local role = tostring(ident.role or ''):upper()
    is_candidate = (role=='MASTER' or role=='MASTER_CANDIDATE')
  end

  local self = { IDENT = ident }
  local dispatcher = cfg.dispatcher or Dispatcher.create({ auth_token = ident.token, modem_side = cfg.modem_side, identity = ident })
  local owns_dispatcher = cfg.dispatcher == nil
  local state = NodeState.create({
    master_timeout_s = cfg.master_timeout_s or 10,
    on_change = function(old, new, reason)
      if type(cfg.on_state_change)=='function' then pcall(cfg.on_state_change, old, new, reason) end
      os.queueEvent('master_state_change', old, new, reason)
    end,
  })

  local HB_INTERVAL    = cfg.heartbeat_interval or 5
  local HELLO_INTERVAL = cfg.hello_interval or 15
  local TICK_INTERVAL  = cfg.tick_interval or 1
  local ELECTION_WINDOW= cfg.election_window or 4

  local SELF_ID = os.getComputerID()
  local current_master = nil
  local election = { active=false, best_prio=nil, best_id=nil, deadline=0, announced=false }
  local timers = {}

  local function reset_timer(key, interval)
    timers[key] = os.startTimer(interval)
  end

  local function reset_election()
    election.active=false; election.best_prio=nil; election.best_id=nil; election.deadline=0; election.announced=false
  end

  local function register_candidate(prio, node_id)
    prio = tonumber(prio) or -math.huge
    node_id = tonumber(node_id) or 0
    if (not election.best_prio)
      or prio > election.best_prio
      or (prio == election.best_prio and node_id < (election.best_id or math.huge)) then
      election.best_prio = prio
      election.best_id   = node_id
    end
  end

  local function send_hello()
    dispatcher:publish(PROTO.make_hello(ident))
  end

  local function send_heartbeat()
    if state:get_state() ~= 'MASTER' or current_master ~= SELF_ID then return end
    dispatcher:publish(PROTO.make_heartbeat(ident, { state=state:get_state(), master=current_master }))
  end

  local function send_state_update(reason)
    dispatcher:publish(PROTO.make_state_update(ident, { state=state:get_state(), reason=reason, master=current_master }))
  end

  local function announce_candidate()
    if election.announced then return end
    election.announced = true
    dispatcher:publish(PROTO.make_master_election(ident, { priority=ident.priority, node_id=SELF_ID }))
  end

  local function start_election()
    if not is_candidate then return end
    reset_election()
    election.active = true
    election.deadline = now_s() + ELECTION_WINDOW
    register_candidate(ident.priority, SELF_ID)
    announce_candidate()
  end

  local function conclude_election()
    if not election.active then return end
    if election.best_id == SELF_ID then
      current_master = SELF_ID
      state:assume_master('elected')
      dispatcher:publish(PROTO.make_master_announce(ident, { node_id=SELF_ID, priority=ident.priority }))
      send_heartbeat()
    else
      state:enter_auto('lost_election')
    end
    reset_election()
  end

  local function handle_state_change(old, new, reason)
    send_state_update(reason)
    if new == 'LOST_MASTER' then start_election() end
    if new == 'AUTO' or new == 'MASTER' then reset_election() end
  end

  dispatcher:subscribe(PROTO.T.HEARTBEAT, function(msg, from)
    if tostring(msg.role or ''):upper()=='MASTER' then
      current_master = from
      state:mark_master_seen()
      if from ~= SELF_ID and state:get_state() == 'MASTER' then
        state:enter_auto('external_master')
      end
      if cfg.on_master_seen then pcall(cfg.on_master_seen, from, msg) end
    end
  end)

  dispatcher:subscribe(PROTO.T.MASTER_ANNOUNCE, function(msg, from)
    current_master = from
    state:enter_auto('announce')
    state:mark_master_seen()
    reset_election()
    if from ~= SELF_ID and state:get_state() == 'MASTER' then
      state:enter_auto('announcement')
    end
    if cfg.on_master_seen then pcall(cfg.on_master_seen, from, msg) end
  end)

  dispatcher:subscribe(PROTO.T.MASTER_ELECTION, function(msg, from)
    if not is_candidate then return end
    local data = type(msg.data)=='table' and msg.data or {}
    local prio = data.priority or msg.priority
    local node_id = data.node_id or from
    register_candidate(prio, node_id)
    if not election.active then start_election() else announce_candidate() end
  end)

  function self:get_dispatcher() return dispatcher end
  function self:get_state() return state:get_state() end
  function self:get_master_id() return current_master end
  function self:is_master() return state:get_state()=='MASTER' and current_master==SELF_ID end

  function self:publish(msg, target)
    return dispatcher:publish(msg, target)
  end

  function self:publish_type(type_name, data_tbl, target)
    return dispatcher:publish_type(type_name, data_tbl, target)
  end

  function self:start_timers()
    reset_timer('hello', 0.1)
    reset_timer('hb', HB_INTERVAL)
    reset_timer('tick', TICK_INTERVAL)
  end

  function self:handle_event(ev)
    if ev[1]=='timer' then
      local id = ev[2]
      if id==timers.hello then send_hello(); reset_timer('hello', HELLO_INTERVAL)
      elseif id==timers.hb then send_heartbeat(); reset_timer('hb', HB_INTERVAL)
      elseif id==timers.tick then
        state:tick()
        if election.active and now_s() > election.deadline then conclude_election() end
        reset_timer('tick', TICK_INTERVAL)
      end
    elseif ev[1]=='master_state_change' then
      local _,old,new,reason = table.unpack(ev)
      handle_state_change(old, new, reason)
    end
  end

  function self:start_dispatcher()
    if owns_dispatcher then dispatcher:start() end
  end

  function self:stop()
    if owns_dispatcher then dispatcher:stop() end
  end

  return self
end

return M
