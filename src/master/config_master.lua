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

  -- policy defaults
  soc_low=0.30, soc_high=0.85, hysteresis=0.03,
  rpm_target=1800, steam_max=2000,

  -- ===== Fuel =====
  fuel_low_threshold     = 0.15,
  fuel_target_threshold  = 0.95,
  refuel_cooldown        = 60,
  fuel_auto_refill       = true,
  fuel_request_type      = "rednet",
  fuel_source_id         = "ME",
  min_refuel_batch       = 1,
  max_refuel_batch       = 64,
  fuel_item_id           = "biggerreactors:yellorium_ingot",

  -- ===== Waste / Reproc =====
  waste_max_threshold    = 0.80,
  waste_target_threshold = 0.20,
  waste_drain_batch      = 64,
  waste_drain_cooldown   = 120,
  waste_auto_drain       = true,
  waste_strategy         = "online",
  waste_item_id          = "biggerreactors:cyanite_ingot",
  reproc_enabled         = true,
  reproc_water_guard     = true,
  reproc_queue_max       = 8,
  reproc_out_item_id     = "biggerreactors:blutonium_ingot",

  -- ===== Adaptive / Thermal / Logging =====
  adapt_enabled     = true,   adapt_k=0.60, adapt_min_factor=0.25, adapt_max_factor=1.00, adapt_smooth=0.60, adapt_dt=5,
  therm_enabled     = true,   therm_target=860, therm_band=40, therm_gain=0.15,
  log_capacity      = 180,    log_path="/xreactor/logs/master_timeseries.json",

  -- ===== HA / Roles / Webhooks / Backup =====
  ha_leader_timeout = 15,     -- s without foreign leader beacon → self promote
  role              = "admin",-- "viewer"|"operator"|"admin"
  pin               = nil,    -- optional PIN for sensitive actions
  webhooks_enabled  = false,
  webhook_url       = "",     -- e.g. Discord webhook; http API must be enabled server-side
  webhook_headers   = {["Content-Type"]="application/json"},
  backup_enabled    = true,
  backup_dir        = "/xreactor/backups",
}
