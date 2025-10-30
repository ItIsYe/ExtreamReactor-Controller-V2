--========================================================
-- /src/shared/matrix.lua
-- Mekanism Induction Matrix Reader (robust, methoden-agnostisch)
-- Erkennt Induction-Port-Peripherals und liefert:
--   energy (FE), capacity (FE), soc (0..1), inFEt, outFEt
--========================================================

local M = {}

-- sichere Methodenaufrufe
local function pcallm(obj, m, ...)
  if not obj or type(obj[m]) ~= "function" then return nil end
  local ok, res = pcall(obj[m], ...)
  if ok then return res end
  return nil
end

-- prüfe, ob Peripheral-Type nach Induction aussieht
local function is_induction_type(t)
  if not t then return false end
  t = tostring(t):lower()
  return t:find("induction") ~= nil
     or t:find("mekanism:induction") ~= nil
     or t:find("induction_port") ~= nil
     or t:find("inductionport") ~= nil
end

-- Liste aller erreichbaren Peripherals (lokal + remote via wired)
local function list_all_peripherals(wired_side)
  local names = {}
  -- lokal
  for _,n in ipairs(peripheral.getNames()) do table.insert(names, n) end
  -- remote
  if wired_side and peripheral.getType(wired_side) == "modem" then
    local wm = peripheral.wrap(wired_side)
    if wm and wm.getNamesRemote then
      for _,rn in ipairs(wm.getNamesRemote()) do table.insert(names, rn) end
    end
  end
  return names
end

-- finde einen geeigneten Induction Port
function M.find(opts)
  opts = opts or {}
  local wired_side = opts.wired_side
  local prefer = opts.prefer -- bevorzugter Name
  if prefer and peripheral.getType(prefer) then
    local t = peripheral.getType(prefer)
    if is_induction_type(t) then return prefer end
  end
  for _,name in ipairs(list_all_peripherals(wired_side)) do
    local t = peripheral.getType(name)
    if is_induction_type(t) then return name end
  end
  return nil
end

-- normiere aus verschiedenen API-Varianten
local function normalize_read(p)
  -- Energie/Capacity
  local energy = pcallm(p, "getEnergy") or pcallm(p, "getEnergyStored") or pcallm(p, "getStored") or 0
  local cap    = pcallm(p, "getMaxEnergy") or pcallm(p, "getMaxEnergyStored") or pcallm(p, "getCapacity") or 0

  -- Raten (optional, nicht jede API bietet das)
  local inRate  = pcallm(p, "getLastInput") or pcallm(p, "getInput") or pcallm(p, "getInputRate") or 0
  local outRate = pcallm(p, "getLastOutput") or pcallm(p, "getOutput") or pcallm(p, "getOutputRate") or 0

  -- Manche APIs liefern Joule, andere FE/RF; hier NICHT umrechnen (unbekannt).
  -- Wir behandeln Werte als "FE" äquivalent und zeigen sie nur an.

  local soc = 0
  if cap and cap > 0 then soc = math.max(0, math.min(1, energy / cap)) end

  return {
    energy   = math.floor(tonumber(energy or 0)),
    capacity = math.floor(tonumber(cap or 0)),
    soc      = soc,
    inFEt    = math.floor(tonumber(inRate or 0)),
    outFEt   = math.floor(tonumber(outRate or 0)),
  }
end

-- Matrix lesen (name optional; wenn nil, auto-find)
function M.read(opts)
  opts = opts or {}
  local name = opts.name
  if not name then
    name = M.find({ wired_side = opts.wired_side, prefer = opts.prefer })
    if not name then return nil, "no_induction_port_found" end
  end
  local p = peripheral.wrap(name)
  if not p then return nil, "wrap_failed" end
  local data = normalize_read(p)
  data.name = name
  return data
end

return M