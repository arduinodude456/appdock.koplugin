# AppDock 9.13.0

## DockAI-Korrekturen und Chat-Verwaltung
- Chatverläufe werden als mehrere getrennte Unterhaltungen gespeichert; bestehende Einzelverläufe werden beim ersten Laden übernommen.
- DockAI ergänzt gespeicherte Erinnerungen zum Nutzer und beschränkt den an das Modell gesendeten Gesprächskontext auf die letzten fünf verwendbaren Nachrichten.
- Die Nutzungsdaten des dchat-Proxys werden zwischengespeichert, sodass UI-Neuaufbauten nicht wiederholt langsame Netzwerkaufrufe auslösen.
- Fehler beim Abrufen der Nutzungsdaten werden abgefangen und mit einer kurzen Wiederholungsfrist versehen.

Der Release enthält dieselben 97 Plugin-Dateien wie 9.12.0. Daher ist keine Änderung an DockUpdates Dateiliste oder Versionsschranken nötig.
