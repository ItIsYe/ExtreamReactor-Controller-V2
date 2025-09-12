return {
  files = {
    shared = {
      { src = "src/shared/gui.lua",      dst = "xreactor/shared/gui.lua" },
      { src = "src/shared/protocol.lua", dst = "xreactor/shared/protocol.lua" },
      { src = "src/shared/storage.lua",  dst = "xreactor/shared/storage.lua" },
      { src = "src/shared/util.lua",     dst = "xreactor/shared/util.lua" },
    },
    master = {
      { src = "src/master/master.lua",        dst = "xreactor/master" },
      { src = "src/master/config_master.lua", dst = "xreactor/config_master.lua" },
    },
    node = {
      { src = "src/node/node.lua",        dst = "xreactor/node" },
      { src = "src/node/config_node.lua", dst = "xreactor/config_node.lua" },
    },
    startup = {
      { src = "startup/startup.lua", dst = "startup" },
    },
  }
}
