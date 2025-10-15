return {
  auth_token = "changeme",
  modem_side = "left",

  -- UI
  monitor_name = nil,
  text_scale   = 0.5,
  rows_per_page = nil,

  -- timings
  telem_timeout     = 10,
  offline_threshold = 30,
  beacon_interval   = 5,
  setpoint_interval = 5,

  -- policy defaults
  soc_low=0.30, soc_high=0.85, hysteresis=0.03,
  rpm_target=1800, steam_max=2000,

  -- ===== Phase B: Fuel =====
  fuel_low_threshold     = 0.15,
  fuel_target_threshold  = 0.95,
  refuel_cooldown        = 60,
  fuel_auto_refill       = true,
  fuel_request_type      = "rednet", -- "rednet" | "ccbridge" (Supply-PC empfohlen)
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

  -- Reprocessing
  reproc_enabled         = true,
  reproc_water_guard     = true,
  reproc_queue_max       = 8,
  reproc_out_item_id     = "biggerreactors:blutonium_ingot",
}
