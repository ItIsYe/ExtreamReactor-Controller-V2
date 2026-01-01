--========================================================
-- ExtreamReactor-Controller-V2 — Manifest (AUTOSTART + Nodes)
--========================================================
return {
  version    = "2025-10-31-9",
  created_at = "2025-10-31T00:00:00Z",
  base_url   = "https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main",

  files = {
    -- Shared
    { src = "src/shared/protocol.lua",          dst = "/xreactor/shared/protocol.lua" },  -- v1.1.0 (Identity)
    { src = "src/shared/identity.lua",          dst = "/xreactor/shared/identity.lua" },  -- NEW
    { src = "src/shared/log.lua",               dst = "/xreactor/shared/log.lua" },
    { src = "src/shared/topbar.lua",            dst = "/xreactor/shared/topbar.lua" },    -- Health-Check
    { src = "src/shared/network_dispatcher.lua",dst = "/xreactor/shared/network_dispatcher.lua" },
    { src = "src/shared/node_state_machine.lua",dst = "/xreactor/shared/node_state_machine.lua" },
    { src = "src/shared/node_runtime.lua",      dst = "/xreactor/shared/node_runtime.lua" },
    { src = "src/shared/local_state_store.lua", dst = "/xreactor/shared/local_state_store.lua" },

    -- Node Core
    { src = "src/node/node_core.lua",           dst = "/xreactor/node/node_core.lua" },

    -- Master UI
    { src = "src/master/master_core.lua",    dst = "/xreactor/master/master_core.lua" },
    { src = "src/master/master_model.lua",   dst = "/xreactor/master/master_model.lua" },
    { src = "src/master/master_home.lua",    dst = "/xreactor/master/master_home.lua" },
    { src = "src/master/fuel_panel.lua",     dst = "/xreactor/master/fuel_panel.lua" },
    { src = "src/master/waste_panel.lua",    dst = "/xreactor/master/waste_panel.lua" },
    { src = "src/master/alarm_center.lua",   dst = "/xreactor/master/alarm_center.lua" },
    { src = "src/master/alarm_panel.lua",    dst = "/xreactor/master/alarm_panel.lua" },
    { src = "src/master/overview_panel.lua", dst = "/xreactor/master/overview_panel.lua" },

    -- Tools & UI Map
    { src = "src/ui_map.lua",                dst = "/xreactor/ui_map.lua" },
    { src = "src/tools/build_ui_map.lua",    dst = "/xreactor/tools/build_ui_map.lua" },
    { src = "src/tools/self_test.lua",       dst = "/xreactor/tools/self_test.lua" },

    -- Universal Autostart
    { src = "startup.lua",                   dst = "/startup.lua" },

    -- Node Runtimes
    { src = "src/node/reactor_node.lua",        dst = "/xreactor/node/reactor_node.lua" },
    { src = "src/node/fuel_node.lua",           dst = "/xreactor/node/fuel_node.lua" },
    { src = "src/node/reprocessing_node.lua",   dst = "/xreactor/node/reprocessing_node.lua" },
    { src = "src/node/energy_node.lua",         dst = "/xreactor/node/energy_node.lua" },
  },
}

