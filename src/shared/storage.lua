-- storage.lua — simple JSON-backed config helpers (CC:T)
local M = {}

local function ensure_dir(path)
  local dir = fs.getDir(path)
  if dir and dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
end

function M.save_json(path, tbl)
  ensure_dir(path)
  local ok, enc = pcall(textutils.serializeJSON, tbl)
  if not ok then enc = textutils.serialize(tbl) end
  local f = fs.open(path, "w")
  if not f then return false, "open_failed" end
  f.write(enc)
  f.close()
  return true
end

function M.load_json(path, default)
  if not fs.exists(path) then return default end
  local f = fs.open(path, "r")
  if not f then return default end
  local s = f.readAll() or ""
  f.close()
  local ok, dec = pcall(textutils.unserializeJSON, s)
  if ok and type(dec)=="table" then return dec end
  local ok2, dec2 = pcall(textutils.unserialize, s)
  if ok2 and type(dec2)=="table" then return dec2 end
  return default
end

return M
