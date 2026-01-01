-- This installer is invoked by bootstrap.lua after downloading from raw.githubusercontent.com.

-- Interactive role selector for XReactor startup configuration

local ROLE_SOURCE_FILES = {
  MASTER       = "src/master/master_home.lua",
  REACTOR      = "src/node/reactor_node.lua",
  ENERGY       = "src/node/energy_node.lua",
  FUEL         = "src/node/fuel_node.lua",
  REPROCESSING = "src/node/reprocessing_node.lua",
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

local function installer_dir()
  local program = shell and shell.getRunningProgram and shell.getRunningProgram()
  if not program or program == "" then
    return "/"
  end
  local dir = fs.getDir(program)
  if dir == "" then return "/" end
  return "/" .. dir
end

local MANIFEST_URL = "https://raw.githubusercontent.com/ExtreamX/ExtreamReactor-Controller-V2/main/installer/manifest.lua"

local function manifest_path()
  return fs.combine(installer_dir(), "manifest.lua")
end

local function write_file(path, contents)
  local dir = fs.getDir(path)
  if dir and dir ~= "" and not fs.exists(dir) then
    fs.makeDir(dir)
  end

  local handle = fs.open(path, "w")
  if not handle then
    return false, "Unable to open manifest for writing: " .. path
  end
  handle.write(contents)
  handle.close()
  return true
end

local function download_manifest()
  local handle, err = http.get(MANIFEST_URL)
  if not handle then
    return nil, "Failed to download manifest: " .. tostring(err)
  end

  local content = handle.readAll() or ""
  handle.close()

  local ok, write_err = write_file(manifest_path(), content)
  if not ok then
    return nil, write_err
  end

  if not fs.exists(manifest_path()) then
    return nil, "Manifest missing after download"
  end

  return manifest_path()
end

local function load_manifest()
  fs.delete(manifest_path())
  local path, download_err = download_manifest()
  if not path then
    return nil, download_err
  end

  local ok, manifest = pcall(dofile, path)
  if not ok then
    return nil, "Unable to load manifest: " .. tostring(manifest)
  end
  if type(manifest) ~= "table" or type(manifest.files) ~= "table" then
    return nil, "Manifest missing file list"
  end
  return manifest
end

local function build_role_targets(manifest)
  local targets = {}
  for role, src in pairs(ROLE_SOURCE_FILES) do
    for _, file in ipairs(manifest.files) do
      if file.src == src then
        targets[role] = file.dst
        break
      end
    end
  end
  return targets
end

local function is_advanced_computer()
  return term.isColor and term.isColor()
end

local function wait_for_key()
  os.pullEvent("key")
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

local function confirm_role(role, role_targets)
  while true do
    term.clear()
    term.setCursorPos(1, 2)
    center_print(2, "Confirm role selection")
    center_print(4, "Role: " .. role.name)
    center_print(5, "Target: " .. (role_targets[role.name] or "unknown"))
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

local function resolve_target(role_name, role_targets)
  local target = role_targets[role_name]
  if not target then
    return nil, "No destination recorded for role: " .. tostring(role_name)
  end
  if not fs.exists(target) then
    return nil, "Startup target missing: " .. target
  end
  return target
end

local function write_startup(role_name, target)
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
  local manifest, manifest_err = load_manifest()
  if not manifest then
    term.clear()
    center_print(2, "Cannot read installer manifest.")
    center_print(4, manifest_err)
    center_print(6, "Press any key to exit.")
    wait_for_key()
     return
   end
 
  local role_targets = build_role_targets(manifest)
  local choice
 
  while true do
    choice = select_role()
    if confirm_role(choice, role_targets) then break end
  end
 
  if choice.name == "MASTER" and not is_advanced_computer() then
    term.clear()
    center_print(2, "MASTER role requires an Advanced Computer.")
    center_print(4, "Install on an Advanced Computer and retry.")
    center_print(6, "Press any key to exit.")
    wait_for_key()
    return
  end
 
  local target, err = resolve_target(choice.name, role_targets)
  if not target then
    term.clear()
    center_print(2, "Cannot configure startup.")
    center_print(4, err)
    center_print(6, "Press any key to exit.")
    wait_for_key()
    return
  end

  write_startup(choice.name, target)

  term.clear()
  term.setCursorPos(1, 2)
  center_print(2, "Startup configured for role: " .. choice.name)
  center_print(4, "Target file: " .. target)
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
