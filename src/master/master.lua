--==========================================================
-- XReactor ◈ MASTER (with Detail Control Buttons)
--==========================================================

local CFG = {
  modem_side       = "right",
  monitor_side     = nil,
  auth_token       = "xreactor",
  telem_timeout    = 15,
  redraw_interval  = 0.3,
}
do local ok,user=pcall(dofile,"/xreactor/config_master.lua"); if ok and type(user)=="table" then for k,v in pairs(user) do CFG[k]=v end end end

assert(peripheral.getType(CFG.modem_side)=="modem","No modem on "..tostring(CFG.modem_side))
rednet.open(CFG.modem_side)
local MASTER_ID = os.getComputerID()

-- Screen helpers
local mon
local function bind_monitor()
  if CFG.monitor_side and peripheral.isPresent(CFG.monitor_side) and peripheral.getType(CFG.monitor_side)=="monitor" then
    mon=peripheral.wrap(CFG.monitor_side)
    local w,h=mon.getSize(); if w>=120 then mon.setTextScale(0.5) elseif w>=60 then mon.setTextScale(0.75) else mon.setTextScale(1) end
  else mon=nil end
end
bind_monitor()
local function T() return mon or term end
local function size() local w,h=T().getSize(); return w,h end
local function cls() local t=T(); t.setBackgroundColor(colors.black); t.setTextColor(colors.white); t.clear(); t.setCursorPos(1,1) end
local function printl(s) local t=T(); local x,y=t.getCursorPos(); local w=t.getSize(); if #s>w then s=s:sub(1,w) end; t.write(s); t.setCursorPos(1,y+1) end
local function setpos(x,y) T().setCursorPos(x,y) end
local function write(s) T().write(s) end
local function fmt(n) if n==nil then return "-" end return tostring(math.floor(n+0.5)) end
local function age_sec(ms) return math.floor((os.epoch("utc")-(ms or 0))/1000) end

-- Data
local nodes={}
local view="list"           -- "list" | "detail"
local rowmap={}             -- y->node_id
local table_y0=0
local selected_id=nil
local detail_scroll=0
local ui_msg=""             -- status messages (ACK etc.)
local ui_msg_ts=0

local function mark_timeouts()
  for id,n in pairs(nodes) do n.offline = age_sec(n.last_ms or 0) > (CFG.telem_timeout or 15) end
end

local function total_agg()
  local A={node_cnt=0,node_on=0,reactors={count=0,active=0,hot=0,energy=0,fuel=0,fuel_max=0},turbines={count=0,active=0,rpm=0,flow=0,flow_max=0,prod=0}}
  for _,n in pairs(nodes) do
    A.node_cnt=A.node_cnt+1; if not n.offline then A.node_on=A.node_on+1 end
    local ag=n.telem and n.telem.agg
    if ag then
      for k,v in pairs(ag.reactors or {}) do A.reactors[k]=(A.reactors[k] or 0)+(v or 0) end
      for k,v in pairs(ag.turbines or {}) do A.turbines[k]=(A.turbines[k] or 0)+(v or 0) end
    end
  end
  return A
end

-- Drawing: List
local function count_nodes() local c=0 for _ in pairs(nodes) do c=c+1 end return c end
local function draw_list()
  cls()
  printl(("Master #%d | Modem:%s | Monitor:%s"):format(MASTER_ID, CFG.modem_side, CFG.monitor_side or "-"))
  printl(("Auth:%s | Timeout:%ss | Nodes:%d"):format(CFG.auth_token, CFG.telem_timeout or 15, count_nodes()))
  printl("")
  local A=total_agg()
  printl(("R: act %d/%d hot %s fuel %s/%s E %s"):format(A.reactors.active,A.reactors.count,fmt(A.reactors.hot),fmt(A.reactors.fuel),fmt(A.reactors.fuel_max),fmt(A.reactors.energy)))
  printl(("T: act %d/%d rpm %s flow %s/%s prod %s/t"):format(A.turbines.active,A.turbines.count,fmt(A.turbines.rpm),fmt(A.turbines.flow),fmt(A.turbines.flow_max),fmt(A.turbines.prod)))
  printl("")
  local w,_=size()
  printl("ID   | age | state    | R(act/total) | T(act/total) | prod/t | rpm | flow/Max")
  printl(("─"):rep(w))
  rowmap={}; table_y0=({T().getCursorPos()})[2]
  local list={}
  for id,n in pairs(nodes) do table.insert(list,{id=id,n=n}) end
  table.sort(list,function(a,b) return a.id<b.id end)
  local y=table_y0
  for _,e in ipairs(list) do
    local id,n=e.id,e.n; local ag=n.telem and n.telem.agg
    local Ra,RT,Ta,TT,prod,rpm,flow,flowm=0,0,0,0,0,0,0,0
    if ag then Ra,RT=ag.reactors.active or 0, ag.reactors.count or 0; Ta,TT=ag.turbines.active or 0, ag.turbines.count or 0;
      prod=ag.turbines.prod or 0; rpm=ag.turbines.rpm or 0; flow=ag.turbines.flow or 0; flowm=ag.turbines.flow_max or 0 end
    local state=n.offline and "OFFLINE" or "online "
    setpos(1,y); write(string.format("#%-3d | %3ds | %-7s | %2d/%-2d      | %2d/%-2d      | %5s | %4s | %4s/%-4s",
      id, age_sec(n.last_ms or 0), state, Ra,RT, Ta,TT, fmt(prod), fmt(rpm), fmt(flow), fmt(flowm)))
    rowmap[y]=id; y=y+1
  end
  printl(""); printl("[F5] Aufräumen   [Klick/Touch] Details   [Q] Quit")
  if ui_msg~="" and (os.clock()-ui_msg_ts)<6 then printl("⚑ "..ui_msg) end
