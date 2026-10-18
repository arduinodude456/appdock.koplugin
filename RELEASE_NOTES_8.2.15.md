# AppDock 8.2.15 — Store-App-Restore ohne Fehlerprüfung

## Änderung

Beim Wiederherstellen installierter Store-DApps und Store-Widgets wird `inspectStoreDApp` beziehungsweise `inspectStoreWidget` nicht mehr aufgerufen. Die Datei wird direkt mit `dofile` ausgeführt. Es gibt dort weder Schema-Prüfung noch `pcall`-Fehlerabfang. Entsprechend der Anforderung eines Anwenders wird ein Syntax-/Laufzeitfehler, eine falsche Definition oder ein fehlender Rückgabewert **nicht mehr einzeln abgefangen** und kann den ganzen AppDock-DApp-Manager beim Start abbrechen. Die Prüfung bleibt nur für neu installierte/aktualisierte Store-Einträge bestehen.

Diese Änderung löscht keine AppDock-Einstellungen oder App-Registrierungen. Sie kann jedoch fehlerhafte Store-Dateien nun ungefiltert ausführen. Nur mit den bekannten Store-Dateien und Testfixtures verifizieren; nicht empfohlen für Installationen mit unbekannten/geänderten Store-Apps.

## Prüfung

Neue Regressionen beweisen, dass die Restore-Pfade die DApp- und Widget-Inspektoren umgehen. Weitere Regressionen verifizieren die normale Prüfung beim erstmaligen Installieren/Updaten.
