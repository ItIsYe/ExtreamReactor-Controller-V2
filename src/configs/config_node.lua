--========================================================
-- /src/configs/config_node.lua
-- XReactor • Reaktor/Turbinen-Node Konfiguration
--========================================================

return {
  auth_token   = "xreactor",
  modem_side   = "right",     -- wireless modem
  tick_rate_s  = 1.0,         -- Telemetrie-Intervall

  -- Fallback-Autosteuerung (wenn Master schweigt)
  auto = {
    enable             = true,   -- Auto-Mode grundsätzlich erlauben
    master_timeout_s   = 20,     -- nach so vielen Sekunden ohne Master-CMD → Auto-Mode
    rpm_target         = 1800,   -- Ziel-RPM pro Turbine
    rpm_band           = 100,    -- Toleranzband ±
    flow_step          = 25,     -- Schrittgröße bei Flow-Anpassung (mB/t), falls API verfügbar
    inductor_on_min_rpm= 500,    -- Inductor ab dieser RPM einschalten
    reactor_keep_on    = true,   -- Reaktor im Auto-Mode eingeschaltet halten
    -- Auto-Waste
    waste_max_pct      = 60,     -- ab diesem % wird automatisch DRAIN versucht
    waste_batch_amount = 4000,   -- gewünschte Drain-Menge (mB), falls API das unterstützt
    waste_cooldown_s   = 90,     -- Cooldown zwischen Auto-DRAINs pro Reaktor
  },

  -- Debug
  log = {
    enabled = false,
    level   = "info",
  },
}