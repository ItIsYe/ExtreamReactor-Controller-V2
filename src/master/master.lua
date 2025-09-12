-- ===== Master Controller (Full Touch UI) =====
-- Suchpfad für Shared-Module
package.path = package.path .. ";/xreactor/?.lua;/xreactor/shared/?.lua;/xreactor/?/init.lua"

local GUI = require("gui")         -- wird für simple Dinge noch genutzt (nicht für Touch-Form)
local STO = require("storage")
local PRO = require("protocol")

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
CFG.monitor_name      = CFG.monitor_name      or nil
CFG.text_scale        = CFG.text_scale        or 0.5
CFG.rows_per_page     = CFG.rows_per_page     or nil

-- ---------- Modem öffnen ----------
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

-- Hotplug
local function peripheral_watcher()
  while true do
    local e = { os.pullEvent() }
    if e[1] == "peripheral" or e[1] == "peripheral_detach" then
      attach_monitor()
    end
  end
end

-- ---------- Daten ----------
local nodes = {}  -- [id] = {floor=?, last=?, offline=?, telem=?, caps=?, ramp=?}
local cur_page = "status" -- "status" oder "config"
local page_idx = 1

-- ===== STUBS (später echte Logik einsetzen) =====
local function read_main_soc() return CFG.soc_target or 0.5 end
local function soc_to_steam_target(_) return 0 end
local function distribute(_) end
local function apply_ramp() end
local function push_setpoints() end

-- ---------- Helpers ----------
local function with_term(t, fn)
  local old = term.redirect(t); local ok, err = pcall(fn); term.redirect(old)
  if not ok then error(err) end
end

local function node_count() local c=0; for _ in pairs(nodes) do c=c+1 end; return c end

local function drawBar(x, y, w, pct, col_fg, col_bg)
  pct = tonumber(pct) or 0
  if pct < 0 then pct = 0 elseif pct > 1 then pct = 1 end
  local fill = math.floor(w * pct + 0.5)

  term.setCursorPos(x, y)
  term.setBackgroundColor(col_bg or colors.gray)
  term.write(string.rep(" ", w))

  term.setCursorPos(x, y)
  term.setBackgroundColor(col_fg or colors.green)
  if fill > 0 then term.write(string.rep(" ", fill)) end

  term.setBackgroundColor(colors.black)
end

-- sortierte IDs (stabile Liste)
local function sorted_ids(t)
  local ids = {}
  for id,_ in pairs(t) do table.insert(ids, id) end
  table.sort(ids)
  local i = 0
  return function()
    i = i + 1
    if ids[i] then return ids[i], t[ids[i]] end
  end
end

-- ---------- Buttons / Hitboxen ----------
local buttons = {}   -- Liste der aktiven Buttons: {id, x1,x2,y, meta=?}
local function add_button(id, x1, y, label, meta)
  local x2 = x1 + #label - 1
  table.insert(buttons, {id=id, x1=x1, x2=x2, y=y, meta=meta, label=label})
  term.setCursorPos(x1, y); term.write(label)
end

local function clear_buttons() buttons = {} end

local function find_button_at(x,y)
  for _,b in ipairs(buttons) do
    if y == b.y and x >= b.x1 and x <= b.x2 then return b end
  end
end

