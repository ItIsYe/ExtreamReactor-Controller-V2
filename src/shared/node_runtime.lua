--========================================================
-- /xreactor/shared/node_runtime.lua
-- Gemeinsame Node-Laufzeit: Dispatcher, Statemachine, HELLO/HB, Masterwahl
--========================================================
local PROTO     = dofile('/xreactor/shared/protocol.lua')
local IDENTM    = dofile('/xreactor/shared/identity.lua')
local Dispatcher= dofile('/xreactor/shared/network_dispatcher.lua')
local NodeState = dofile('/xreactor/shared/node_state_machine.lua')

local function now_s() return os.epoch('utc')/1000 end

local Runtime = {}

function Runtime.create(opts)
  local cfg = opts or {}
  local ident = IDENTM.load_identity()
  if type(cfg.identity) == 'table' then
    for k,v in pairs(cfg.identity) do ident[k] = v end
  end
  local is_candidate = cfg.is_candidate
  if is_candidate == nil then
    local role = tostring(ident.role or ''):upper()
    is_candidate = (role=='MASTER' or role=='MASTER_CANDIDATE')
  end

  local self = { IDENT=ident }

  local dispatcher = Dispatcher.create({ auth_token=ident.token, identity=ident })
  local state = NodeState.create({
    master_timeout_s = cfg.master_timeout_s or 10,
    on_change = function(old, new, reason)
      if type(cfg.on_state_change)=='function' then
        pcall(cfg.on_state_change, self, old, new, reason)
      end
      os.queueEvent('node_state_change', old, new, reason)
    end,
  })

  local HB_INTERVAL    = cfg.heartbeat_interval or 5
  local HELLO_INTERVAL = cfg.hello_interval or 15
  local TICK_INTERVAL  = cfg.tick_interval or 1
  local ELECTION_WINDOW= cfg.election_window or 4

  local current_master = nil
  local election = { active=false, best_prio=nil, best_id=nil, deadline=0, announced=false }
  local SELF_ID = os.getComputerID()

  local function log(msg)
    print(('[%s] %s'):format(ident.hostname or ident.id or 'node', tostring(msg)))
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
    dispatcher:publish(PROTO.make_node_hello(ident, cfg.extra_hello))
  end

  local function send_heartbeat()
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
    election.active=true
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
    end
    reset_election()
  end

  function self:get_state_machine() return state end
  function self:get_dispatcher() return dispatcher end
  function self:get_master_id() return current_master end
  function self:is_master_candidate() return is_candidate end

  function self:publish_telem(data_tbl)
    return dispatcher:publish(PROTO.make_telem(ident, data_tbl or {}))
  end

  function self:publish_alarm(level, code, text, uid)
    return dispatcher:publish(PROTO.make_alarm(level, code, text, ident.id, uid))
  end

  dispatcher:subscribe(PROTO.T.HEARTBEAT, function(msg, from)
    if tostring(msg.role or ''):upper()=='MASTER' then
      current_master = from
      state:mark_master_seen()
      if cfg.on_master_seen then pcall(cfg.on_master_seen, self, from, msg) end
    end
  end)

  dispatcher:subscribe(PROTO.T.MASTER_ANNOUNCE, function(msg, from)
    current_master = from
    state:enter_auto('announce')
    state:mark_master_seen()
    reset_election()
    if cfg.on_master_seen then pcall(cfg.on_master_seen, self, from, msg) end
  end)

  dispatcher:subscribe(PROTO.T.TARGET_UPDATE, function(msg, from)
    if type(cfg.on_target_update)=='function' then
      pcall(cfg.on_target_update, self, msg, from)
    else
      log('Neue Zielvorgaben erhalten')
    end
  end)

  dispatcher:subscribe(PROTO.T.ALARM, function(msg, from)
    if type(cfg.on_alarm)=='function' then
      pcall(cfg.on_alarm, self, msg, from)
    else
      log('ALARM: '..tostring(msg.msg or ''))
    end
  end)

  dispatcher:subscribe(PROTO.T.MASTER_ELECTION, function(msg, from)
    if not is_candidate then return end
    local data = type(msg.data)=='table' and msg.data or {}
    local prio = data.priority or msg.priority
    local node_id = data.node_id or from
    register_candidate(prio, node_id)
    if not election.active then start_election() else announce_candidate() end
  end)

  local timers = {}
  local running = true
  local function reset_timer(key, interval)
    timers[key] = os.startTimer(interval)
  end

  local function handle_timer(id)
    if id==timers.hello then send_hello(); reset_timer('hello', HELLO_INTERVAL)
    elseif id==timers.hb then send_heartbeat(); reset_timer('hb', HB_INTERVAL)
    elseif id==timers.tick then
      state:tick()
      if election.active and now_s() > election.deadline then conclude_election() end
      if type(cfg.on_tick)=='function' then pcall(cfg.on_tick, self, state:get_state(), current_master) end
      reset_timer('tick', TICK_INTERVAL)
    end
  end

  local function event_loop()
    term.clear(); term.setCursorPos(1,1)
    print(('XReactor Node [%s]'):format(ident.hostname or '?'))
    print('Heartbeat + HELLO aktiv. Warte auf Events…')

    reset_timer('hello', 0.1)
    reset_timer('hb', HB_INTERVAL)
    reset_timer('tick', TICK_INTERVAL)

    while running do
      local ev = {os.pullEvent()}
      if ev[1]=='timer' then handle_timer(ev[2])
      elseif ev[1]=='node_state_change' then
        local _,old,new,reason = table.unpack(ev)
        log(('STATE %s -> %s (%s)'):format(tostring(old), tostring(new), tostring(reason)))
        send_state_update(reason)
        if new=='LOST_MASTER' then start_election() end
        if new=='AUTO' or new=='MASTER' then reset_election() end
      elseif ev[1]=='terminate' then
        dispatcher:stop(); running=false; return
      end
    end
  end

  function self:start()
    parallel.waitForAny(function() dispatcher:start() end, event_loop)
  end

  function self:stop()
    running=false
    dispatcher:stop()
    os.queueEvent('terminate')
  end

  return self
end

return Runtime