end

-- Drawing: Detail with buttons
local hitboxes={} -- list of {x1,y1,x2,y2, on_click=function() end}
local function add_btn(x,y,label,cb)
  local x2=x+#label-1; setpos(x,y); write(label); table.insert(hitboxes,{x1=x,y1=y,x2=x2,y2=y,on_click=cb})
end

local function draw_detail()
  cls(); hitboxes={}
  if not selected_id or not nodes[selected_id] then printl("Kein Node ausgewählt"); view="list"; return end
  local n=nodes[selected_id]; local ag=n.telem and n.telem.agg
  printl(("Node #%d | age %ds | %s"):format(selected_id, age_sec(n.last_ms or 0), n.offline and "OFFLINE" or "online"))
  if ag then
    printl(("R: %d/%d hot %s fuel %s/%s E %s"):format(ag.reactors.active or 0, ag.reactors.count or 0, fmt(ag.reactors.hot), fmt(ag.reactors.fuel), fmt(ag.reactors.fuel_max), fmt(ag.reactors.energy)))
    printl(("T: %d/%d rpm %s flow %s/%s prod %s/t"):format(ag.turbines.active or 0, ag.turbines.count or 0, fmt(ag.turbines.rpm), fmt(ag.turbines.flow), fmt(ag.turbines.flow_max), fmt(ag.turbines.prod)))
  end
  printl("")

  local w,h=size()
  local y=({T().getCursorPos()})[2]

  -- Reaktoren
  printl("=== Reaktoren ===")
  local reactors=(n.telem and n.telem.reactors) or {}
  for _,r in ipairs(reactors) do
    setpos(1,y+0); write(string.format("%-30s | act:%s hot:%s fuel:%s/%s E:%s T:%s",
      r.name or "reactor", r.active and "on " or "off", fmt(r.hot_mb), fmt(r.fuel), fmt(r.fuel_max), fmt(r.energy), fmt(r.temp)))
    -- Buttons: [On] [Off]
    local line_y=y+1
    add_btn(4, line_y, "[On ]", function()
      rednet.send(selected_id,{type="CMD",target="reactor",name=r.name,cmd="setActive",value=true,_auth=CFG.auth_token})
      ui_msg="Reaktor "..(r.name or "").." → ON (gesendet)"; ui_msg_ts=os.clock()
    end)
    add_btn(10,line_y, "[Off]", function()
      rednet.send(selected_id,{type="CMD",target="reactor",name=r.name,cmd="setActive",value=false,_auth=CFG.auth_token})
      ui_msg="Reaktor "..(r.name or "").." → OFF (gesendet)"; ui_msg_ts=os.clock()
    end)
    y=y+3
  end

  -- Turbinen
  setpos(1,y); printl("=== Turbinen ==="); y=y+1
  local turbines=(n.telem and n.telem.turbines) or {}
  for _,t in ipairs(turbines) do
    setpos(1,y); write(string.format("%-30s | act:%s rpm:%s flow:%s/%s prod:%s ind:%s",
      t.name or "turbine", t.active and "on " or "off", fmt(t.rpm), fmt(t.flow), fmt(t.flow_max), fmt(t.prod), tostring(t.inductor)))
    local line_y=y+1
    add_btn(4,  line_y, "[Ind]", function()
      rednet.send(selected_id,{type="CMD",target="turbine",name=t.name,cmd="setInductorEngaged",value=not t.inductor,_auth=CFG.auth_token})
      ui_msg="Turbine "..(t.name or "").." → Inductor toggle (gesendet)"; ui_msg_ts=os.clock()
    end)
    add_btn(10, line_y, "[–100]", function()
      local new=(t.flow_max or 0)-100; if new<0 then new=0 end
      rednet.send(selected_id,{type="CMD",target="turbine",name=t.name,cmd="setFluidFlowRateMax",value=math.floor(new),_auth=CFG.auth_token})
      ui_msg="Turbine "..(t.name or "").." → Flow -100 (gesendet)"; ui_msg_ts=os.clock()
    end)
    add_btn(18, line_y, "[+100]", function()
      local new=(t.flow_max or 0)+100
      rednet.send(selected_id,{type="CMD",target="turbine",name=t.name,cmd="setFluidFlowRateMax",value=math.floor(new),_auth=CFG.auth_token})
      ui_msg="Turbine "..(t.name or "").." → Flow +100 (gesendet)"; ui_msg_ts=os.clock()
    end)
    add_btn(26, line_y, "[Auto]", function()
      rednet.send(selected_id,{type="CMD",target="turbine",name=t.name,cmd="autotune",target_rpm=1800,timeout_s=25,_auth=CFG.auth_token})
      ui_msg="Turbine "..(t.name or "").." → Auto-Tune (gesendet)"; ui_msg_ts=os.clock()
    end)
    y=y+3
    if y>h-3 then break end
  end

  setpos(1,h); write("[ESC] zurück  |  Klick: Buttons  |  ")
  if ui_msg~="" and (os.clock()-ui_msg_ts)<6 then write("⚑ "..ui_msg) end
