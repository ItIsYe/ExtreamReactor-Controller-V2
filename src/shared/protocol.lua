-- protocol.lua – einfache Wrapper für rednet, plus Konstanten

local protocol = {}

protocol.MSG = {
  HELLO   = "HELLO",
  HELLO_ACK = "HELLO_ACK",
  TELEM   = "TELEM",
  COMMAND = "COMMAND",
}

-- send() / broadcast() hängen _auth automatisch an, wenn token übergeben wird.
function protocol.send(to_id, tbl, token)
  if type(tbl) ~= "table" then error("send expects table") end
  local msg = tbl
  msg._auth = token
  rednet.send(to_id, msg)
end

function protocol.broadcast(tbl, token)
  if type(tbl) ~= "table" then error("broadcast expects table") end
  local msg = tbl
  msg._auth = token
  rednet.broadcast(msg)
end

-- recv(timeout): holt exakt 1 Nachricht (table) mit optionalem Timeout (Sekunden)
function protocol.recv(timeout)
  local id, msg = rednet.receive(nil, timeout)
  if id and type(msg) == "table" then
    return id, msg
  end
  return nil, nil
end

return protocol
