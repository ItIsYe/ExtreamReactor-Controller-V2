--========================================================
-- /src/master/config_master.lua
-- XReactor • Master Konfigurationsdatei
--========================================================
-- Diese Datei legt die grundlegende Kommunikation und GUI-Parameter
-- für den Master-Controller fest.
--
-- Sie wird beim Start von master.lua eingelesen und kann jederzeit
-- im laufenden Betrieb bearbeitet werden.
--========================================================

return {
  --======================================================
  -- Hardware & Kommunikation
  --======================================================
  modem_side      = "right",     -- Seite des Wireless-Modems für Rednet
  auth_token      = "xreactor",  -- Muss mit Node-Config übereinstimmen!
  telem_timeout_s = 15,          -- Sekunden bis Node als „offline“ gilt

  --======================================================
  -- Anzeige & GUI
  --======================================================
  redraw_interval = 0.25,        -- Sekundentakt für GUI-Refresh
  views = {
    dashboard = nil,             -- z. B. "monitor_0"  → Haupt-Dashboard
    control   = nil,             -- z. B. "monitor_1"  → Steuer-Panel
    config    = nil,             -- z. B. "monitor_2"  → Konfigurations-Panel
  },

  --======================================================
  -- (Optional) Logging / Debug
  --======================================================
  log_enabled = true,            -- einfache Terminal-Logs aktivieren
  log_level   = "info",          -- info | warn | error
}
