-- This installer is invoked by bootstrap.lua after downloading from raw.githubusercontent.com.

-- Interactive role selector for XReactor startup configuration

local function sanitizeText(text)
  local sanitized = tostring(text or "")
  sanitized = sanitized:gsub("[%c]", "")
  return sanitized
end

local ROLE_SOURCE_FILES = {
  MASTER        = "src/master/master_home.lua",
  REACTOR       = "src/node/reactor_node.lua",
  ENERGY        = "src/node/energy_node.lua",
  FUEL          = "src/node/fuel_node.lua",
  REPROCESSING  = "src/node/reprocessing_node.lua",
}

local FORBIDDEN_NODE_PATHS = {
  ["src/node/turbine_node.lua"]       = "Turbine control is handled by reactor_node.lua; remove turbine_node.lua",
  ["/xreactor/node/turbine_node.lua"] = "Turbine control must be driven by reactor_node.lua; turbine_node.lua is not supported",
}

local ROLE_EXPECTED_TARGETS = {
  MASTER        = "/xreactor/master/master_home.lua",
  REACTOR       = "/xreactor/node/reactor_node.lua",
  ENERGY        = "/xreactor/node/energy_node.lua",
  FUEL          = "/xreactor/node/fuel_node.lua",
  REPROCESSING  = "/xreactor/node/reprocessing_node.lua",
}

local STARTUP_PATH = "/startup.lua"

local function build_startup_content(target)
  return string.format("shell.run(%q)", target)
end

