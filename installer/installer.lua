-- This installer is invoked by bootstrap.lua after downloading from raw.githubusercontent.com.

-- Interactive role selector for XReactor startup configuration

local text_utils = dofile("src/shared/text.lua")
local sanitizeText = (text_utils and text_utils.sanitizeText) or function(text) return tostring(text or "") end

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

local REQUIRED_MASTER_FILES = {
  { src = "src/master/master_home.lua",  dst = "/xreactor/master/master_home.lua"  },
  { src = "src/master/master_core.lua",  dst = "/xreactor/master/master_core.lua"  },
  { src = "src/master/master_model.lua", dst = "/xreactor/master/master_model.lua" },
  { src = "src/master/fuel_panel.lua",   dst = "/xreactor/master/fuel_panel.lua"   },
  { src = "src/master/waste_panel.lua",  dst = "/xreactor/master/waste_panel.lua"  },
  { src = "src/master/overview_panel.lua", dst = "/xreactor/master/overview_panel.lua" },
  { src = "src/master/alarm_panel.lua",  dst = "/xreactor/master/alarm_panel.lua"  },
  { src = "src/master/alarm_center.lua", dst = "/xreactor/master/alarm_center.lua" },
}

local REQUIRED_MASTER_DEPENDENCIES = {
  "/xreactor/master/master_home.lua",
  "/xreactor/master/master_core.lua",
  "/xreactor/master/master_model.lua",
  "/xreactor/master/fuel_panel.lua",
  "/xreactor/master/waste_panel.lua",
  "/xreactor/master/overview_panel.lua",
  "/xreactor/master/alarm_panel.lua",
  "/xreactor/master/alarm_center.lua",
  "/xreactor/shared/text.lua",
  "/xreactor/shared/protocol.lua",
  "/xreactor/shared/identity.lua",
  "/xreactor/shared/local_state_store.lua",
  "/xreactor/shared/network_dispatcher.lua",
  "/xreactor/shared/node_state_machine.lua",
  "/xreactor/shared/topbar.lua",
  "/xreactor/shared/gui.lua",
}

local EMBEDDED_MANIFEST = {
  version    = "2025-10-31-9",
  created_at = "2025-10-31T00:00:00Z",
  base_url   = "https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main",

  files = {
    -- Shared
    { src = "src/shared/text.lua",              dst = "/xreactor/shared/text.lua" },
    { src = "src/shared/protocol.lua",           dst = "/xreactor/shared/protocol.lua" },
    { src = "src/shared/identity.lua",           dst = "/xreactor/shared/identity.lua" },
    { src = "src/shared/log.lua",                dst = "/xreactor/shared/log.lua" },
    { src = "src/shared/topbar.lua",             dst = "/xreactor/shared/topbar.lua" },
    { src = "src/shared/network_dispatcher.lua", dst = "/xreactor/shared/network_dispatcher.lua" },
    { src = "src/shared/node_state_machine.lua", dst = "/xreactor/shared/node_state_machine.lua" },
    { src = "src/shared/node_runtime.lua",       dst = "/xreactor/shared/node_runtime.lua" },
    { src = "src/shared/local_state_store.lua",  dst = "/xreactor/shared/local_state_store.lua" },
    { src = "xreactor/shared/gui.lua",           dst = "/xreactor/shared/gui.lua" },

    -- Node Core
    { src = "src/node/node_core.lua",            dst = "/xreactor/node/node_core.lua" },

    -- Master UI
    { src = "src/master/master_core.lua",        dst = "/xreactor/master/master_core.lua" },
    { src = "src/master/master_model.lua",       dst = "/xreactor/master/master_model.lua" },
    { src = "src/master/master_home.lua",        dst = "/xreactor/master/master_home.lua" },
    { src = "src/master/fuel_panel.lua",         dst = "/xreactor/master/fuel_panel.lua" },
    { src = "src/master/waste_panel.lua",        dst = "/xreactor/master/waste_panel.lua" },
    { src = "src/master/alarm_center.lua",       dst = "/xreactor/master/alarm_center.lua" },
    { src = "src/master/alarm_panel.lua",        dst = "/xreactor/master/alarm_panel.lua" },
    { src = "src/master/overview_panel.lua",     dst = "/xreactor/master/overview_panel.lua" },

    -- Tools & UI Map
    { src = "src/ui_map.lua",                     dst = "/xreactor/ui_map.lua" },
    { src = "src/tools/build_ui_map.lua",         dst = "/xreactor/tools/build_ui_map.lua" },
    { src = "src/tools/self_test.lua",            dst = "/xreactor/tools/self_test.lua" },

    -- Universal Autostart
    { src = "startup.lua",                        dst = "/startup.lua" },

    -- Node Runtimes
    { src = "src/node/reactor_node.lua",          dst = "/xreactor/node/reactor_node.lua" },
    { src = "src/node/fuel_node.lua",             dst = "/xreactor/node/fuel_node.lua" },
    { src = "src/node/reprocessing_node.lua",     dst = "/xreactor/node/reprocessing_node.lua" },
    { src = "src/node/energy_node.lua",           dst = "/xreactor/node/energy_node.lua" },
  },
}

