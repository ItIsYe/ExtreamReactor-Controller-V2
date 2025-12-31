diff --git a/installer/installer.lua b/installer/installer.lua
index e186f65ce70414af36f8fed6b67a08e8dcb18d67..99f3ab64e3bc3b03f3cab728e216fda54ae07037 100644
--- a/installer/installer.lua
+++ b/installer/installer.lua
@@ -1,235 +1,259 @@
--- installer.lua  (XReactor Hybrid-Installer • inkl. topbar.lua + GUI mkRouter-Fallback + Auto-Health-Check)
-local REPO_BASE = "https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main"
-
--- ===== Utils =====
-local function ensureDir(path)
-  local parts={} for p in path:gmatch("[^/]+") do parts[#parts+1]=p end
-  if #parts<=1 then return end
-  local dir="/"..table.concat(parts,"/",1,#parts-1)
-  if not fs.exists(dir) then fs.makeDir(dir) end
-end
-local function fmtBytes(n) local u={"B","KB","MB"} local i=1 while n>1024 and i<#u do n=n/1024 i=i+1 end return string.format("%.1f %s",n,u[i]) end
-local function getFree() local ok,free=pcall(function() return fs.getFreeSpace("/") end) return ok and free or 0 end
-local function http_get(url) local ok,h=pcall(http.get,url,nil,true) if not ok or not h then return nil,"HTTP-Fehler" end local b=h.readAll() or "" h.close() if b=="" then return nil,"Leerer Inhalt" end return b end
-local function save_text(path,text) ensureDir(path) if #text>getFree()-2048 then return false,"Out of space" end local f=fs.open(path,"w") if not f then return false,"Pfad nicht verfügbar oder kein Speicherplatz" end f.write(text) f.close() return true end
-local function save_url(url,path) local body,err=http_get(url) if not body then return false,err end return save_text(path,body) end
-local function say(...) print(table.concat({...}," ")) end
-local function ask(prompt,def) write(prompt..(def and (" ["..def.."]") or "")..": ") local a=read() if a=="" and def then a=def end return a end
-local function monitor_present() local ok,mon=pcall(function() return peripheral.find("monitor") end) return ok and (mon~=nil) end
-
--- ===== Rolle =====
-local function choose_role()
-  say("")
-  say("[1] MASTER (UI)   [2] REACTOR   [3] ENERGY   [4] FUEL   [5] REPROCESS")
-  local sel=ask("Auswahl 1-5","2")
-  local val=tostring(sel):lower()
-  if val=="1" or val=="master" then return "MASTER","master" end
-  if val=="3" or val=="energy" then return "ENERGY","energy" end
-  if val=="4" or val=="fuel" then return "FUEL","fuel" end
-  if val=="5" or val=="reprocess" or val=="reprocessing" then return "REPROCESS","reprocess" end
-  return "REACTOR","reactor"
-end
-
--- ===== Manifeste =====
--- Basis inkl. Node-Runtime + Topbar
-local BASE = {
-  {"src/shared/protocol.lua",          "/xreactor/shared/protocol.lua"},
-  {"src/shared/identity.lua",          "/xreactor/shared/identity.lua"},
-  {"src/shared/log.lua",               "/xreactor/shared/log.lua"},
-  {"src/shared/topbar.lua",            "/xreactor/shared/topbar.lua"},
-  {"src/shared/network_dispatcher.lua","/xreactor/shared/network_dispatcher.lua"},
-  {"src/shared/node_state_machine.lua", "/xreactor/shared/node_state_machine.lua"},
-  {"src/shared/node_runtime.lua",      "/xreactor/shared/node_runtime.lua"},
-  {"src/node/node_core.lua",           "/xreactor/node/node_core.lua"},
-  {"src/node/reactor_node.lua",        "/xreactor/node/reactor_node.lua"},
-  {"src/node/energy_node.lua",         "/xreactor/node/energy_node.lua"},
-  {"src/node/fuel_node.lua",           "/xreactor/node/fuel_node.lua"},
-  {"src/node/reprocessing_node.lua",   "/xreactor/node/reprocessing_node.lua"},
-  {"startup.lua",                      "/startup.lua"},
+
+local function abort_if_html_download()
+  local program = shell and shell.getRunningProgram and shell.getRunningProgram()
+  if not program or program == "" or not fs.exists(program) then
+    return false
+  end
+
+  local handle = fs.open(program, "r")
+  if not handle then return false end
+
+  local sample = string.lower(handle.read(512) or "")
+  handle.close()
+
+  if sample:find("<!doctype", 1, true) or sample:find("<html", 1, true) then
+    print("Installer download appears to be HTML.")
+    print("Please download installer.lua from raw.githubusercontent.com and retry.")
+    return true
+  end
+
+  return false
+end
+
+if abort_if_html_download() then return end
+
+-- Interactive role selector for XReactor startup configuration
+
+local ROLE_SOURCE_FILES = {
+  MASTER       = "src/master/master_home.lua",
+  REACTOR      = "src/node/reactor_node.lua",
+  ENERGY       = "src/node/energy_node.lua",
+  FUEL         = "src/node/fuel_node.lua",
+  REPROCESSING = "src/node/reprocessing_node.lua",
 }
--- MASTER-UI
-local MASTER = {
-  {"xreactor/shared/gui.lua",       "/xreactor/shared/gui.lua"},
-  {"src/master/master_home.lua",    "/xreactor/master/master_home.lua"},
-  {"src/master/fuel_panel.lua",     "/xreactor/master/fuel_panel.lua"},
-  {"src/master/waste_panel.lua",    "/xreactor/master/waste_panel.lua"},
-  {"src/master/alarm_center.lua",   "/xreactor/master/alarm_center.lua"},
-  {"src/master/overview_panel.lua", "/xreactor/master/overview_panel.lua"},
+
+local ROLE_LIST = {
+  { name = "MASTER",       description = "Cluster UI and coordinator" },
+  { name = "REACTOR",      description = "Controls the main reactor node" },
+  { name = "ENERGY",       description = "Manages power transfer" },
+  { name = "FUEL",         description = "Handles fuel processing" },
+  { name = "REPROCESSING", description = "Supervises reprocessing" },
 }
 
--- ===== Schreiben & Helfer =====
-local function ensure_dirs()
-  for _,d in ipairs({"/xreactor","/xreactor/shared","/xreactor/master","/xreactor/node"}) do
-    if not fs.exists(d) then fs.makeDir(d) end
-  end
-end
-local function download_set(set)
-  for i,p in ipairs(set) do
-    local src,dst=p[1],p[2]; local url=REPO_BASE.."/"..src
-    say(string.format("[%d/%d] %s -> %s",i,#set,src,dst))
-    local ok,err=save_url(url,dst)
-    if not ok then error(("Fehler bei %s: %s"):format(dst,tostring(err))) end
-  end
-end
-local function write_config_identity(role)
-  local path="/xreactor/config_identity.lua"
-  if fs.exists(path) then say("Config existiert bereits:",path) return end
-  local tpl=([[return {
-  role     = "%s",
-  id       = "01",
-  hostname = "",
-  cluster  = "XR-CLUSTER-ALPHA",
-  token    = "xreactor",
-}]])
-  save_text(path,string.format(tpl,role)); say("Config geschrieben:",path)
-end
-local function write_config_master()
-  local path="/xreactor/config_master.lua"
-  if fs.exists(path) then return end
-  save_text(path,[[return {
-  modem_side   = nil,   -- "right" o.ä., nil=auto
-  monitor_side = nil,   -- "top"  o.ä.,  nil=auto
-  text_scale   = 0.5,
-}]])
-end
-local function write_launchers(role)
-  local map=[[
-local function choose()
-  local ok,cfg=pcall(function() return require("xreactor.config_identity") end)
-  local fallback="%s"
-  local role_val=(ok and cfg and cfg.role) or fallback
-  local upper=string.upper(tostring(role_val or "REACTOR"))
-  local paths={
-    MASTER      = "/xreactor/master/master_home.lua",
-    REACTOR     = "/xreactor/node/reactor_node.lua",
-    ENERGY      = "/xreactor/node/energy_node.lua",
-    FUEL        = "/xreactor/node/fuel_node.lua",
-    REPROCESS   = "/xreactor/node/reprocessing_node.lua",
-  }
-  return paths[upper] or paths.REACTOR
-end
-local target=choose()
-shell.run(target)
-]]
-  save_text("/xreactor/master",'shell.run("/xreactor/master/master_home.lua")')
-  save_text("/xreactor/node",  string.format(map, role or "REACTOR"))
-  say("Launcher angelegt/aktualisiert: /xreactor/master und /xreactor/node")
-end
-local function write_role_txt(role_lower)
-  save_text("/xreactor/role.txt",role_lower.."\n"); say("role.txt gesetzt:",role_lower)
-end
-
--- ===== GUI-Fallback (mkRouter) =====
-local function ensure_gui_mkrouter()
-  local ok,gui=pcall(function() return dofile("/xreactor/shared/gui.lua") end)
-  local has = ok and type(gui)=="table" and type(gui.mkRouter)=="function"
-  if has then return end
-  local shim=[[
--- /xreactor/shared/gui.lua  (mkRouter-Shim)
-local M={}
-local function resolveMonitor(name)
-  local dev
-  if type(name)=="string" and name~="" then pcall(function() dev=peripheral.wrap(name) end) end
-  if not dev then dev=peripheral.find("monitor") end
-  if not dev then dev=term.current() end
-  return dev
-end
-function M.mkRouter(opts)
-  opts=opts or {}
-  local dev=resolveMonitor(opts.monitorName or opts.monitor_side)
-  local r={dev=dev}
-  function r:setTextScale(s) if self.dev.setTextScale then pcall(self.dev.setTextScale,s or 0.5) end end
-  function r:getSize() if self.dev.getSize then return self.dev.getSize() end return term.getSize() end
-  function r:clear() if self.dev.clear then self.dev.clear() else term.clear() end if self.dev.setCursorPos then self.dev.setCursorPos(1,1) else term.setCursorPos(1,1) end end
-  function r:setCursorPos(x,y) if self.dev.setCursorPos then self.dev.setCursorPos(x,y) else term.setCursorPos(x,y) end end
-  function r:write(t) t=tostring(t or "") if self.dev.write then self.dev.write(t) else term.write(t) end end
-  function r:printAt(x,y,t) self:setCursorPos(x,y) self:write(t) end
-  function r:center(y,t) local w=select(1,self:getSize()) local s=tostring(t or "") local x=math.max(1,math.floor((w-#s)/2)+1) self:printAt(x,y,s) end
-  return r
-end
-local _d=M.mkRouter({})
-function M.init() end
-function M.clear() _d:clear() end
-function M.writeAt(x,y,t) _d:printAt(x,y,t) end
-function M.center(y,t) _d:center(y,t) end
-function M.bar(x,y,w,f) w=math.max(3,w or 10) f=math.max(0,math.min(1,f or 0)) _d:setCursorPos(x,y) _d:write("[") local filled=math.floor((w-2)*f) for i=1,w-2 do if i<=filled then _d:write("#") else _d:write(" ") end end _d:write("]") end
-function M.button(x,y,label) local txt="["..tostring(label or "").."]" _d:printAt(x,y,txt) return {x=x,y=y,w=#txt,h=1,label=label} end
-function M.loop(step,tick) tick=tick or 0.2 while true do if type(step)=="function" then local ok,err=pcall(step) if not ok then pcall(function() local log=require("xreactor.shared.log") if log and log.error then log.error("GUI loop error: "..tostring(err)) end end) end end sleep(tick) end end
-return M
-]]
-  save_text("/xreactor/shared/gui.lua",shim)
-  say("GUI mkRouter-Shim geschrieben: /xreactor/shared/gui.lua")
-end
-
--- ===== Health-Check =====
-local function write_health_check(role)
-  local hc=[[
--- /xreactor/health_check.lua
-local function ok(b) return b and "OK" or "FAIL" end
-local function exists(p) return fs.exists(p) and not fs.isDir(p) end
-print("== XReactor Health-Check ==")
-local role="unknown" if fs.exists("/xreactor/role.txt") then local f=fs.open("/xreactor/role.txt","r") role=(f.readLine() or "unknown") f.close() end
-print("role.txt:",role)
-local node=[[ROLEPATH]]
-print("Node-Datei vorhanden:", ok(exists(node)))
-if exists(node) then local lf=loadfile(node) print("Node-Datei ladbar:", ok(type(lf)=="function")) end
-local mh="/xreactor/master/master_home.lua"
-print("MASTER-Hauptskript:", ok(exists(mh)))
-local gui="/xreactor/shared/gui.lua"
-print("GUI vorhanden:", ok(exists(gui)))
-local top="/xreactor/shared/topbar.lua"
-print("TOPBAR vorhanden:", ok(exists(top)))
-local hasModem=false
-for _,n in ipairs(peripheral.getNames()) do if peripheral.getType(n)=="modem" then hasModem=true print("Modem "..n..": "..(rednet.isOpen(n) and "offen" or "geschlossen")) end end
-print("Mind. ein Modem:", ok(hasModem))
-local mon=peripheral.find("monitor"); print("Monitor gefunden:", ok(mon~=nil))
-print("== Ende. Wenn alles OK: reboot ==")
-]]
-  local paths={
-    MASTER      = "/xreactor/master/master_home.lua",
-    REACTOR     = "/xreactor/node/reactor_node.lua",
-    ENERGY      = "/xreactor/node/energy_node.lua",
-    FUEL        = "/xreactor/node/fuel_node.lua",
-    REPROCESS   = "/xreactor/node/reprocessing_node.lua",
-  }
-  local node_path=paths[(role or "REACTOR"):upper()] or paths.REACTOR
-  save_text("/xreactor/health_check.lua",hc:gsub("%[%[ROLEPATH%]%]", node_path))
-end
-
--- ===== Main =====
-local function run()
-  ensure_dirs()
-  local role, role_lower = choose_role()
-  local auto_master = monitor_present()
-  say("Gewählte Rolle:", role, " | Monitor erkannt:", tostring(auto_master))
-  say("Freier Speicher:", fmtBytes(getFree())); say("")
-
-  local plan={} for _,p in ipairs(BASE)   do plan[#plan+1]=p end
-  if role=="MASTER" or auto_master then for _,p in ipairs(MASTER) do plan[#plan+1]=p end end
-
-  local ok,err=pcall(download_set, plan)
+local function center_print(y, text)
+  local w = term.getSize()
+  local x = math.max(1, math.floor((w - #text) / 2) + 1)
+  term.setCursorPos(x, y)
+  term.write(text)
+end
+
+local function installer_dir()
+  local program = shell and shell.getRunningProgram and shell.getRunningProgram()
+  if not program or program == "" then
+    return "/"
+  end
+  local dir = fs.getDir(program)
+  if dir == "" then return "/" end
+  return "/" .. dir
+end
+
+local function load_manifest()
+  local path = fs.combine(installer_dir(), "manifest.lua")
+  local ok, manifest = pcall(dofile, path)
   if not ok then
-    say(""); say("❌ Fehler:", tostring(err))
-    say("Tipp: Speicher freigeben (z.B. delete /xreactor/log.txt) oder Advanced Computer nutzen.")
+    return nil, "Unable to load manifest: " .. tostring(manifest)
+  end
+  if type(manifest) ~= "table" or type(manifest.files) ~= "table" then
+    return nil, "Manifest missing file list"
+  end
+  return manifest
+end
+
+local function build_role_targets(manifest)
+  local targets = {}
+  for role, src in pairs(ROLE_SOURCE_FILES) do
+    for _, file in ipairs(manifest.files) do
+      if file.src == src then
+        targets[role] = file.dst
+        break
+      end
+    end
+  end
+  return targets
+end
+
+local function is_advanced_computer()
+  return term.isColor and term.isColor()
+end
+
+local function wait_for_key()
+  os.pullEvent("key")
+end
+
+local function draw_menu(selected)
+  term.clear()
+  term.setCursorPos(1, 1)
+  center_print(1, "XReactor Role Installer")
+  center_print(3, "Use ↑/↓ or W/S to select a role, Enter to continue")
+
+  for i, role in ipairs(ROLE_LIST) do
+    local prefix = "[ ]"
+    if i == selected then prefix = "[>]" end
+    local line = string.format("%s %s - %s", prefix, role.name, role.description)
+    term.setCursorPos(3, 4 + i)
+    term.clearLine()
+    term.write(line)
+  end
+end
+
+local function select_role()
+  local selected = 1
+  while true do
+    draw_menu(selected)
+    local event, code = os.pullEvent()
+    if event == "key" then
+      if code == keys.up or code == keys.w then
+        selected = (selected == 1) and #ROLE_LIST or (selected - 1)
+      elseif code == keys.down or code == keys.s then
+        selected = (selected == #ROLE_LIST) and 1 or (selected + 1)
+      elseif code == keys.enter or code == keys.numPadEnter or code == keys.space then
+        return ROLE_LIST[selected]
+      end
+    elseif event == "char" then
+      if code == "w" then
+        selected = (selected == 1) and #ROLE_LIST or (selected - 1)
+      elseif code == "s" then
+        selected = (selected == #ROLE_LIST) and 1 or (selected + 1)
+      elseif code >= "1" and code <= tostring(#ROLE_LIST) then
+        selected = tonumber(code)
+      end
+    end
+  end
+end
+
+local function confirm_role(role, role_targets)
+  while true do
+    term.clear()
+    term.setCursorPos(1, 2)
+    center_print(2, "Confirm role selection")
+    center_print(4, "Role: " .. role.name)
+    center_print(5, "Target: " .. (role_targets[role.name] or "unknown"))
+    center_print(7, "Press Y/Enter to confirm or N to go back")
+
+    local event, code = os.pullEvent()
+    if event == "char" then
+      local c = string.lower(code)
+      if c == "y" then return true end
+      if c == "n" then return false end
+    elseif event == "key" then
+      if code == keys.enter or code == keys.numPadEnter then return true end
+      if code == keys.backspace then return false end
+    end
+  end
+end
+
+local function resolve_target(role_name, role_targets)
+  local target = role_targets[role_name]
+  if not target then
+    return nil, "No destination recorded for role: " .. tostring(role_name)
+  end
+  if not fs.exists(target) then
+    return nil, "Startup target missing: " .. target
+  end
+  return target
+end
+
+local function write_startup(role_name, target)
+  local contents = string.format([[-- Auto-generated startup for role %s
+local target = %q
+
+package.path = table.concat({
+  "/xreactor/?.lua",
+  "/xreactor/?/init.lua",
+  "/xreactor/?/?.lua",
+  "/?.lua",
+}, ";")
+
+if not fs.exists(target) then
+  print("Startup target missing: " .. target)
+  return
+end
+
+local loader = loadfile(target)
+if not loader then
+  print("Unable to load " .. target)
+  return
+end
+
+local ok, err = pcall(loader)
+if not ok then
+  print("Error while running " .. target .. ": " .. tostring(err))
+end
+]], role_name, target)
+
+  local handle = fs.open("/startup.lua", "w")
+  if not handle then
+    error("Cannot open /startup.lua for writing")
+  end
+  handle.write(contents)
+  handle.close()
+end
+
+local function main()
+  term.setCursorBlink(false)
+  local manifest, manifest_err = load_manifest()
+  if not manifest then
+    term.clear()
+    center_print(2, "Cannot read installer manifest.")
+    center_print(4, manifest_err)
+    center_print(6, "Press any key to exit.")
+    wait_for_key()
     return
   end
 
-  -- Configs
-  write_config_identity(role)
-  if role=="MASTER" or auto_master then write_config_master() end
+  local role_targets = build_role_targets(manifest)
+  local choice
 
-  -- Start-Dateien & Rolle
-  save_text("/xreactor/role.txt",role_lower.."\n"); say("role.txt gesetzt:",role_lower)
-  write_launchers(role)
+  while true do
+    choice = select_role()
+    if confirm_role(choice, role_targets) then break end
+  end
 
-  -- GUI-Kompatibilität absichern + Health-Check
-  ensure_gui_mkrouter()
-  write_health_check(role)
+  if choice.name == "MASTER" and not is_advanced_computer() then
+    term.clear()
+    center_print(2, "MASTER role requires an Advanced Computer.")
+    center_print(4, "Install on an Advanced Computer and retry.")
+    center_print(6, "Press any key to exit.")
+    wait_for_key()
+    return
+  end
 
-  say(""); say("✅ Installation fertig. Starte Health-Check …")
-  local ok2,err2=pcall(function() dofile("/xreactor/health_check.lua") end)
-  if not ok2 then printError("Health-Check Fehler: "..tostring(err2)) end
-  say(""); say("→ Wenn alles OK ist: reboot")
+  local target, err = resolve_target(choice.name, role_targets)
+  if not target then
+    term.clear()
+    center_print(2, "Cannot configure startup.")
+    center_print(4, err)
+    center_print(6, "Press any key to exit.")
+    wait_for_key()
+    return
+  end
+
+  write_startup(choice.name, target)
+
+  term.clear()
+  term.setCursorPos(1, 2)
+  center_print(2, "Startup configured for role: " .. choice.name)
+  center_print(4, "Target file: " .. target)
+  center_print(6, "Reboot the computer to launch the selected role.")
+  center_print(8, "Installer will now exit.")
 end
 
-local ok,err=pcall(run) if not ok then printError(err) end
+local ok, err = pcall(main)
+if not ok then
+  term.clear()
+  term.setCursorPos(1, 2)
+  center_print(2, "Installer error:")
+  center_print(4, tostring(err))
+  center_print(6, "Press any key to exit.")
+  os.pullEvent("key")
+end
