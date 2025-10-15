-- =========================================================
-- XReactor Manifest
--   Installations-Manifest für alle Rollen:
--   MASTER | NODE | DEBUG
-- =========================================================

return {

  -- =========================================================
  -- MASTER (zentraler Bildschirm)
  -- =========================================================
  ["/xreactor/master"] = {
    ver   = "2025-10-15-03",
    roles = {"master"},
    url   = "https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/src/master/master.lua",
    desc  = "Zentrale Steuerung & Anzeige aller Reaktor-Nodes"
  },

  ["/xreactor/config_master.lua"] = {
    ver   = "2025-10-15-01",
    roles = {"master"},
    url   = "https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/src/master/config_master.lua",
    desc  = "Master-Konfigurationsdatei"
  },

  -- =========================================================
  -- NODE (Erfassungseinheit)
  -- =========================================================
  ["/xreactor/node"] = {
    ver   = "2025-10-15-03",
    roles = {"node"},
    url   = "https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/src/node/node.lua",
    desc  = "XReactor Node – scannt BigReactors & Turbinen, sendet Telemetrie"
  },

  ["/xreactor/config_node.lua"] = {
    ver   = "2025-10-15-02",
    roles = {"node"},
    url   = "https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/src/node/config_node.lua",
    desc  = "Node-Konfigurationsdatei (Modem, Monitor, Auth usw.)"
  },

  -- =========================================================
  -- DEBUG TOOL
  -- =========================================================
  ["/xreactor/debug"] = {
    ver   = "2025-10-15-01",
    roles = {"debug"},
    url   = "https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/src/debug/debug.lua",
    desc  = "Peripherie- und Netzwerk-Debugger für Nodes"
  },

  -- =========================================================
  -- INSTALLER (Selbstupdate & AutoStart)
  -- =========================================================
  ["/xreactor/installer.lua"] = {
    ver   = "2025-10-15-01",
    roles = {"master","node","debug"},
    url   = "https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/installer/installer.lua",
    desc  = "Installer – lädt & aktualisiert alle Komponenten"
  },

  ["/startup.lua"] = {
    ver   = "2025-10-15-01",
    roles = {"master","node"},
    url   = "https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/installer/startup.lua",
    desc  = "Startskript: Automatischer Start von XReactor je nach Rolle"
  },

  -- =========================================================
  -- META
  -- =========================================================
  ["_meta"] = {
    repo  = "https://github.com/ItIsYe/ExtreamReactor-Controller-V2",
    maintainer = "ItIsYe",
    last_update = "2025-10-16",
  }
}
