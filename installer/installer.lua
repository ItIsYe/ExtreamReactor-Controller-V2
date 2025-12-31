-- installer.lua
-- Interactive role selector for XReactor startup configuration

local ROLE_TARGETS = {
  MASTER       = "/xreactor/master/master_home.lua",
  REACTOR      = "/xreactor/node/reactor_node.lua",
  ENERGY       = "/xreactor/node/energy_node.lua",
  FUEL         = "/xreactor/node/fuel_node.lua",
  REPROCESSING = "/xreactor/node/reprocessing_node.lua",
}

local ROLE_LIST = {
  { name = "MASTER",       description = "Cluster UI and coordinator" },
  { name = "REACTOR",      description = "Controls the main reactor node" },
  { name = "ENERGY",       description = "Manages power transfer" },
  { name = "FUEL",         description = "Handles fuel processing" },
  { name = "REPROCESSING", description = "Supervises reprocessing" },
}

local function center_print(y, text)
  local w = term.getSize()
  local x = math.max(1, math.floor((w - #text) / 2) + 1)
  term.setCursorPos(x, y)
  term.write(text)
end

local function draw_menu(selected)
  term.clear()
  term.setCursorPos(1, 1)
  center_print(1, "XReactor Role Installer")
  center_print(3, "Use ↑/↓ or W/S to select a role, Enter to continue")

  for i, role in ipairs(ROLE_LIST) do
    local prefix = "[ ]"
    if i == selected then prefix = "[>]" end
    local line = string.format("%s %s - %s", prefix, role.name, role.description)
    term.setCursorPos(3, 4 + i)
    term.clearLine()
    term.write(line)
  end
end

local function select_role()
  local selected = 1
  while true do
    draw_menu(selected)
    local event, code = os.pullEvent()
    if event == "key" then
      if code == keys.up or code == keys.w then
        selected = (selected == 1) and #ROLE_LIST or (selected - 1)
      elseif code == keys.down or code == keys.s then
        selected = (selected == #ROLE_LIST) and 1 or (selected + 1)
      elseif code == keys.enter or code == keys.numPadEnter or code == keys.space then
        return ROLE_LIST[selected]
      end
    elseif event == "char" then
      if code == "w" then
        selected = (selected == 1) and #ROLE_LIST or (selected - 1)
      elseif code == "s" then
        selected = (selected == #ROLE_LIST) and 1 or (selected + 1)
      elseif code >= "1" and code <= tostring(#ROLE_LIST) then
        selected = tonumber(code)
      end
    end
  end
end

local function confirm_role(role)
  while true do
    term.clear()
    term.setCursorPos(1, 2)
    center_print(2, "Confirm role selection")
    center_print(4, "Role: " .. role.name)
    center_print(5, "Target: " .. (ROLE_TARGETS[role.name] or "unknown"))
    center_print(7, "Press Y/Enter to confirm or N to go back")

    local event, code = os.pullEvent()
    if event == "char" then
      local c = string.lower(code)
      if c == "y" then return true end
      if c == "n" then return false end
    elseif event == "key" then
      if code == keys.enter or code == keys.numPadEnter then return true end
      if code == keys.backspace then return false end
    end
  end
end

local function write_startup(role_name)
  local target = ROLE_TARGETS[role_name]
  if not target then
    error("Unknown role: " .. tostring(role_name))
  end

  local contents = string.format([[-- Auto-generated startup for role %s
local target = %q

package.path = table.concat({
  "/xreactor/?.lua",
  "/xreactor/?/init.lua",
  "/xreactor/?/?.lua",
  "/?.lua",
}, ";")

if not fs.exists(target) then
  print("Startup target missing: " .. target)
  return
end

local loader = loadfile(target)
if not loader then
  print("Unable to load " .. target)
  return
end

local ok, err = pcall(loader)
if not ok then
  print("Error while running " .. target .. ": " .. tostring(err))
end
]], role_name, target)

  local handle = fs.open("/startup.lua", "w")
  if not handle then
    error("Cannot open /startup.lua for writing")
  end
  handle.write(contents)
  handle.close()
end

local function main()
  term.setCursorBlink(false)
  local choice

  while true do
    choice = select_role()
    if confirm_role(choice) then break end
  end

  write_startup(choice.name)

  term.clear()
  term.setCursorPos(1, 2)
  center_print(2, "Startup configured for role: " .. choice.name)
  center_print(4, "Target file: " .. ROLE_TARGETS[choice.name])
  center_print(6, "Reboot the computer to launch the selected role.")
  center_print(8, "Installer will now exit.")
end

local ok, err = pcall(main)
if not ok then
  term.clear()
  term.setCursorPos(1, 2)
  center_print(2, "Installer error:")
  center_print(4, tostring(err))
  center_print(6, "Press any key to exit.")
  os.pullEvent("key")
end
