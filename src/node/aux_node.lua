--========================================================
-- /xreactor/node/aux_node.lua
-- Einfache AUX-Node (Vorlage/Platzhalter)
--========================================================
local PROTO = dofile("/xreactor/shared/protocol.lua")
local IDENTM= dofile("/xreactor/shared/identity.lua")
local IDENT = IDENTM.load_identity()

local function open_any_modem()
  local opened=false
  for _,n in ipairs(peripheral.getNames()) do
    if peripheral.getType(n)=="modem" then if not rednet.isOpen(n) then pcall(rednet.open,n) end; if rednet.isOpen(n) then opened=true end end
  end
  return opened
end
open_any_modem()

local function bcast(msg) msg=PROTO.tag(msg, IDENT.token or PROTO.AUTH_TOKEN_DEFAULT); pcall(rednet.broadcast, msg) end

term.clear(); term.setCursorPos(1,1)
print(("XReactor AUX Node  [%s]"):format(IDENT.hostname or "?")); print("Sende HELLO & Heartbeats. Warte auf Kommandos...")

local last_hello=0
while true do
  local t=os.clock()
  if t-last_hello>5 then last_hello=t; bcast(PROTO.make_node_hello(IDENT)) end
  local id,msg=rednet.receive(0.5)
  if id and type(msg)=="table" and msg._auth==(IDENT.token or PROTO.AUTH_TOKEN_DEFAULT) then
    -- Platz für AUX-Kommandos
  end
end
