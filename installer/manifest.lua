--====================================================
--  XReactor Controller Manifest
--  Version: v2025-10-16-02
--  Repository: ItIsYe/ExtreamReactor-Controller-V2
--====================================================
--  Beschreibung:
--  Manifest für Installer V2 mit vollständigen URLs.
--  Unterstützt Master & Node Rollen, GUI, Autostart & Debug.
--====================================================

local manifest = {
    manifest_version = "v2025-10-16-02",
    author = "ItIsYe + ChatGPT Integration",
    repo = "ItIsYe/ExtreamReactor-Controller-V2",
    branch = "main",
    description = "ExtreamReactor Controller V2 (Master/Node setup with GUI, autostart and modem sync)",

    -----------------------------------------------------
    -- Gemeinsame Dateien (werden bei allen Rollen installiert)
    -----------------------------------------------------
    shared = {
        { dst="/xreactor/shared/json.lua",     url="https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/src/shared/json.lua",     ver="2025-09-12-01" },
        { dst="/xreactor/shared/storage.lua",  url="https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/src/shared/storage.lua",  ver="2025-09-12-01" },
        { dst="/xreactor/shared/gui.lua",      url="https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/src/shared/gui.lua",      ver="2025-09-12-01" },
        { dst="/xreactor/shared/util.lua",     url="https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/src/shared/util.lua",     ver="2025-09-12-01" },
    },

    -----------------------------------------------------
    -- Installer-Dateien
    -----------------------------------------------------
    installer = {
        { dst="/xreactor/installer.lua", url="https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/installer/installer.lua", ver="2025-09-30-01" },
    },

    -----------------------------------------------------
    -- Master-Rolle
    -----------------------------------------------------
    master = {
        { dst="/xreactor/master.lua",         url="https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/src/master/master.lua",         ver="2025-10-15-04" },
        { dst="/xreactor/config_master.lua",  url="https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/src/master/config_master.lua",  ver="2025-10-15-01" },
        { dst="/xreactor/debug.lua",          url="https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/src/master/debug.lua",          ver="2025-10-15-01" },
    },

    -----------------------------------------------------
    -- Node-Rolle
    -----------------------------------------------------
    node = {
        { dst="/xreactor/node.lua",        url="https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/src/node/node.lua",        ver="2025-10-16-01" },
        { dst="/xreactor/config_node.lua", url="https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/src/node/config_node.lua", ver="2025-10-16-01" },
        { dst="/xreactor/debug.lua",       url="https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/src/node/debug.lua",       ver="2025-10-16-01" },
    },

    -----------------------------------------------------
    -- Autostart
    -----------------------------------------------------
    autosetup = {
        { dst="/startup", url="https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/src/startup.lua", ver="2025-10-15-01" },
    },
}

return manifest
