-- XReactor JSON helper (CC:T compatible)
-- Nutzt textutils.serializeJSON/unserializeJSON, fällt sonst auf serialize/unserialize zurück.

local M = {}

local has_json = type(textutils.serializeJSON) == "function"
               and type(textutils.unserializeJSON) == "function"

--- Encode Lua-Wert als JSON-String.
-- @param v any
-- @param pretty boolean|nil  -- true = formatiert
function M.encode(v, pretty)
  if has_json then
    local ok, res = pcall(textutils.serializeJSON, v, pretty and true or false)
    if ok then return res end
  end
  -- Fallback (kein echtes JSON, aber stabil)
  return textutils.serialize(v)
end

--- Decode JSON-String zu Lua-Wert.
-- @param s string
function M.decode(s)
  if has_json then
    local ok, res = pcall(textutils.unserializeJSON, s)
    if ok then return res end
  end
  -- Fallback
  local fn, err = load(s, "json_fallback", "t", {})
  if fn then
    local ok, val = pcall(fn)
    if ok then return val end
  end
  return nil, "json_decode_failed"
end

--- Pretty-JSON für Debug/Logs
function M.pretty(v)
  if has_json then
    return textutils.serializeJSON(v, true)
  end
  return textutils.serialize(v)
end

return M
