-- installer.lua  (XReactor Hybrid-Installer • inkl. topbar.lua + GUI mkRouter-Fallback + Auto-Health-Check)
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
local function monitor_present() local ok,mon=pcall(function() return peripheral.find("monitor") end) return ok and (mon~=nil) end

-- ===== Rolle =====
local function choose_role()
  say("") say("[1] MASTER (UI)   [2] AUX (Worker/Textmodus)")
  local sel=ask("Auswahl 1/2","2")
  if tostring(sel)=="1" or tostring(sel):lower()=="master" then return "MASTER","master" end
  return "AUX","node"
end

-- ===== Manifeste =====
-- Basis inkl. AUX-Node (für sicheren Fallback)  +++  topbar.lua NEU dabei +++
local BASE = {
  {"src/shared/protocol.lua","/xreactor/shared/protocol.lua"},
  {"src/shared/identity.lua","/xreactor/shared/identity.lua"},
  {"src/shared/log.lua",     "/xreactor/shared/log.lua"},
  {"src/shared/topbar.lua",  "/xreactor/shared/topbar.lua"},   -- <<<
  {"src/node/aux_node.lua",  "/xreactor/node/aux_node.lua"},
  {"startup.lua",            "/startup.lua"},
}
-- MASTER-UI
local MASTER = {
  {"xreactor/shared/gui.lua",       "/xreactor/shared/gui.lua"},
  {"src/master/master_home.lua",    "/xreactor/master/master_home.lua"},
  {"src/master/fuel_panel.lua",     "/xreactor/master/fuel_panel.lua"},
  {"src/master/waste_panel.lua",    "/xreactor/master/waste_panel.lua"},
  {"src/master/alarm_center.lua",   "/xreactor/master/alarm_center.lua"},
  {"src/master/overview_panel.lua", "/xreactor/master/overview_panel.lua"},
}

-- ===== Schreiben & Helfer =====
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

