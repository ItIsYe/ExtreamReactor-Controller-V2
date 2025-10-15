return {
  node_title   = "Node@"..os.getComputerID(),
  auth_token   = "changeme",

  -- Peripherie
  modem_comm   = "right",   -- wireless → Master
  wired_side   = "top",     -- wired → reactors/turbines/matrix
  monitor_side = "bottom",  -- local monitor

  -- Betrieb
  update        = 2,     -- telem interval (s)
  grace_duration= 90,    -- hold last setpoints after master loss

  -- Safety (light, Phase A)
  max_temp      = 900,   -- °C (reactor casing)
  max_rpm       = 2300,  -- turbine rotor
  min_soc_shutdown = nil,

  -- Mapping reaktorzentriert (optional jetzt, später UI-Editor)
  reactors    = {},        -- e.g. {"R-A","R-B"} (IDs frei wählbar)
  assignments = {},        -- turbine_name -> reactor_id
}
