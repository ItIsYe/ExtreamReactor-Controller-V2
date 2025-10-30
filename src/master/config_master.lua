--========================================================
-- /src/master/config_master.lua
-- XReactor • Master Konfigurationsdatei
--========================================================

return {
  -- Hardware & Kommunikation
  modem_side      = "right",
  auth_token      = "xreactor",
  telem_timeout_s = 15,

  -- Anzeige & GUI
  redraw_interval = 0.25,
  views = {
    dashboard = nil,
    control   = nil,
    config    = nil,
  },

  -- Monitore über Wired-Modem
  monitor_wired_side = nil,

  -- Mekanism Induction Matrix (optional)
  matrix = { enable=true, name=nil, wired_side=nil },

  -- Logging
  log_enabled = true,
  log_level   = "info",

  -- AutoScale-Defaults
  default_view_scale = {
    dashboard = { autoscale=true, desired_cols=60, correction=0.0, manual=1.0 },
    control   = { autoscale=true, desired_cols=60, correction=0.0, manual=1.0 },
    config    = { autoscale=true, desired_cols=60, correction=0.0, manual=1.0 },
  },

  -- Phase 1 • Fuel-Management
  fuel = {
    enable       = true,
    min_pct      = 20,
    target_pct   = 60,
    request_unit = 4,
    cooldown_s   = 90,
    supplier_tag = "any",
  },

  -- Phase 2 • Waste-Management (Drain über Reaktor-Nodes)
  waste = {
    enable        = true,   -- aktiviert Master-Seite (Drain-Commands an Nodes)
    max_pct       = 40,     -- ab diesem Waste-% wird drain angewiesen
    cooldown_s    = 120,    -- Cooldown pro Reaktor/Node für Drain-Befehle
    batch_amount  = 4000,   -- gewünschte Menge pro Drain-Vorgang (mB, falls unterstützt)
    tag_receiver  = "any",  -- nur Info/Markierung (Fuel/Waste-Node arbeitet autonom)
  },
}