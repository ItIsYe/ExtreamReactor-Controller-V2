return {
  version = "2025-10-15-PhaseE-01",

  startup = {
    master = "/xreactor/master",
    node   = "/xreactor/node",
    supply = "/xreactor/supply",
  },

  files = {
    -- shared
    ["/xreactor/shared/storage.lua"]    = { ver="2025-10-15-01", roles={"all"},
      url="https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/src/shared/storage.lua" },
    ["/xreactor/shared/protocol.lua"]   = { ver="2025-10-15-02", roles={"all"},
      url="https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/src/shared/protocol.lua" },
    ["/xreactor/shared/policy.lua"]     = { ver="2025-10-15-01", roles={"all"},
      url="https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/src/shared/policy.lua" },
    ["/xreactor/shared/devices.lua"]    = { ver="2025-10-15-02", roles={"all"},
      url="https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/src/shared/devices.lua" },
    ["/xreactor/shared/logger.lua"]     = { ver="2025-10-15-01", roles={"master"},
      url="https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/src/shared/logger.lua" },
    ["/xreactor/shared/auth.lua"]       = { ver="2025-10-15-01", roles={"master"},
      url="https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/src/shared/auth.lua" },
    ["/xreactor/shared/backup.lua"]     = { ver="2025-10-15-01", roles={"master"},
      url="https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/src/shared/backup.lua" },
    ["/xreactor/shared/webhooks.lua"]   = { ver="2025-10-15-01", roles={"master"},
      url="https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/src/shared/webhooks.lua" },
    ["/xreactor/shared/ha.lua"]         = { ver="2025-10-15-01", roles={"master"},
      url="https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/src/shared/ha.lua" },

    -- master (config + main)
    ["/xreactor/config_master.lua"]     = { ver="2025-10-15-04", roles={"master"},
      url="https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/src/master/config_master.lua" },
    ["/xreactor/master"]                = { ver="2025-10-15-04", roles={"master"},
      url="https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/src/master/master.lua" },

    -- master modules (direkt unter /xreactor/)
    ["/xreactor/sequencer.lua"]         = { ver="2025-10-15-03", roles={"master"},
      url="https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/src/master/sequencer.lua" },
    ["/xreactor/playbooks.lua"]         = { ver="2025-10-15-03", roles={"master"},
      url="https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/src/master/playbooks.lua" },
    ["/xreactor/matrix_core.lua"]       = { ver="2025-10-15-02", roles={"master"},
      url="https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/src/master/matrix_core.lua" },
    ["/xreactor/fuel_core.lua"]         = { ver="2025-10-15-02", roles={"master"},
      url="https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/src/master/fuel_core.lua" },
    ["/xreactor/waste_core.lua"]        = { ver="2025-10-15-02", roles={"master"},
      url="https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/src/master/waste_core.lua" },

    -- node
    ["/xreactor/config_node.lua"]       = { ver="2025-10-15-01", roles={"node"},
      url="https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/src/node/config_node.lua" },
    ["/xreactor/node"]                  = { ver="2025-10-15-02", roles={"node"},
      url="https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/src/node/node.lua" },

    -- node debug (NEU)
    ["/xreactor/debug.lua"]             = { ver="2025-10-15-01", roles={"node"},
      url="https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/src/node/debug.lua" },

    -- supply (optional)
    ["/xreactor/config_supply.lua"]     = { ver="2025-10-15-01", roles={"supply"},
      url="https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/src/supply/config_supply.lua" },
    ["/xreactor/supply"]                = { ver="2025-10-15-01", roles={"supply"},
      url="https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/src/supply/supply.lua" },

    -- self-update
    ["/installer.lua"] = {
      ver="2025-10-15-02", roles={"all"},
      url="https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/installer/installer.lua"
    },
    ["/xreactor/.installed_manifest.lua"] = {
      ver="meta", roles={"all"},
      url="https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/installer/manifest.lua"
    },
  }
}
