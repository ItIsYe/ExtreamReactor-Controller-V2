-- /xreactor/config_identity.lua
return {
  -- Rolle des aktuellen Computers:
  --  "MASTER"  → versucht GUI/Monitor zu verwenden (fällt auf AUX zurück, falls GUI fehlt)
  --  "AUX"     → Textmodus/Worker-Node
  role     = "AUX",

  -- Beliebige ID zur Unterscheidung (String):
  id       = "01",

  -- Leer lassen = auto (ComputerLabel oder generiert)
  hostname = "",

  -- Cluster-Name (alle Nodes im selben Cluster sprechen miteinander):
  cluster  = "XR-CLUSTER-ALPHA",

  -- Shared Token/Passwort für Rednet-Protokolle:
  token    = "xreactor"
}
