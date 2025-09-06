local M = {}


local function ensure_dir(path)
local parts = {}
for p in string.gmatch(path, "[^/]+") do table.insert(parts, p) end
local cur = ""
for i = 1, #parts-1 do
cur = cur .. (i==1 and parts[i] or ("/"..parts[i]))
if not fs.exists(cur) then fs.makeDir(cur) end
end
end


local function read_all(path)
if not fs.exists(path) then return nil end
local h = fs.open(path, "r")
if not h then return nil end
local s = h.readAll()
h.close()
return s
end


local function write_all(path, s)
ensure_dir(path)
local h = fs.open(path, "w")
if not h then error("cannot write "..path) end
h.write(s)
h.close()
end


function M.load_json(path, defaults)
local s = read_all(path)
if not s then return defaults end
local ok, data = pcall(textutils.unserializeJSON, s)
if not ok or type(data) ~= "table" then return defaults end
return setmetatable(data, {__index = defaults})
end


function M.save_json(path, tbl)
write_all(path, textutils.serializeJSON(tbl, true))
end


return M
