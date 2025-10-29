-- /src/shared/gui.lua
-- XReactor • Simple UI Toolkit (PC + Monitor Mirroring)
-- Ziel: übersichtliche, leicht verständliche, gut aussehende Touch-GUIs
-- Kompatibel mit Master/Node

local GUI = {}

------------------------------------------------------------
-- Theme
------------------------------------------------------------
local theme = {
  bg       = colors.black,
  fg       = colors.white,
  accent   = colors.cyan,
  muted    = colors.lightGray,
  danger   = colors.red,
  ok       = colors.lime,
  warn     = colors.orange,
  title    = colors.cyan,
  shadow   = colors.gray,
}

function GUI.theme(t)
  if t then for k,v in pairs(t) do theme[k]=v end end
  return theme
end

------------------------------------------------------------
-- Surface
------------------------------------------------------------
local Surface = {}
Surface.__index = Surface

function Surface.new(termObj, scale)
  local self = setmetatable({}, Surface)
  self.t = termObj or term
  if self.t.setTextScale and scale then self.t.setTextScale(scale) end
  self.w, self.h = self.t.getSize()
  self.clip = {x1=1,y1=1,x2=self.w,y2=self.h}
  return self
end

local function within(x,y,c)
  return x>=c.x1 and x<=c.x2 and y>=c.y1 and y<=c.y2
end

function Surface:clear(bg)
  self.t.setBackgroundColor(bg or theme.bg)
  self.t.clear()
end

function Surface:size()
  return self.w,self.h
end

function Surface:clipTo(x,y,w,h)
  self.clip = {x1=x,y1=y,x2=x+w-1,y2=y+h-1}
end

function Surface:resetClip()
  self.clip = {x1=1,y1=1,x2=self.w,y2=self.h}
end

function Surface:drawText(x,y,txt,fg,bg)
  if not within(x,y,self.clip) then return end
  if bg then self.t.setBackgroundColor(bg) end
  if fg then self.t.setTextColor(fg) end
  self.t.setCursorPos(x,y)
  self.t.write(txt)
end

function Surface:drawHLine(x,y,w,col)
  if y<self.clip.y1 or y>self.clip.y2 then return end
  local sx=math.max(x,self.clip.x1)
  local ex=math.min(x+w-1,self.clip.x2)
  if sx>ex then return end
  self.t.setBackgroundColor(col)
  self.t.setCursorPos(sx,y)
  self.t.write(string.rep(" ", ex-sx+1))
end

function Surface:drawBox(x,y,w,h,col)
  for i=0,h-1 do self:drawHLine(x,y+i,w,col) end
end

------------------------------------------------------------
-- Widgets
------------------------------------------------------------
local Widget = {}
Widget.__index = Widget

function Widget.new(kind,x,y,w,h,props)
  local self=setmetatable({},Widget)
  self.kind, self.x,self.y,self.w,self.h = kind,x,y,w,h
  self.props=props or {}
  self.disabled=false
  self.hidden=false
  self.onTap=nil
  return self
end

function Widget:contains(px,py)
  return (px>=self.x and px<=self.x+self.w-1 and py>=self.y and py<=self.y+self.h-1)
end

local function drawLabel(s,w)
  if w.hidden then return end
  local p=w.props
  s:drawText(w.x,w.y,p.text or "", p.color or theme.fg, p.bg)
end

