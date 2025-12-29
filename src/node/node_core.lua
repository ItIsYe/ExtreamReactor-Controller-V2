--========================================================
-- /xreactor/node/node_core.lua
-- Kernmodul für Nodes: State-Machine, Heartbeat/Timeout, Masterwahl (Prio + ID)
-- Baut auf der gemeinsamen Runtime auf und stellt einheitliche Helper bereit
--========================================================
local Runtime = dofile('/xreactor/shared/node_runtime.lua')

local Core = {}

-- Erstellt einen neuen Node-Core auf Basis der gemeinsamen Runtime.
-- cfg.priority wird – falls gesetzt – in die Identity übernommen, um die Wahl-Logik
-- (Priority + Node-ID) zu steuern. Heartbeat, HELLO, Master-Timeout und Wahl laufen
-- innerhalb der Runtime automatisch.
function Core.create(cfg)
  cfg = cfg or {}

  -- Priority auf Identity spiegeln, damit die Election-Logik ein konsistentes Feld nutzt
  if cfg.priority ~= nil then
    cfg.identity = cfg.identity or {}
    if cfg.identity.priority == nil then
      cfg.identity.priority = cfg.priority
    end
  end

  -- Lokale Zielvorgaben/Policies, die auch ohne Netzwerk weiter gelten
  local last_target = {}
  if type(cfg.default_target) == 'table' then
    for k,v in pairs(cfg.default_target) do last_target[k] = v end
  end

  local control_fn   = cfg.control_loop or cfg.local_control
  local user_on_tick = cfg.on_tick
  local user_on_tgt  = cfg.on_target_update

  local function merge_target(msg)
    if type(msg) ~= 'table' then return end
    local data = msg.data or msg.target or msg
    if type(data) ~= 'table' then return end
    for k,v in pairs(data) do last_target[k] = v end
  end

  -- Halte die letzte Zielvorgabe aktiv und triggere lokale Regelung auch ohne Netzwerk
  cfg.on_target_update = function(runtime, msg, from)
    merge_target(msg)
    if type(control_fn) == 'function' then
      pcall(control_fn, last_target, runtime, runtime:get_state_machine():get_state(), runtime:get_master_id(), 'target', from)
    end
    if type(user_on_tgt) == 'function' then
      pcall(user_on_tgt, runtime, msg, from, last_target)
    end
  end

  cfg.on_tick = function(runtime, state, master_id)
    if type(control_fn) == 'function' then
      pcall(control_fn, last_target, runtime, state, master_id, 'tick')
    end
    if type(user_on_tick) == 'function' then
      pcall(user_on_tick, runtime, state, master_id, last_target)
    end
  end

  local runtime = Runtime.create(cfg)
  local state   = runtime:get_state_machine()

  local self = {
    runtime = runtime,
    state   = state,
  }

  function self:get_state()
    return state:get_state()
  end

  function self:get_master_id()
    return runtime:get_master_id()
  end

  function self:get_dispatcher()
    if runtime.get_dispatcher then return runtime:get_dispatcher() end
  end

  function self:is_master_candidate()
    return runtime:is_master_candidate()
  end

  function self:publish_telem(data_tbl)
    return runtime:publish_telem(data_tbl)
  end

  function self:publish_alarm(level, code, text, uid)
    return runtime:publish_alarm(level, code, text, uid)
  end

  -- Liefert die letzte bekannte Zielvorgabe/Policy, bleibt aktiv bis überschrieben
  function self:get_last_target()
    return last_target
  end

  -- Startet Dispatcher + Eventloop (Heartbeat/HELLO/Timeout/Wahl inklusive)
  function self:start()
    return runtime:start()
  end

  function self:stop()
    if runtime.stop then runtime:stop() end
  end

  return self
end

return Core
