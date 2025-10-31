--========================================================
-- /xreactor/ui_map.lua
-- Monitor-Rollen & Skalierung (Beispielbelegung)
--========================================================
return {
  monitors = {
    ["monitor_0"] = { role = "master_home",     scale = 0.5 },
    ["monitor_1"] = { role = "fuel_manager",    scale = 0.5 },
    ["monitor_2"] = { role = "waste_service",   scale = 0.5 },
    ["monitor_3"] = { role = "alarm_center",    scale = 0.5 },
    ["monitor_4"] = { role = "system_overview", scale = 0.5 },
  },
  autoscale = { enabled = true }
}
