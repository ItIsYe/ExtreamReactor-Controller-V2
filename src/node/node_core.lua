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

  function self:is_master_candidate()
    return runtime:is_master_candidate()
  end

  function self:publish_telem(data_tbl)
    return runtime:publish_telem(data_tbl)
  end

  function self:publish_alarm(level, code, text, uid)
    return runtime:publish_alarm(level, code, text, uid)
  end

  -- Startet Dispatcher + Eventloop (Heartbeat/HELLO/Timeout/Wahl inklusive)
  function self:start()
    return runtime:start()
  end

  return self
end

return Core
