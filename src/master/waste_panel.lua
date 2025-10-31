--========================================================
-- /xreactor/master/waste_panel.lua
-- Waste-Management (GUI-Skeleton) mit Topbar
--========================================================
local PROTO = dofile("/xreactor/shared/protocol.lua")

local CFG=(function() local t={ auth_token="xreactor", modem_side="right", ui={text_scale=0.5} }
  if fs.exists("/xreactor/config_waste.lua") then local ok,c=pcall(dofile,"/xreactor/config_waste.lua"); if ok and type(c)=="table" then
    t.auth_token=c.auth_token or t.auth_token; t.modem_side=c.modem_side or t.modem_side; if c.ui then t.ui=c.ui end
  end end; return t end)()

assert(peripheral.getType(CFG.modem_side)=="modem","Kein Modem an "..tostring(CFG.modem_side))
if not rednet.isOpen(CFG.modem_side) then rednet.open(CFG.modem_side) end

local GUI; do local ok,g=pcall(require,"xreactor.shared.gui"); if ok then GUI=g elseif fs.exists("/xreactor/shared/gui.lua") then GUI=dofile("/xreactor/shared/gui.lua") end end
local function load_ui_map() if fs.exists("/xreactor/ui_map.lua") then local ok,t=pcall(dofile,"/xreactor/ui_map.lua"); if ok and type(t)=="table" then return t end end; return {monitors={}, autoscale={enabled=false}} end
local UIMAP=load_ui_map()
local function pick_monitor_for_role(role) local name; for n,cfg in pairs(UIMAP.monitors or {}) do if cfg.role==role then name=n break end end; local mon=name and peripheral.wrap(name) or ({peripheral.find("monitor")})[1]; if not mon then return nil end; local e=(UIMAP.monitors or {})[peripheral.getName(mon)]; local s=e and e.scale or (CFG.ui and CFG.ui.text_scale); if s then pcall(mon.setTextScale, tonumber(s) or 1.0) end; return mon end
local MON=pick_monitor_for_role("waste_service"); if MON and not GUI then pcall(MON.setTextScale, 0.5) end

local Topbar = dofile("/xreactor/shared/topbar.lua")
local TB

local WASTE = {} -- Beispiel-Speicher (uid -> {host, last_seen, info})
local function rx_loop()
  while true do
    local id,msg=rednet.receive(0.5)
    if id and type(msg)=="table" and PROTO.is_auth(msg, CFG.auth_token) then
      -- Hier könnten zukünftige WASTE_TELEM / WASTE_CTRL Statusmeldungen ausgewertet werden
      if msg.type==PROTO.T.TELEM and type(msg.data)=="table" then
        local d=msg.data; WASTE[d.uid or ("id:"..tostring(id))] = { host=msg.hostname, last_seen=os.epoch("utc")/1000, info=string.format("RPM:%d P:%d", tonumber(d.rpm or 0), tonumber(d.power_mrf or 0)) }
      end
    end
  end
end

local function build_gui()
  if not (GUI and MON) then return nil end
  local router=GUI.mkRouter({monitorName=peripheral.getName(MON)})
  local scr=GUI.mkScreen("waste","Waste ▢ Panel")
  TB = Topbar.create({title="Waste ▢ Panel", auth_token=CFG.auth_token, modem_side=CFG.modem_side, monitor_name=peripheral.getName(MON)}); TB:mount(GUI,scr); TB:start_rx()

  local list=GUI.mkList(2,3,78,16,{}); scr:add(list)
  local btnHome=GUI.mkButton(2,20,10,3,"Home", function() shell.run("/xreactor/master/master_home.lua") end, colors.lightGray); scr:add(btnHome)

  scr._redraw=function()
    local rows={}
    for uid,d in pairs(WASTE) do
      table.insert(rows, {text=string.format("%-12s host:%-12s info:%s", tostring(uid), tostring(d.host or "-"), tostring(d.info or "")), color=colors.white})
    end
    if #rows==0 then rows={{text="(Noch keine Daten)", color=colors.gray}} end
    list.props.items=rows; TB:update()
  end

  router:register(scr); router:show("waste")
  return router, scr
end

local function tui_loop()
  if GUI and MON then return end
  while true do
    term.clear(); term.setCursorPos(1,1)
    print("Waste ▢ Panel  "..os.date("%H:%M:%S")); print(string.rep("-",78))
    local c=0; for uid,d in pairs(WASTE) do print(string.format("%-12s host:%-12s %s", tostring(uid), tostring(d.host or "-"), tostring(d.info or ""))); c=c+1 end
    if c==0 then print("(Noch keine Daten)") end
    print(string.rep("-",78)); print("[H] Home  [Q] Quit")
    local e,k=os.pullEvent("key"); if k==keys.q then return elseif k==keys.h then shell.run("/xreactor/master/master_home.lua") end
  end
end

local function gui_loop() if not (GUI and MON) then return end; local router,scr=build_gui(); while true do if scr and scr._redraw then scr._redraw() end; router:draw(); sleep(0.05) end end

print("Waste Panel ▢ gestartet ("..(GUI and MON and "Monitor" or "TUI")..")")
parallel.waitForAny(rx_loop, gui_loop, tui_loop)
