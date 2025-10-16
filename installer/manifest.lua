-- ==============================================================
--  XReactor Controller Manifest
--  Version: v2025-10-16-PhaseD-01
--  Erstellt: 2025-10-16
--  Kompatibel mit Installer/Updater v2+
-- ==============================================================

local manifest = {
  version = "v2025-10-16-PhaseD-01",
  author  = "ItIsYe & GPT-5",
  description = "ExtreamReactor Controller – Master/Node Autoupdate Manifest (Phase D)",
  min_cc_version = 1.9,

  files = {

    -- ========== SHARED ==========
    ["/xreactor/shared/json.lua"]      = "https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/src/shared/json.lua",
    ["/xreactor/shared/storage.lua"]   = "https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/src/shared/storage.lua",
    ["/xreactor/shared/gui.lua"]       = "https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/src/shared/gui.lua",
    ["/xreactor/shared/ha.lua"]        = "https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/src/shared/ha.lua",
    ["/xreactor/shared/policy.lua"]    = "https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/src/shared/policy.lua",
    ["/xreactor/shared/webhooks.lua"]  = "https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/src/shared/webhooks.lua",
    ["/xreactor/shared/protocol.lua"]  = "https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/src/shared/protocol.lua",
    ["/xreactor/shared/backup.lua"]    = "https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/src/shared/backup.lua",

    -- ========== INSTALLER / CORE ==========
    ["/xreactor/installer.lua"]        = "https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/src/installer/installer.lua",
    ["/xreactor/matrix_core.lua"]      = "https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/src/matrix_core.lua",
    ["/xreactor/master.lua"]           = "https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/src/master.lua",
    ["/xreactor/node.lua"]             = "https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/src/node.lua",

    -- ========== CONFIGS ==========
    ["/xreactor/config_master.lua"]    = "https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/src/configs/config_master.lua",
    ["/xreactor/config_node.lua"]      = "https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/src/configs/config_node.lua",

    -- ========== TOOLS ==========
    ["/xreactor/tools/debug.lua"]      = "https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/src/tools/debug.lua",
    ["/xreactor/tools/dump.lua"]       = "https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/src/tools/dump.lua",

    -- ========== BACKUP/LOG ==========
    ["/xreactor/shared/storage_backup.lua"] = "https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/src/shared/storage_backup.lua",

  },

  roles = {
    master = {
      required = {
        "/xreactor/master.lua",
        "/xreactor/config_master.lua",
        "/xreactor/shared/json.lua",
        "/xreactor/shared/gui.lua",
        "/xreactor/shared/storage.lua",
      },
    },
    node = {
      required = {
        "/xreactor/node.lua",
        "/xreactor/config_node.lua",
        "/xreactor/shared/json.lua",
        "/xreactor/shared/storage.lua",
      },
    },
  },
}

return manifest
