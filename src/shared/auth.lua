-- auth.lua — simple roles/permissions (Viewer/Operator/Admin)
local M = {}

-- actions: "OVERRIDE","REFUEL","DRAIN","CONFIG","BACKUP","RESTORE","ADMIN"
local DEFAULT = {
  role = "admin", -- "viewer"|"operator"|"admin"
  pin  = nil,     -- optional numeric pin for sensitive actions
  perms = {
    viewer   = {OVERRIDE=false, REFUEL=false, DRAIN=false, CONFIG=false, BACKUP=false, RESTORE=false, ADMIN=false},
    operator = {OVERRIDE=true,  REFUEL=true,  DRAIN=true,  CONFIG=false, BACKUP=true,  RESTORE=false, ADMIN=false},
    admin    = {OVERRIDE=true,  REFUEL=true,  DRAIN=true,  CONFIG=true,  BACKUP=true,  RESTORE=true,  ADMIN=true},
  }
}

function M.init(cfg)
  M.cfg = M.cfg or {}
  for k,v in pairs(DEFAULT) do if M.cfg[k]==nil then M.cfg[k]=v end end
  if cfg and type(cfg.role)=="string" then M.cfg.role = cfg.role end
  if cfg and cfg.pin ~= nil then M.cfg.pin = cfg.pin end
  if cfg and type(cfg.perms)=="table" then M.cfg.perms = cfg.perms end
end

local function has_perm(role, action)
  local p = M.cfg.perms[role or "viewer"] or M.cfg.perms.viewer
  local v = p[action] ; if v==nil then return false end
  return v
end

function M.can(action) return has_perm(M.cfg.role, action) end

-- optional PIN check for sensitive ops (returns true if ok or no pin set)
function M.check_pin(input_pin)
  if M.cfg.pin == nil then return true end
  return tostring(input_pin or "") == tostring(M.cfg.pin)
end

return M
