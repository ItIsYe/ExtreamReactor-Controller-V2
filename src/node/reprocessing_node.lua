--========================================================
-- /xreactor/node/reprocessing_node.lua
-- Fuel-Reprocessing Node: Steuerung der Wiederaufbereitung
--========================================================
local Runtime = dofile('/xreactor/shared/node_runtime.lua')

local M = {}

function M.run(opts)
  local cfg = opts or {}
  cfg.identity = cfg.identity or { role='REPROCESS' }
  local rt = Runtime.create(cfg)
  rt:start()
  return rt
end

return M