local function center_print(y, text)
  local sanitized = sanitizeText(text)
  local w = term.getSize()
  local x = math.max(1, math.floor((w - #sanitized) / 2) + 1)
  term.setCursorPos(x, y)
  term.write(sanitized)
end

local function safe_term_write(text)
  term.write(sanitizeText(text))
end

local function safe_print(text)
  print(sanitizeText(text))
end

local function write_file(path, contents)
  local dir = fs.getDir(path)
  if dir and dir ~= "" and not fs.exists(dir) then
    fs.makeDir(dir)
  end

  local handle = fs.open(path, "w")
  if not handle then
    return false, "Unable to open file for writing: " .. path
  end
  handle.write(contents)
  handle.close()
  return true
end

local function load_manifest()
  if type(EMBEDDED_MANIFEST) ~= "table" then
    return nil, "Installer manifest missing"
  end

  if type(EMBEDDED_MANIFEST.files) ~= "table" then
    return nil, "Installer manifest missing file list"
  end

  local manifest = {
    version    = EMBEDDED_MANIFEST.version,
    created_at = EMBEDDED_MANIFEST.created_at,
    base_url   = EMBEDDED_MANIFEST.base_url or "https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main",
    files      = {},
  }

  for _, file in ipairs(EMBEDDED_MANIFEST.files) do
    if not file.src or not file.dst then
      return nil, "Installer manifest contains an invalid file entry"
    end
    table.insert(manifest.files, { src = file.src, dst = file.dst })
  end

  return manifest
end

local function ensure_manifest_has_master_files(manifest)
  local missing = {}
  for _, required in ipairs(REQUIRED_MASTER_FILES) do
    local found = false
    for _, file in ipairs(manifest.files) do
      if file.src == required.src and file.dst == required.dst then
        found = true
        break
      end
    end
    if not found then table.insert(missing, required.src) end
  end

  if #missing > 0 then
    return false, "Installer manifest missing master files: " .. table.concat(missing, ", ")
  end

  return true
end

local function verify_master_installation()
  local missing = {}
  for _, path in ipairs(REQUIRED_MASTER_DEPENDENCIES) do
    if not fs.exists(path) then table.insert(missing, path) end
  end

  if #missing > 0 then
    return false, "Missing master files after install: " .. table.concat(missing, ", ")
  end

  return true
end

local function download_file(base_url, src, dst)
  local url = string.format("%s/%s", base_url, src)
  local handle, err = http.get(url)
  if not handle then
    return nil, "Failed to download " .. src .. ": " .. tostring(err)
  end

  local status = handle.getResponseCode and handle.getResponseCode() or 0
  if status == 404 then
    handle.close()
    return nil, "File not found (404): " .. src
  elseif status >= 400 or status < 200 then
    handle.close()
    return nil, "Download failed for " .. src .. " with status " .. tostring(status)
  end

  local contents = handle.readAll() or ""
  handle.close()

  if contents == "" then
    return nil, "Empty content for " .. src
  end

  local ok, write_err = write_file(dst, contents)
  if not ok then
    return nil, write_err
  end

  return dst
end

local function copy_file(src, dst)
  if not fs.exists(src) then
    return nil, "Source missing: " .. src
  end

  local handle = fs.open(src, "r")
  if not handle then
    return nil, "Unable to read source file: " .. src
  end
  local contents = handle.readAll() or ""
  handle.close()

  local ok, write_err = write_file(dst, contents)
  if not ok then
    return nil, write_err
  end

  return dst
end

local function install_from_manifest(manifest, opts)
  opts = opts or {}
  local skip = opts.skip or {}
  local updated = {}

  for _, file in ipairs(manifest.files) do
    if skip[file.dst] then
      -- Preserve user-managed files during update
    else
      local path, err = download_file(manifest.base_url, file.src, file.dst)
      if not path then
        return nil, err, updated
      end
      table.insert(updated, path)
    end
  end

  return true, updated
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
    safe_term_write(line)
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
  safe_print("Startup target missing: " .. target)
  return
end

local loader = loadfile(target)
if not loader then
  safe_print("Unable to load " .. target)
  return
end

local ok, err = pcall(loader)
if not ok then
  safe_print("Error while running " .. target .. ": " .. tostring(err))
end
]], role_name, target)

  local handle = fs.open("/startup.lua", "w")
  if not handle then
    error("Cannot open /startup.lua for writing")
  end
  handle.write(contents)
  handle.close()
