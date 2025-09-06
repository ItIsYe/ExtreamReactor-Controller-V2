local G = {}
local U = require("util")


local function bestMonitor()
local mons = U.findMonitors()
return mons[1]
end


function G.attach()
local mon = bestMonitor()
local scr = term.current()
if mon then mon.setTextScale(0.5); mon.clear(); term.redirect(mon) end
term.setCursorBlink(false)
term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.clear()
return scr, mon
end


local function readLine(x,y,init)
term.setCursorPos(x,y); term.setCursorBlink(true)
local s = init or ""
write(s)
while true do
local e,p = os.pullEvent()
if e=="char" then s=s..p; write(p)
elseif e=="key" then
if p==keys.enter then term.setCursorBlink(false); return s
elseif p==keys.backspace and #s>0 then
local cx = ({term.getCursorPos()})[1]; term.setCursorPos(cx-1,y); write(" "); term.setCursorPos(cx-1,y); s=s:sub(1,-2)
end
end
end
end


function G.form(title, spec, data)
term.clear()
local w,h = term.getSize()
term.setCursorPos(1,1); write(title)
local y=3
for i,f in ipairs(spec) do
term.setCursorPos(2,y); write(f.label..": ")
local val = data[f.key]
if f.type=="toggle" then write((val and "ON" or "OFF").." [SPACE]")
else write(tostring(val or "")) end
y=y+1
end
term.setCursorPos(1,h-1); write("[ENTER]=Bearbeiten [TAB]=Weiter [S]=Speichern [Q]=Zurück")


local idx=1
local function redraw(i)
local yy = 2+i
term.setCursorPos(2,yy); term.clearLine();
local f = spec[i]
write(f.label..": ")
if f.type=="toggle" then write((data[f.key] and "ON" or "OFF").." [SPACE]") else write(tostring(data[f.key] or "")) end
end


while true do
local e,k = os.pullEvent("key")
if k==keys.tab then idx=(idx % #spec)+1
elseif k==keys.enter then
local f=spec[idx]; local yy=2+idx
if f.type=="toggle" then data[f.key]=not data[f.key]
elseif f.type=="number" or f.type=="text" then
term.setCursorPos(2,yy); term.clearLine(); write(f.label..": ")
local s = readLine(2+#f.label+2, yy, tostring(data[f.key] or ""))
if f.type=="number" then data[f.key]=tonumber(s) or data[f.key] else data[f.key]=s end
elseif f.type=="list" then
term.setCursorPos(2,yy); term.clearLine(); write(f.label..": (Komma)")
local s = readLine(2+#f.label+10, yy, table.concat(data[f.key] or {}, ","))
local arr={}; for part in string.gmatch(s,"[^,]+") do local t=part:gsub("^%s+",""):gsub("%s+$",""); if #t>0 then table.insert(arr,t) end end
data[f.key]=arr
end
redraw(idx)
elseif k==keys.s then return "save", data
elseif k==keys.q or k==keys.escape then return "quit" end
end
end


return G
