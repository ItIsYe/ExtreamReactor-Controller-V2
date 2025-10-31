-- /xreactor/shared/gui.lua
-- Kompatibler GUI-Shim für MASTER-UI
-- Stellt GUI.mkRouter(...) bereit und bietet einfache Zeichen-Helfer.

local M = {}

-- Monitor (oder Terminal) auswählen
local function resolveMonitor(name)
  local dev
  if type(name) == "string" and name ~= "" then
    pcall(function() dev = peripheral.wrap(name) end)
  end
  if not dev then
    dev = peripheral.find("monitor")
  end
  if not dev then
    dev = term.current()
  end
  return dev
end

-- Router-Objekt mit Monitor/Terminal-API
function M.mkRouter(opts)
  opts = opts or {}
  local dev = resolveMonitor(opts.monitorName or opts.monitor_side)

  local router = { dev = dev }

  function router:setTextScale(s)
    if self.dev.setTextScale then pcall(self.dev.setTextScale, s or 0.5) end
  end

  function router:getSize()
    if self.dev.getSize then return self.dev.getSize() end
    return term.getSize()
  end

  function router:clear()
    if self.dev.clear then self.dev.clear() else term.clear() end
    if self.dev.setCursorPos then self.dev.setCursorPos(1,1) else term.setCursorPos(1,1) end
  end

  function router:setCursorPos(x,y)
    if self.dev.setCursorPos then self.dev.setCursorPos(x,y) else term.setCursorPos(x,y) end
  end

  function router:write(txt)
    txt = tostring(txt or "")
    if self.dev.write then self.dev.write(txt) else term.write(txt) end
  end

  function router:blit(a,b,c)
    if self.dev.blit then self.dev.blit(a,b,c) else self:write(a) end
  end

  function router:setTextColor(c)
    if self.dev.setTextColor then self.dev.setTextColor(c) end
  end

  function router:setBackgroundColor(c)
    if self.dev.setBackgroundColor then self.dev.setBackgroundColor(c) end
  end

  function router:printAt(x,y,txt)
    self:setCursorPos(x,y)
    self:write(txt)
  end

  function router:center(y,txt)
    local w = select(1, self:getSize())
    local s = tostring(txt or "")
    local x = math.max(1, math.floor((w - #s)/2) + 1)
    self:printAt(x,y,s)
  end

  return router
end

-- ===== Kompatibilitäts-Helfer auf einem Default-Router =====
local _default = M.mkRouter({})

function M.init() end

function M.clear()
  _default:clear()
end

function M.writeAt(x,y,text)
  _default:printAt(x,y,text)
end

function M.center(y,text)
  _default:center(y,text)
end

function M.bar(x,y,width,fill)
  width = math.max(3, width or 10)
  fill  = math.max(0, math.min(1, fill or 0))
  _default:setCursorPos(x,y); _default:write("[")
  local filled = math.floor((width-2)*fill)
  for i=1,width-2 do
    if i <= filled then _default:write("#") else _default:write(" ") end
  end
  _default:write("]")
end

function M.button(x,y,label)
  local txt = "["..tostring(label or "").."]"
  _default:printAt(x,y,txt)
  return {x=x,y=y,w=#txt,h=1,label=label}
end

function M.loop(stepFn,tick)
  tick = tick or 0.2
  while true do
    if type(stepFn) == "function" then
      local ok, err = pcall(stepFn)
      if not ok then
        pcall(function()
          local log = require("xreactor.shared.log")
          if log and log.error then log.error("GUI loop error: "..tostring(err)) end
        end)
      end
    end
    sleep(tick)
  end
end

return M
