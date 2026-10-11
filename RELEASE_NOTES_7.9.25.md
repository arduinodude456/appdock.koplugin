# AppDock 7.9.25

## Draw: korrekter KOReader-Druckkanal

Die Druckerkennung verwendet jetzt den von KOReader für das Gerät konfigurierten `pressure_event`-Code. Für aktuelle Kobo-Modelle wie Elipsa, Sage, Libra 2, Elipsa 2E und Libra Colour ist das `ABS_MT_PRESSURE` (Linux-Code 58).

Der zuvor fest angenommene Code 24 (`ABS_PRESSURE`) wird nicht mehr verwendet, wenn KOReader einen gerätespezifischen Druckkanal gesetzt hat. Nur ältere Geräte ohne Konfiguration verwenden den Legacy-Fallback.

Die Druckstärke wird weiterhin aus dem Rohwert normalisiert und pro Stylus-Sample an Draw weitergegeben.
