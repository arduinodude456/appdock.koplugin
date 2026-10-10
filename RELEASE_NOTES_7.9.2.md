# AppDock 7.9.2 — Draw-Zeichenfläche korrigiert

## Fehlerkorrektur

- Die Draw-Werkzeuge und das Zeichen-Canvas werden jetzt in einem KOReader-`OverlapGroup` anhand ihrer vorgesehenen Offsets angeordnet. Das behebt die fehlerhafte Darstellung beim Öffnen der Mal-App, bei der Inhalte am oberen linken Bildschirmrand überlagert werden konnten.
- Die Zeichenfläche wird im Regressionstest nun über die vollständige Pane-Geometrie aufgebaut; der Test prüft die tatsächliche Toolbar-/Canvas-Positionierung und den weißen Start-Hintergrund.

## Prüfung

Alle 11 Lua-Regressionsdateien liefen erfolgreich. Sämtliche AppDock-Lua-Quelldateien ließen sich mit LuaJIT kompilieren; `git diff --check` meldete keine Formatfehler.
