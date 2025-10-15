return {
  auth_token = "changeme",
  modem_side = "left",

  -- UI
  monitor_name   = nil,
  text_scale     = 0.5,
  rows_per_page  = nil,

  -- timings
  telem_timeout     = 10,
  offline_threshold = 30,
  beacon_interval   = 5,
  setpoint_interval = 5,

  -- policy defaults (Phase A/B baseline)
  soc_low=0.30, soc_high=0.85, hysteresis=0.03,
  rpm_target=1800, steam_max=2000,

  -- ===== Phase B: Fuel =====
  fuel_low_threshold     = 0.15,
  fuel_target_threshold  = 0.95,
  refuel_cooldown        = 60,
  fuel_auto_refill       = true,
  fuel_request_type      = "rednet", -- "rednet" | "ccbridge"
  fuel_source_id         = "ME",
  min_refuel_batch       = 1,
  max_refuel_batch       = 64,
  fuel_item_id           = "biggerreactors:yellorium_ingot",

  -- ===== Phase B: Waste =====
  waste_max_threshold    = 0.80,
  waste_target_threshold = 0.20,
  waste_drain_batch      = 64,
  waste_drain_cooldown   = 120,
  waste_auto_drain       = true,
  waste_strategy         = "online", -- "online" | "pause"
  waste_item_id          = "biggerreactors:cyanite_ingot",
  reproc_enabled         = true,
  reproc_water_guard     = true,
  reproc_queue_max       = 8,
  reproc_out_item_id     = "biggerreactors:blutonium_ingot",

  -- ===== Phase C: Adaptive Ramp =====
  adapt_enabled     = true,   -- aktiviere adaptive Stellgröße
  adapt_k           = 0.60,   -- Verstärkung (0..1)
  adapt_min_factor  = 0.25,   -- untere Klemme relativer Steam-Anteil
  adapt_max_factor  = 1.00,   -- obere Klemme
  adapt_smooth      = 0.60,   -- EMA Glättung (0..1)
  adapt_dt          = 5,      -- Sekundenfenster für Trend (≈ setpoint_interval)

  -- ===== Phase C: Thermisches Band =====
  therm_enabled     = true,
  therm_target      = 860,    -- °C Ziel
  therm_band        = 40,     -- ±Bandbreite
  therm_gain        = 0.15,   -- Korrekturfaktor (0..1) auf steam_target

  -- ===== Phase C: Logging & Graphs =====
  log_capacity      = 180,    -- ~15 min bei 5s interval
  log_path          = "/xreactor/logs/master_timeseries.json",
}
