return {
  auth_token = "changeme",
  modem_side = "left",

  -- UI
  monitor_name = nil, -- auto-pick the largest monitor if nil
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
}
