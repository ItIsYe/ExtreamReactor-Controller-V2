-- Bootstrap installer for XReactor
local INSTALLER_URL = "https://raw.githubusercontent.com/ExtreamX/ExtreamReactor-Controller-V2/main/installer/installer.lua"
local INSTALLER_PATH = "installer.lua"

local function download_installer()
  local handle, err = http.get(INSTALLER_URL)
  if not handle then
    error("Failed to download installer: " .. tostring(err))
  end

  local content = handle.readAll() or ""
  handle.close()

  local first_nonspace = content:match("^%s*.")
  if first_nonspace == "<" then
    error("Downloaded installer looks like HTML; use the raw.githubusercontent.com URL.")
  end

  local file = fs.open(INSTALLER_PATH, "w")
  if not file then
    error("Unable to write installer.lua")
  end
  file.write(content)
  file.close()
end

download_installer()
shell.run(INSTALLER_PATH)
