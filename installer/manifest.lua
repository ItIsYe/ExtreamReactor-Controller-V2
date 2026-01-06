--========================================================
-- ExtreamReactor-Controller-V2 — Manifest (AUTOSTART + Nodes)
--========================================================
return {
  version    = "2025-10-31-9",
  created_at = "2025-10-31T00:00:00Z",
  base_url   = "https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main",

  files = {
    -- Shared
    { src = "src/shared/text.lua",              dst = "/xreactor/shared/text.lua",              size = 355 },
    { src = "src/shared/protocol.lua",          dst = "/xreactor/shared/protocol.lua",          size = 4603 },
    { src = "src/shared/identity.lua",          dst = "/xreactor/shared/identity.lua",          size = 1408 },
    { src = "src/shared/log.lua",               dst = "/xreactor/shared/log.lua",               size = 1169 },
    { src = "src/shared/topbar.lua",            dst = "/xreactor/shared/topbar.lua",            size = 3639 },
    { src = "src/shared/network_dispatcher.lua",dst = "/xreactor/shared/network_dispatcher.lua", size = 4917 },
    { src = "src/shared/node_state_machine.lua",dst = "/xreactor/shared/node_state_machine.lua", size = 1880 },
    { src = "src/shared/node_runtime.lua",      dst = "/xreactor/shared/node_runtime.lua",      size = 8810 },
    { src = "src/shared/local_state_store.lua", dst = "/xreactor/shared/local_state_store.lua", size = 1856 },

    -- Node Core
    { src = "src/node/node_core.lua",           dst = "/xreactor/node/node_core.lua",           size = 14745 },

    -- Master UI
    { src = "src/master/master_core.lua",       dst = "/xreactor/master/master_core.lua",       size = 6697 },
    { src = "src/master/master_model.lua",      dst = "/xreactor/master/master_model.lua",      size = 23156 },
    { src = "src/master/master_home.lua",       dst = "/xreactor/master/master_home.lua",       size = 13670 },
    { src = "src/master/fuel_panel.lua",        dst = "/xreactor/master/fuel_panel.lua",        size = 3363 },
    { src = "src/master/waste_panel.lua",       dst = "/xreactor/master/waste_panel.lua",       size = 3250 },
    { src = "src/master/alarm_center.lua",      dst = "/xreactor/master/alarm_center.lua",      size = 5753 },
    { src = "src/master/alarm_panel.lua",       dst = "/xreactor/master/alarm_panel.lua",       size = 4994 },
    { src = "src/master/overview_panel.lua",    dst = "/xreactor/master/overview_panel.lua",    size = 5574 },

    -- Tools & UI Map
    { src = "src/ui_map.lua",                   dst = "/xreactor/ui_map.lua",                   size = 571 },
    { src = "src/tools/build_ui_map.lua",       dst = "/xreactor/tools/build_ui_map.lua",       size = 2872 },
    { src = "src/tools/self_test.lua",          dst = "/xreactor/tools/self_test.lua",          size = 1570 },

    -- Universal Autostart
    { src = "startup.lua",                      dst = "/startup.lua",                           size = 45 },

    -- Node Runtimes
    { src = "src/node/reactor_node.lua",        dst = "/xreactor/node/reactor_node.lua",        size = 11157 },
    { src = "src/node/energy_node.lua",         dst = "/xreactor/node/energy_node.lua",         size = 6166 },
    { src = "src/node/fuel_node.lua",           dst = "/xreactor/node/fuel_node.lua",           size = 6278 },
    { src = "src/node/reprocessing_node.lua",   dst = "/xreactor/node/reprocessing_node.lua",   size = 2453 },
  },
}

