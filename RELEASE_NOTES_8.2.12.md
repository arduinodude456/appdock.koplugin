# AppDock 8.2.12

## Stabilität und Crash-Schutz

Gespeicherte Einstellungsgruppen werden beim Laden typgeprüft und fehlende Standardwerte ergänzt. Fehlerhafte Homescreen-, DApp- oder Fremdplugin-Aufrufe werden an zentralen Grenzen abgefangen, sodass ein einzelnes fehlerhaftes Modul nicht den KOReader-Eventloop beendet. DApp-Panes erhalten bei Fehlern eine wiederherstellbare Fehleransicht; verspätete Lifecycle-Aufrufe werden abgefangen.

Der periodische DApp-Hintergrundlauf wird gegen Runtime-Ausnahmen geschützt und bleibt danach aktiv. Einzelne unvollständige Fremdplugin-Module werden übersprungen.

## TBS-Konto verständlicher erklärt

Der TBS-Kontoeintrag zeigt klarer, wofür das Konto verwendet wird. Die Offline-Hilfe erläutert in Deutsch und Englisch Kontozweck, synchronisierte bzw. lokale Daten, Datenschutz, Wiederherstellungscode und Gerätewechsel.

## WLAN-Migration robuster

Die WLAN-Migration validiert und begrenzt empfangene Daten und importierte Assets. Überdimensionierte Nachrichten und ungültige Zustände werden kontrolliert abgewiesen, statt den Importpfad zu destabilisieren.

## Weitere UI-Korrekturen

Der About-Bereich verwendet die zentrale aktuelle Version statt einer alten fest codierten Nummer. Die Hilfekapitel wurden nach dem neuen TBS-Abschnitt neu nummeriert.

## Prüfung

Alle Plugin-Lua-Dateien bestehen die Lua-Syntaxprüfung. 15 ausführbare Regressionstests für TBS, Dialoge, Recovery, Dateiverwaltung, E-Ink-UI, Themes und weitere Komponenten laufen erfolgreich. Einzelne DApp-Tests benötigen KOReader-Subprozess- bzw. Bluetooth-Hardwarefunktionen und sind in einer generischen Sandbox nur eingeschränkt ausführbar.
