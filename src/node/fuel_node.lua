--========================================================
-- /xreactor/node/fuel_node.lua
-- Fuel-Node: nutzt Node-Core für Autonomie + Master-Wahl
--========================================================
local NodeCore = dofile('/xreactor/node/node_core.lua')

local M = {}

function M.run(opts)
  local cfg = opts or {}
  cfg.identity = cfg.identity or { role='FUEL' }
  local node = NodeCore.create(cfg)
  node:start()
  return node
end

return M
