-- protocol.lua — rednet helpers + message constructors
local M = {}

function M.open(side)
  if rednet.isOpen() then rednet.close() end
  assert(peripheral.getType(side)=="modem", "No modem on "..tostring(side))
  rednet.open(side)
end

function M.close() if rednet.isOpen() then rednet.close() end end

function M.send(to, msg) rednet.send(to, msg) end
function M.broadcast(msg) rednet.broadcast(msg) end

-- typed constructors (light)
function M.msg_hello(cfg)
  return {
    type = "HELLO",
    node_title = cfg.node_title,
    caps = { steam=true, rpm=true, fill=true, temp=true, fuel=true, waste=true },
    _auth = cfg.auth_token,
    ts = os.epoch("utc"),
  }
end

function M.msg_hello_ack(master_id, gen, cfg, token)
  return {
    type="HELLO_ACK", master_id=master_id, master_generation=gen, cfg={ rpm_target=cfg.rpm_target },
    _auth=token, ts=os.epoch("utc"),
  }
end

function M.msg_beacon(master_id, gen, token)
  return { type="BEACON", master_id=master_id, master_generation=gen, _auth=token, ts=os.epoch("utc") }
end

function M.msg_command_setpoints(gen, token, reactors, turbines)
  return {
    type="COMMAND", action="SETPOINTS",
    reactors=reactors, turbines=turbines,
    master_generation=gen, _auth=token, ts=os.epoch("utc"),
  }
end

function M.msg_discover(token) return { type="DISCOVER", _auth=token, ts=os.epoch("utc") } end

return M
