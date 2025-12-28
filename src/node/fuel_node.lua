--========================================================
-- /xreactor/node/fuel_node.lua
-- Fuel-Management Node: Vorräte/Prognosen monitoren
--========================================================
local Runtime = dofile('/xreactor/shared/node_runtime.lua')

local M = {}

function M.run(opts)
  local cfg = opts or {}
  cfg.identity = cfg.identity or { role='FUEL' }
  local rt = Runtime.create(cfg)
  rt:start()
  return rt
end

return M
