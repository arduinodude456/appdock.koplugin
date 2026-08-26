# AppDock 3.2.0

AppDock 3.2.0 ist ein fokussiertes Kernrelease vor der größeren Version 4. Es verbessert die DApp-Kopfzeile, korrigiert die lokale Speicheranalyse und ergänzt ein freiwilliges lokales Lockscreen-Profil. Die Änderungen bleiben auf KOReader und die AppDock-Installation beschränkt.

## Korrekturen

Die drei DApp-Fensteraktionen **Home**, **Open apps** und **Schließen** liegen nun gemeinsam etwas tiefer innerhalb der 52-Pixel-Kopfzeile. Größe und Touchfläche bleiben unverändert.

Die Speicheransicht bewahrt jetzt den von LuaFileSystem bereitgestellten Verzeichniszustand zusammen mit dem Iterator. Dadurch werden lesbare lokale Dateien und Ordner wieder in die Größe und die Speichersegmente einbezogen. Installierte DApps bleiben als eigener, nach Größe sortierter Abschnitt erhalten. Begrenzte Scan-Tiefe und Dateibudgets bestehen weiter, damit die Ansicht auf E-Ink-Geräten responsiv bleibt.

## Optionales Lockscreen-Profil

Unter **Settings → Other → AppDock lockscreen** kann ein optionaler Anzeigename sowie ein Profilbild festgelegt werden. Der Name wird lokal gekürzt und bereinigt. Das Bild muss eine vorhandene lokale PNG-, JPG-, JPEG-, GIF-, WEBP- oder SVG-Datei mit erlaubter Endung sein; ungültige oder nicht lesbare Pfade werden nicht gespeichert. Ein fehlendes Bild lässt den Lockscreen weiterhin normal funktionieren.

> Der Lockscreen schützt weiterhin nur den AppDock-Homescreen. Er ist **keine** Gerätesperre, Verschlüsselung oder Zugriffssicherung für KOReader, Nickel oder gespeicherte Dateien.

## Bluetooth auf Kobo Libra Colour

Bluetooth wird in AppDock ausschließlich angezeigt, wenn KOReader das Gerät als **Kobo Libra Colour** (`Kobo_monza`) erkennt. AppDock bringt weder einen Bluetooth-Treiber noch Shell- oder D-Bus-Steuerung mit. Stattdessen prüft es, ob eine kompatible Bluetooth-Erweiterung bereits in KOReader geladen ist, und öffnet ausschließlich deren bereitgestellte Menüaktionen.

| Situation | Verhalten von AppDock |
|---|---|
| Kein Kobo Libra Colour | Bluetooth erscheint nicht in den Einstellungen. |
| Kobo Libra Colour ohne kompatible Erweiterung | AppDock zeigt einen Setup-Hinweis; es schaltet Bluetooth nicht selbst. |
| Kobo Libra Colour mit kompatibler Erweiterung | AppDock delegiert an das Menü der Erweiterung. |

Externe MTK-Bluetooth-Lösungen können experimentell sein. Nach einer Rückkehr zu Nickel kann ein Neustart des Geräts erforderlich sein. Diese Einschränkung wird in der Bluetooth-Einstellung angezeigt.

## Prüfung

Die 3.2.0-Regressionen decken die nichtleere lokale Speichersegmentierung, die gemeinsame Kopfzeilenposition der drei DApp-Aktionen, Profilnamen sowie vorhandene und fehlende lokale Profilbilder ab. Zusätzlich prüfen sie, dass Bluetooth auf nicht unterstützter Hardware verborgen bleibt und auf Kobo Libra Colour ausschließlich an ein vorhandenes Plugin-Menü delegiert wird.
