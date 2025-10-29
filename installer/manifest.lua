-- /installer/manifest.lua
local manifest = {
  manifest_version = "v2025-10-29",
  author = "ItIsYe + XReactor",
  repo   = "ItIsYe/ExtreamReactor-Controller-V2",
  branch = "main",

  -- Gemeinsame Module
  shared = {
    { dst="/xreactor/shared/json.lua",    url="https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/src/shared/json.lua",    ver="2025-09-12-01" },
    { dst="/xreactor/shared/storage.lua", url="https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/src/shared/storage.lua", ver="2025-09-12-01" },
    { dst="/xreactor/shared/util.lua",    url="https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/src/shared/util.lua",    ver="2025-09-12-01" },
    { dst="/xreactor/shared/gui.lua",     url="https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/src/shared/gui.lua",     ver="2025-10-29-01", force=true },
  },

  -- Installer selbst
  installer = {
    { dst="/xreactor/installer.lua", url="https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/installer/installer.lua", ver="2025-10-29-01" },
  },

  -- Master
  master = {
    { dst="/xreactor/master.lua",        url="https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/src/master/master.lua",       ver="2025-10-29-01", force=true },
    { dst="/xreactor/config_master.lua", url="https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/src/master/config_master.lua", ver="2025-10-15-01" },
  },

  -- Node
  node = {
    { dst="/xreactor/node.lua",        url="https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/src/node/node.lua",           ver="2025-10-29-01", force=true },
    { dst="/xreactor/config_node.lua", url="https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/src/configs/config_node.lua", ver="2025-10-29-01", force=true },
  },

  -- Autostart
  autosetup = {
    { dst="/startup", url="https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/startup/startup.lua", ver="2025-10-29-01" },
  },
}

return manifest
