# AppDock 8.5.7 — Game-Installer-Fix

Der Game-Installer setzt nach dem Entpacken das erwartete Programm unter `<game>/bin/<game>` explizit auf ausführbar (`0755`). Damit starten Spiele auch dann, wenn das ZIP-Archiv – etwa durch Erstellung auf einem FAT-/Windows-Dateisystem – keine Unix-Ausführungsrechte enthält.

Der Installer prüft außerdem, ob die erwartete Binärdatei im Archiv vorhanden ist, und meldet einen verständlichen Fehler, wenn sie fehlt oder nicht ausführbar gemacht werden kann. Die ZIP-Dateien von Midless und Geometry Rush sind intakt; ihr bisher fehlendes Ausführungsbit war die Ursache dafür, dass die Spiele nach dem Installieren nicht starteten.
