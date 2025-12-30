--========================================================
-- /xreactor/shared/protocol.lua
-- Zentrale Protokollversion, Auth, Nachrichtentypen, Identity-Helpers
--========================================================
local P = {}

P.PROTO_VERSION = "1.2.0"                     -- Version der Draht-Protokoll-Struktur
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

-- Kern-Nachrichtentypen (Akzeptanzvorgaben)
P.MSG = {
  HELLO = P.T.HELLO,
  HEARTBEAT = P.T.HEARTBEAT,
  STATE_UPDATE = P.T.STATE_UPDATE,
  TARGET_UPDATE = P.T.TARGET_UPDATE,
  ALARM = P.T.ALARM,
  MASTER_ELECTION = P.T.MASTER_ELECTION,
  MASTER_ANNOUNCE = P.T.MASTER_ANNOUNCE,
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
    msg.priority = ident.priority
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

local function normalize_severity(raw)
  local s = tostring(raw or "INFO"):upper()
  if s == "CRIT" then return "CRITICAL" end
  if s == "WARNING" then return "WARN" end
  if s ~= "WARN" and s ~= "CRITICAL" then return "INFO" end
  return s
end

local function make_alarm_id(source, ts)
  source = tostring(source or "node")
  ts = tonumber(ts) or os.epoch('utc')
  return string.format("ALARM-%s-%d-%04d", source, ts, math.random(0,9999))
end

-- Alarm-Helfer
-- Alarme sind passive Signale und dürfen keine direkten Steueraktionen auslösen.
-- Sie tragen immer eine eindeutige ID, Quell-Node, Schweregrad und Zeitstempel.
function P.make_alarm(arg1, message, source_node_id, alarm_id, timestamp)
  local opts = {}
  if type(arg1) == 'table' then
    for k,v in pairs(arg1) do opts[k]=v end
  else
    opts.severity = arg1
    opts.message = message
    opts.source_node_id = source_node_id
    opts.alarm_id = alarm_id
    opts.timestamp = timestamp
  end

  local ts = tonumber(opts.timestamp or opts.ts) or os.epoch('utc')
  local src = opts.source_node_id or opts.node or opts.source or opts.uid or "-"
  local alarm_uid = opts.alarm_id or opts.uid or make_alarm_id(src, ts)
  local severity = normalize_severity(opts.severity or opts.level)
  local msg = tostring(opts.message or opts.msg or opts.text or opts.code or "")

  local alarm = {
    type = P.T.ALARM,
    alarm_id = alarm_uid,
    source_node_id = src,
    severity = severity,
    message = msg,
    timestamp = ts,
  }

  if opts.code then alarm.code = tostring(opts.code) end
  if opts.details and type(opts.details) == 'table' then alarm.details = opts.details end

  return alarm
end

return P

