-- =========================================================
-- XReactor Node Debug Utility (paged + dump)
-- Listet lokale und via Wired Modem angebundene Peripherals
-- und deren Methoden. Mit Blättern & optionalem Datei-Dump.
-- Steuerung:
--   Space  -> nächste Seite
--   B      -> vorherige Seite
--   Q/Esc  -> beenden
-- =========================================================

local function keyloop()
  while true do
    local e, k = os.pullEvent("key")
    if k == keys.q or k == keys.escape then return "quit"
    elseif k == keys.b then return "prev"
    elseif k == keys.space or k == keys.enter or k == keys.n then return "next"
    end
  end
end

local function wrap(x)
  if type(x) == "string" then return x end
  return textutils.serialize(x)
end

-- collect peripherals
local entries = {}

-- 1) feste Seiten (für direkt angeschlossene Geräte)
local sides = {"top","bottom","left","right","front","back"}
for _,side in ipairs(sides) do
  if peripheral.isPresent(side) then
    local t = peripheral.getType(side) or "unknown"
    local methods = peripheral.getMethods(side) or {}
    table.insert(entries, {
      name = side,
      ptype = t,
      methods = methods,
      is_local = true
    })
  end
end

-- 2) alle bekannten Namen (via Wired Modem/Network)
for _,name in ipairs(peripheral.getNames()) do
  local is_side = false
  for _,s in ipairs(sides) do if s == name then is_side = true break end end
  if not is_side then
    local t = peripheral.getType(name) or "unknown"
    local methods = peripheral.getMethods(name) or {}
    table.insert(entries, {
      name = name,
      ptype = t,
      methods = methods,
      is_local = false
    })
  end
end

-- sort: lokale Seiten zuerst, danach alphabetisch
table.sort(entries, function(a,b)
  if a.is_local ~= b.is_local then return a.is_local end
  return tostring(a.name) < tostring(b.name)
end)

-- build printable lines + optional dump text
local lines = {}
local function pushLine(s) table.insert(lines, s) end

pushLine("=== XReactor Node Debug (local + network) ===")
pushLine(("Gefundene Peripherals: %d"):format(#entries))
pushLine("")

for _,e in ipairs(entries) do
  local tag = e.is_local and "[LOCAL]" or "[NET ]"
  pushLine(("%s %s  %s"):format(tag, e.name, e.ptype))
  if #e.methods == 0 then
    pushLine("  (keine Methoden gefunden)")
  else
    -- Methoden sortiert ausgeben
    local msorted = {}
    for _,m in ipairs(e.methods) do table.insert(msorted, m) end
    table.sort(msorted)
    for _,m in ipairs(msorted) do
      pushLine("  - "..m)
    end
  end
  pushLine("")
end

-- optional: Dump in Datei (immer schreiben, praktisch bei vielen Einträgen)
local function write_dump()
  local ok, err = pcall(function()
    local path = "/xreactor/debug_dump.txt"
    local f = fs.open(path, "w")
    for _,ln in ipairs(lines) do f.write(ln.."\n") end
    f.close()
    return path
  end)
  if ok and err then
    return err
  else
    return nil
  end
end

local dump_path = write_dump()

-- paging render
local function draw_page(idx)
  term.clear()
  term.setCursorPos(1,1)
  local w,h = term.getSize()
  local header = "=== XReactor Node Debug ==="
  local footer = "[Space]=weiter  [B]=zurück  [Q]=quit"
  if dump_path then footer = footer.."  |  Dump: "..dump_path end

  print(header)
  print(("Zeilen gesamt: %d  |  Seite: %d"):format(#lines, idx))
  print(("Peripherals: %d (LOCAL+NET)"):format(#entries))
  print(("—"):rep(math.max(10, w)))

  local start = (idx-1) * (h-5) + 1
  local stop  = math.min(#lines, start + (h-5) - 1)
  for i = start, stop do
    local s = lines[i]
    if s then
      if #s > w then s = s:sub(1, w) end
      print(s)
    end
  end

  term.setCursorPos(1, h)
  term.clearLine()
  write(footer)
end

local page = 1
local w,h = term.getSize()
local max_per_page = h-5
local max_page = math.max(1, math.ceil(#lines / math.max(1, max_per_page)))

while true do
  if page < 1 then page = 1 end
  if page > max_page then page = max_page end
  draw_page(page)

  local act = keyloop()
  if act == "quit" then break
  elseif act == "next" then page = page + 1
  elseif act == "prev" then page = page - 1
  end
end

term.setCursorPos(1, h)
print("")
print("Fertig.")
