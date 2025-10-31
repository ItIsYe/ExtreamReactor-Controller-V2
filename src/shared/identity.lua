--========================================================
-- /xreactor/shared/identity.lua
-- Lädt die Node-/Master-Identität, generiert fehlende Werte, setzt Label.
--========================================================
local M = {}

local DEFAULTS = {
  role    = "MASTER",            -- MASTER | REACTOR | FUEL | WASTE | AUX
  id      = "01",
  cluster = "XR-CLUSTER-ALPHA",
  token   = "xreactor",
}

local function gen_hostname(role, id)
  role = tostring(role or "NODE"):upper()
  id   = tostring(id or "01")
  return "XR-"..(role=="MASTER" and "MASTER" or ("NODE-"..role)).."-"..id
end

local function load_cfg()
  local path="/xreactor/config_identity.lua"
  local cfg={}
  if fs.exists(path) then
    local ok,t=pcall(dofile,path)
    if ok and type(t)=="table" then cfg=t end
  end
  for k,v in pairs(DEFAULTS) do if cfg[k]==nil then cfg[k]=v end end
  if not cfg.hostname or cfg.hostname=="" then cfg.hostname=gen_hostname(cfg.role, cfg.id) end
  return cfg
end

function M.load_identity()
  local cfg = load_cfg()
  pcall(os.setComputerLabel, cfg.hostname) -- Label für Sichtbarkeit
  return {
    role     = tostring(cfg.role):upper(),
    id       = tostring(cfg.id),
    hostname = tostring(cfg.hostname),
    cluster  = tostring(cfg.cluster),
    token    = tostring(cfg.token),
  }
end

return M
