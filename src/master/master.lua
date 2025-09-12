-- ===== Master Controller (Monitor + Touch-Steuerung) =====
package.path = package.path .. ";/xreactor/?.lua;/xreactor/shared/?.lua;/xreactor/?/init.lua"

local GUI = require("gui")
local STO = require("storage")

-- ---------- Config laden ----------
local CFG_PATH = "/xreactor/config_master.lua"
local CFG = {}
do
  local ok, def = pcall(require, "config_master")
  if ok and type(def)=="table" then for k,v in pairs(def) do CFG[k]=v end end
  if STO and STO.load_json then
    local j = STO.load_json(CFG_PATH, nil)
    if type(j)=="table" then for k,v in pairs(j) do CFG[k]=v end end
  end
end

-- Defaults
CFG.modem_side        = CFG.modem_side        or "left"
CFG.auth_token        = CFG.auth_token        or "changeme"
CFG.telem_timeout     = CFG.telem_timeout     or 10
CFG.setpoint_interval = CFG.setpoint_interval or 5
CFG.soc_target        = CFG.soc_target        or 0.5
CFG.rpm_target        = CFG.rpm_target        or 1800
CFG.ramp_floor_offset = CFG.ramp_floor_offset or 1
CFG.monitor_name      = CFG.monitor_name      or nil   -- z.B. "monitor_0"
CFG.text_scale        = CFG.text_scale        or 0.5

-- Modem (wireless) öffnen
if rednet.isOpen() then rednet.close() end
rednet.open(CFG.modem_side)

-- ---------- Monitor finden ----------
local scr = term.current()
local MON, MON_NAME, MW, MH

local function find_best_monitor()
  local best, bestName, bestArea = nil, nil, 0
  for _,name in ipairs(peripheral.getNames()) do
    if peripheral.hasType(name, "monitor") then
      local m = peripheral.wrap(name)
      local w,h = m.getSize()
      local area = w*h
      if area > bestArea then best, bestName, bestArea = m, name, area end
    end
  end
  return best, bestName
end

local function attach_monitor()
  if CFG.monitor_name and peripheral.isPresent(CFG.monitor_name) and peripheral.hasType(CFG.monitor_name, "monitor") then
    MON = peripheral.wrap(CFG.monitor_name); MON_NAME = CFG.monitor_name
  else
    MON, MON_NAME = find_best_monitor()
  end
  if MON then
    pcall(function()
      MON.setTextScale(CFG.text_scale or 0.5)
      MON.setBackgroundColor(colors.black)
      MON.setTextColor(colors.white)
      MON.clear()
      MW, MH = MON.getSize()
    end)
  else
    MW, MH = term.getSize()
  end
end

attach_monitor()

-- bei An-/Abstecken neu erkennen
local function peripheral_watcher()
  while true do
    local e, side = os.pullEvent()
    if e == "peripheral" or e == "peripheral_detach" then
      attach_monitor()
    end
  end
end

-- Helper-Terminal-Wrapper
local function with_term(t, fn)
  local old = term.redirect(t); local ok, err = pcall(fn); term.redirect(old)
  if not ok then error(err) end
end

-- ---------- Daten ----------
local nodes = {}  -- [id] = {floor=?, last=?, offline=?, telem=?, caps=?, ramp=?}
local page_idx = 1

-- ===== STUBS (später echte Logik einsetzen) =====
local function read_main_soc() return CFG.soc_target or 0.5 end
local function soc_to_steam_target(_) return 0 end
local function distribute(_) end
local function apply_ramp() end
local function push_setpoints() end

local function node_count() local c=0; for _ in pairs(nodes) do c=c+1 end; return c end

-- ---------- UI / Zeichnen ----------
-- Soft-Buttons (Koordinaten werden dynamisch berechnet)
local buttons = {
  {id="cfg",  label="[ Config ]"},
  {id="pgup", label="[ PgUp ]"},
  {id="pgdn", label="[ PgDn ]"},
  {id="quit", label="[ Quit ]"},
}

