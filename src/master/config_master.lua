return {
modem_side = "right",
auth_token = "changeme", -- Master & Nodes müssen identisch sein
rpm_target = 1800,
steam_total_min = 0,
steam_total_max = 250000,
setpoint_interval = 5,
telem_timeout = 10,
main_storages = { },
soc_target = 0.70,
kP = 180000,
kI = 20000,
distribute = "by_turbines", -- even | by_turbines | by_soc


-- Multi‑Monitor / Paging
page_interval = 5, -- Sekunden bis nächste Seite
rows_per_page = 10,


-- Gestaffeltes Hochfahren
ramp_enabled = true,
ramp_step = 5000, -- mB/t pro Schritt & Node
ramp_interval = 3, -- Sekunden zwischen Schritten
ramp_floor_offset = 2,-- Sekunden Etagen‑Versatz (floor * offset)


-- Alarm-Konfiguration (Master-Sicht)
alarm_sound = true,
alarm_rpm_low = 1600,
alarm_rpm_high = 1950,
alarm_floor_soc_low = 0.10,
alarm_node_offline_s = 15,
}
