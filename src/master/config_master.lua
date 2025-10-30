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
  monitor_wired_side = nil,      -- z. B. "left" oder nil

  -- Mekanism Induction Matrix (optional)
  matrix = {
    enable     = true,
    name       = nil,            -- fester Peripheral-Name (oder nil = auto-find)
    wired_side = nil,            -- z. B. "left" falls über Wired-Modem erreichbar
  },

  -- Logging
  log_enabled = true,
  log_level   = "info",

  -- AutoScale-Defaults (pro View; kann in /xreactor/ui_master.json überschrieben werden)
  default_view_scale = {
    dashboard = { autoscale=true, desired_cols=60, correction=0.0, manual=1.0 },
    control   = { autoscale=true, desired_cols=60, correction=0.0, manual=1.0 },
    config    = { autoscale=true, desired_cols=60, correction=0.0, manual=1.0 },
  },

  --======================================================
  -- PHASE 1 • FUEL-MANAGEMENT (ohne ME-Anbindung)
  --======================================================
  fuel = {
    enable       = true,   -- Master überwacht Fuel-Level & sendet FUEL_REQ
    min_pct      = 20,     -- unter diesem % wird nachgefordert
    target_pct   = 60,     -- Zielwert; Bedarf = Differenz bis target
    request_unit = 4,      -- in Ingots pro Anfrage (Abrundung auf Einheit)
    cooldown_s   = 90,     -- Cooldown pro Reaktor, um Spam zu vermeiden
    supplier_tag = "any",  -- optional: Supplier-Gruppe/Tag (frei für Phase 2)
  },
}