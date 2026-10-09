# AppDock 7.8.25

## YouTube-Player lädt das ausgewählte Video korrekt

Beim Starten der Wiedergabe lud AppDock die BWR1-Datei zunächst erfolgreich. Der anschließende Neuaufbau der DApp-Ansicht deaktivierte jedoch das bisherige Bibliothekspane, dessen Aufräumcode den gerade geladenen Player wieder stoppte. Deshalb zeigte der Player „No BWR1 file is loaded“ und sein Play-Knopf „No video is loaded“.

Die Bibliotheksansicht schließt den Player jetzt nicht mehr, wenn der Wechsel gerade in die Wiedergabe führt. Beim Verlassen der Player-Ansicht wird die Wiedergabe weiterhin ordnungsgemäß beendet.

## Verifikation

Die YouTube-Regression simuliert jetzt ausdrücklich die Deaktivierung der alten Bibliotheksansicht nach dem Laden eines gültigen BWR1-Videos. Der Player muss danach weiterhin einen geladenen Engine-Zustand besitzen. Die vollständige Regressionstestsuite und die Lua-Syntaxprüfung aller Plugin-Dateien liefen erfolgreich.
