-- storage.lua – simple Persistenz (JSON wenn möglich, Fallback auf Lua-Serialize)

local storage = {}

local function ensureDir(path)
  local dir = fs.getDir(path)
  if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
end

local function write_all(path, s)
  ensureDir(path)
  local f = fs.open(path, "w")
  if not f then error("cannot write "..path) end
  f.write(s); f.close()
end

local function read_all(path)
  if not fs.exists(path) then return nil end
  local f = fs.open(path, "r")
  if not f then return nil end
  local s = f.readAll(); f.close()
  return s
end

-- JSON save/load (CC:T hat textutils.serializeJSON/parseJSON; Fallbacks vorhanden)
function storage.save_json(path, tbl)
  if type(tbl) ~= "table" then error("save_json expects table") end
  local ok, s
  if textutils.serializeJSON then
    ok, s = pcall(textutils.serializeJSON, tbl)
  else
    -- Fallback: als Lua-Table serialisieren
    ok, s = pcall(textutils.serialize, tbl)
  end
  if not ok then error("serialize failed: "..tostring(s)) end
  write_all(path, s)
end

function storage.load_json(path, default)
  local s = read_all(path)
  if not s then return default end
  if textutils.unserializeJSON then
    local ok, data = pcall(textutils.unserializeJSON, s)
    if ok and type(data) == "table" then return data end
  end
  -- Fallback: Lua-Table unserialize
  local ok2, data2 = pcall(textutils.unserialize, s)
  if ok2 and type(data2) == "table" then return data2 end
  return default
end

-- optional: Lua-Table Speichern/Laden (wenn du lieber *.lua-artige Dateien willst)
function storage.save_lua(path, tbl)
  if type(tbl) ~= "table" then error("save_lua expects table") end
  local ok, s = pcall(textutils.serialize, tbl)
  if not ok then error("serialize failed: "..tostring(s)) end
  write_all(path, s)
end

function storage.load_lua(path, default)
  local s = read_all(path)
  if not s then return default end
  local ok, data = pcall(textutils.unserialize, s)
  if ok and type(data) == "table" then return data end
  return default
end

return storage
