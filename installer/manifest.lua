-- =========================================================
-- XReactor ◈ Installer Manifest
-- =========================================================
-- Dieses Manifest beschreibt alle Module, ihre Rollen
-- und GitHub-Quellen. Der Installer vergleicht lokale
-- Versionen und aktualisiert automatisch.
-- =========================================================

local MANIFEST = {

  -- ===================== MASTER ==========================
  ["/xreactor/master"] = {
    ver = "2025-10-16-01",
    roles = {"master"},
    url = "https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/src/master/master.lua",
    desc = "Master-Controller mit Monitor-UI, Node-Übersicht und Touch-Steuerung (Reaktor/Turbine)."
  },

  -- ===================== NODE ============================
  ["/xreactor/node"] = {
    ver = "2025-10-16-01",
    roles = {"node"},
    url = "https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/src/node/node.lua",
    desc = "Node-Agent für Reaktoren und Turbinen, sendet Telemetrie und empfängt Steuerbefehle."
  },

  -- ===================== SHARED MODULES ==================
  ["/xreactor/shared/json.lua"] = {
    ver = "2025-09-12-01",
    roles = {"master","node"},
    url = "https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/src/shared/json.lua",
    desc = "JSON-Utility (Encoding/Decoding für Config & Netzwerkdaten)."
  },

  ["/xreactor/shared/storage.lua"] = {
    ver = "2025-09-12-01",
    roles = {"master","node"},
    url = "https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/src/shared/storage.lua",
    desc = "Speicher-Utility für JSON-basierte lokale Konfigurationen."
  },

  ["/xreactor/shared/gui.lua"] = {
    ver = "2025-09-12-01",
    roles = {"master","node"},
    url = "https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/src/shared/gui.lua",
    desc = "Einfache GUI-Komponenten (Formulare, Menüs, Touch-Eingabe)."
  },

  -- ===================== CONFIGS =========================
  ["/xreactor/config_master.lua"] = {
    ver = "2025-09-18-01",
    roles = {"master"},
    url = "https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/src/configs/config_master.lua",
    desc = "Standardkonfiguration für den Master-Controller."
  },

  ["/xreactor/config_node.lua"] = {
    ver = "2025-09-18-01",
    roles = {"node"},
    url = "https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/src/configs/config_node.lua",
    desc = "Standardkonfiguration für Node-Agenten."
  },

  -- ===================== STARTUP =========================
  ["/startup"] = {
    ver = "2025-09-30-01",
    roles = {"master","node"},
    url = "https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/src/startup.lua",
    desc = "Automatischer Start-Launcher für Master- oder Node-Modus."
  },

  -- ===================== INSTALLER =======================
  ["/xreactor/installer.lua"] = {
    ver = "2025-09-30-01",
    roles = {"installer"},
    url = "https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/installer/installer.lua",
    desc = "Installer-Script für XReactor-System. Prüft und lädt alle Module neu."
  },

}

-- =========================================================
-- Manifest zurückgeben
-- =========================================================
return MANIFEST
