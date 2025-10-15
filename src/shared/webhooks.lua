-- webhooks.lua — send events to Discord/HTTP; fallback to rednet "WEBHOOK_EVENT"
local M = {}

local function http_enabled() return http and http.post end

local function post(url, payload, headers)
  if not http_enabled() then return false, "http_disabled" end
  headers = headers or {["Content-Type"]="application/json"}
  local ok, res = pcall(http.post, url, textutils.serializeJSON(payload), headers)
  if not ok or not res then return false, "request_failed" end
  res.close()
  return true
end

local function fallback_rednet(channel, payload)
  if rednet and rednet.isOpen() then rednet.broadcast({type="WEBHOOK_EVENT", channel=channel, payload=payload}) end
end

function M.send(cfg, channel, event, data)
  if not (cfg and cfg.webhooks_enabled and cfg.webhook_url) then
    fallback_rednet(channel or "default", {event=event, data=data, ts=os.epoch("utc")})
    return false, "disabled"
  end
  local payload = { channel=channel or "default", event=event, data=data, ts=os.epoch("utc") }
  local ok, err = post(cfg.webhook_url, payload, cfg.webhook_headers or {["Content-Type"]="application/json"})
  if not ok then fallback_rednet(channel or "default", payload) end
  return ok, err
end

return M
