--========================================================
-- /xreactor/master/alarm_center.lua
-- Zentrale Alarmansicht mit Topbar + Liste + Quittierung (lokal)
--========================================================
local PROTO = dofile("/xreactor/shared/protocol.lua")

local CFG=(function() local t={ auth_token="xreactor", modem_side="right", ui={text_scale=0.5} }
  if fs.exists("/xreactor/config_alarm.lua") then local ok,c=pcall(dofile,"/xreactor/config_alarm.lua"); if ok and type(c)=="table" then
    t.auth_token=c.auth_token or t.auth_token; t.modem_side=c.modem_side or t.modem_side; if c.ui then t.ui=c.ui end
  end end; return t end)()

assert(peripheral.getType(CFG.modem_side)=="modem","Kein Modem an "..tostring(CFG.modem_side))
if not rednet.isOpen(CFG.modem_side) then rednet.open(CFG.modem_side) end

local GUI; do local ok,g=pcall(require,"xreactor.shared.gui"); if ok then GUI=g elseif fs.exists("/xreactor/shared/gui.lua") then GUI=dofile("/xreactor/shared/gui.lua") end end
local function load_ui_map() if fs.exists("/xreactor/ui_map.lua") then local ok,t=pcall(dofile,"/xreactor/ui_map.lua"); if ok and type(t)=="table" then return t end end; return {monitors={}, autoscale={enabled=false}} end
local UIMAP=load_ui_map()
local function pick_monitor_for_role(role) local name; for n,cfg in pairs(UIMAP.monitors or {}) do if cfg.role==role then name=n break end end; local mon=name and peripheral.wrap(name) or ({peripheral.find("monitor")})[1]; if not mon then return nil end; local e=(UIMAP.monitors or {})[peripheral.getName(mon)]; local s=e and e.scale or (CFG.ui and CFG.ui.text_scale); if s then pcall(mon.setTextScale, tonumber(s) or 1.0) end; return mon end
local MON=pick_monitor_for_role("alarm_center"); if MON and not GUI then pcall(MON.setTextScale, 0.5) end

local Topbar = dofile("/xreactor/shared/topbar.lua")
local TB

local ALARMS = {} -- { {ts, level, code, msg, node, uid}, ... }
local function push_alarm(a) table.insert(ALARMS, 1, a); if #ALARMS>100 then table.remove(ALARMS) end end

local function rx_loop()
  while true do
    local id,msg = rednet.receive(0.5)
    if id and type(msg)=="table" and PROTO.is_auth(msg, CFG.auth_token) and msg.type=="ALARM" then
      push_alarm({ ts=os.date("%H:%M:%S"), level=string.upper(msg.level or "INFO"), code=msg.code or "?", msg=msg.msg or "", node=msg.node or "-", uid=msg.uid or "-" })
    end
  end
end

local function build_gui()
  if not (GUI and MON) then return nil end
  local router=GUI.mkRouter({monitorName=peripheral.getName(MON)})
  local scr=GUI.mkScreen("alarm","Alarm ▢ Center")
  TB = Topbar.create({title="Alarm ▢ Center", auth_token=CFG.auth_token, modem_side=CFG.modem_side, monitor_name=peripheral.getName(MON)}); TB:mount(GUI,scr); TB:start_rx()

  local lst=GUI.mkList(2,3,78,16,{}); scr:add(lst)
  local btnAck = GUI.mkButton(2,20,12,3,"Quittieren", function() ALARMS={} end, colors.gray); scr:add(btnAck)
  local btnHome= GUI.mkButton(16,20,10,3,"Home", function() shell.run("/xreactor/master/master_home.lua") end, colors.lightGray); scr:add(btnHome)

  scr._redraw=function()
    local rows={}
    if #ALARMS==0 then rows={{text="(Keine Alarme)", color=colors.lightGray}}
    else
      for _,a in ipairs(ALARMS) do
        local color = (a.level=="CRIT" and colors.red) or (a.level=="WARN" and colors.orange) or colors.white
        local line = string.format("%s [%s] %s %-8s %s", a.ts, a.level, a.code, a.node or "-", a.msg or "")
        table.insert(rows, {text=line, color=color})
      end
    end
    lst.props.items=rows; TB:update()
  end

  router:register(scr); router:show("alarm")
  return router, scr
end

local function tui_loop()
  if GUI and MON then return end
  while true do
    term.clear(); term.setCursorPos(1,1)
    print("Alarm ▢ Center  "..os.date("%H:%M:%S")); print(string.rep("-",78))
    for _,a in ipairs(ALARMS) do print(string.format("%s [%s] %s %s", a.ts, a.level, a.code or "?", a.msg or "")) end
    if #ALARMS==0 then print("(Keine Alarme)") end
    print(string.rep("-",78)); print("[C] Clear  [H] Home  [Q] Quit")
    local e,k=os.pullEvent("key")
    if k==keys.q then return elseif k==keys.c then ALARMS={} elseif k==keys.h then shell.run("/xreactor/master/master_home.lua") end
  end
end

local function gui_loop() if not (GUI and MON) then return end; local router,scr=build_gui(); while true do if scr and scr._redraw then scr._redraw() end; router:draw(); sleep(0.05) end end

print("Alarm Center ▢ gestartet ("..(GUI and MON and "Monitor" or "TUI")..")")
parallel.waitForAny(rx_loop, gui_loop, tui_loop)