local function draw_body()
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.white)
  term.clear()

  local w,h = term.getSize()
  term.setCursorPos(1,1)
  print(("Master @ %s | Modem: %s"):format(tostring(MON_NAME or "screen"), tostring(CFG.modem_side)))
  print("Nodes: "..tostring(node_count()))

  -- Liste
  local y = 4
  for id,n in pairs(nodes) do
    local status = n.offline and "OFFLINE" or "ONLINE"
    local last = n.last and math.floor((os.epoch("utc") - n.last)/1000).."s" or "?"
    term.setCursorPos(1,y)
    term.write(string.format("Node %d | Floor %s | %-7s | Last %s",
      id, tostring(n.floor or "?"), status, last))
    y = y + 1
    if y > h-2 then break end
  end

  -- Soft-Buttons unten mittig
  local labels = {}
  for i,b in ipairs(buttons) do table.insert(labels, b.label) end
  local line = table.concat(labels, "  ")
  local startx = math.max(1, math.floor((w - #line)/2) + 1)
  local cx = startx
  local by = h
  term.setCursorPos(1, by); term.clearLine()
  term.setCursorPos(startx, by)
  term.write(line)

  -- Klickflächen merken
  cx = startx
  for _,b in ipairs(buttons) do
    b.x1 = cx
    b.x2 = cx + #b.label - 1
    b.y  = by
    cx = b.x2 + 3  -- 2 Spaces + 1 Startpunkt
  end
end

local function draw()
  if MON then with_term(MON, draw_body) else with_term(scr, draw_body) end
end

-- ---------- Config-Dialog (auf dem Monitor gerendert, Tastatur-Eingabe) ----------
local function do_config()
  local spec = {
    {key="distribute",          label="Verteilung",              type="text"},
    {key="page_interval",       label="Page Intervall (s)",      type="number"},
    {key="rows_per_page",       label="Rows/Page",               type="number"},
    {key="ramp_enabled",        label="Ramp enabled",            type="toggle"},
    {key="ramp_step",           label="Ramp Step (mB/t)",        type="number"},
    {key="ramp_interval",       label="Ramp Interval (s)",       type="number"},
    {key="ramp_floor_offset",   label="Ramp Offset/Etage (s)",   type="number"},
    {key="alarm_sound",         label="Alarm Sound",             type="toggle"},
    {key="alarm_rpm_low",       label="Alarm RPM low",           type="number"},
    {key="alarm_rpm_high",      label="Alarm RPM high",          type="number"},
    {key="alarm_floor_soc_low", label="Alarm Floor SoC low",     type="number"},
    {key="main_storages",       label="Hauptspeicher (Komma)",   type="list"},
    {key="modem_side",          label="Modem-Seite",             type="text"},
    {key="monitor_name",        label="Monitor-Name (leer=auto)",type="text"},
    {key="text_scale",          label="Textscale (0.5..5)",      type="number"},
    {key="auth_token",          label="Auth-Token",              type="text"},
  }
  local work = {}; for k,v in pairs(CFG) do work[k]=v end
  local function run_form()
    local res, data = GUI.form("Master Konfiguration", spec, work)
    if res == "save" and type(data)=="table" then
      for k,v in pairs(data) do CFG[k]=v end
      if STO and STO.save_json then STO.save_json(CFG_PATH, CFG) end
      -- Modem neu
      if rednet.isOpen() then rednet.close() end
      if CFG.modem_side then rednet.open(CFG.modem_side) end
      -- Monitor neu anhängen
      attach_monitor()
    end
  end
  -- Formular auf dem Monitor darstellen (Tastatur bleibt am PC)
  if MON then with_term(MON, run_form) else with_term(scr, run_form) end
  draw()
end

-- ---------- RX: HELLO / TELEM ----------
local function rx_loop()
  while true do
    local id, msg = rednet.receive(nil, 1)
    if id and type(msg)=="table" then
      if msg._auth ~= CFG.auth_token then
        -- falscher Token
      else
        if msg.type == "HELLO" then
          nodes[id] = nodes[id] or {}
          nodes[id].floor   = msg.floor
          nodes[id].caps    = msg.caps or {}
          nodes[id].last    = os.epoch("utc")
          nodes[id].offline = false
          rednet.send(id, { type="HELLO_ACK", cfg={ rpm_target=CFG.rpm_target }, _auth=CFG.auth_token })

        elseif msg.type == "TELEM" then
          nodes[id] = nodes[id] or {}
          nodes[id].telem   = msg.data or msg
          nodes[id].floor   = nodes[id].floor or msg.floor
          nodes[id].last    = os.epoch("utc")
          nodes[id].offline = false
        end
      end
    end

    -- Timeouts
    for nid,n in pairs(nodes) do
      if (os.epoch("utc")-(n.last or 0))/1000 > CFG.telem_timeout then
        n.offline = true
      end
    end
  end
end

-- ---------- Control ----------
local function ctrl_loop()
  while true do
    local soc   = read_main_soc() or CFG.soc_target
    local total = soc_to_steam_target(soc)
    distribute(total)
    apply_ramp()
    push_setpoints()
    draw()
    sleep(CFG.setpoint_interval)
  end
end

-- ---------- Eingaben ----------
local function key_loop()
  while true do
    local e,k = os.pullEvent("key")
    if k == keys.f1 then
      do_config()
    elseif k == keys.pageup then
      page_idx = math.max(1, page_idx-1); draw()
    elseif k == keys.pagedown then
      page_idx = page_idx + 1; draw()
    elseif k == keys.q or k == keys.escape then
      with_term(scr, function() term.clear(); term.setCursorPos(1,1) end)
      return
    end
  end
end

-- Monitor-Touch-Buttons
local function touch_loop()
  while true do
    local e, side, x, y = os.pullEvent("monitor_touch")
    if not MON or side ~= MON_NAME then goto continue end
    for _,b in ipairs(buttons) do
      if y == b.y and x >= b.x1 and x <= b.x2 then
        if     b.id=="cfg"  then do_config()
        elseif b.id=="pgup" then page_idx = math.max(1, page_idx-1); draw()
        elseif b.id=="pgdn" then page_idx = page_idx + 1; draw()
        elseif b.id=="quit" then with_term(scr, function() term.clear(); term.setCursorPos(1,1) end); return end
      end
    end
    ::continue::
  end
end

-- ---------- Start ----------
with_term(scr, function()
  term.clear(); term.setCursorPos(1,1)
  print("Master startet...")
  print("Modem: "..tostring(CFG.modem_side).."  |  Monitor: "..tostring(MON_NAME or "none"))
end)

parallel.waitForAny(rx_loop, ctrl_loop, key_loop, touch_loop, peripheral_watcher)
