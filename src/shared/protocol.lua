-- protocol.lua — rednet helpers + message constructors (Phase B)
local M = {}

function M.open(side)
  if rednet.isOpen() then rednet.close() end
  assert(peripheral.getType(side)=="modem", "No modem on "..tostring(side))
  rednet.open(side)
end
function M.close() if rednet.isOpen() then rednet.close() end end

function M.send(to, msg) rednet.send(to, msg) end
function M.broadcast(msg) rednet.broadcast(msg) end

-- HELLO/ACK/BEACON
function M.msg_hello(cfg)
  return {
    type = "HELLO",
    node_title = cfg.node_title,
    caps = { steam=true, rpm=true, fill=true, temp=true, fuel=true, waste=true, matrix=true },
    _auth = cfg.auth_token,
    ts = os.epoch("utc"),
  }
end

function M.msg_hello_ack(master_id, gen, cfg, token)
  return {
    type="HELLO_ACK", master_id=master_id, master_generation=gen,
    cfg={ rpm_target=cfg.rpm_target },
    _auth=token, ts=os.epoch("utc"),
  }
end

function M.msg_beacon(master_id, gen, token)
  return { type="BEACON", master_id=master_id, master_generation=gen, _auth=token, ts=os.epoch("utc") }
end

-- COMMAND: SETPOINTS
function M.msg_command_setpoints(gen, token, reactors, turbines)
  return {
    type="COMMAND", action="SETPOINTS",
    reactors=reactors, turbines=turbines,
    master_generation=gen, _auth=token, ts=os.epoch("utc"),
  }
end

function M.msg_discover(token) return { type="DISCOVER", _auth=token, ts=os.epoch("utc") } end

-- ===== Phase B: Fuel/Waste Supply Protocol =====

-- Fuel request to Supply (or internal handler)
function M.msg_fuel_request(token, reactor_id, amount, fuel_item, priority)
  return {
    type="FUEL_REQUEST", reactor_id=reactor_id, amount=amount,
    fuel_item=fuel_item, priority=priority or 5,
    _auth=token, ts=os.epoch("utc"),
  }
end

function M.msg_fuel_confirm(token, reactor_id, req_amount, granted_amount)
  return { type="FUEL_CONFIRM", reactor_id=reactor_id, req_amount=req_amount,
           granted_amount=granted_amount, _auth=token, ts=os.epoch("utc") }
end

function M.msg_fuel_deny(token, reactor_id, req_amount, reason)
  return { type="FUEL_DENY", reactor_id=reactor_id, req_amount=req_amount,
           reason=tostring(reason or "unknown"), _auth=token, ts=os.epoch("utc") }
end

function M.msg_fuel_done(token, reactor_id, req_amount)
  return { type="FUEL_DONE", reactor_id=reactor_id, req_amount=req_amount,
           _auth=token, ts=os.epoch("utc") }
end

-- Waste drain
function M.msg_waste_drain_request(token, reactor_id, amount, item_id, strategy)
  return {
    type="WASTE_DRAIN_REQUEST", reactor_id=reactor_id, amount=amount,
    item_id=item_id, strategy=strategy or "online",
    _auth=token, ts=os.epoch("utc"),
  }
end

function M.msg_waste_confirm(token, reactor_id, req_amount, granted_amount)
  return { type="WASTE_CONFIRM", reactor_id=reactor_id, req_amount=req_amount,
           granted_amount=granted_amount, _auth=token, ts=os.epoch("utc") }
end

function M.msg_waste_deny(token, reactor_id, req_amount, reason)
  return { type="WASTE_DENY", reactor_id=reactor_id, req_amount=req_amount,
           reason=tostring(reason or "unknown"), _auth=token, ts=os.epoch("utc") }
end

function M.msg_waste_done(token, reactor_id, total_moved)
  return { type="WASTE_DONE", reactor_id=reactor_id, total_moved=total_moved,
           _auth=token, ts=os.epoch("utc") }
end

-- Reprocessing
function M.msg_reproc_request(token, amount, in_item, out_item, water_required)
  return {
    type="REPROC_REQUEST", amount=amount, in_item=in_item, out_item=out_item,
    water_required=water_required, _auth=token, ts=os.epoch("utc")
  }
end

function M.msg_reproc_confirm(token, req_amount, granted_amount)
  return { type="REPROC_CONFIRM", req_amount=req_amount, granted_amount=granted_amount,
           _auth=token, ts=os.epoch("utc") }
end

function M.msg_reproc_deny(token, req_amount, reason)
  return { type="REPROC_DENY", req_amount=req_amount, reason=tostring(reason or "unknown"),
           _auth=token, ts=os.epoch("utc") }
end

function M.msg_reproc_done(token, out_amount)
  return { type="REPROC_DONE", out_amount=out_amount, _auth=token, ts=os.epoch("utc") }
end

return M
