--========================================================
-- ExtreamReactor-Controller-V2 — Manifest (AUTOSTART + AUX)
--========================================================
return {
  version    = "2025-10-31-3",
  created_at = "2025-10-31T00:00:00Z",
  base_url   = "https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main",

  files = {
    -- Shared
    { src = "src/shared/protocol.lua",    dst = "/xreactor/shared/protocol.lua" },  -- v1.1.0 (Identity)
    { src = "src/shared/identity.lua",    dst = "/xreactor/shared/identity.lua" },  -- NEW
    { src = "src/shared/log.lua",         dst = "/xreactor/shared/log.lua" },
    { src = "src/shared/topbar.lua",      dst = "/xreactor/shared/topbar.lua" },    -- Health-Check

    -- Master UI
    { src = "src/master/master_home.lua",    dst = "/xreactor/master/master_home.lua" },
    { src = "src/master/fuel_panel.lua",     dst = "/xreactor/master/fuel_panel.lua" },
    { src = "src/master/waste_panel.lua",    dst = "/xreactor/master/waste_panel.lua" },
    { src = "src/master/alarm_center.lua",   dst = "/xreactor/master/alarm_center.lua" },
    { src = "src/master/overview_panel.lua", dst = "/xreactor/master/overview_panel.lua" },

    -- Tools & UI Map
    { src = "src/ui_map.lua",                dst = "/xreactor/ui_map.lua" },
    { src = "src/tools/build_ui_map.lua",    dst = "/xreactor/tools/build_ui_map.lua" },
    { src = "src/tools/self_test.lua",       dst = "/xreactor/tools/self_test.lua" },

    -- Universal Autostart
    { src = "startup.lua",                   dst = "/startup.lua" },

    -- Node AUX (Platzhalter/Beispiel)
    { src = "src/node/aux_node.lua",         dst = "/xreactor/node/aux_node.lua" },
  },
}

