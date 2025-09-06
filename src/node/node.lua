local CFG_DEF = require("config_node")
local function do_config()
local spec = {
{key="modem_side", label="Modem-Seite", type="text"},
{key="auth_token", label="Auth-Token", type="text"},
{key="node_id", label="Node-ID (leer=auto)", type="text"},
{key="floor", label="Etage", type="number"},
{key="rpm_target_default", label="RPM Ziel", type="number"},
{key="flow_min", label="Flow min", type="number"},
{key="flow_max", label="Flow max", type="number"},
{key="flow_step", label="Flow Schritt", type="number"},
{key="rod_min", label="Rod min (%)", type="number"},
{key="rod_max", label="Rod max (%)", type="number"},
{key="rod_step", label="Rod Schritt (%)", type="number"},
{key="reactor", label="Reaktor-Peripherie", type="text"},
{key="turbines", label="Turbinen (Komma)", type="list"},
{key="floor_storages", label="Speicher (Komma)", type="list"},
{key="alarm_rpm_low", label="Alarm RPM low", type="number"},
{key="alarm_rpm_high", label="Alarm RPM high", type="number"},
{key="alarm_enable_sound", label="Alarm Sound", type="toggle"},
}
local work={}; for k,v in pairs(CFG) do work[k]=v end
local res, data = GUI.form("Node Konfiguration", spec, work)
if res=="save" then
for k,v in pairs(data) do CFG[k]=v end
STO.save_json(CFG_PATH, CFG)
rednet.close(); rednet.open(CFG.modem_side)
bind()
set.rpm_target = CFG.rpm_target_default
end
end


-- Start
if reactor and reactor.setActive then reactor.setActive(true) end
hello(); draw()


parallel.waitForAny(
function() -- RX
while true do
local id, msg = P.recv(3)
if id and msg and msg._auth==CFG.auth_token then
if msg.type=="HELLO_ACK" and msg.cfg and msg.cfg.rpm_target then set.rpm_target = msg.cfg.rpm_target end
if msg.type=="SETPOINT" and (msg.node_id==ID or not msg.node_id) then
set.steam_target = msg.steam_target or set.steam_target
set.rpm_target = msg.rpm_target or set.rpm_target
if msg.rod_limits then set.rod_min = msg.rod_limits.min or set.rod_min; set.rod_max = msg.rod_limits.max or set.rod_max end
end
else
hello()
end
end
end,
function() -- Control & UI
while true do
loop_control()
draw()
local e,k = os.pullEventTimeout("key", 0.2)
if e=="key" then
if k==keys.f1 then do_config(); draw()
elseif k==keys.f2 then
term.clear(); term.setCursorPos(1,1); print("Peripherie:")
local y=2; for _,n in ipairs(peripheral.getNames()) do term.setCursorPos(1,y); print( ("%-24s (%s)"):format(n, peripheral.getType(n)) ); y=y+1 end
os.pullEvent("key"); draw()
elseif k==keys.space then running = not running; draw()
elseif k==keys.q or k==keys.escape then return end
end
end
end
)
