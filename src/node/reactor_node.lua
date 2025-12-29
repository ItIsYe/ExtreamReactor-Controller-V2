--========================================================
-- /xreactor/node/reactor_node.lua
-- Reactor/Turbinen Node: lokale Regelung + Node-Core Runtime
--========================================================
local NodeCore = dofile('/xreactor/node/node_core.lua')

local M = {}

function M.run(opts)
  local cfg = opts or {}
  cfg.identity = cfg.identity or { role='REACTOR' }
  local node = NodeCore.create(cfg)
  node:start()
  return node
end

return M
