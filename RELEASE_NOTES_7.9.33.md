# AppDock 7.9.33

## Bluetooth und Lizenzbereinigung

- Der zuvor übernommene Bluetooth-Code aus `audiobook.koplugin` wurde vollständig entfernt.
- AppDock verwendet jetzt eine eigene kleine Bluetooth-Steuerung über die standardisierte `bluetoothctl`-Schnittstelle.
- Die Einstellungen sind nicht mehr auf den Kobo Libra Colour beschränkt. Sie zeigen eine verständliche Meldung, wenn `bluetoothctl` auf dem Gerät nicht vorhanden ist.
- AGPL-Lizenzdateien und Audiobook-Herkunftshinweise wurden aus dem Plugin entfernt.

## Weitere Änderungen aus 7.9.32

- DuckDuckGo-Fallback-Suche.
- Mehrseitiger Update-Dialog aus `features.adf`.
- Korrekte Store-Theme-Hintergrundbilder.
- Verbesserte Theme-Kontraste und Lautstärkeeinstellungen.

## Hinweis

Die Bluetooth-Steuerung benötigt eine vom Gerät bereitgestellte Bluetooth-Stack-Implementierung mit `bluetoothctl`. AppDock installiert keine Firmware, keinen Treiber und keinen Bluetooth-Stack.
