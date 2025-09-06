local U = {}


function U.clamp(x, lo, hi) if x<lo then return lo elseif x>hi then return hi else return x end end
function U.round(x, d) local m = 10^(d or 0) return math.floor(x*m+0.5)/m end


function U.readEnergy(dev)
if not dev then return nil end
local function get(name) if dev[name] then return dev[name](dev) end end
local stored = get("getEnergyStored") or get("getEnergy")
local max = get("getMaxEnergyStored") or get("getMaxEnergy")
return stored, max
end


function U.findMonitors()
local mons = {}
for _, n in ipairs(peripheral.getNames()) do
if peripheral.getType(n) == "monitor" then table.insert(mons, peripheral.wrap(n)) end
end
table.sort(mons, function(a,b) local aw,ah=a.getSize(); local bw,bh=b.getSize(); return aw*ah>bw*bh end)
return mons
end


function U.printf(x,y,fmt,...)
term.setCursorPos(x,y); write(string.format(fmt,...))
end


function U.bell() if term.isColor() and peripheral.find("speaker") then local s=peripheral.find("speaker"); if s and s.playNote then s.playNote("pling") end end end


return U
