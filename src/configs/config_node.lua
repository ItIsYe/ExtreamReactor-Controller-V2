--========================================================
-- /src/configs/config_node.lua
-- XReactor • Reaktor/Turbinen-Node Konfiguration
--========================================================
return {
  auth_token   = "xreactor",
  modem_side   = "right",   -- wireless modem
  tick_rate_s  = 1.0,       -- Telemetrie-Intervall (s)

  -- Fallback-Autosteuerung (wenn Master schweigt)
  auto = {
    enable               = true,   -- Auto-Mode grundsätzlich erlauben
    master_timeout_s     = 20,     -- nach so vielen Sekunden ohne Master-CMD → Auto-Mode

    -- Turbinen-Regelung (nur wenn API es kann)
    rpm_target           = 1800,   -- Ziel-RPM
    rpm_band             = 100,    -- Toleranzband ±
    flow_step            = 25,     -- Schrittgröße mB/t, falls setFlowRate unterstützt wird
    inductor_on_min_rpm  = 500,    -- Inductor ab dieser RPM einschalten

    -- Reaktor-Policy
    reactor_keep_on      = true,   -- Reaktor im Auto-Mode anlassen

    -- Auto-WASTE
    waste_max_pct        = 60,     -- ab diesem % wird automatisch drain versucht
    waste_batch_amount   = 4000,   -- gewünschte Drain-Menge (mB), falls API das unterstützt
    waste_cooldown_s     = 90,     -- Cooldown pro Reaktor (s)
  },

  log = { enabled = false, level = "info" },
}