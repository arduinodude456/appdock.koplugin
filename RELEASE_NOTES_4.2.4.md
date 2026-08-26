# AppDock 4.2.4 — Stability

## Fundamentaler Splitscreen-Fix

Der Splitscreen-Mittelstreifen verwendet keine eigene Unterwidget-Geste mehr. Stattdessen empfängt der dauerhafte DApp-Host jede Pan- und Pan-Release-Geste über eine breite, absolute Touchzone um die aktuelle Trennposition. Die Steuerung ist damit unabhängig von der vorherigen Zugrichtung und bleibt bei Aufwärts- wie Abwärtsbewegungen am selben Host gebunden.

## Web Browser

Der Browser importiert die zentrale Theme-Hilfe jetzt explizit. Dadurch ist `Theme.fitLabel` beim Aufbau der Browser-Aktionsbuttons verfügbar und der Startcrash durch eine fehlende globale `Theme`-Referenz ist behoben.

## Validierung

Lua-5.1-Syntax, Root-/Paketspiegel, Browserstart und die DApp-Core-Regression wurden ausgeführt. Die Splitter-Regression prüft die breite Host-Touchzone, Bewegungen nach unten und oben, positionsloses Loslassen, Persistenz und den DApp-Lebenszyklus.
