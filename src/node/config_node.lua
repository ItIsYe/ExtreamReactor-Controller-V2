-- XReactor Node Config
return {
  modem_side     = "right",   -- Modem zum Master (wireless oder wired)
  monitor_side   = "bottom",  -- optional, nil wenn keiner
  telem_interval = 2,
  auth_token     = "xreactor"
}
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
