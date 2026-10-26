# AppDock 8.5.8 — Game-Paketinstallation auf KOReader-Geräten

Der Game-Installer unterstützt jetzt sowohl Info-ZIP als auch BusyBox `unzip`. Für die sichere Archivprüfung wird die portable Listenoption `-lq` statt der Info-ZIP-spezifischen Option `-Z1` verwendet; der Installer prüft außerdem, dass tatsächlich ZIP-Einträge gelesen wurden.

Nach dem Entpacken setzt AppDock den erwarteten Launcher unter `<game>/bin/<game>` auf ausführbar (`0755`). Damit werden beide Hürden abgedeckt: Archive ohne Unix-Ausführungsbits und Geräte, die nur BusyBox statt eines separaten `unzip` bereitstellen.
