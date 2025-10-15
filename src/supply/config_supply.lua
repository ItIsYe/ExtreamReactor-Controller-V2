return {
  auth_token = "changeme",

  -- choose one: either a meBridge/rsBridge peripheral name or a chest/inv to export to
  me_bridge_name = "meBridge",  -- Advanced Peripherals ME Bridge (if available), else nil
  rs_bridge_name = nil,         -- Refined Storage Bridge (if available)

  -- export target: name of inventory next to the reactor input port (if using bridge export by name)
  export_target_name = "minecraft:chest_0", -- adjust to your world (or nil to use directions)

  -- directions (if your bridge uses directions instead of names): "up","down","north","south","east","west"
  export_direction = nil,

  -- default items
  fuel_item_id   = "biggerreactors:yellorium_ingot",
  waste_item_id  = "biggerreactors:cyanite_ingot",
  reproc_out_item_id = "biggerreactors:blutonium_ingot",

  -- water-guard flag for reproc (if your setup can check a tank via another peripheral, plug it here later)
  water_guard = false,
}
