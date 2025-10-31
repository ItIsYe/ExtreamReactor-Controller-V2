-- installer.lua  (XReactor Installer mit robustem save_text)
local REPO_BASE = "https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main"

-- === Hilfsfunktionen ===
local function ensureDir(path)
  local parts = {}
  for p in string.gmatch(path, "[^/]+") do parts[#parts+1] = p end
  if #parts <= 1 then return end
  local dir = "/" .. table.concat(parts, "/", 1, #parts - 1)
  if not fs.exists(dir) then fs.makeDir(dir) end
end

local function fmtBytes(n)
  local u = { "B", "KB", "MB" }
  local i = 1
  while n > 1024 and i < #u do n = n / 1024 i = i + 1 end
  return string.format("%.1f %s", n, u[i])
end

local function getFree()
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

local function save_text(path, text)
  ensureDir(path)
  if #text > getFree() - 2048 then return false, "Out of space" end
  local f = fs.open(path, "w")
  if not f then return false, "Pfad nicht verfügbar oder kein Speicherplatz" end
  f.write(text)
  f.close()
  return true
end

local function save_url(url, path)
  local body, err = http_get(url)
  if not body then return false, err end
  return save_text(path, body)
end

local function say(...) print(table.concat({...}, " ")) end
local function ask(prompt, def)
  write(prompt .. (def and (" [" .. def .. "]") or "") .. ": ")
  local a = read()
  if a == "" and def then a = def end
  return a
end

-- === Installer Hauptlogik ===
local function choose_role()
  say("")
  say("Welche Rolle soll dieser Computer übernehmen?")
  say("  [1] MASTER  (UI/Monitor empfohlen)")
  say("  [2] AUX     (Worker/Textmodus)")
  local sel = ask("Auswahl 1/2", "2")
  if tostring(sel) == "1" or tostring(sel):lower() == "master" then
    return "MASTER", "master"
  end
  return "AUX", "node"
end

local MANIFEST_BASE = {
  { "src/shared/protocol.lua", "/xreactor/shared/protocol.lua" },
  { "src/shared/identity.lua", "/xreactor/shared/identity.lua" },
  { "src/shared/log.lua", "/xreactor/shared/log.lua" },
  { "src/node/aux_node.lua", "/xreactor/node/aux_node.lua" },
  { "startup.lua", "/startup.lua" },
}

local MANIFEST_MASTER = {
  { "xreactor/shared/gui.lua", "/xreactor/shared/gui.lua" },
  { "src/master/master_home.lua", "/xreactor/master/master_home.lua" },
  { "src/master/fuel_panel.lua", "/xreactor/master/fuel_panel.lua" },
  { "src/master/waste_panel.lua", "/xreactor/master/waste_panel.lua" },
  { "src/master/alarm_center.lua", "/xreactor/master/alarm_center.lua" },
  { "src/master/overview_panel.lua", "/xreactor/master/overview_panel.lua" },
}

local function write_launchers()
  save_text("/xreactor/master", 'shell.run("/xreactor/master/master_home.lua")')
  save_text("/xreactor/node", 'shell.run("/xreactor/node/aux_node.lua")')
  say("Launcher angelegt: /xreactor/master und /xreactor/node")
end

local function write_role_txt(role_lower)
  save_text("/xreactor/role.txt", role_lower .. "\n")
  say("role.txt gesetzt:", role_lower)
end

local function write_config_identity(role)
  local path = "/xreactor/config_identity.lua"
  if fs.exists(path) then
    say("Config existiert bereits:", path)
    return
  end
  local tpl = ([[return {
  role     = "%s",
  id       = "01",
  hostname = "",
  cluster  = "XR-CLUSTER-ALPHA",
  token    = "xreactor",
}]])
  save_text(path, string.format(tpl, role))
  say("Config geschrieben:", path)
end

local function write_config_master()
  local path = "/xreactor/config_master.lua"
  if fs.exists(path) then return end
  local tpl = [[return {
  modem_side   = nil,   -- z.B. "right"; nil = auto
  monitor_side = nil,   -- z.B. "top";   nil = auto
  text_scale   = 0.5,
}]]
  save_text(path, tpl)
end

local function ensure_dirs()
  for _, d in ipairs({ "/xreactor", "/xreactor/shared", "/xreactor/master", "/xreactor/node" }) do
    if not fs.exists(d) then fs.makeDir(d) end
  end
end

local function download_set(set)
  for i, p in ipairs(set) do
    local src, dst = p[1], p[2]
    local url = REPO_BASE .. "/" .. src
    say(string.format("[%d/%d] %s -> %s", i, #set, src, dst))
    local ok, err = save_url(url, dst)
    if not ok then error(string.format("Fehler bei %s: %s", dst, tostring(err))) end
  end
end

local function run()
  ensure_dirs()
  local role, role_lower = choose_role()
  say("Gewählte Rolle:", role)
  say("")
  say("Freier Speicher vor Installation:", fmtBytes(getFree()))

  local plan = {}
  for _, p in ipairs(MANIFEST_BASE) do plan[#plan + 1] = p end
  if role == "MASTER" then
    for _, p in ipairs(MANIFEST_MASTER) do plan[#plan + 1] = p end
  end

  local ok, err = pcall(download_set, plan)
  if not ok then
    say("")
    say("❌ Fehler:", tostring(err))
    return
  end

  write_config_identity(role)
  if role == "MASTER" then write_config_master() end
  write_launchers()
  write_role_txt(role_lower)

  say("")
  say("✅ Installation abgeschlossen. Empfohlen: reboot")
end

local ok, err = pcall(run)
if not ok then printError(err) end
