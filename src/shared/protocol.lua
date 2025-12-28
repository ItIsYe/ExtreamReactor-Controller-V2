--========================================================
-- /xreactor/shared/protocol.lua
-- Zentrale Protokollversion, Auth, Nachrichtentypen, Identity-Helpers
--========================================================
local P = {}

P.PROTO_VERSION = "1.1.0"                     -- Version der Draht-Protokoll-Struktur
P.AUTH_TOKEN_DEFAULT = "xreactor"             -- Standard-Token (via config überschreibbar)

P.T = {
  HELLO        = "HELLO",
  NODE_HELLO   = "NODE_HELLO",
  NODE_STATE   = "NODE_STATE",
  TELEM        = "TELEM",
  HEARTBEAT    = "HEARTBEAT",
  STATE_UPDATE = "STATE_UPDATE",
  TARGET_UPDATE= "TARGET_UPDATE",
  FUEL_CTRL    = "FUEL_CTRL",
  FUEL_STATUS  = "FUEL_STATUS",
  WASTE_CTRL   = "WASTE_CTRL",
  WASTE_TELEM  = "WASTE_TELEM",
  ALARM        = "ALARM",
  MASTER_ELECTION = "MASTER_ELECTION",
  MASTER_ANNOUNCE = "MASTER_ANNOUNCE",
}

function P.tag(msg, auth)                     -- Auth + Version anfügen
  msg = msg or {}
  msg._auth = auth or P.AUTH_TOKEN_DEFAULT
  msg._v    = P.PROTO_VERSION
  return msg
end

function P.is_auth(msg, expect)               -- Auth prüfen
  return type(msg)=="table" and msg._auth == (expect or P.AUTH_TOKEN_DEFAULT)
end

function P.attach_identity(msg, ident)        -- Identity anfügen (role/id/hostname/cluster)
  if type(msg)~="table" then msg={} end
  if type(ident)=="table" then
    msg.role     = ident.role
    msg.id       = ident.id
    msg.hostname = ident.hostname
    msg.cluster  = ident.cluster
  end
  return msg
end

-- Convenience-Erzeuger mit Identity
function P.make_hello(ident)       return P.attach_identity({ type=P.T.HELLO }, ident) end
function P.make_node_hello(ident, extra)
  local m={ type=P.T.NODE_HELLO }; if type(extra)=="table" then for k,v in pairs(extra) do m[k]=v end end
  return P.attach_identity(m, ident)
end
function P.make_telem(ident, data_tbl)
  return P.attach_identity({ type=P.T.TELEM, data=data_tbl or {} }, ident)
end

function P.make_heartbeat(ident, data_tbl)
  return P.attach_identity({ type=P.T.HEARTBEAT, data=data_tbl or {} }, ident)
end

function P.make_state_update(ident, data_tbl)
  return P.attach_identity({ type=P.T.STATE_UPDATE, data=data_tbl or {} }, ident)
end

function P.make_target_update(ident, data_tbl)
  return P.attach_identity({ type=P.T.TARGET_UPDATE, data=data_tbl or {} }, ident)
end

function P.make_master_announce(ident, data_tbl)
  return P.attach_identity({ type=P.T.MASTER_ANNOUNCE, data=data_tbl or {} }, ident)
end

function P.make_master_election(ident, data_tbl)
  return P.attach_identity({ type=P.T.MASTER_ELECTION, data=data_tbl or {} }, ident)
end

-- Alarm-Helfer
function P.make_alarm(level, code, text, node, uid)
  return { type=P.T.ALARM, level=string.upper(level or "INFO"), code=tostring(code or "?"), msg=text or "", node=node, uid=uid }
end

return P

