--========================================================
-- /xreactor/node/aux_node.lua
-- AUX-Node Basis: nutzt Node-Core für Dispatcher + State-Machine + Heartbeat/HELLO
--========================================================
local NodeCore = dofile('/xreactor/node/node_core.lua')

local M = {}

function M.run(opts)
  local cfg = opts or {}
  cfg.identity = cfg.identity or { role='AUX' }
  local node = NodeCore.create(cfg)
  node:start()
  return node
end

return M
