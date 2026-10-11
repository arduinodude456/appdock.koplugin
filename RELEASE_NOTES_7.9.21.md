# AppDock 7.9.21

## Draw: Kobo-Stiftdruck, Radierer und Marker

Draw nutzt nun den Kobo-Rohereignispfad für Stylus-Eingaben. Stiftdruck wird aus dem Sensorwert normalisiert und auf die ausgewählte Pinselgröße angewendet. Die physische Radiererspitze löscht mit der weißen Zeichenfarbe; der Marker aktiviert die breitere Marker-Spitze.

Die Bildschirmrotation wird bei den Rohkoordinaten berücksichtigt. Der Stylus-Listener ist nur während einer aktiven Draw-Pane registriert und stellt beim Verlassen den ursprünglichen KOReader-Gesture-Handler wieder her. Normale Touch-Eingaben und KOReader-Gesten bleiben unverändert.

## Tests

Alle 14 AppDock-LuaJIT-Regressionstests laufen durch, einschließlich der neuen Draw-Stylus-Tests für Druck, Radierer, Marker, Rotation, Tracking-IDs und Listener-Lifecycle. LuaJIT-Syntaxprüfung aller Plugin-Dateien und `git diff --check` sind sauber.
