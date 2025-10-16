-- ==============================================================
--  XReactor Node – Standardkonfiguration
--  Version: v2025-10-16-01
--  Autor: ItIsYe & GPT-5
--  Beschreibung:
--    - Steuerung & Telemetrie für Extreme Reactors / Turbinen.
--    - Unterstützt automatisches Erkennen von Modems & Geräten.
--    - Kompatibel mit Master-/Node-Netzwerk über Wired/Rednet.
-- ==============================================================

local CFG = {

  ----------------------------------------------------------------
  -- 🧩  Netzwerkschnittstellen
  ----------------------------------------------------------------

  -- Wireless / Rednet Modem (Kommunikation mit Master)
  modem_side   = "right",   -- z.B. "left", "right", "back", "top", "bottom"

  -- Wired-Modem für Reaktoren, Turbinen, Induktionsmatrix, etc.
  -- Wird für die lokale Gerätekommunikation verwendet.
  wired_side   = "top",     -- Seite, an der das Kabel angeschlossen ist

  -- Optionaler Monitor (lokale Anzeige, falls vorhanden)
  monitor_side = "bottom",  -- "none", wenn kein Monitor angeschlossen ist


  ----------------------------------------------------------------
  -- ⚙️  Gerätekonfiguration / Filter
  ----------------------------------------------------------------

  -- Gerätefilter – nur Geräte scannen, deren Namen darauf passen:
  -- (Lua-Muster, kein Regex!)
  reactor_filter  = "^BigReactors%-Reactor",  -- oder nil für alle
  turbine_filter  = "^BigReactors%-Turbine",  -- oder nil für alle
  battery_filter  = "^mekanism:InductionPort", -- für Mekanism Matrix optional

  -- Wenn true → Geräte werden beim Start automatisch erkannt
  auto_discover = true,

  -- Wenn true → erkennt neue/entfernte Geräte automatisch im Betrieb
  auto_recalibrate = true,

  -- Wenn false → feste Gerätekonfiguration nur aus Cache
  dynamic_scan = true,


  ----------------------------------------------------------------
  -- 🔐  Netzwerksicherheit / Kommunikation
  ----------------------------------------------------------------

  -- Verbindungsschlüssel – MUSS mit Master übereinstimmen, wenn Auth aktiviert.
  auth_token = "changeme",

  -- Netz-ID (wird von Master vergeben, falls nil)
  network_id = nil,

  -- Kommunikationskanäle:
  channel_telem = 1001,     -- Telemetrie-Daten an Master
  channel_ctrl  = 1002,     -- Steuerbefehle vom Master
  channel_ping  = 1003,     -- Keepalive-/HELLO-Verkehr


  ----------------------------------------------------------------
  -- 🕒  Zeitsteuerung
  ----------------------------------------------------------------

  telem_interval = 1.0,     -- Sekundenintervall für Statusübertragung
  hello_interval = 5.0,     -- Sekundenintervall für Master-Kontakt
  rescan_interval = 30.0,   -- Automatischer Re-Scan bei aktivem Betrieb
  watchdog_timeout = 60.0,  -- Keine Antwort → Master als „offline“ markieren


  ----------------------------------------------------------------
  -- 🖥️  Anzeigeeinstellungen
  ----------------------------------------------------------------

  ui_scale = 1,             -- 1..5 (wird automatisch angepasst)
  ui_theme = "dark",        -- "dark" | "light"
  show_power_bar = true,    -- Zeige Balkenanzeige für Energie
  show_text_info = true,    -- Zeige Textwerte (Temperatur, Steam etc.)
  show_alerts = true,       -- Zeige Warnungen auf Monitor

  -- Farben (Monitor muss "color" unterstützen)
  color_ok       = colors.lime,
  color_warning  = colors.yellow,
  color_critical = colors.red,
  color_label    = colors.lightBlue,
  color_value    = colors.white,


  ----------------------------------------------------------------
  -- 🧮  Kalibrierungs- & Sicherheitslogik
  ----------------------------------------------------------------

  -- Automatische Erkennung der optimalen Drehzahl (Turbinen)
  auto_rpm_tuning = true,

  -- Ziel-Drehzahl für Turbinen (wird nur bei auto_rpm_tuning=false verwendet)
  target_rpm = 1800,

  -- Maximale Reaktorleistung (als Sicherheitslimit)
  reactor_max_output = 1000000, -- RF/t

  -- Warnlevel (Prozent)
  warn_fuel_low = 15,      -- bei 15% Brennstoff
  warn_temp_high = 90,     -- bei 90% Max-Temperatur

  -- Not-Aus bei kritischer Bedingung
  emergency_shutdown = true,


  ----------------------------------------------------------------
  -- 🧾  Systeminformationen
  ----------------------------------------------------------------

  -- Version für automatische Updates
  version = "v2025-10-16-01",

  -- Sprache / Lokalisierung
  language = "de",

  -- Metadaten zur Node-Position / Zuordnung
  site_name = "MainFacility",
  floor = 0,
  rack_id = "A1",

  ----------------------------------------------------------------
  -- 🧰  Debug & Logging
  ----------------------------------------------------------------

  enable_debug = true,
  log_file = "/xreactor/logs/node_debug.log",
  log_level = "INFO", -- INFO | WARN | ERROR | DEBUG
}

return CFG
