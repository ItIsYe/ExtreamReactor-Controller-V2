-- supply.lua — rednet Supply daemon for Fuel/Waste/Reproc via ME/RS Bridge (Phase B)
package.path = package.path .. ";/xreactor/?.lua;/xreactor/shared/?.lua;/xreactor/?/init.lua"

local PRO = require("protocol")

local CFG = (function()
  local ok, def = pcall(require,"config_supply")
  return (ok and def) or {}
end)()

-- open modem (auto-pick first modem)
local function find_modem()
  for _,n in ipairs(peripheral.getNames()) do
    if peripheral.getType(n)=="modem" then return n end
  end
  return nil
end

local modem = find_modem()
assert(modem, "No modem found for Supply")
PRO.open(modem)

local me = (CFG.me_bridge_name and peripheral.wrap(CFG.me_bridge_name)) or nil
local rs = (CFG.rs_bridge_name and peripheral.wrap(CFG.rs_bridge_name)) or nil

local function have_bridge()
  return (me ~= nil) or (rs ~= nil)
end

local function bridge_get_item_count(name)
  local ok, res
  if me then ok, res = pcall(me.getItem, {name=name}) ; if ok and type(res)=="table" and res.amount then return res.amount end end
  if rs then ok, res = pcall(rs.getItem, {name=name}) ; if ok and type(res)=="table" and res.amount then return res.amount end end
  return 0
end

local function bridge_export_item(name, amount, target_name, direction)
  if me and me.exportItem then
    local ok, out = pcall(me.exportItem, {name=name}, amount, target_name or direction)
    return ok and out
  end
  if rs and rs.exportItem then
    local ok, out = pcall(rs.exportItem, {name=name}, amount, target_name or direction)
    return ok and out
  end
  return false
end

local function reply(to, msg)
  if to then PRO.send(to, msg) else PRO.broadcast(msg) end
end

print("Supply daemon ready.")
while true do
  local id, msg = rednet.receive()
  if id and type(msg)=="table" and msg._auth == CFG.auth_token then
    if msg.type=="FUEL_REQUEST" then
      local want = tonumber(msg.amount or 0) or 0
      local item = msg.fuel_item or CFG.fuel_item_id
      if not have_bridge() then
        reply(id, PRO.msg_fuel_deny(CFG.auth_token, msg.reactor_id, want, "no_bridge"))
      else
        local avail = bridge_get_item_count(item)
        if avail <= 0 then
          reply(id, PRO.msg_fuel_deny(CFG.auth_token, msg.reactor_id, want, "out_of_stock"))
        else
          local grant = math.min(want, avail)
          local ok = bridge_export_item(item, grant, CFG.export_target_name, CFG.export_direction)
          if ok then
            reply(id, PRO.msg_fuel_confirm(CFG.auth_token, msg.reactor_id, want, grant))
            reply(id, PRO.msg_fuel_done(CFG.auth_token, msg.reactor_id, grant))
          else
            reply(id, PRO.msg_fuel_deny(CFG.auth_token, msg.reactor_id, want, "export_failed"))
          end
        end
      end

    elseif msg.type=="WASTE_DRAIN_REQUEST" then
      -- In vielen Setups zieht der Reaktor Waste über Reprocessor/IO selbständig wenn im Zielinventar Platz ist.
      -- Wir behandeln das wie einen Exportauftrag des Waste-Items AUS dem Reaktor-Port ist nicht möglich via ME-Bridge;
      -- stattdessen erwartet man, dass Waste in einer Chest landet und ME diese einsaugt. Hier ack'n wir minimal.
      local batch = tonumber(msg.amount or 0) or 0
      reply(id, PRO.msg_waste_confirm(CFG.auth_token, msg.reactor_id, batch, batch))
      reply(id, PRO.msg_waste_done(CFG.auth_token, msg.reactor_id, batch))

    elseif msg.type=="REPROC_REQUEST" then
      -- Optional: wenn du Patterns hast, könntest du hier Autocrafting starten.
      -- Wir ack'n minimal „confirm/done“ damit Master die Pipeline sieht.
      local want = tonumber(msg.amount or 0) or 0
      reply(id, PRO.msg_reproc_confirm(CFG.auth_token, want, want))
      reply(id, PRO.msg_reproc_done(CFG.auth_token, want))
    end
  end
end
