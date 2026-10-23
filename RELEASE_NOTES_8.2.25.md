# AppDock 8.2.25 — Einheitlicher Plugin-Host und Shorts UX

## YouTube Shorts

Die Shorts-DApp erhält eine klarere, intuitivere Feed-Oberfläche mit direkten Aktionen für **Previous**, **Play/Pause**, **Next**, **Topics**, **Reload** und **Tools**. Video-, Metadaten- und Transportbereiche bleiben auch in schmalen AppDock-Panes innerhalb ihrer lokalen Grenzen.

Swipe-Navigation, Canvas-Offsets, Ladezustände und der Inline-Player wurden stabilisiert. Ein verspäteter Such- oder Prefetch-Abschluss kann keinen neuen Feed überschreiben und startet keine Wiedergabe in einer geschlossenen oder unsichtbaren Oberfläche. Fortschritts-Neuaufbauten behalten den laufenden Short; tatsächliches Verlassen beendet Suche und Player sauber.

## Einheitlicher Plugin-Host

Nicht-DApps werden jetzt immer in AppDock gehostet. Sie dürfen keine eigene native Oberfläche mehr neben AppDock öffnen. Plugin-Panes, Events, Dialoge, ConfirmBoxen, Eingaben, Menüs und Cleanup laufen über eine begrenzte AppDock-Bridge.

Kooperierende Plugins erhalten AppDocks Palette, Kontrastrollen, Metriken und lokale Layout-Geometrie. Lange Aktionslisten, dynamische Untermenüs sowie verzögerte Plugin-Callbacks bleiben innerhalb des aktiven AppDock-Hosts. Nicht sicher adaptierbare Spezialansichten werden nicht als eigenständige Oberfläche geöffnet, sondern als AppDock-Kompatibilitätshinweis dargestellt.

Plugin-Hosts bleiben vom Split-Screen und von Floating Windows ausgeschlossen.

## Prüfung

Die vollständige native UI-Regression wird mit `bash scripts/test_appdock_ui.sh` ausgeführt. Die Suite umfasst DApp-Host, Shorts/YouTube, YouTube Music, Dialoge, Setup, Theme-Kontrast, Gruppen, Manager, Tastatur und Textkompatibilität. Zusätzlich werden alle installierbaren Lua-Dateien auf Syntaxfehler geprüft.
