-- /xreactor/shared/gui.lua
-- Minimaler GUI-Shim: bietet ein paar häufig genutzte Calls, fällt auf term zurück, wenn kein Monitor existiert.
local M = {}

local monitor, termBlit = nil, term.current()
local cfg = nil

local function findMonitor(side)
  if side and peripheral.getType(side) == "monitor" then return peripheral.wrap(side) end
  return peripheral.find("monitor")
end

local function setTextScale(mon, scale)
  if mon and mon.setTextScale then
    local ok = pcall(function() mon.setTextScale(scale or 0.5) end)
    if not ok then pcall(function() mon.setTextScale(0.5) end) end
  end
end

function M.init()
  local ok, cm = pcall(function() return require("xreactor.config_master") end)
  cfg = ok and type(cm)=="table" and cm or { text_scale = 0.5 }
  monitor = findMonitor(cfg.monitor_side)
  if monitor then
    setTextScale(monitor, cfg.text_scale or 0.5)
    monitor.setBackgroundColor(colors.black)
    monitor.setTextColor(colors.white)
    monitor.clear()
  else
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
  end
end

local function w() return monitor or termBlit end

function M.clear()
  w().setBackgroundColor(colors.black)
  w().setTextColor(colors.white)
  w().clear()
  w().setCursorPos(1,1)
end

function M.writeAt(x, y, text)
  local dev = w()
  dev.setCursorPos(math.floor(x), math.floor(y))
  dev.write(tostring(text))
end

function M.center(y, text)
  local dev = w()
  local W = dev.getSize and select(1, dev.getSize()) or term.getSize()
  local tx = tostring(text)
  local x = math.max(1, math.floor((W - #tx)/2)+1)
  dev.setCursorPos(x, y)
  dev.write(tx)
end

function M.bar(x, y, width, fill)
  width = math.max(3, width or 10)
  fill  = math.max(0, math.min(1, fill or 0))
  local dev = w()
  dev.setCursorPos(x, y); dev.write("[")
  for i=1,width-2 do
    if i <= math.floor((width-2)*fill) then dev.write("#") else dev.write(" ") end
  end
  dev.write("]")
end

function M.button(x, y, label)
  local dev = w()
  local txt = "["..tostring(label).."]"
  dev.setCursorPos(x, y); dev.write(txt)
  -- Dummy-Rückgabe: Bounding Box, falls dein Code damit rechnet
  return {x=x, y=y, w=#txt, h=1, label=label}
end

-- Einfache Event-Loop (non-blocking Callback)
function M.loop(stepFn, tick)
  tick = tick or 0.2
  while true do
    if type(stepFn) == "function" then
      local ok, err = pcall(stepFn)
      if not ok then
        -- nicht crashen; minimal loggen (falls verfügbar)
        local logOk, log = pcall(function() return require("xreactor.shared.log") end)
        if logOk and log and type(log.error)=="function" then
          pcall(log.error, "GUI loop error: "..tostring(err))
        end
      end
    end
    sleep(tick)
  end
end

return M
