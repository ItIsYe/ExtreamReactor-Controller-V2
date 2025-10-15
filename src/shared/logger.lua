-- logger.lua — ring buffer + file flush (lightweight)
local M = {}

local function rb_new(cap)
  return {cap=math.max(10,cap or 300), head=0, size=0, data={}}
end

local function rb_push(rb, row)
  rb.head = (rb.head % rb.cap) + 1
  rb.data[rb.head] = row
  rb.size = math.min(rb.size + 1, rb.cap)
end

local function rb_iter(rb)
  local n = rb.size
  local i = (rb.size==rb.cap) and (rb.head+1) or 1
  local c = 0
  return function()
    if c >= n then return nil end
    local idx = ((i-1) % rb.cap) + 1
    local v = rb.data[idx]
    i = i + 1; c = c + 1
    return v
  end
end

local function save_json(path, tbl)
  local dir = fs.getDir(path); if dir~="" and not fs.exists(dir) then fs.makeDir(dir) end
  local f = fs.open(path,"w"); if not f then return false end
  local ok, js = pcall(textutils.serializeJSON, tbl)
  if not ok then js = textutils.serialize(tbl) end
  f.write(js); f.close(); return true
end

M.new = rb_new
M.push = rb_push
M.iter = rb_iter
M.flush = function(path, rb) return save_json(path, {cap=rb.cap, size=rb.size, head=rb.head, data=rb.data}) end

return M