local function drawButton(s,w)
  if w.hidden then return end
  local p=w.props
  local col=w.disabled and theme.muted or (p.color or theme.accent)
  s:drawBox(w.x,w.y,w.w,w.h,col)
  local tx=w.x+math.max(0, math.floor((w.w-#(p.text or "BTN"))/2))
  local ty=w.y+math.floor((w.h-1)/2)
  s:drawText(tx,ty,p.text or "BTN", theme.bg, col)
end

local function drawProgress(s,w)
  if w.hidden then return end
  local p=w.props
  local val=math.max(0,math.min(1,p.value or 0))
  s:drawBox(w.x,w.y,w.w,1,theme.shadow)
  local fill=math.floor(val*w.w)
  if fill>0 then s:drawBox(w.x,w.y,fill,1,p.color or theme.ok) end
end

local function drawKV(s,w)
  if w.hidden then return end
  local p=w.props
  s:drawText(w.x,w.y,p.key or "", theme.muted)
  local val=tostring(p.value or "")
  local tx=w.x+w.w-#val
  s:drawText(tx,w.y,val,p.color or theme.fg)
end

local painters={ label=drawLabel, button=drawButton, bar=drawProgress, kv=drawKV }

------------------------------------------------------------
-- Screen
------------------------------------------------------------
local Screen = {}
Screen.__index = Screen

function Screen.new(id,title)
  local self=setmetatable({},Screen)
  self.id=id
  self.title=title or id
  self.widgets={}
  self.onShow=nil
  self.onEvent=nil
  return self
end

function Screen:add(w)
  table.insert(self.widgets,w)
  return w
end

function Screen:draw(s)
  local W,H=s:size()
  s:clear(theme.bg)
  s:drawHLine(1,1,W, theme.title)
  local t=" "..self.title.." "
  local tx=math.max(2, math.floor((W-#t)/2))
  s:drawText(tx,1,t, theme.bg, theme.title)
  for _,wg in ipairs(self.widgets) do
    local p=painters[wg.kind]
    if p then p(s,wg) end
  end
end

function Screen:tap(x,y)
  for _,wg in ipairs(self.widgets) do
    if not wg.hidden and not wg.disabled and wg.onTap and wg:contains(x,y) then
      wg.onTap(wg)
      return true
    end
  end
  return false
end

------------------------------------------------------------
-- Router
------------------------------------------------------------
local Router = {}
Router.__index = Router

function Router.new(opts)
  local self=setmetatable({},Router)
  self.screens={}
  self.current=nil
  self.termSurf=Surface.new(term)
  self.monSurf=nil
  if opts and opts.monitorName then
    local mon=peripheral.wrap(opts.monitorName)
    if mon then
      mon.setTextScale(opts.textScale or 0.5)
      self.monSurf=Surface.new(mon, opts.textScale)
    end
  end
  return self
end

function Router:register(s)
  self.screens[s.id]=s
  return s
end

function Router:show(id)
  self.current=self.screens[id]
  if not self.current then return end
  if self.current.onShow then pcall(self.current.onShow,self.current) end
  self:draw()
end

function Router:draw()
  if not self.current then return end
  self.current:draw(self.termSurf)
  if self.monSurf then self.current:draw(self.monSurf) end
end

function Router:handleTouch(e,p1,p2,p3)
  if not self.current then return end
  local isMon=(e=="monitor_touch")
  local s=isMon and self.monSurf or self.termSurf
  if not s then return end
  local x,y=(isMon and p2 or p1),(isMon and p3 or p2)
  local handled=self.current:tap(x,y)
  if handled then self:draw() end
  if self.current.onEvent then
    local ok,redraw=pcall(self.current.onEvent,self.current,e,p1,p2,p3)
    if ok and redraw then self:draw() end
  end
end

------------------------------------------------------------
-- Factory-Funktionen
------------------------------------------------------------
function GUI.mkScreen(id,title) return Screen.new(id,title) end
function GUI.mkLabel(x,y,text,props) return Widget.new("label",x,y,#text,1,{text=text,color=props and props.color,bg=props and props.bg}) end
function GUI.mkButton(x,y,w,h,text,onTap,color) local b=Widget.new("button",x,y,w,h,{text=text,color=color}); b.onTap=onTap; return b end
function GUI.mkBar(x,y,w,color) return Widget.new("bar",x,y,w,1,{value=0,color=color}) end
function GUI.mkKV(x,y,w,key,color) return Widget.new("kv",x,y,w,1,{key=key,value="",color=color}) end
function GUI.mkRouter(opts) return Router.new(opts or {}) end

------------------------------------------------------------
-- Quick-Run App (optional)
------------------------------------------------------------
function GUI.run(app)
  local r=app.router or GUI.mkRouter({monitorName=app.monitor,textScale=app.textScale})
  GUI.router=r
  GUI.onNav=function(id) r:show(id) end
  r:show(app.init or "master")
  while true do
    local e,p1,p2,p3=os.pullEvent()
    if e=="term_resize" then r:draw()
    elseif e=="mouse_click" or e=="monitor_touch" then r:handleTouch(e,p1,p2,p3)
    end
  end
end

return GUI