end

local function installer_self_check()
  local required = {
    load_manifest = load_manifest,
    download_file = download_file,
    copy_file = copy_file,
    install_from_manifest = install_from_manifest,
    write_startup = write_startup,
    build_role_targets = build_role_targets,
    select_role = select_role,
    confirm_role = confirm_role,
    resolve_target = resolve_target,
    draw_menu = draw_menu,
    wait_for_key = wait_for_key,
    is_advanced_computer = is_advanced_computer,
    center_print = center_print,
  }

  for name, fn in pairs(required) do
    if type(fn) ~= "function" then
      return false, "Installer missing required function: " .. name
    end
  end

  return true
end

local function detect_existing_installation(manifest)
  if fs.exists("/xreactor") or fs.exists("/startup.lua") then
    return true
  end

  for _, file in ipairs(manifest.files) do
    if fs.exists(file.dst) then
      return true
    end
  end

  return false
end

local function draw_mode_menu(options, selected)
  term.clear()
  term.setCursorPos(1, 1)
  center_print(1, "XReactor Installer")
  center_print(3, "Use ↑/↓ or W/S to choose an action")

  for i, option in ipairs(options) do
    local prefix = "[ ]"
    if i == selected then prefix = "[>]" end
    term.setCursorPos(3, 4 + i)
    term.clearLine()
    safe_term_write(string.format("%s %s", prefix, option.label))
  end
end

local function select_mode(installed)
  if not installed then
    return "install"
  end

  local options = {
    { key = "install", label = "Install (fresh)" },
    { key = "update",  label = "Update (preserve config)" },
  }

  local selected = 1
  while true do
    draw_mode_menu(options, selected)
    local event, code = os.pullEvent()
    if event == "key" then
      if code == keys.up or code == keys.w then
        selected = (selected == 1) and #options or (selected - 1)
      elseif code == keys.down or code == keys.s then
        selected = (selected == #options) and 1 or (selected + 1)
      elseif code == keys.enter or code == keys.numPadEnter or code == keys.space then
        return options[selected].key
      end
    elseif event == "char" then
      if code == "w" then
        selected = (selected == 1) and #options or (selected - 1)
      elseif code == "s" then
        selected = (selected == #options) and 1 or (selected + 1)
      elseif code == "1" then
        return options[1].key
      elseif code == "2" then
        return options[2].key
      end
    end
  end
end

local function main()
  term.setCursorBlink(false)

  local ok, self_check_err = installer_self_check()
  if not ok then
    error(self_check_err)
  end

  local manifest, manifest_err = load_manifest()
  if not manifest then
    term.clear()
    center_print(2, "Cannot read installer manifest.")
    center_print(4, manifest_err)
    center_print(6, "Press any key to exit.")
    wait_for_key()
    return
  end

  local manifest_ok, manifest_missing_err = ensure_manifest_has_master_files(manifest)
  if not manifest_ok then
    term.clear()
    center_print(2, "Installer manifest invalid.")
    center_print(4, manifest_missing_err)
    center_print(6, "Press any key to exit.")
    wait_for_key()
    return
  end

  local already_installed = detect_existing_installation(manifest)
  local mode = select_mode(already_installed)

  if mode == "update" then
    local skip_paths = {}
    if fs.exists("/startup.lua") then
      skip_paths["/startup.lua"] = true
    end

    local installed, install_err, updated = install_from_manifest(manifest, { skip = skip_paths })
    if not installed then
      term.clear()
      center_print(2, "Update failed to download files.")
      center_print(4, install_err)
      center_print(6, "Press any key to exit.")
      wait_for_key()
      return
    end

    term.clear()
    center_print(2, "Update complete.")
    center_print(4, "Updated files:")
    local line = 5
    for _, path in ipairs(updated) do
      term.setCursorPos(4, line)
      term.clearLine()
      safe_term_write(path)
      line = line + 1
      if line > select(2, term.getSize()) then break end
    end

    if #updated == 0 then
      term.setCursorPos(4, line)
      safe_term_write("No files needed updating.")
    end

    term.setCursorPos(1, line + 2)
    center_print(line + 2, "Existing configuration preserved.")
    center_print(line + 4, "Installer will now exit.")
    return
  end

  local installed, install_err = install_from_manifest(manifest)
  if not installed then
    term.clear()
    center_print(2, "Installer failed to download files.")
    center_print(4, install_err)
    center_print(6, "Press any key to exit.")
    wait_for_key()
    return
  end

  local master_ok, master_err = verify_master_installation()
  if not master_ok then
    term.clear()
    center_print(2, "Master installation incomplete.")
    center_print(4, master_err)
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
