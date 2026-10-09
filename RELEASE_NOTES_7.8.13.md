# AppDock 7.8.13

## Deutsch

### YouTube: automatische Werkzeugeinrichtung

Beim ersten Öffnen der YouTube-DApp sucht AppDock nach **yt-dlp** und **ffmpeg**. Fehlende Werkzeuge werden im Hintergrund bezogen, auf Prüfsummen geprüft und in `appdock/tools` im KOReader-Datenverzeichnis installiert. Sobald beide Werkzeuge laufen, wechselt AppDock zur Suche — die manuelle Pfadeingabe entfällt auf unterstützten Geräten.

- yt-dlp wird direkt aus dem offiziellen GitHub-Release geladen und anhand der mitgelieferten SHA-256-Summen geprüft.
- ffmpeg stammt aus einem passenden statischen Linux-Build von John Van Sickle; die bereitgestellte MD5-Summe erkennt beschädigte Downloads.
- Unterstützt werden x86_64, aarch64 (glibc und musl) sowie ARMv7 mit glibc 2.31 oder neuer. Android/Bionic, ARMv6, ARMv7/musl und unbekannte ABIs erhalten ausdrücklich keine inkompatiblen Linux-Binärdateien; die DApp zeigt die manuelle Konfigurationsansicht.
- Downloads und Installationen laufen im Hintergrund, verwenden temporäre Dateien und werden erst nach erfolgreichem Versions-/Starttest atomar eingesetzt. Bei Netz-, Speicher-, Prüfsummen- oder Laufzeitfehlern bietet die App **Retry setup** und **Tool settings**.
- Bereits vorhandene oder manuell konfigurierte Werkzeuge werden nicht ersetzt.

### Qualitätssicherung

- Lua-Syntax aller Plugin-Dateien geprüft.
- YouTube-Tests prüfen Architekturwahl, ARMv7-glibc-Untergrenze, Android-/musl-Ausschlüsse und die Prüfsummen-/Installationsschritte.
- Keyboard-, AppStore-, Browser-, BWR1-, DApp-, Ordering-, Setup-Assistant- und YouTube-Regressionstests erfolgreich.

## English

### YouTube: automatic first-run tool setup

On first opening the YouTube DApp, AppDock checks for **yt-dlp** and **ffmpeg**. Missing tools are downloaded in the background, checksum-checked and installed under `appdock/tools` in the KOReader data directory. Once both executables pass a run test, AppDock opens the search view—no manual path entry is needed on supported devices.

- yt-dlp is downloaded directly from the official GitHub release and verified against its published SHA-256 sums.
- ffmpeg comes from a matching static Linux build by John Van Sickle; its published MD5 checksum detects incomplete or corrupted downloads.
- Supported targets are x86_64, aarch64 (glibc and musl), and ARMv7 with glibc 2.31 or newer. Android/Bionic, ARMv6, ARMv7/musl and unknown ABIs are not given incompatible Linux executables; the DApp shows the manual configuration view instead.
- Downloads and installs run in the background using temporary files and are moved into place only after version/start checks succeed. Network, storage, checksum or runtime failures offer **Retry setup** and **Tool settings**.
- Existing or manually configured tools are not replaced.

### Quality assurance

- Lua syntax checked for all plugin files.
- YouTube tests cover architecture selection, the ARMv7 glibc minimum, Android/musl exclusions and checksum/install commands.
- Keyboard, AppStore, browser, BWR1, DApp, ordering, setup-assistant and YouTube regression tests pass.
