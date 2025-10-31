-- installer.lua  (XReactor Light/Role-based Installer)
-- Quelle: https://github.com/ItIsYe/ExtreamReactor-Controller-V2
-- Nutzung:   dofile("installer.lua")   oder   wget run <RAW-URL-zu-dieser-Datei>

local REPO_BASE = "https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main"

-- -------- utils --------
local function ensureDir(path)
  local parts = {}; for p in string.gmatch(path, "[^/]+") do parts[#parts+1]=p end
  if #parts <= 1 then return end
  local dir = "/"..table.concat(parts, "/", 1, #parts-1)
  if not fs.exists(dir) then fs.makeDir(dir) end
end

local function fmtBytes(n)
  local units = {"B","KB","MB"}; local i=1
  while n>1024 and i<#units do n=n/1024 i=i+1 end
  return string.format("%.1f %s", n, units[i])
end

local function getFree()
  if fs.getFreeSpace then return fs.getFreeSpace("/") end
  -- ältere CC-Versionen
  local ok, free = pcall(function() return fs.getFreeSpace("/") end)
  return ok and free or 0
end

local function http_get(url)
  local ok, h = pcall(http.get, url, nil, true)
  if not ok or not h then return nil, "HTTP-Fehler" end
  local body = h.readAll() or ""
  h.close()
  if body == "" then return nil, "Leerer Inhalt" end
  return body
end

local function save_url(url, path)
  local body, err = http_get(url)
  if not body then return false, err end
  ensureDir(path)
  if #body > getFree() - 2048 then
    return false, "Out of space"
  end
  local f = fs.open(path, "w")
  f.write(body)
  f.close()
  return true
end

local function say(...)
  print(table.concat({...}," "))
end

local function ask(prompt, def)
  write(prompt .. (def and (" ["..def.."]") or "") .. ": ")
  local a = read()
  if a == "" and def then a = def end
  return a
end

-- -------- self install --------
local function self_install()
  local target = "/xreactor/installer.lua"
  say("== ExtreamReactor Installer ==")
  say("Speichere Installer nach ", target, " …")
  local ok, err = save_url(REPO_BASE.."/installer/installer.lua", target)
  if ok then
    say("Installer aktualisiert.")
  else
    say("Hinweis: Konnte Original-Installer nicht speichern (", tostring(err), ").")
    -- Nicht kritisch: wir laufen ja bereits. Weiter …
  end
end

-- -------- role selection --------
local function choose_role()
  say("")
  say("Welche Rolle soll dieser Computer übernehmen?")
  say("  [1] MASTER  (UI/Bedienoberfläche, Monitor empfohlen)")
  say("  [2] AUX     (Worker/Textmodus, minimaler Umfang)")
  local sel = ask("Auswahl 1/2", "2")
  if tostring(sel) == "1" or tostring(sel):lower()=="master" then return "MASTER" end
  return "AUX"
end

-- -------- manifests (quelle → ziel) --------
local MANIFEST_SHARED = {
  {"src/shared/protocol.lua", "/xreactor/shared/protocol.lua"},
  {"src/shared/identity.lua", "/xreactor/shared/identity.lua"},
  {"src/shared/log.lua",      "/xreactor/shared/log.lua"},
  {"startup.lua",             "/startup.lua"},
}

local MANIFEST_MASTER = {
  {"xreactor/shared/gui.lua",             "/xreactor/shared/gui.lua"}, -- GUI aus Repo (falls vorhanden)
  {"src/master/master_home.lua",          "/xreactor/master/master_home.lua"},
  {"src/master/fuel_panel.lua",           "/xreactor/master/fuel_panel.lua"},
  {"src/master/waste_panel.lua",          "/xreactor/master/waste_panel.lua"},
  {"src/master/alarm_center.lua",         "/xreactor/master/alarm_center.lua"},
  {"src/master/overview_panel.lua",       "/xreactor/master/overview_panel.lua"},
}

local MANIFEST_AUX = {
  {"src/node/aux_node.lua",               "/xreactor/node/aux_node.lua"},
}

-- -------- write config templates --------
local function write_config_identity(role)
  local path = "/xreactor/config_identity.lua"
  if fs.exists(path) then
    say("Config existiert bereits:", path)
    return
  end
  local tpl = [[return {
  role     = "%s",
  id       = "01",
  hostname = "",
  cluster  = "XR-CLUSTER-ALPHA",
  token    = "xreactor",
}]]
  ensureDir(path)
  local f = fs.open(path, "w")
  f.write(string.format(tpl, role))
  f.close()
  say("Config geschrieben:", path)
end

local function write_config_master()
  local path = "/xreactor/config_master.lua"
  if fs.exists(path) then return end
  local tpl = [[return {
  modem_side   = nil,   -- z.B. "right"; nil = auto
  monitor_side = nil,   -- z.B. "top"; nil = auto
  text_scale   = 0.5,
}]]
  ensureDir(path)
  local f = fs.open(path, "w")
  f.write(tpl)
  f.close()
end

-- -------- installer core --------
local function ensure_dirs()
  for _, d in ipairs({
    "/xreactor", "/xreactor/shared", "/xreactor/master", "/xreactor/node"
  }) do if not fs.exists(d) then fs.makeDir(d) end end
end

local function download_set(set)
  for i, pair in ipairs(set) do
    local src, dst = pair[1], pair[2]
    local url = REPO_BASE.."/"..src
    say(string.format("[%d/%d] %s -> %s", i, #set, src, dst))
    local ok, err = save_url(url, dst)
    if not ok then
      error(string.format("Fehler bei %s: %s", dst, tostring(err)))
    end
  end
end

local function run()
  self_install()
  ensure_dirs()

  local role = choose_role()
  say("Gewählte Rolle:", role)
  say("")
  say("Freier Speicher vor Installation:", fmtBytes(getFree()))

  local plan = {}
  -- immer Shared
  for _,p in ipairs(MANIFEST_SHARED) do plan[#plan+1]=p end
  if role == "MASTER" then
    for _,p in ipairs(MANIFEST_MASTER) do plan[#plan+1]=p end
  else
    for _,p in ipairs(MANIFEST_AUX) do plan[#plan+1]=p end
  end

  -- grobe Größen-Schätzung (nur HTTP-Abfrage pro Datei wäre zu teuer; wir vertrauen aufs Limit-Handling)
  local ok, err = pcall(download_set, plan)
  if not ok then
    if tostring(err):match("Out of space") then
      say("")
      say("❌ Fehler: Nicht genug Speicherplatz. Bitte Dateien löschen oder auf Advanced Computer wechseln.")
      say("Tipp:  delete /xreactor/log.txt   oder  delete /old  /logs  /programs  (falls vorhanden)")
      return
    else
      say("")
      say("❌ Download-Fehler: ", tostring(err))
      return
    end
  end

  -- configs
  write_config_identity(role)
  if role == "MASTER" then write_config_master() end

  say("")
  say("✅ Installation abgeschlossen.")
  say("Empfohlen: reboot")
end

-- entry
local ok, err = pcall(run)
if not ok then
  printError(err)
end
