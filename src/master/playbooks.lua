-- playbooks.lua — Safety playbooks for common incidents (Phase B)
local PRO = require("protocol")

local M = {}

-- Evaluate telem and return optional override setpoints (or nil)
function M.evaluate(cfg, nodes)
  -- Scan all nodes for dangerous conditions (simple rules Phase B)
  local override = nil
  for _,n in pairs(nodes) do
    local tr = n.telem and n.telem.reactors or nil
    if tr then
      for _,R in ipairs(tr) do
        -- Overtemperature guard (reactor casing temp)
        if R.temp and cfg and (R.temp >= (cfg.max_temp_guard or 950)) then
          override = override or {}
          table.insert(override, { reactor_id=tostring(R.reactor_id or "GLOBAL"), reactor_on=false, steam_target=0, rpm_target=cfg.rpm_target or 1800 })
        end
        -- (Extend with steam-deficit / matrix-low etc. in later phases)
      end
    end
  end
  return override
end

return M
