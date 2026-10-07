# AppDock 7.8.4

## Deutsch

### Files im Google-Files-Stil
- Files erhält einen zweispaltigen Google-Files-inspirierten Startbildschirm mit Suche, zuletzt verwendeten Dateien, Kategorien und Speicherbereichen.
- Beim ersten Start werden unter `/mnt/onboard` die Ordner `Downloads`, `Documents`, `Images`, `Videos` und `Audio` angelegt, sofern sie fehlen.
- **Internal storage** öffnet direkt `/mnt/onboard`.
- **Sort my files** zeigt passende Dateien virtuell nach Kategorien an, ohne Dateien zu verschieben oder zu kopieren.
- Gedrückthalten einer Datei oder eines Ordners öffnet Aktionen für **Umbenennen**, **Open with ...**, **Löschen**, **Verschieben** und **Kopieren**.
- Suche, Umbenennen und die Speicheraktionen verwenden die AppDock-eigene Tastatur bzw. sichere Pfadprüfungen.

### Hardware-Tasten und Bildschirmschoner
- Kurzes Drücken der oberen bzw. unteren Blättertaste erhöht bzw. verringert die Frontlight-Helligkeit.
- Während der Änderung erscheint seitlich eine kompakte Helligkeitsanzeige mit Balken und Prozentwert.
- Gedrückthalten der oberen Blättertaste öffnet ein Power-Menü mit **KOReader neustarten**, **Ausschalten** und **Gerät neustarten**.
- Gedrückthalten der unteren Blättertaste aktiviert einen animierten Bildschirmschoner mit einem fröhlichen eReader.
- Die Bildschirmschoner-Animation besteht aus vier kontrastreichen Schwarzweiß-Frames und kann per Tippen oder Zurück-Taste beendet werden.

### Qualitätssicherung
- Lua-Syntax aller Plugin-Dateien geprüft.
- Keyboard-, AppStore-, Browser-, DApp-, Ordering- und Setup-Assistant-Regressionstests erfolgreich ausgeführt.
- Tests prüfen die neue AppDock-Tastatur, Long-Press-Aktionen, Storage-Sortierung, Seiten-Tasten-Bindings und Bildschirmschoner-Struktur.

## English

### Google Files-inspired Files app
- Files now has a two-column Google Files-inspired dashboard with search, recent files, categories, and storage areas.
- On first use, `Downloads`, `Documents`, `Images`, `Videos`, and `Audio` are created under `/mnt/onboard` when missing.
- **Internal storage** opens `/mnt/onboard` directly.
- **Sort my files** presents matching files virtually by category without moving or copying them.
- Holding a file or folder opens actions for **Rename**, **Open with ...**, **Delete**, **Move**, and **Copy**.
- Search, rename, and storage actions use the AppDock keyboard and bounded storage paths.

### Hardware keys and screensaver
- A short press of the upper or lower page key increases or decreases frontlight brightness.
- A compact side indicator shows a brightness bar and percentage while adjusting brightness.
- Holding the upper page key opens a power menu with **Restart KOReader**, **Power off**, and **Restart device**.
- Holding the lower page key activates an animated screensaver featuring a happy e-reader.
- The screensaver uses four high-contrast black-and-white frames and can be dismissed by tapping or pressing Back.

### Quality assurance
- Lua syntax checked for all plugin files.
- Keyboard, AppStore, Browser, DApp, ordering, and setup-assistant regression tests pass.
- Tests cover the AppDock keyboard, long-press actions, non-destructive storage sorting, page-key bindings, and screensaver structure.
