--========================================================
-- /xreactor/tools/build_ui_map.lua
-- Interaktiver Builder für /xreactor/ui_map.lua
--========================================================
local roles={"master_home","fuel_manager","waste_service","alarm_center","system_overview"}

local TEXT_UTILS_PATH = "/xreactor/shared/text.lua"

local function resolve_text_utils()
  if not (fs and fs.exists and fs.exists(TEXT_UTILS_PATH)) then
    error("Unable to locate text utilities (text.lua) at " .. TEXT_UTILS_PATH)
  end

  local ok, mod = pcall(dofile, TEXT_UTILS_PATH)
  if ok and mod and mod.sanitizeText then return mod.sanitizeText end

  error("Unable to load text utilities from " .. TEXT_UTILS_PATH .. ": " .. tostring(mod))
end

local sanitizeText = resolve_text_utils()

local function safe_print(text)
  print(sanitizeText(text))
end

local function safe_write(text)
  io.write(sanitizeText(text))
end

local function read_line(prompt, default)
  safe_write(prompt); if default then safe_write(" ["..tostring(default).."]") end; safe_write(": ")
  local s = read() or ""; s=s:gsub("^%s+",""):gsub("%s+$",""); if s=="" and default then return default end; return s
end

local function propose_scale(w,h) local a=(tonumber(w) or 0)*(tonumber(h) or 0); if a>=2400 then return 0.5 elseif a>=1200 then return 1.0 else return 2.0 end end

local mons={}
for _,n in ipairs(peripheral.getNames()) do
  if peripheral.getType(n)=="monitor" then local m=peripheral.wrap(n); local w,h=0,0; if m and m.getSize then w,h=m.getSize() end; table.insert(mons,{name=n,w=w,h=h}) end
end
if #mons==0 then safe_print("Keine Monitore gefunden."); return end
table.sort(mons,function(a,b) return tostring(a.name)<tostring(b.name) end)

safe_print("Gefundene Monitore:"); for i,m in ipairs(mons) do safe_print(string.format("  %d) %s (%dx%d)", i,m.name,m.w,m.h)) end; safe_print("")

local map={}
for i,m in ipairs(mons) do
  local role = read_line("Rolle für "..m.name, roles[math.min(i,#roles)] or "system_overview")
  local known=false; for _,r in ipairs(roles) do if r==role then known=true break end end; if not known then safe_print("  Unbekannte Rolle, nutze 'system_overview'."); role="system_overview" end
  local sc = tonumber(read_line("Textscale für "..m.name.." (0.5/1/2)", tostring(propose_scale(m.w,m.h)))) or 1.0
  map[m.name] = { role=role, scale=sc }
  safe_print("")
end

local path="/xreactor/ui_map.lua"
local h=fs.open(path,"w")
h.writeLine("-- automatisch erzeugt von /xreactor/tools/build_ui_map.lua")
h.writeLine("return {"); h.writeLine("  monitors = {")
for name,cfg in pairs(map) do h.writeLine(string.format("    [\"%s\"] = { role = %q, scale = %s },", name, cfg.role, tostring(cfg.scale))) end
h.writeLine("  },"); h.writeLine("  autoscale = { enabled = true },"); h.writeLine("}")
h.close()

safe_print("Geschrieben: "..path.."\nFertig.")

