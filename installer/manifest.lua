return {
  version = "2025-10-15-PhaseD-01",

  -- welche Datei ist die Start-Exe je Rolle?
  startup = {
    master = "/xreactor/master",
    node   = "/xreactor/node",
    supply = "/xreactor/supply",
  },

  -- alle Dateien mit Zielpfad → {url, ver, roles}
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

    -- master
    ["/xreactor/config_master.lua"]     = { ver="2025-10-15-04", roles={"master"},
      url="https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/src/master/config_master.lua" },
    ["/xreactor/master"]                = { ver="2025-10-15-04", roles={"master"},
      url="https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/src/master/master.lua" },
    ["/xreactor/master/fuel_core.lua"]  = { ver="2025-10-15-01", roles={"master"},
      url="https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/src/master/fuel_core.lua" },
    ["/xreactor/master/waste_core.lua"] = { ver="2025-10-15-01", roles={"master"},
      url="https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/src/master/waste_core.lua" },
    ["/xreactor/master/sequencer.lua"]  = { ver="2025-10-15-01", roles={"master"},
      url="https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/src/master/sequencer.lua" },
    ["/xreactor/master/playbooks.lua"]  = { ver="2025-10-15-01", roles={"master"},
      url="https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/src/master/playbooks.lua" },
    ["/xreactor/master/matrix_core.lua"]= { ver="2025-10-15-01", roles={"master"},
      url="https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/src/master/matrix_core.lua" },

    -- node
    ["/xreactor/config_node.lua"]       = { ver="2025-10-15-01", roles={"node"},
      url="https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/src/node/config_node.lua" },
    ["/xreactor/node"]                  = { ver="2025-10-15-02", roles={"node"},
      url="https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/src/node/node.lua" },

    -- supply
    ["/xreactor/config_supply.lua"]     = { ver="2025-10-15-01", roles={"supply"},
      url="https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/src/supply/config_supply.lua" },
    ["/xreactor/supply"]                = { ver="2025-10-15-01", roles={"supply"},
      url="https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/src/supply/supply.lua" },

    -- (optional) installer selbst → so kann er sich updaten
    ["/installer.lua"]                  = { ver="2025-10-15-02", roles={"all"},
      url="https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/installer.lua" },
    ["/xreactor/.installed_manifest.lua"]= { ver="meta", roles={"all"},
      url="https://raw.githubusercontent.com/ItIsYe/ExtreamReactor-Controller-V2/main/manifest.lua" }, -- nur Referenz
  }
}
