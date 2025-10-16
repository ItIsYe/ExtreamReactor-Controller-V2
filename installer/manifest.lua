--====================================================
--  XReactor Controller - Manifest v2025-10-16-01
--====================================================
--  Repository: ItIsYe/ExtreamReactor-Controller-V2
--  Compatible with Installer v2
--====================================================

local manifest = {
    manifest_version = "v2025-10-16-01",
    author = "ItIsYe + ChatGPT Integration",
    repo = "ItIsYe/ExtreamReactor-Controller-V2",
    branch = "main",
    description = "ExtreamReactor Controller V2 (Master/Node setup with GUI, autostart and modem sync)",

    -- =========================================================
    -- SHARED FILES (used by both Master and Node)
    -- =========================================================
    shared = {
        { dst="/xreactor/shared/json.lua",     url="src/shared/json.lua",     ver="2025-09-12-01" },
        { dst="/xreactor/shared/storage.lua",  url="src/shared/storage.lua",  ver="2025-09-12-01" },
        { dst="/xreactor/shared/gui.lua",      url="src/shared/gui.lua",      ver="2025-09-12-01" },
        { dst="/xreactor/shared/util.lua",     url="src/shared/util.lua",     ver="2025-09-12-01" },
    },

    -- =========================================================
    -- INSTALLER FILES
    -- =========================================================
    installer = {
        { dst="/xreactor/installer.lua", url="installer/installer.lua", ver="2025-09-30-01" },
    },

    -- =========================================================
    -- MASTER ROLE FILES
    -- =========================================================
    master = {
        { dst="/xreactor/master.lua",          url="src/master/master.lua",          ver="2025-10-15-04" },
        { dst="/xreactor/config_master.lua",   url="src/master/config_master.lua",   ver="2025-10-15-01" },
        { dst="/xreactor/debug.lua",           url="src/master/debug.lua",           ver="2025-10-15-01" },
    },

    -- =========================================================
    -- NODE ROLE FILES
    -- =========================================================
    node = {
        { dst="/xreactor/node.lua",           url="src/node/node.lua",           ver="2025-10-15-02" },
        { dst="/xreactor/config_node.lua",    url="src/node/config_node.lua",    ver="2025-10-15-01" },
        { dst="/xreactor/debug.lua",          url="src/node/debug.lua",          ver="2025-10-15-01" },
    },

    -- =========================================================
    -- AUTOSETUP FILES (optional utilities)
    -- =========================================================
    autosetup = {
        { dst="/startup", url="src/startup.lua", ver="2025-10-15-01" }
    },
}

return manifest
