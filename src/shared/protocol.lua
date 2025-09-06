local M = {}
M.PROTO = "xreactor.net.v2"


local function has_json() return textutils.serializeJSON and textutils.unserializeJSON end


function M.send(id, tbl, token)
if not has_json() then error("JSON not available") end
tbl._auth = token
rednet.send(id, textutils.serializeJSON(tbl), M.PROTO)
end


function M.broadcast(tbl, token)
if not has_json() then error("JSON not available") end
tbl._auth = token
rednet.broadcast(textutils.serializeJSON(tbl), M.PROTO)
end


function M.recv(timeout)
local id, msg, proto = rednet.receive(M.PROTO, timeout)
if not id then return nil end
local ok, data = pcall(textutils.unserializeJSON, msg)
if not ok then return nil end
return id, data, proto
end


return M
