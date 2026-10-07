# AppDock 7.8.5

## Deutsch

### Blättertasten korrigiert
- Die Hardware-Tasten werden jetzt über KOReaders kanonische Gruppen `PgBack` und `PgFwd` erkannt; damit funktionieren sie auch auf Geräten, auf denen die längeren Aliasnamen nicht vorhanden sind.
- Kurzes Drücken der oberen bzw. unteren Blättertaste erhöht bzw. verringert weiterhin die Frontlight-Helligkeit und zeigt die seitliche Helligkeitsanzeige.
- Gedrückthalten wird jetzt über echte Key-Repeat-Ereignisse erkannt: Oben öffnet das Power-Menü, unten startet der animierte fröhliche eReader-Bildschirmschoner.
- Wiederholte Key-Repeat-Ereignisse lösen das jeweilige Menü nur einmal pro Haltevorgang aus.

### AppStore
- Der DApp-Uninstall-Bestätigungsdialog wird beim Deinstallieren korrekt geschlossen.

### Qualitätssicherung
- Lua-Syntaxprüfung für die geänderten Plugin-Dateien erfolgreich.
- AppStore- und DApp-Regressionstests erfolgreich.

## English

### Page keys fixed
- Hardware buttons now use KOReader’s canonical `PgBack` and `PgFwd` groups, so they work on devices where the longer aliases are unavailable.
- Short presses of the upper and lower page buttons still increase and decrease frontlight brightness and show the side brightness indicator.
- Long-press behavior now uses real key-repeat events: upper opens the power menu, lower starts the animated happy e-reader screensaver.
- Repeated key-repeat events trigger each menu only once per hold gesture.

### AppStore
- The DApp uninstall confirmation dialog now closes correctly when uninstalling.

### Quality assurance
- Lua syntax checks pass for the changed plugin files.
- AppStore and DApp regression tests pass.