end

local function draw() if view=="list" then draw_list() else draw_detail() end end

-- Networking
local function send_ack(id) rednet.send(id,{type="HELLO_ACK",_auth=CFG.auth_token,master_id=MASTER_ID}) end
local function rx_loop()
  while true do
    local id,msg = rednet.receive(1)
    if id and type(msg)=="table" and msg._auth==CFG.auth_token then
      if msg.type=="HELLO" then
        nodes[id]=nodes[id] or {}; nodes[id].caps=msg.caps or nodes[id].caps or {}; nodes[id].last_ms=os.epoch("utc"); nodes[id].offline=false; send_ack(id)
      elseif msg.type=="TELEM" then
        nodes[id]=nodes[id] or {}; nodes[id].caps=msg.caps or nodes[id].caps or {}; nodes[id].telem=msg.telem or nodes[id].telem; nodes[id].last_ms=os.epoch("utc"); nodes[id].offline=false
      elseif msg.type=="CMD_ACK" then
        ui_msg = (msg.ok and "OK: " or "FEHLER: ")..(msg.msg or "")
        ui_msg_ts = os.clock()
      end
    end
  end
end

-- Housekeeping & Input
local function house_loop()
  local last=0
  while true do
    if os.clock()-last >= (CFG.redraw_interval or 0.3) then mark_timeouts(); draw(); last=os.clock() end
    os.sleep(0.05)
  end
end

local function open_detail_by_row(y) if view=="list" and rowmap[y] and nodes[rowmap[y]] then selected_id=rowmap[y]; detail_scroll=0; view="detail"; draw() end end
local function inside(x,y, hb) return x>=hb.x1 and x<=hb.x2 and y>=hb.y1 and y<=hb.y2 end

local function input_loop()
  while true do
    local ev={os.pullEvent()}
    if ev[1]=="key" then
      local k=ev[2]
      if view=="list" then
        if k==keys.f5 then local keep={}; for id,n in pairs(nodes) do if n.last_ms and age_sec(n.last_ms)<600 then keep[id]=n end end; nodes=keep; draw()
        elseif k==keys.q then cls(); term.setCursorPos(1,1); print("Master beendet."); return end
      else
        if k==keys.left or k==keys.escape then view="list"; selected_id=nil; draw()
        elseif k==keys.q then cls(); term.setCursorPos(1,1); print("Master beendet."); return end
      end
    elseif ev[1]=="mouse_click" then
      local btn,x,y=ev[2],ev[3],ev[4]
      if view=="list" and btn==1 then open_detail_by_row(y)
      elseif view=="detail" and btn==1 then for _,hb in ipairs(hitboxes) do if inside(x,y,hb) then hb.on_click(); break end end end
    elseif ev[1]=="monitor_touch" then
      local side,x,y=ev[2],ev[3],ev[4]
      if CFG.monitor_side and side==CFG.monitor_side then
        if view=="list" then open_detail_by_row(y)
        else for _,hb in ipairs(hitboxes) do if inside(x,y,hb) then hb.on_click(); break end end end
      end
    end
  end
end

-- Run
cls(); printl(("Master startet…  Modem:%s  Monitor:%s"):format(CFG.modem_side, CFG.monitor_side or "-"))
parallel.waitForAny(rx_loop, house_loop, input_loop)
