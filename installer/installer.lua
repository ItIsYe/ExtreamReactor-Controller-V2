-- installer.lua  (XReactor Installer • mit Auto-Health-Check & Launchern)
local REPO_BASE = "https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main"

-- ===== Utils =====
local function ensureDir(path)
  local parts={} for p in path:gmatch("[^/]+") do parts[#parts+1]=p end
  if #parts<=1 then return end
  local dir="/"..table.concat(parts,"/",1,#parts-1)
  if not fs.exists(dir) then fs.makeDir(dir) end
end
local function fmtBytes(n) local u={"B","KB","MB"} local i=1 while n>1024 and i<#u do n=n/1024 i=i+1 end return string.format("%.1f %s",n,u[i]) end
local function getFree() local ok,free=pcall(function() return fs.getFreeSpace("/") end) return ok and free or 0 end
local function http_get(url) local ok,h=pcall(http.get,url,nil,true) if not ok or not h then return nil,"HTTP-Fehler" end local b=h.readAll() or "" h.close() if b=="" then return nil,"Leerer Inhalt" end return b end
local function save_text(path,text) ensureDir(path) if #text>getFree()-2048 then return false,"Out of space" end local f=fs.open(path,"w") if not f then return false,"Pfad nicht verfügbar oder kein Speicherplatz" end f.write(text) f.close() return true end
local function save_url(url,path) local body,err=http_get(url) if not body then return false,err end return save_text(path,body) end
local function say(...) print(table.concat({...}," ")) end
local function ask(prompt,def) write(prompt..(def and (" ["..def.."]") or "")..": ") local a=read() if a=="" and def then a=def end return a end

-- ===== Rolle =====
local function choose_role()
  say("") say("[1] MASTER (UI)   [2] AUX (Worker)")
  local sel=ask("Auswahl 1/2","2")
  if tostring(sel)=="1" or tostring(sel):lower()=="master" then return "MASTER","master" end
  return "AUX","node"
end

-- ===== Manifeste =====
-- Basis inkl. AUX-Node (für sicheren Fallback)
local BASE = {
  {"src/shared/protocol.lua","/xreactor/shared/protocol.lua"},
  {"src/shared/identity.lua","/xreactor/shared/identity.lua"},
  {"src/shared/log.lua",     "/xreactor/shared/log.lua"},
  {"src/node/aux_node.lua",  "/xreactor/node/aux_node.lua"},
  {"startup.lua",            "/startup.lua"},
}
-- Zusatz für MASTER-UI
local MASTER = {
  {"xreactor/shared/gui.lua",       "/xreactor/shared/gui.lua"},
  {"src/master/master_home.lua",    "/xreactor/master/master_home.lua"},
  {"src/master/fuel_panel.lua",     "/xreactor/master/fuel_panel.lua"},
  {"src/master/waste_panel.lua",    "/xreactor/master/waste_panel.lua"},
  {"src/master/alarm_center.lua",   "/xreactor/master/alarm_center.lua"},
  {"src/master/overview_panel.lua", "/xreactor/master/overview_panel.lua"},
}

-- ===== Schreibkram =====
local function ensure_dirs()
  for _,d in ipairs({"/xreactor","/xreactor/shared","/xreactor/master","/xreactor/node"}) do
    if not fs.exists(d) then fs.makeDir(d) end
  end
end
local function download_set(set)
  for i,p in ipairs(set) do
    local src,dst=p[1],p[2]; local url=REPO_BASE.."/"..src
    say(string.format("[%d/%d] %s -> %s",i,#set,src,dst))
    local ok,err=save_url(url,dst)
    if not ok then error(("Fehler bei %s: %s"):format(dst,tostring(err))) end
  end
end
local function write_config_identity(role)
  local path="/xreactor/config_identity.lua"
  if fs.exists(path) then say("Config existiert bereits:",path) return end
  local tpl=([[return {
  role     = "%s",
  id       = "01",
  hostname = "",
  cluster  = "XR-CLUSTER-ALPHA",
  token    = "xreactor",
}]])
  save_text(path,string.format(tpl,role)); say("Config geschrieben:",path)
end
local function write_config_master()
  local path="/xreactor/config_master.lua"
  if fs.exists(path) then return end
  save_text(path,[[return {
  modem_side   = nil,   -- "right" o.ä., nil=auto
  monitor_side = nil,   -- "top"  o.ä.,  nil=auto
  text_scale   = 0.5,
}]])
end
local function write_launchers()
  save_text("/xreactor/master",'shell.run("/xreactor/master/master_home.lua")')
  save_text("/xreactor/node",  'shell.run("/xreactor/node/aux_node.lua")')
  say("Launcher angelegt/aktualisiert: /xreactor/master und /xreactor/node")
end
local function write_role_txt(role_lower)
  save_text("/xreactor/role.txt",role_lower.."\n"); say("role.txt gesetzt:",role_lower)
end

-- ===== Health-Check =====
local function write_health_check()
  local hc=[[
-- /xreactor/health_check.lua
local function ok(b) return b and "OK" or "FAIL" end
local function exists(p) return fs.exists(p) and not fs.isDir(p) end
print("== XReactor Health-Check ==")
-- role
local role="unknown"
if fs.exists("/xreactor/role.txt") then local f=fs.open("/xreactor/role.txt","r") role=(f.readLine() or "unknown") f.close() end
print("role.txt:",role)
-- AUX presence
local aux="/xreactor/node/aux_node.lua"
print("AUX-Datei vorhanden:", ok(exists(aux)))
if exists(aux) then local lf=loadfile(aux) print("AUX-Datei ladbar:", ok(type(lf)=="function")) else print("  -> fehlt: wget https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/src/node/aux_node.lua /xreactor/node/aux_node.lua") end
-- MASTER presence
if role=="master" then
  local mh="/xreactor/master/master_home.lua"
  print("MASTER-Hauptskript:", ok(exists(mh)))
  local gui="/xreactor/shared/gui.lua"
  print("GUI vorhanden:", ok(exists(gui)))
end
-- Modems
local hasModem=false
for _,n in ipairs(peripheral.getNames()) do
  if peripheral.getType(n)=="modem" then
    hasModem=true
    local st=rednet.isOpen(n) and "offen" or "geschlossen"
    print("Modem "..n..": "..st)
  end
end
print("Mind. ein Modem:", ok(hasModem))
if not hasModem then print("  -> Modem anschließen & einschalten (Rechtsklick)") end
-- Monitor
local mon=peripheral.find("monitor")
print("Monitor gefunden:", ok(mon~=nil))
print("== Ende. Wenn alles OK: reboot ==")
]]
  save_text("/xreactor/health_check.lua",hc)
end

-- ===== Main =====
local function run()
  ensure_dirs()
  local role,role_lower=choose_role()
  say("Gewählte Rolle:",role); say(""); say("Freier Speicher:",fmtBytes(getFree()))
  local plan={} for _,p in ipairs(BASE) do plan[#plan+1]=p end
  if role=="MASTER" then for _,p in ipairs(MASTER) do plan[#plan+1]=p end end
  local ok,err=pcall(download_set,plan)
  if not ok then
    say(""); say("❌ Fehler:",tostring(err))
    say("Tipp: Speicher freigeben (z.B. delete /xreactor/log.txt) oder Advanced Computer nutzen.")
    return
  end
  write_config_identity(role)
  if role=="MASTER" then write_config_master() end
  write_launchers()
  write_role_txt(role_lower)
  write_health_check()

  say(""); say("✅ Installation fertig. Starte Health-Check …")
  local ok2,err2=pcall(function() dofile("/xreactor/health_check.lua") end)
  if not ok2 then printError("Health-Check Fehler: "..tostring(err2)) end
  say(""); say("→ Wenn alles OK ist: reboot")
end

local ok,err=pcall(run) if not ok then printError(err) end
