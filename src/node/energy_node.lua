--========================================================
-- /xreactor/node/energy_node.lua
-- Energy-Node: nutzt Node-Core für Telemetrie + Master-Integration
--========================================================
local NodeCore = dofile('/xreactor/node/node_core.lua')

local M = {}

function M.run(opts)
  local cfg = opts or {}
  cfg.identity = cfg.identity or { role='ENERGY' }
  local node = NodeCore.create(cfg)
  node:start()
  return node
end

return M