-- ---------- STATUS-SEITE ----------
local function draw_status()
  clear_buttons()
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.white)
  term.clear()

  local w,h = term.getSize()
  term.setCursorPos(1,1)
  term.write(("Master @ %s  |  Modem: %s"):format(tostring(MON_NAME or "screen"), tostring(CFG.modem_side)))
  term.setCursorPos(1,2)
  term.write("Nodes: "..tostring(node_count()))

  -- SoC-Bar oben rechts
  local soc = read_main_soc()
  local barw = math.max(10, math.floor(w * 0.3))
  local bx = w - barw + 1
  local by = 2
  term.setCursorPos(bx-6, by); term.setTextColor(colors.lightGray); term.write("SoC:")
  drawBar(bx, by, barw, soc, colors.blue, colors.gray)
  term.setTextColor(colors.white)

  -- Kopfzeile
  term.setCursorPos(1,4)
  term.setTextColor(colors.cyan)
  term.write(string.format("%-6s %-7s %-7s %-8s  %-s", "ID", "Floor", "Status", "Last", "Fill/RPM/Steam"))
  term.setTextColor(colors.white)

  local rows_avail = (CFG.rows_per_page or (h - 7))
  if rows_avail < 1 then rows_avail = 1 end
  local start_idx = (page_idx-1) * rows_avail
  local list = {}
  for id,_ in pairs(nodes) do list[#list+1] = id end
  table.sort(list)

  local row_y = 5
  for ii = start_idx+1, math.min(#list, start_idx+rows_avail) do
    local id = list[ii]
    local n  = nodes[id]
    local status = n.offline and "OFFLINE" or "ONLINE"
    local last = n.last and math.floor((os.epoch("utc") - n.last)/1000).."s" or "?"
    local fill = (n.telem and n.telem.fill) or 0
    local rpm  = (n.telem and n.telem.rpm)  or 0
    local steam= (n.telem and n.telem.steam) or 0

    term.setCursorPos(1, row_y)
    term.write(string.format("%-6s %-7s %-7s %-8s  ", tostring(id), tostring(n.floor or "?"), status, last))

    local col = colors.green
    if n.offline then col = colors.red
    elseif fill < 0.25 then col = colors.orange end

    local info_x = 1 + 6 + 1 + 7 + 1 + 7 + 1 + 8 + 2
    local infow  = math.max(10, w - info_x + 1)
    drawBar(info_x, row_y, math.max(10, math.floor(infow*0.6)), fill, col, colors.gray)
    local txt = string.format("  %4d RPM  |  %4d st", rpm, steam)
    local tx = info_x + math.max(10, math.floor(infow*0.6)) + 1
    if tx <= w then term.setCursorPos(tx, row_y); term.write(txt) end

    row_y = row_y + 1
    if row_y > h-2 then break end
  end

  -- Footer + Buttons
  local total_pages = math.max(1, math.ceil(#list / rows_avail))
  if page_idx > total_pages then page_idx = total_pages end
  local footer = ("Page %d/%d"):format(page_idx, total_pages)
  term.setCursorPos(1, h); term.clearLine()
  term.setCursorPos(1, h); term.setTextColor(colors.lightGray); term.write(footer); term.setTextColor(colors.white)

  -- Buttons mittig
  local opts = {"[ Config ]","[ PgUp ]","[ PgDn ]","[ Quit ]"}
  local line = table.concat(opts, "  ")
  local startx = math.max(1, math.floor((w - #line)/2) + 1)
  local x = startx
  add_button("cfg",  x, h, opts[1]); x = x + #opts[1] + 2
  add_button("pgup", x, h, opts[2]); x = x + #opts[2] + 2
  add_button("pgdn", x, h, opts[3]); x = x + #opts[3] + 2
  add_button("quit", x, h, opts[4])
end

-- ---------- CONFIG-SEITE (Touch-Form) ----------
-- Soft-Keyboard für Text/List
local keyboard = {
  "ABCDEF GHIJKL MNOPQR STUVWX YZ",
  "abcdef ghijkl mnopqr stuvwx yz",
  "0123456789 -_./:,@",
  "[Space] [Del] [Save] [Cancel]"
}

local function keyboard_input(initial)
  local txt = tostring(initial or "")
  while true do
    term.setBackgroundColor(colors.black); term.setTextColor(colors.white); term.clear()
    local w,h = term.getSize()
    term.setCursorPos(1,1); term.write("Text-Eingabe (Touch)  |  Tippe Save zum Übernehmen")
    term.setCursorPos(1,3); term.setTextColor(colors.yellow)
    term.write(txt); term.setTextColor(colors.white)

    -- Tasten malen und Hitboxen bauen
    clear_buttons()
    local y = 5
    for _,row in ipairs(keyboard) do
      local x = 2
      local i = 1
      while i <= #row do
        if row:sub(i,i) == "[" then
          local j = row:find("%]", i+1) or #row
          local label = row:sub(i, j)
          add_button(label, x, y, label)
          x = x + #label + 1
          i = j + 1
        elseif row:sub(i,i) == " " then
          x = x + 1; i = i + 1
        else
          local ch = row:sub(i,i)
          add_button(ch, x, y, ch)
          x = x + 2
          i = i + 1
        end
      end
      y = y + 2
    end

    -- Eingabe warten
    local e, side, px, py = os.pullEvent("monitor_touch")
    if not MON or side ~= MON_NAME then goto continue end
    local b = find_button_at(px, py)
    if b then
      local lab = b.label
      if     lab == "[Space]"  then txt = txt .. " "
      elseif lab == "[Del]"    then txt = txt:sub(1, #txt-1)
      elseif lab == "[Save]"   then return txt
      elseif lab == "[Cancel]" then return initial
      else txt = txt .. lab
      end
    end
    ::continue::
  end
end

-- Spezifikation der Config-Felder
local config_spec = {
  {key="modem_side",          label="Modem-Seite",             type="text"},
  {key="monitor_name",        label="Monitor-Name (leer=auto)",type="text"},
  {key="text_scale",          label="Textscale (0.5..5)",      type="number", step=0.5, min=0.5, max=5},
  {key="auth_token",          label="Auth-Token",              type="text"},
  {key="rows_per_page",       label="Rows/Page (leer=auto)",   type="number", step=1, min=0},
  {key="telem_timeout",       label="Telem Timeout (s)",       type="number", step=1, min=1},
  {key="setpoint_interval",   label="Setpoint Intervall (s)",  type="number", step=1, min=1},
  {key="soc_target",          label="SoC Target (0..1)",       type="number", step=0.05, min=0, max=1},
  {key="rpm_target",          label="RPM Target",              type="number", step=50, min=0},
  {key="ramp_floor_offset",   label="Ramp Offset/Etage (s)",   type="number", step=0.5, min=0},
  -- weitere Felder aus deinem Projekt kannst du hier ergänzen…
}

local function draw_config()
  clear_buttons()
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.white)
  term.clear()
  local w,h = term.getSize()

  term.setCursorPos(1,1); term.write("Konfiguration (Touch) – Tippe [+]/[-]/ON/OFF/Edit")
  term.setCursorPos(1,2); term.write("Save speichert & wendet an • Back zurück")

  -- Kopfzeile
  term.setCursorPos(1,4); term.setTextColor(colors.cyan)
  term.write(string.format("%-20s %-18s %-s", "Feld", "Wert", "Aktion"))
  term.setTextColor(colors.white)

  -- Rows pro Seite auf dem Monitor
  local rows = h - 8
  local start = 1
  local y = 5
  for i = start, math.min(#config_spec, start + rows - 1) do
    local f = config_spec[i]
    local val = CFG[f.key]
    term.setCursorPos(1,y); term.clearLine()
    term.write(string.format("%-20s ", f.label))

    local val_str
    if type(val) == "table" then
      val_str = table.concat(val, ",")
    else
      val_str = (val == nil) and "(leer)" or tostring(val)
    end
    term.setCursorPos(22,y); term.write(string.format("%-18s ", val_str))

    local x = 41
    if f.type == "number" then
      add_button("dec:"..f.key, x, y, "[-]", f); x = x + 5
      add_button("inc:"..f.key, x, y, "[+]", f); x = x + 5
      add_button("edit:"..f.key, x, y, "[Edit]", f)
    elseif f.type == "toggle" then
      local on = (val == true)
      add_button("tog:"..f.key, x, y, on and "[ ON ]" or "[ OFF ]", f)
    elseif f.type == "list" then
      add_button("edit:"..f.key, x, y, "[Edit]", f)
    else -- text
      add_button("edit:"..f.key, x, y, "[Edit]", f)
    end

    y = y + 1
  end

  -- Footer-Buttons
  term.setCursorPos(1, h); term.clearLine()
  local opts = {"[ Save ]","[ Back ]"}
  local line = table.concat(opts, "  ")
  local startx = math.max(1, math.floor((w - #line)/2) + 1)
  add_button("save", startx, h, opts[1])
  add_button("back", startx + #opts[1] + 2, h, opts[2])
end

local function apply_and_save()
  if STO and STO.save_json then STO.save_json(CFG_PATH, CFG) end
  -- Modem
  if rednet.isOpen() then rednet.close() end
  if CFG.modem_side then rednet.open(CFG.modem_side) end
  -- Monitor
  attach_monitor()
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
    for _,n in pairs(nodes) do
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
    -- zeichnen nur in Status-Seite häufig
    if cur_page == "status" then
      with_term(MON or scr, draw_status)
    end
    sleep(CFG.setpoint_interval)
  end
end

-- ---------- Touch-Loop (Status + Config) ----------
local function touch_loop()
  -- initiale Seite
  with_term(MON or scr, function()
    if cur_page == "status" then draw_status() else draw_config() end
  end)

  while true do
    local e, side, x, y = os.pullEvent("monitor_touch")
    if not MON or side ~= MON_NAME then goto continue end

    local b = find_button_at(x,y)
    if not b then goto continue end

    -- STATUS-Seite Buttons
    if cur_page == "status" then
      if b.id == "cfg" then
        cur_page = "config"; with_term(MON, draw_config)
      elseif b.id == "pgup" then
        page_idx = math.max(1, page_idx-1); with_term(MON, draw_status)
      elseif b.id == "pgdn" then
        page_idx = page_idx + 1; with_term(MON, draw_status)
      elseif b.id == "quit" then
        with_term(scr, function() term.clear(); term.setCursorPos(1,1) end)
        return
      end

    -- CONFIG-Seite Buttons
    elseif cur_page == "config" then
      if b.id == "back" then
        cur_page = "status"; with_term(MON, draw_status)
      elseif b.id == "save" then
        apply_and_save()
        cur_page = "status"; with_term(MON, draw_status)
      else
        -- Feld-spezifische Aktionen
        local action, key = b.id:match("^(%a+):(.+)$")
        local f = b.meta
        if action and key and f then
          local t = f.type or "text"
          if action == "dec" and t == "number" then
            local step = f.step or 1
            local min  = f.min
            local v = tonumber(CFG[key] or 0) or 0
            v = v - step; if min and v < min then v = min end
            CFG[key] = v
            with_term(MON, draw_config)
          elseif action == "inc" and t == "number" then
            local step = f.step or 1
            local maxv = f.max
            local v = tonumber(CFG[key] or 0) or 0
            v = v + step; if maxv and v > maxv then v = maxv end
            CFG[key] = v
            with_term(MON, draw_config)
          elseif action == "tog" and t == "toggle" then
            CFG[key] = not (CFG[key] == true)
            with_term(MON, draw_config)
          elseif action == "edit" then
            -- Text oder List -> Soft-Keyboard
            local current = CFG[key]
            if type(current) == "table" then current = table.concat(current, ",") end
            local newtxt = with_term(MON, function() return keyboard_input(current or "") end)
            if t == "list" then
              local list = {}
              for part in tostring(newtxt):gmatch("[^,]+") do
                local v = part:gsub("^%s+",""):gsub("%s+$","")
                if v ~= "" then table.insert(list, v) end
              end
              CFG[key] = list
            else
              if t == "number" then
                local n = tonumber(newtxt)
                if n ~= nil then CFG[key] = n end
              else
                CFG[key] = newtxt
              end
            end
            with_term(MON, draw_config)
          end
        end
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

parallel.waitForAny(rx_loop, ctrl_loop, touch_loop, peripheral_watcher)
