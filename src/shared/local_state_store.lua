--========================================================
-- /xreactor/shared/local_state_store.lua
-- Persistiert lokale Node-Betriebszustände sicher und atomar.
--========================================================
local M = {}

local function build_path(cfg)
  if cfg.path and cfg.path ~= '' then return cfg.path end
  local role = tostring((cfg.identity or {}).role or 'node'):lower()
  local id = tostring((cfg.identity or {}).id or os.getComputerID())
  return string.format('/xreactor/state/%s_%s_state.lua', role, id)
end

local function ensure_dir(path)
  local dir = fs.getDir(path)
  if dir and dir ~= '' and not fs.exists(dir) then fs.makeDir(dir) end
end

local function atomic_write(path, content)
  ensure_dir(path)
  local tmp = path .. '.tmp'
  local fh = fs.open(tmp, 'w')
  if not fh then return false, 'open_failed' end
  fh.write(content)
  fh.close()
  if fs.exists(path) then fs.delete(path) end
  fs.move(tmp, path)
  return true
end

local function serialize(tbl)
  local ok, serialized = pcall(textutils.serialize, tbl)
  if not ok or type(serialized) ~= 'string' then
    return nil, 'serialize_failed'
  end
  return 'return ' .. serialized
end

function M.create(cfg)
  cfg = cfg or {}
  local path = build_path(cfg)

  local self = { path = path }

  function self:load()
    if not self.path or not fs.exists(self.path) then return nil end
    local ok, data = pcall(dofile, self.path)
    if not ok then return nil, tostring(data) end
    if type(data) ~= 'table' then return nil, 'invalid_data' end
    return data
  end

  function self:save(tbl)
    if type(tbl) ~= 'table' then return false end
    tbl._saved_at = tbl._saved_at or os.epoch('utc')
    local content, err = serialize(tbl)
    if not content then return false, err end
    return atomic_write(self.path, content)
  end

  return self
end

return M
