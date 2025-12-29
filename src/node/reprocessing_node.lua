--========================================================
-- /xreactor/node/reprocessing_node.lua
-- Reprocessing-Node: nutzt Node-Core für Autonomie + Wahl
--========================================================
local NodeCore = dofile('/xreactor/node/node_core.lua')

local M = {}

function M.run(opts)
  local cfg = opts or {}
  cfg.identity = cfg.identity or { role='REPROCESS' }
  local node = NodeCore.create(cfg)
  node:start()
  return node
end

return M
