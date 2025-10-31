--========================================================
-- /xreactor/shared/log.lua
-- Einfaches Rolling-Log mit Leveln und Größenlimit
--========================================================
local L = {}

local DIR  = "/xreactor/logs"
local FILE = DIR.."/latest.log"
local MAX_BYTES = 128*1024

local function ensure_dir() if not fs.exists(DIR) then fs.makeDir(DIR) end end
local function rotate_if_needed()
  if not fs.exists(FILE) then return end
  local size = fs.getSize(FILE)
  if size and size > MAX_BYTES then
    local ts = os.epoch("utc")
    fs.move(FILE, ("%s/%d.log"):format(DIR, ts))
  end
end

local function write_line(line)
  ensure_dir(); rotate_if_needed()
  local h=fs.open(FILE,"a"); if not h then return end
  h.writeLine(line); h.close()
end

local function ts() return os.date("%Y-%m-%d %H:%M:%S") end
local function fmt(level, msg) return string.format("[%s] %-5s %s", ts(), level, tostring(msg)) end

function L.debug(msg) write_line(fmt("DEBUG", msg)) end
function L.info(msg)  write_line(fmt("INFO",  msg)) end
function L.warn(msg)  write_line(fmt("WARN",  msg)) end
function L.error(msg) write_line(fmt("ERROR", msg)) end

return L
