-- Extreme Reactor Controller – Startup
-- Startet beim Booten automatisch Master oder Node.
-- Erste Ausführung: fragt Rolle ab und merkt sie sich in /xreactor/role.txt

local baseDir   = "/xreactor"
local roleFile  = baseDir.."/role.txt"
local exec = { master = baseDir.."/master", node = baseDir.."/node" }

local function exists(p) return fs.exists(p) and not fs.isDir(p) end

local function chooseRole()
  term.clear(); term.setCursorPos(1,1)
  print("Extreme Reactor Controller – Setup")
  print("Welche Rolle soll dieses System haben?")
  print("[1] Master")
  print("[2] Node")
  write("> ")
  local c = read()
  if c == "1" then return "master"
  elseif c == "2" then return "node"
  else
    print("Abbruch. (ungueltige Eingabe)")
    sleep(1)
    return nil
  end
end

local function loadRole()
  if exists(roleFile) then
    local f = fs.open(roleFile, "r"); local r = f.readAll(); f.close()
    r = (r or ""):gsub("%s+", "")
    if r == "master" or r == "node" then return r end
  end
  return nil
end

local function saveRole(r)
  if not fs.exists(baseDir) then fs.makeDir(baseDir) end
  local f = fs.open(roleFile, "w"); f.write(r); f.close()
end

local function runRole(r)
  local path = exec[r]
  if not path or not exists(path) then
    print("Fehler: Programm fuer Rolle '"..tostring(r).."' nicht gefunden: "..tostring(path))
    print("Bitte Installer erneut ausfuehren oder Rolle aendern mit: delete "..roleFile)
    sleep(3); return
  end
  print("Starte "..r.."...")
  local ok, err = pcall(function() shell.run(path) end)
  if not ok then
    print("Programm abgestuerzt: "..tostring(err))
    print("Neustart in 5s (Strg+T zum Abbrechen).")
    sleep(5)
    os.reboot()
  end
end

-- --- Main ---
local role = loadRole()
if not role then
  role = chooseRole()
  if not role then return end
  saveRole(role)
end
runRole(role)

