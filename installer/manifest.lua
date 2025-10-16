-- ==============================================================
--  XReactor Controller – Manifest
--  Repo: ItIsYe/ExtreamReactor-Controller-V2 (branch: main)
--  Dieses Manifest ist auf die aktuelle Repo-Struktur angepasst.
-- ==============================================================

local base = "https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/"

local function u(p) return base .. p end

local manifest = {
  version = "v2025-10-16-PhaseD-03",
  author  = "ItIsYe & contributors",

  -- Alle Dateien, jeweils mit Zielpfad, Quelle, Version und Rollen
  files = {

    ----------------------------------------------------------------
    -- Shared (für master + node)
    ----------------------------------------------------------------
    { dst="/xreactor/shared/json.lua",      url=u("src/shared/json.lua"),      ver="2025-09-12-01", roles={"master","node"} },
    { dst="/xreactor/shared/storage.lua",   url=u("src/shared/storage.lua"),   ver="2025-09-12-01", roles={"master","node"} },
    { dst="/xreactor/shared/gui.lua",       url=u("src/shared/gui.lua"),       ver="2025-09-12-01", roles={"master","node"} },
    { dst="/xreactor/shared/protocol.lua",  url=u("src/shared/protocol.lua"),  ver="2025-10-15-02", roles={"master","node"} },
    { dst="/xreactor/shared/backup.lua",    url=u("src/shared/backup.lua"),    ver="2025-09-12-01", roles={"master","node"} },
    { dst="/xreactor/shared/ha.lua",        url=u("src/shared/ha.lua"),        ver="2025-10-15-01", roles={"master","node"} },
    { dst="/xreactor/shared/policy.lua",    url=u("src/shared/policy.lua"),    ver="2025-10-15-01", roles={"master","node"} },
    { dst="/xreactor/shared/webhooks.lua",  url=u("src/shared/webhooks.lua"),  ver="2025-10-15-01", roles={"master","node"} },

    ----------------------------------------------------------------
    -- Installer (Self-Update an feste Stelle)
    ----------------------------------------------------------------
    { dst="/xreactor/installer.lua",        url=u("installer/installer.lua"),  ver="2025-10-15-04", roles={"master","node"} },

    ----------------------------------------------------------------
    -- Master
    -- (Hauptprogramm liegt im Repo unter src/master/master.lua,
    --  wird aber als /xreactor/master installiert/gestartet)
    ----------------------------------------------------------------
    { dst="/xreactor/master",               url=u("src/master/master.lua"),     ver="2025-10-15-04", roles={"master"} },
    { dst="/xreactor/master/sequencer.lua", url=u("src/master/sequencer.lua"),  ver="2025-10-15-01", roles={"master"} },
    { dst="/xreactor/master/playbooks.lua", url=u("src/master/playbooks.lua"),  ver="2025-10-15-01", roles={"master"} },
    { dst="/xreactor/master/matrix_core.lua", url=u("src/master/matrix_core.lua"), ver="2025-10-15-02", roles={"master"} },
    { dst="/xreactor/master/fuel_core.lua", url=u("src/master/fuel_core.lua"),  ver="2025-10-15-01", roles={"master"} },
    { dst="/xreactor/master/waste_core.lua",url=u("src/master/waste_core.lua"), ver="2025-10-15-01", roles={"master"} },

    -- Master-Config (nur bei Erstinstallation überschreiben; das regelt der Installer)
    { dst="/xreactor/config_master.lua",    url=u("src/master/config_master.lua"), ver="2025-10-15-04", roles={"master"} },

    ----------------------------------------------------------------
    -- Node
    -- (Hauptprogramm liegt im Repo unter src/node/node.lua,
    --  wird aber als /xreactor/node installiert/gestartet)
    ----------------------------------------------------------------
    { dst="/xreactor/node",                 url=u("src/node/node.lua"),         ver="2025-10-15-02", roles={"node"} },

    -- Node-Config
    { dst="/xreactor/config_node.lua",      url=u("src/node/config_node.lua"),  ver="2025-10-16-01", roles={"node"} },

    ----------------------------------------------------------------
    -- Tools (optional; nützlich fürs Troubleshooting)
    ----------------------------------------------------------------
    { dst="/xreactor/debug",                url=u("src/tools/debug.lua"),       ver="2025-10-15-01", roles={"master","node"}, optional=true },
    { dst="/xreactor/dump",                 url=u("src/tools/dump.lua"),        ver="2025-10-15-01", roles={"master","node"}, optional=true },
  },

  -- Rollenübersicht (für schnelle „Pflichtdateien“-Kontrolle im Installer)
  roles = {
    master = {
      "/xreactor/master",
      "/xreactor/config_master.lua",
      "/xreactor/shared/json.lua",
      "/xreactor/shared/gui.lua",
      "/xreactor/shared/storage.lua",
      "/xreactor/shared/protocol.lua",
    },
    node = {
      "/xreactor/node",
      "/xreactor/config_node.lua",
      "/xreactor/shared/json.lua",
      "/xreactor/shared/storage.lua",
      "/xreactor/shared/protocol.lua",
    },
  },
}

return manifest