-- ===== GUI-Fallback (mkRouter) =====
local function ensure_gui_mkrouter()
  local ok,gui=pcall(function() return dofile("/xreactor/shared/gui.lua") end)
  local has = ok and type(gui)=="table" and type(gui.mkRouter)=="function"
  if has then return end
  local shim=[[
-- /xreactor/shared/gui.lua  (mkRouter-Shim)
local M={}
local function resolveMonitor(name)
  local dev
  if type(name)=="string" and name~="" then pcall(function() dev=peripheral.wrap(name) end) end
  if not dev then dev=peripheral.find("monitor") end
  if not dev then dev=term.current() end
  return dev
end
function M.mkRouter(opts)
  opts=opts or {}
  local dev=resolveMonitor(opts.monitorName or opts.monitor_side)
  local r={dev=dev}
  function r:setTextScale(s) if self.dev.setTextScale then pcall(self.dev.setTextScale,s or 0.5) end end
  function r:getSize() if self.dev.getSize then return self.dev.getSize() end return term.getSize() end
  function r:clear() if self.dev.clear then self.dev.clear() else term.clear() end if self.dev.setCursorPos then self.dev.setCursorPos(1,1) else term.setCursorPos(1,1) end end
  function r:setCursorPos(x,y) if self.dev.setCursorPos then self.dev.setCursorPos(x,y) else term.setCursorPos(x,y) end end
  function r:write(t) t=tostring(t or "") if self.dev.write then self.dev.write(t) else term.write(t) end end
  function r:printAt(x,y,t) self:setCursorPos(x,y) self:write(t) end
  function r:center(y,t) local w=select(1,self:getSize()) local s=tostring(t or "") local x=math.max(1,math.floor((w-#s)/2)+1) self:printAt(x,y,s) end
  return r
end
local _d=M.mkRouter({})
function M.init() end
function M.clear() _d:clear() end
function M.writeAt(x,y,t) _d:printAt(x,y,t) end
function M.center(y,t) _d:center(y,t) end
function M.bar(x,y,w,f) w=math.max(3,w or 10) f=math.max(0,math.min(1,f or 0)) _d:setCursorPos(x,y) _d:write("[") local filled=math.floor((w-2)*f) for i=1,w-2 do if i<=filled then _d:write("#") else _d:write(" ") end end _d:write("]") end
function M.button(x,y,label) local txt="["..tostring(label or "").."]" _d:printAt(x,y,txt) return {x=x,y=y,w=#txt,h=1,label=label} end
function M.loop(step,tick) tick=tick or 0.2 while true do if type(step)=="function" then local ok,err=pcall(step) if not ok then pcall(function() local log=require("xreactor.shared.log") if log and log.error then log.error("GUI loop error: "..tostring(err)) end end) end end sleep(tick) end end
return M
]]
  save_text("/xreactor/shared/gui.lua",shim)
  say("GUI mkRouter-Shim geschrieben: /xreactor/shared/gui.lua")
end

-- ===== Health-Check =====
local function write_health_check()
  local hc=[[
-- /xreactor/health_check.lua
local function ok(b) return b and "OK" or "FAIL" end
local function exists(p) return fs.exists(p) and not fs.isDir(p) end
print("== XReactor Health-Check ==")
local role="unknown" if fs.exists("/xreactor/role.txt") then local f=fs.open("/xreactor/role.txt","r") role=(f.readLine() or "unknown") f.close() end
print("role.txt:",role)
local aux="/xreactor/node/aux_node.lua"
print("AUX-Datei vorhanden:", ok(exists(aux)))
if exists(aux) then local lf=loadfile(aux) print("AUX-Datei ladbar:", ok(type(lf)=="function")) end
local mh="/xreactor/master/master_home.lua"
print("MASTER-Hauptskript:", ok(exists(mh)))
local gui="/xreactor/shared/gui.lua"
print("GUI vorhanden:", ok(exists(gui)))
local top="/xreactor/shared/topbar.lua"
print("TOPBAR vorhanden:", ok(exists(top)))
local hasModem=false
for _,n in ipairs(peripheral.getNames()) do if peripheral.getType(n)=="modem" then hasModem=true print("Modem "..n..": "..(rednet.isOpen(n) and "offen" or "geschlossen")) end end
print("Mind. ein Modem:", ok(hasModem))
local mon=peripheral.find("monitor"); print("Monitor gefunden:", ok(mon~=nil))
print("== Ende. Wenn alles OK: reboot ==")
]]
  save_text("/xreactor/health_check.lua",hc)
end

-- ===== Main =====
local function run()
  ensure_dirs()
  local role, role_lower = choose_role()
  local auto_master = monitor_present()
  say("Gewählte Rolle:", role, " | Monitor erkannt:", tostring(auto_master))
  say("Freier Speicher:", fmtBytes(getFree())); say("")

  local plan={} for _,p in ipairs(BASE)   do plan[#plan+1]=p end
  if role=="MASTER" or auto_master then for _,p in ipairs(MASTER) do plan[#plan+1]=p end end

  local ok,err=pcall(download_set, plan)
  if not ok then
    say(""); say("❌ Fehler:", tostring(err))
    say("Tipp: Speicher freigeben (z.B. delete /xreactor/log.txt) oder Advanced Computer nutzen.")
    return
  end

  -- Configs
  write_config_identity(role)
  if role=="MASTER" or auto_master then write_config_master() end

  -- Start-Dateien & Rolle
  save_text("/xreactor/master",'shell.run("/xreactor/master/master_home.lua")')
  save_text("/xreactor/node",  'shell.run("/xreactor/node/aux_node.lua")')
  say("Launcher angelegt/aktualisiert: /xreactor/master und /xreactor/node")
  save_text("/xreactor/role.txt",role_lower.."\n"); say("role.txt gesetzt:",role_lower)

  -- GUI-Kompatibilität absichern + Health-Check
  ensure_gui_mkrouter()
  write_health_check()

  say(""); say("✅ Installation fertig. Starte Health-Check …")
  local ok2,err2=pcall(function() dofile("/xreactor/health_check.lua") end)
  if not ok2 then printError("Health-Check Fehler: "..tostring(err2)) end
  say(""); say("→ Wenn alles OK ist: reboot")
end

local ok,err=pcall(run) if not ok then printError(err) end
