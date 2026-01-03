-- /xreactor/shared/gui.lua
-- Kompatibler GUI-Shim für MASTER-UI
-- Stellt GUI.mkRouter(...) bereit und bietet einfache Zeichen-Helfer.

local TEXT_UTILS_PATH = "/xreactor/shared/text.lua"
local text_utils = nil

do
  if not (fs and fs.exists and fs.exists(TEXT_UTILS_PATH)) then
    error("Unable to locate text utilities (text.lua) at " .. TEXT_UTILS_PATH)
  end

  local ok, mod = pcall(dofile, TEXT_UTILS_PATH)
  if not ok or not mod then
    error("Unable to load text utilities from " .. TEXT_UTILS_PATH .. ": " .. tostring(mod))
  end

  text_utils = mod
end

local function sanitizeText(text)
  if text_utils and text_utils.sanitizeText then
    return text_utils.sanitizeText(text)
  end
  return tostring(text or "")
end

local M = {}

-- ===== Monitor autoscale =====
local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function round_to_step(value, step)
  if not step or step <= 0 then return value end
  return math.floor((value / step) + 0.5) * step
end

--- Compute and apply a readable text scale based on the monitor resolution.
-- Prefers larger text on large displays while keeping columns/rows within a
-- comfortable range. Scale is clamped to CC:Tweaked limits and reapplied on
-- demand.
-- @param dev monitor/terminal peripheral
-- @param opts table {name, fixed_scale, min_cols, max_cols, min_rows, max_rows, min_scale, max_scale, step}
-- @return number|nil applied scale or nil if unavailable
function M.apply_text_scale(dev, opts)
  opts = opts or {}
  if not (dev and dev.setTextScale and dev.getSize) then return nil end

  local min_cols = tonumber(opts.min_cols) or 40
  local max_cols = tonumber(opts.max_cols) or 80
  local min_rows = tonumber(opts.min_rows) or 15
  local max_rows = tonumber(opts.max_rows) or 30
  local min_scale = clamp(tonumber(opts.min_scale) or 0.5, 0.5, 5)
  local max_scale = clamp(tonumber(opts.max_scale) or 5, min_scale, 5)
  local step = tonumber(opts.step) or 0.5
  if step <= 0 then step = 0.5 end

  local fixed = opts.fixed_scale
  if fixed then
    local forced = clamp(tonumber(fixed) or 1.0, min_scale, max_scale)
    pcall(dev.setTextScale, forced)
    return forced
  end

  pcall(dev.setTextScale, 1)
  local base_w, base_h = dev.getSize()
  if not (base_w and base_h) then return nil end

  local target_w = base_w
  if base_w > max_cols then target_w = max_cols end
  if base_w < min_cols then target_w = base_w end

  local target_h = base_h
  if base_h > max_rows then target_h = max_rows end
  if base_h < min_rows then target_h = base_h end

  local scale_w = base_w / (target_w > 0 and target_w or base_w)
  local scale_h = base_h / (target_h > 0 and target_h or base_h)
  local target_scale = clamp(math.max(scale_w, scale_h, min_scale), min_scale, max_scale)
  target_scale = clamp(round_to_step(target_scale, step), min_scale, max_scale)

  pcall(dev.setTextScale, target_scale)
  return target_scale
end

--- Backward compatible alias used by legacy callers.
function M.autoscale(dev, opts)
  return M.apply_text_scale(dev, opts)
end

-- ===== Primitive UI components =====
local function mkLabel(x, y, text, opts)
  local props = {
    x = x or 1,
    y = y or 1,
    text = text or "",
    color = opts and opts.color or colors.white,
    bg = opts and opts.bg or nil,
  }

  local el = { kind = "label", props = props }

  function el:draw(router)
    if not router then return end
    if self.props.bg and router.setBackgroundColor then router:setBackgroundColor(self.props.bg) end
    if router.setTextColor and self.props.color then router:setTextColor(self.props.color) end
    router:printAt(self.props.x, self.props.y, self.props.text)
  end

  return el
end

