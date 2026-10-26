# AppDock 8.5.10 — Game-Installer-ZIP-Prüfung

Der separate `unzip -tq`-Vorabtest wurde entfernt. Auf dem Kobo schlug genau dieser Test fehl, obwohl der Installer anschließend die normale Extraktion hätte ausführen können. Der Game-Installer prüft das ZIP weiterhin vor dem Entpacken auf unsichere Pfade; maßgeblich für die Integrität ist jetzt der Exit-Status der tatsächlichen Extraktion, die ZIP-Daten und CRCs dabei ebenfalls überprüft.

Die kurze, stufenspezifische Fehlermeldung aus 8.5.9 bleibt erhalten, falls die eigentliche Extraktion nach diesem Fix weiterhin fehlschlägt.