local ROLE_LIST = {
  { name = "MASTER",       description = "Master UI" },
  { name = "REACTOR",      description = "Reactor + Turbine Node" },
  { name = "ENERGY",       description = "Energy Node" },
  { name = "FUEL",         description = "Fuel Node" },
  { name = "REPROCESSING", description = "Reprocessing Node" },
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

local SAFETY_MARGIN_BYTES = 1024
local MIN_PROBE_SIZE = 1024
local DOWNLOAD_CHUNK_SIZE = 16 * 1024

local function ensure_directory(path)
  local dir = fs.getDir(path)
  if dir and dir ~= "" and not fs.exists(dir) then
    fs.makeDir(dir)
  end
end

local function ensure_free_space(required, context)
  local free = fs.getFreeSpace and fs.getFreeSpace("/") or nil
  if not free then
    return true
  end

  if free < required then
    return false, string.format("Insufficient disk space for %s (need %d bytes, have %d)", context or "operation", required, free)
  end

  return true
end

local function get_startup_path()
  local path = STARTUP_PATH

  if type(path) ~= "string" or path == "" then
    error("Startup path is invalid")
  end

  if not path:match("^/") then
    error("Startup path must be absolute: " .. tostring(path))
  end

  if path ~= "/startup.lua" then
    error("Startup path must be /startup.lua (got " .. tostring(path) .. ")")
  end

  if path:match("^/rom") then
    error("Startup path must be writable; refusing to use ROM location: " .. path)
  end

  return path
end

local function write_file(path, reader, expected_size)
  ensure_directory(path)

  local existing_size = (fs.exists(path) and fs.getSize and fs.getSize(path)) or 0
  local estimated_size = expected_size or MIN_PROBE_SIZE
  local size_delta = math.max(estimated_size - existing_size, 0)
  local required = size_delta + SAFETY_MARGIN_BYTES
  local space_ok, space_err = ensure_free_space(required, "writing " .. path)
  if not space_ok then
    return false, space_err
  end

  local handle = fs.open(path, "w")
  if not handle then
    return false, "Unable to open file for writing: " .. path
  end

  while true do
    local chunk = reader()
    if not chunk then break end
    handle.write(chunk)
  end

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

local function probe_remote_size(base_url, src)
  local url = string.format("%s/%s", base_url, src)
  local handle = http.get(url, { Range = "bytes=0-0" })
  if not handle then
    return nil
  end

  local headers = (handle.getResponseHeaders and handle.getResponseHeaders()) or {}
  local content_length = tonumber(headers["Content-Length"] or headers["content-length"])
  local body = handle.readAll() or ""
  handle.close()

  if content_length and content_length > 0 then
    return content_length
  end

  if #body > 0 then
    return math.max(#body, MIN_PROBE_SIZE)
  end

  return nil
end

local function download_file(base_url, src, dst)
  local expected_size = probe_remote_size(base_url, src) or MIN_PROBE_SIZE
  local existing_size = (fs.exists(dst) and fs.getSize and fs.getSize(dst)) or 0
  local required = math.max(expected_size - existing_size, 0) + SAFETY_MARGIN_BYTES
  local space_ok, space_err = ensure_free_space(required, "downloading " .. dst)
  if not space_ok then
    return nil, space_err
  end

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

  local headers = (handle.getResponseHeaders and handle.getResponseHeaders()) or {}
  local expected_size = tonumber(headers["Content-Length"] or headers["content-length"])

  local function reader()
    return handle.read(DOWNLOAD_CHUNK_SIZE)
  end

  local ok, write_err = write_file(dst, reader, expected_size)
  handle.close()

  if not ok then
    return nil, write_err
  end

  return dst
end

local function copy_file(src, dst)
  if not fs.exists(src) then
    return nil, "Source missing: " .. src
  end

  local expected_size = fs.getSize and fs.getSize(src) or nil
  local handle = fs.open(src, "r")
  if not handle then
    return nil, "Unable to read source file: " .. src
  end

  local function reader()
    return handle.read(DOWNLOAD_CHUNK_SIZE)
  end

  local ok, write_err = write_file(dst, reader, expected_size)
  handle.close()

  if not ok then
    return nil, write_err
  end

  return dst
end

local function calculate_required_space(manifest, opts)
  opts = opts or {}
  local skip = opts.skip or {}
  local total = 0

  for _, file in ipairs(manifest.files) do
    if not skip[file.dst] then
      local remote_size = probe_remote_size(manifest.base_url, file.src) or MIN_PROBE_SIZE
      local existing_size = (fs.exists(file.dst) and fs.getSize and fs.getSize(file.dst)) or 0
      local additional_needed = math.max(remote_size - existing_size, 0)
      total = total + additional_needed
    end
  end

  return total + SAFETY_MARGIN_BYTES
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
  local missing = {}

  for _, file in ipairs(manifest.files) do
    if FORBIDDEN_NODE_PATHS[file.src] then
      return nil, FORBIDDEN_NODE_PATHS[file.src]
    end
    if FORBIDDEN_NODE_PATHS[file.dst] then
      return nil, FORBIDDEN_NODE_PATHS[file.dst]
    end
  end

  for role, src in pairs(ROLE_SOURCE_FILES) do
    local found
    for _, file in ipairs(manifest.files) do
      if file.src == src then
        local expected_dst = ROLE_EXPECTED_TARGETS[role]
        if type(file.dst) ~= "string" or file.dst == "" then
          table.insert(missing, string.format("%s (invalid destination for %s)", role, tostring(file.src)))
        elseif expected_dst and file.dst ~= expected_dst then
          table.insert(missing, string.format("%s (expected %s, found %s)", role, expected_dst, tostring(file.dst)))
        else
          targets[role] = file.dst
        end
        found = true
        break
      end
    end
    if not found then
      table.insert(missing, role)
    end
  end

  if #missing > 0 then
    return nil, "Installer manifest missing targets for roles: " .. table.concat(missing, ", ")
  end

  return targets
end

local function verify_role_targets(role_targets)
  local missing = {}

  for forbidden, reason in pairs(FORBIDDEN_NODE_PATHS) do
    if fs.exists(forbidden) then
      table.insert(missing, reason)
    end
  end

  for role, expected in pairs(ROLE_EXPECTED_TARGETS) do
    local path = role_targets[role]
    if type(path) ~= "string" or path == "" then
      table.insert(missing, role .. " (invalid target)")
    elseif expected and path ~= expected then
      table.insert(missing, string.format("%s (expected %s, found %s)", role, expected, path))
    elseif not path:match("^/") then
      table.insert(missing, string.format("%s (startup target must be absolute: %s)", role, path))
    elseif not fs.exists(path) then
      table.insert(missing, string.format("%s (%s)", role, path))
    end
  end

  if #missing > 0 then
    return false, "Missing startup targets: " .. table.concat(missing, ", ")
  end

  return true
end

local function is_advanced_computer()
  return term.isColor and term.isColor()
end

local function wait_for_key()
  os.pullEvent("key")
end

local function configure_startup_for_role(role_targets)
  local choice

  while true do
    choice = select_role_from_menu()
    if confirm_role(choice, role_targets) then break end
  end

  if choice.name == "MASTER" and not is_advanced_computer() then
    term.clear()
    center_print(2, "MASTER role requires an Advanced Computer.")
    center_print(4, "Install on an Advanced Computer and retry.")
    center_print(6, "Press any key to exit.")
    wait_for_key()
    return false
  end

  local target, err = resolve_target(choice.name, role_targets)
  if not target then
    term.clear()
    center_print(2, "Cannot configure startup.")
    center_print(4, err)
    center_print(6, "Press any key to exit.")
    wait_for_key()
    return false
  end

  local wrote, write_err = write_startup(choice.name, target)
  if not wrote then
    term.clear()
    center_print(2, "Failed to write startup.lua.")
    center_print(4, write_err)
    center_print(6, "Press any key to exit.")
    wait_for_key()
    return false
  end

  local ok, verify_err = verify_startup_file(choice.name, target)
  if not ok then
    term.clear()
    center_print(2, "Autostart verification failed.")
    center_print(4, verify_err)
    center_print(6, "Press any key to exit.")
    wait_for_key()
    return false
  end

  term.clear()
  term.setCursorPos(1, 2)
  center_print(2, "Startup configured for role: " .. choice.name)
  center_print(4, "Target file: " .. target)
  center_print(6, "Reboot the computer to launch the selected role.")
  center_print(8, "Installer will now exit.")

  return true
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

local function select_role_from_menu()
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
  local expected = ROLE_EXPECTED_TARGETS[role_name]

  if type(target) ~= "string" or target == "" then
    return nil, "No destination recorded for role: " .. tostring(role_name)
  end
  if expected and target ~= expected then
    return nil, string.format("Unexpected target for %s: %s (expected %s)", role_name, target, expected)
  end
  if target:match("^/rom") then
    return nil, "Startup target must be writable; refusing to use ROM location: " .. target
  end
  if not target:match("^/") then
    return nil, "Startup target must be an absolute path: " .. tostring(target)
  end
  if not fs.exists(target) then
    return nil, "Startup target missing: " .. target
  end

  return target
end

local function purge_secondary_startup_files()
  local startup_path = get_startup_path()

  local function walk(path)
    for _, name in ipairs(fs.list(path)) do
      local child = fs.combine(path, name)
      if child:match("^/rom") then
        -- Treat ROM as strictly read-only; never touch or traverse it.
      elseif name == "startup.lua" and child ~= startup_path then
        fs.delete(child)
      elseif fs.isDir(child) then
        walk(child)
      end
    end
  end

  walk("/")
end

local function write_startup(role_name, target)
  local expected = ROLE_EXPECTED_TARGETS[role_name]

  if not expected then
    return nil, "Unknown role: " .. tostring(role_name)
  end

  if target ~= expected then
    return nil, string.format("Startup target mismatch for %s: %s (expected %s)", role_name, tostring(target), expected)
  end

  if type(target) ~= "string" or target == "" then
    return nil, "Invalid startup target"
  end

  if target:match("^/rom") then
    return nil, "Startup target must be writable; refusing to use ROM location: " .. target
  end

  if not target:match("^/") then
    return nil, "Startup target must be an absolute path: " .. target
  end

  if not fs.exists(target) then
    return nil, "Startup target missing: " .. target
  end

  purge_secondary_startup_files()

  local startup_path = get_startup_path()
  local handle = fs.open(startup_path, "w")
  if not handle then
    error("Cannot open " .. startup_path .. " for writing")
  end
  handle.write(build_startup_content(target))
  handle.close()

  return true
end

local function verify_startup_file(role_name, target)
  local expected = ROLE_EXPECTED_TARGETS[role_name]

  if not expected then
    return false, "Unknown role: " .. tostring(role_name)
  end

  if target ~= expected then
    return false, string.format("Startup target mismatch for %s: %s (expected %s)", role_name, tostring(target), expected)
  end

  if type(target) ~= "string" or target == "" then
    return false, "Invalid startup target"
  end

  if target:match("^/rom") then
    return false, "Startup target must be writable; refusing to use ROM location: " .. target
  end

  if not target:match("^/") then
    return false, "Startup target must be an absolute path: " .. target
  end

  if not fs.exists(target) then
    return false, "Startup target missing: " .. target
  end

  local startup_path = get_startup_path()
  local handle = fs.open(startup_path, "r")
  if not handle then
    return false, "Unable to read " .. startup_path .. " after writing"
  end

  local content = handle.readAll() or ""
  handle.close()

  if content ~= build_startup_content(target) then
    return false, "startup.lua must contain exactly: shell.run(\"" .. target .. "\")"
  end

  return true
end

local function configure_startup_for_role(role_targets)
  local choice

  while true do
    choice = select_role_from_menu()
    if confirm_role(choice, role_targets) then break end
  end

  if choice.name == "MASTER" and not is_advanced_computer() then
    term.clear()
    center_print(2, "MASTER role requires an Advanced Computer.")
    center_print(4, "Install on an Advanced Computer and retry.")
    center_print(6, "Press any key to exit.")
    wait_for_key()
    return false
  end

  local target, err = resolve_target(choice.name, role_targets)
  if not target then
    term.clear()
    center_print(2, "Cannot configure startup.")
    center_print(4, err)
    center_print(6, "Press any key to exit.")
    wait_for_key()
    return false
  end

  local wrote, write_err = write_startup(choice.name, target)
  if not wrote then
    term.clear()
    center_print(2, "Failed to write startup.lua.")
    center_print(4, write_err)
    center_print(6, "Press any key to exit.")
    wait_for_key()
    return false
  end

  local ok, verify_err = verify_startup_file(choice.name, target)
  if not ok then
    term.clear()
    center_print(2, "Autostart verification failed.")
    center_print(4, verify_err)
    center_print(6, "Press any key to exit.")
    wait_for_key()
    return false
  end

  term.clear()
  term.setCursorPos(1, 2)
  center_print(2, "Startup configured for role: " .. choice.name)
  center_print(4, "Target file: " .. target)
  center_print(6, "Reboot the computer to launch the selected role.")
  center_print(8, "Installer will now exit.")

  return true
end

local function detect_existing_installation(manifest)
  local startup_path = get_startup_path()

  if fs.exists("/xreactor") or fs.exists(startup_path) then
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

local function installer_self_check()
  local required = {
    load_manifest = load_manifest,
    download_file = download_file,
    copy_file = copy_file,
    install_from_manifest = install_from_manifest,
    calculate_required_space = calculate_required_space,
    detect_existing_installation = detect_existing_installation,
    write_startup = write_startup,
    build_role_targets = build_role_targets,
    select_role_from_menu = select_role_from_menu,
    confirm_role = confirm_role,
    resolve_target = resolve_target,
    configure_startup_for_role = configure_startup_for_role,
    draw_menu = draw_menu,
    select_mode = select_mode,
    verify_startup_file = verify_startup_file,
    safe_term_write = safe_term_write,
    safe_print = safe_print,
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

local function main()
  local startup_path = get_startup_path()
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

  local manifest_role_targets, manifest_role_err = build_role_targets(manifest)
  if not manifest_role_targets then
    term.clear()
    center_print(2, "Installer manifest invalid for roles.")
    center_print(4, manifest_role_err)
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
  local role_targets
  local skip_files = { [startup_path] = true }

  if mode == "update" then
    local required_space = calculate_required_space(manifest, { skip = skip_files })
    local has_space, space_err = ensure_free_space(required_space, "update")
    if not has_space then
      term.clear()
      center_print(2, "Update aborted: insufficient space.")
      center_print(4, space_err)
      center_print(6, "Free up space and retry.")
      wait_for_key()
      return
    end

    local installed, install_err, updated = install_from_manifest(manifest, { skip = skip_files })
    if not installed then
      term.clear()
      center_print(2, "Update failed to download files.")
      center_print(4, install_err)
      center_print(6, "Press any key to exit.")
      wait_for_key()
      return
    end

    local targets_ok, targets_err = verify_role_targets(manifest_role_targets)
    if not targets_ok then
      term.clear()
      center_print(2, "Role targets missing after update.")
      center_print(4, targets_err)
      center_print(6, "Press any key to exit.")
      wait_for_key()
      return
    end

    role_targets = manifest_role_targets
  else
    local required_space = calculate_required_space(manifest, { skip = skip_files })
    local has_space, space_err = ensure_free_space(required_space, "installation")
    if not has_space then
      term.clear()
      center_print(2, "Installation aborted: insufficient space.")
      center_print(4, space_err)
      center_print(6, "Free up space and retry.")
      wait_for_key()
      return
    end

    local installed, install_err = install_from_manifest(manifest, { skip = skip_files })
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

    local targets_ok, targets_err = verify_role_targets(manifest_role_targets)
    if not targets_ok then
      term.clear()
      center_print(2, "Role targets missing after installation.")
      center_print(4, targets_err)
      center_print(6, "Press any key to exit.")
      wait_for_key()
      return
    end

    role_targets = manifest_role_targets
  end

  local configured = configure_startup_for_role(role_targets)
  if not configured then return end
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
