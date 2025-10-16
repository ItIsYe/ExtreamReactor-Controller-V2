-- XReactor Node – Standardkonfiguration
-- Diese Datei wird bei Erstinstallation geschrieben und danach NICHT überschrieben.
-- Passe sie an deine Verkabelung an.

local CFG = {

  -- ▸ Seiten der lokalen Peripherie
  -- Funk/Rednet-Modem zum Master:
  modem_side   = "right",
  -- Monitor am Node (Statusanzeige); auf "none" setzen, falls keiner verbunden ist:
  monitor_side = "bottom",

  -- ▸ Identität/Metadaten
  -- Willst du den Node einer Ebene/Floor zuordnen, trage hier eine Zahl ein.
  -- (Nur Info; Master kann das in der Anzeige nutzen)
  floor = 0,

  -- ▸ Sicherheit/Netz
  -- Einfacher Token, muss mit dem Master übereinstimmen, wenn Auth genutzt wird:
  auth_token = "changeme",

  -- ▸ Scan-/Polling-Intervalle (Sekunden)
  telem_interval = 1.0,   -- wie oft Telemetrie an den Master gesendet wird
  hello_interval = 5.0,   -- HELLO/Keepalive

  -- ▸ Anzeige
  ui_scale = 1,           -- 1..5 (wird vom Code automatisch auf Monitorgröße angepasst)

  -- ▸ Filter (optional)
  -- Wenn gesetzt, werden NUR Peripherie-Namen gematcht, die auf das Pattern passen.
  -- Beispiel: "^BigReactors%-Reactor"  oder  "BigReactors%-Turbine"
  reactor_filter  = nil,
  turbine_filter  = nil,

  -- ▸ Sprache für evtl. Meldungen
  language = "de",
}

return CFG