local function mkButton(x, y, w, h, label, handler, bg)
  local props = {
    x = x or 1,
    y = y or 1,
    w = math.max(1, w or 1),
    h = math.max(1, h or 1),
    label = label or "",
    bg = bg or colors.gray,
  }

  local el = { kind = "button", props = props, onClick = handler }

  local function contains(px, py)
    return px >= props.x and px <= props.x + props.w - 1 and py >= props.y and py <= props.y + props.h - 1
  end

  function el:draw(router)
    if not router then return end
    if router.setBackgroundColor then router:setBackgroundColor(props.bg) end
    if router.setTextColor then router:setTextColor(colors.white) end
    for dy = 0, props.h - 1 do
      router:setCursorPos(props.x, props.y + dy)
      router:write(string.rep(" ", props.w))
    end
    local lbl = sanitizeText(props.label)
    local lx = math.max(props.x, props.x + math.floor((props.w - #lbl) / 2))
    local ly = props.y + math.floor((props.h - 1) / 2)
    router:printAt(lx, ly, lbl)
  end

  function el:handleEvent(ev)
    local et = ev and ev[1]
    if et == "monitor_touch" then
      local px, py = ev[3], ev[4]
      if contains(px, py) and type(self.onClick) == "function" then pcall(self.onClick) end
    elseif et == "mouse_click" then
      local px, py = ev[3], ev[4]
      if contains(px, py) and type(self.onClick) == "function" then pcall(self.onClick) end
    end
  end

  return el
end

local function mkList(x, y, w, h, items)
  local props = {
    x = x or 1,
    y = y or 1,
    w = math.max(1, w or 1),
    h = math.max(1, h or 1),
    items = items or {},
  }

  local el = { kind = "list", props = props }

  function el:draw(router)
    if not router then return end
    for i = 1, props.h do
      local entry = props.items[i]
      local txt = ""
      local color = colors.white
      if type(entry) == "table" then
        txt = sanitizeText(entry.text or "")
        color = entry.color or color
      else
        txt = sanitizeText(entry)
      end

      if router.setTextColor then router:setTextColor(color) end
      if router.setCursorPos then router:setCursorPos(props.x, props.y + i - 1) end
      router:write(string.sub(txt .. string.rep(" ", props.w), 1, props.w))
    end
  end

  return el
end

-- ===== Screen / Router primitives =====
local function mkScreen(id, title)
  local scr = { id = id or "screen", title = title or id or "", elements = {} }

  function scr:add(el)
    table.insert(self.elements, el)
    return el
  end

  function scr:draw(router)
    if not router then return end
    router:clear()
    for _, el in ipairs(self.elements) do
      if el and el.draw then el:draw(router) end
    end
  end

  function scr:handleEvent(ev)
    for _, el in ipairs(self.elements) do
      if el and el.handleEvent then el:handleEvent(ev) end
    end
  end

  return scr
end

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
  local monitor_name = opts.monitorName or (peripheral and peripheral.getName and dev and peripheral.getName(dev)) or nil
  local fixed_scale = opts.text_scale or opts.scale
  local autoscale_opts = opts.autoscale
  if autoscale_opts == true or autoscale_opts == nil then autoscale_opts = {} end
  if autoscale_opts == false then autoscale_opts = nil end

  if dev then
    pcall(M.apply_text_scale, dev, {
      name = monitor_name,
      fixed_scale = fixed_scale,
      min_cols = autoscale_opts and autoscale_opts.min_cols or nil,
      max_cols = autoscale_opts and autoscale_opts.max_cols or nil,
      min_rows = autoscale_opts and autoscale_opts.min_rows or nil,
      max_rows = autoscale_opts and autoscale_opts.max_rows or nil,
      min_scale = autoscale_opts and (autoscale_opts.min_scale or autoscale_opts.min) or nil,
      max_scale = autoscale_opts and (autoscale_opts.max_scale or autoscale_opts.max) or nil,
      step = autoscale_opts and autoscale_opts.step or nil,
    })
  end

  local router = { dev = dev, screens = {}, current = nil }

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
    txt = sanitizeText(txt)
    if self.dev.write then self.dev.write(txt) else term.write(txt) end
  end

  function router:blit(a,b,c)
    local txt = sanitizeText(a or "")
    local fg = b or string.rep("0", #txt)
    local bg = c or string.rep("f", #txt)
    if #fg < #txt then fg = fg .. string.rep(fg:sub(#fg, #fg), #txt - #fg) end
    if #bg < #txt then bg = bg .. string.rep(bg:sub(#bg, #bg), #txt - #bg) end
    fg = fg:sub(1, #txt)
    bg = bg:sub(1, #txt)
    if self.dev.blit then self.dev.blit(txt, fg, bg) else self:write(txt) end
  end

  function router:setTextColor(c)
    if self.dev.setTextColor then self.dev.setTextColor(c) end
  end

  function router:setBackgroundColor(c)
    if self.dev.setBackgroundColor then self.dev.setBackgroundColor(c) end
  end

  function router:printAt(x,y,txt)
    self:setCursorPos(x,y)
    self:write(sanitizeText(txt))
  end

  function router:center(y,txt)
    local w = select(1, self:getSize())
    local s = sanitizeText(txt)
    local x = math.max(1, math.floor((w - #s)/2) + 1)
    self:printAt(x,y,s)
  end

  function router:register(screen)
    if screen and screen.id then self.screens[screen.id] = screen end
  end

  function router:show(id)
    if type(id) == "table" then
      self.current = id
    else
      self.current = self.screens[id]
    end
    self:draw()
  end

  function router:draw()
    if self.current and self.current.draw then self.current:draw(self) end
  end

  function router:handleEvent(ev)
    if not ev then return end
    if ev[1] == "monitor_resize" or ev[1] == "monitor_resized" or ev[1] == "term_resize" then
      if not ev[2] or not monitor_name or ev[2] == monitor_name then
        pcall(M.apply_text_scale, self.dev, {
          name = monitor_name,
          fixed_scale = fixed_scale,
          min_cols = autoscale_opts and autoscale_opts.min_cols or nil,
          max_cols = autoscale_opts and autoscale_opts.max_cols or nil,
          min_rows = autoscale_opts and autoscale_opts.min_rows or nil,
          max_rows = autoscale_opts and autoscale_opts.max_rows or nil,
          min_scale = autoscale_opts and (autoscale_opts.min_scale or autoscale_opts.min) or nil,
          max_scale = autoscale_opts and (autoscale_opts.max_scale or autoscale_opts.max) or nil,
          step = autoscale_opts and autoscale_opts.step or nil,
        })
      end
    end
    if self.current and self.current.handleEvent then self.current:handleEvent(ev) end
  end

  return router
end

M.mkScreen = mkScreen
M.mkLabel  = mkLabel
M.mkButton = mkButton
M.mkList   = mkList

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
