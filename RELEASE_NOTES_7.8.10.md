# AppDock 7.8.10

## Deutsch

### Helligkeit und Bildschirmschoner

- Die Blättertasten ändern die Helligkeit jetzt in **10er-Schritten** statt in Einerschritten.
- Beim Start des animierten Bildschirmschoners wird die Frontlight-Helligkeit vollständig ausgeschaltet.
- Beim Beenden des Bildschirmschoners wird die vorherige Helligkeit automatisch wiederhergestellt.
- Die Wiederherstellung ist defensiv abgesichert und verändert das Verhalten auf Geräten ohne verfügbare Frontlight-Steuerung nicht.

### Qualitätssicherung

- Lua-Syntax aller Plugin-Dateien geprüft.
- Keyboard-, AppStore-, Browser-, DApp-, Ordering- und Setup-Assistant-Regressionstests erfolgreich ausgeführt.

## English

### Brightness and screensaver

- Page keys now change brightness in **10-step increments** instead of single steps.
- The frontlight is fully switched off when the animated screensaver starts.
- The previous brightness is restored automatically when the screensaver closes.
- Restoration is guarded defensively and does not change behavior on devices without frontlight control.

### Quality assurance

- Lua syntax checked for all plugin files.
- Keyboard, AppStore, Browser, DApp, ordering, and setup-assistant regression tests pass.
