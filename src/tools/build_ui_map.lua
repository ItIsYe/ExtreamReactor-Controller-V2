--========================================================
-- /xreactor/tools/build_ui_map.lua
-- Interaktiver Builder für /xreactor/ui_map.lua
--========================================================
local roles={"master_home","fuel_manager","waste_service","alarm_center","system_overview"}

local function read_line(prompt, default)
  io.write(prompt); if default then io.write(" ["..tostring(default).."]") end; io.write(": ")
  local s = read() or ""; s=s:gsub("^%s+",""):gsub("%s+$",""); if s=="" and default then return default end; return s
end

local function propose_scale(w,h) local a=(tonumber(w) or 0)*(tonumber(h) or 0); if a>=2400 then return 0.5 elseif a>=1200 then return 1.0 else return 2.0 end end

local mons={}
for _,n in ipairs(peripheral.getNames()) do
  if peripheral.getType(n)=="monitor" then local m=peripheral.wrap(n); local w,h=0,0; if m and m.getSize then w,h=m.getSize() end; table.insert(mons,{name=n,w=w,h=h}) end
end
if #mons==0 then print("Keine Monitore gefunden."); return end
table.sort(mons,function(a,b) return tostring(a.name)<tostring(b.name) end)

print("Gefundene Monitore:"); for i,m in ipairs(mons) do print(string.format("  %d) %s (%dx%d)", i,m.name,m.w,m.h)) end; print("")

local map={}
for i,m in ipairs(mons) do
  local role = read_line("Rolle für "..m.name, roles[math.min(i,#roles)] or "system_overview")
  local known=false; for _,r in ipairs(roles) do if r==role then known=true break end end; if not known then print("  Unbekannte Rolle, nutze 'system_overview'."); role="system_overview" end
  local sc = tonumber(read_line("Textscale für "..m.name.." (0.5/1/2)", tostring(propose_scale(m.w,m.h)))) or 1.0
  map[m.name] = { role=role, scale=sc }
  print("")
end

local path="/xreactor/ui_map.lua"
local h=fs.open(path,"w")
h.writeLine("-- automatisch erzeugt von /xreactor/tools/build_ui_map.lua")
h.writeLine("return {"); h.writeLine("  monitors = {")
for name,cfg in pairs(map) do h.writeLine(string.format("    [\"%s\"] = { role = %q, scale = %s },", name, cfg.role, tostring(cfg.scale))) end
h.writeLine("  },"); h.writeLine("  autoscale = { enabled = true },"); h.writeLine("}")
h.close()

print("Geschrieben: "..path.."\nFertig.")

