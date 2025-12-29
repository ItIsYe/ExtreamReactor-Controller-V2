--========================================================
-- /xreactor/tools/self_test.lua
-- Simulator/Smoke-Test: fake Telemetrie & Alarme
--========================================================
local PROTO = dofile("/xreactor/shared/protocol.lua")
local AUTH  = PROTO.AUTH_TOKEN_DEFAULT
local MODEM = "right"

assert(peripheral.getType(MODEM)=="modem", "Kein Modem an "..MODEM)
if not rednet.isOpen(MODEM) then rednet.open(MODEM) end

local function bcast(m) rednet.broadcast(PROTO.tag(m, AUTH)) end

local uid_list={"reactor-A","reactor-B","reactor-C"}
local rpm={1200,900,1600}; local pwr={250000,180000,320000}; local flow={1200,900,1500}; local fuel={85,60,35}

bcast({type=PROTO.T.HELLO})
for _,u in ipairs(uid_list) do bcast({type=PROTO.T.NODE_HELLO, uid=u, hostname="SIM-"..u, role="REACTOR", cluster="SIM"}) end

while true do
  for i,u in ipairs(uid_list) do
    rpm[i]=math.max(0,rpm[i]+math.random(-5,5)); pwr[i]=math.max(0,pwr[i]+math.random(-500,500)); flow[i]=math.max(0,flow[i]+math.random(-5,5)); fuel[i]=math.max(0,math.min(100,fuel[i]+(math.random()<0.3 and -1 or 0)))
    bcast({type=PROTO.T.TELEM, data={uid=u, rpm=rpm[i], power_mrf=pwr[i], flow=flow[i], fuel_pct=fuel[i]}, hostname="SIM-"..u, role="REACTOR", cluster="SIM"})
  end
  if math.random()<0.1 then
    bcast(PROTO.make_alarm({ severity = "WARN", message = "Schwankende Drehzahl", source_node_id = "sim-node" }))
  end
  if math.random()<0.05 then
    bcast(PROTO.make_alarm({ severity = "CRITICAL", message = "Fuel niedrig", source_node_id = "sim-node" }))
  end
  sleep(0.7)
end

