-- /src/configs/config_node.lua
return {
  modem_side     = "right",      -- Wireless-Modem zum Master
  wired_side     = "top",        -- Wired-Modem für Reaktor/Turbinen
  monitor_view   = nil,          -- z.B. "monitor_0" (kann per GUI gesetzt werden)
  auth_token     = "xreactor",   -- gleiche Auth wie Master
  telem_interval = 1.0,          -- Sekunden zwischen Telemetrie-Sendungen
  hello_interval = 5.0,          -- Sekunden zwischen HELLOs
}
