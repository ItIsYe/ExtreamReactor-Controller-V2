--========================================================
-- /src/master/config_master.lua
-- XReactor • Master Konfigurationsdatei
--========================================================

return {
  -- Hardware & Kommunikation
  modem_side      = "right",     -- Wireless-Modem (Rednet)
  auth_token      = "xreactor",  -- muss mit Node-Config übereinstimmen
  telem_timeout_s = 15,          -- Sekunden bis Node als „offline“ gilt

  -- Anzeige & GUI
  redraw_interval = 0.25,        -- GUI-Refresh-Intervall
  views = {
    dashboard = nil,             -- z. B. "monitor_0"
    control   = nil,             -- z. B. "monitor_1"
    config    = nil,             -- z. B. "monitor_2"
  },

  -- Monitore über Wired-Modem (für remote angeschlossene Monitore)
  -- Setze hier die Seite deines WIRED-Modems (z. B. "left"), wenn deine Monitore
  -- per Kabel am Netzwerk hängen. Bei nil werden nur lokale Monitore gelistet.
  monitor_wired_side = nil,

  -- Mekanism Induction Matrix (optional)
  matrix = {
    enable     = true,           -- Matrix anzeigen, wenn gefunden
    name       = nil,            -- fester Peripheral-Name (oder nil = auto-find)
    wired_side = nil,            -- z. B. "left" falls über Wired-Modem erreichbar
  },

  -- Logging
  log_enabled = true,
  log_level   = "info",
}