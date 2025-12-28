--========================================================
-- /xreactor/node/reactor_node.lua
-- Reactor/Turbinen Node: lokale Regelung + Runtime
--========================================================
local Runtime = dofile('/xreactor/shared/node_runtime.lua')

local M = {}

function M.run(opts)
  local cfg = opts or {}
  cfg.identity = cfg.identity or { role='REACTOR' }
  local rt = Runtime.create(cfg)
  rt:start()
  return rt
end

return M
