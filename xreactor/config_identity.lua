--========================================================
-- /xreactor/config_identity.lua
-- Identität dieses Computers im XReactor-Cluster
--========================================================
return {
  role     = "MASTER",            -- MASTER | REACTOR | FUEL | WASTE | AUX
  id       = "01",
  hostname = "",                  -- leer => auto "XR-MASTER-01"
  cluster  = "XR-CLUSTER-ALPHA",
  token    = "xreactor"
}

