-- gui.lua – sehr einfache Formular-UI für Computer/Monitore
-- Nutzt IMMER das aktuell gesetzte Terminal (term.redirect entscheidet der Aufrufer)

local gui = {}

local function centerText(y, text)
  local w, _ = term.getSize()
  local x = math.floor((w - #text) / 2) + 1
  term.setCursorPos(math.max(1,x), y)
  term.write(text)
end

-- Einfache Eingabezeile mit Default (Leer = behalte)
local function prompt(y, label, current)
  term.setCursorPos(1, y); term.clearLine()
  term.write(label .. " [" .. (current == nil and "" or tostring(current)) .. "]: ")
  return read()
end

-- Spezifikation:
-- spec = { {key="name", label="Name", type="text|number|toggle|list"}, ... }
-- values = Tabelle mit initialen Werten
function gui.form(title, spec, values)
  values = values or {}
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.white)
  term.clear()

  centerText(1, tostring(title))
  term.setCursorPos(1,3)
  print("(Eingabe + Enter. Leer = Wert behalten. Toggle: y/n, true/false)")

  local y = 5
  local out = {}
  for i,field in ipairs(spec or {}) do
    local cur = values[field.key]
    local inp = prompt(y, field.label, cur); y = y + 1

    if inp == nil then inp = "" end
    if inp == "" then
      out[field.key] = cur
    else
      local t = field.type or "text"
      if t == "number" then
        local n = tonumber(inp)
        if n == nil then
          print("  -> Ungueltige Zahl, behalte alten Wert"); out[field.key] = cur
        else
          out[field.key] = n
        end
      elseif t == "toggle" then
        local s = tostring(inp):lower()
        out[field.key] = (s=="y" or s=="yes" or s=="true" or s=="1")
      elseif t == "list" then
        -- Kommagetrennt in Tabelle
        local list = {}
        for part in inp:gmatch("[^,]+") do
          local v = part:gsub("^%s+",""):gsub("%s+$","")
          if v ~= "" then table.insert(list, v) end
        end
        out[field.key] = list
      else
        out[field.key] = inp
      end
    end
  end

  term.setCursorPos(1, y+1)
  print("[Enter] Speichern, [Esc] Abbrechen …")
  while true do
    local e, key = os.pullEvent("key")
    if key == keys.enter then
      return "save", out
    elseif key == keys.escape then
      return "cancel", values
    end
  end
end

-- ein paar kleine Helfer für Überschriften/Labels (optional)
function gui.header(text)
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.white)
  term.clear()
  centerText(1, text)
end

function gui.label(x, y, text, color)
  term.setCursorPos(x, y)
  if color then term.setTextColor(color) end
  term.write(text)
  if color then term.setTextColor(colors.white) end
end

return gui
