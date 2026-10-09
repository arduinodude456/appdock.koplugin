# YouTube-DApp: automatische Werkzeugdownloads

AppDock lädt fehlende Werkzeuge direkt von den jeweiligen Anbietern nach und prüft sie vor der Installation. Es werden keine Binärdateien in diesem Repository gebündelt. Die App legt sie im KOReader-Datenordner unter `appdock/tools/` ab und verwendet dort die Namen `yt-dlp` und `ffmpeg`.

## Quellen und unterstützte Assets

| Werkzeug | Upstream | Asset-Auswahl | Integritätsprüfung |
|---|---|---|---|
| yt-dlp | [GitHub Releases](https://github.com/yt-dlp/yt-dlp/releases/latest) und [Release-Dateiübersicht](https://github.com/yt-dlp/yt-dlp#release-files) | `yt-dlp_linux` (x86_64/glibc), `yt-dlp_musllinux` (x86_64/musl), `yt-dlp_linux_aarch64` (aarch64/glibc), `yt-dlp_musllinux_aarch64` (aarch64/musl), `yt-dlp_linux_armv7l.zip` (ARMv7/glibc) | Offizielle `SHA2-256SUMS`-Datei des Releases |
| ffmpeg | [John Van Sickle – Static Builds](https://johnvansickle.com/ffmpeg/) und [Installations-/FAQ-Hinweise](https://www.johnvansickle.com/ffmpeg/faq/) | `ffmpeg-release-{amd64,arm64,armhf}-static.tar.xz` | Anbieter-`.md5`-Datei zur Erkennung beschädigter Downloads; anschließend wird die Binärdatei tatsächlich gestartet |

Die yt-dlp-Releaseübersicht nennt für die Linux-x86_64- und aarch64-Builds glibc 2.17+ und für die ARMv7-Datei glibc 2.31+. Die offiziellen musl-Varianten benötigen musl 1.2+. Der Installer verweigert bekannte inkompatible Targets: Android/Bionic, ARMv6, ARMv7/musl und ARMv7 mit glibc älter als 2.31. Unbekannte Architekturen werden nicht geraten. In diesen Fällen bleibt die manuelle Pfadeingabe verfügbar.

## Ablauf

Beim Öffnen der YouTube-DApp werden zuerst vorhandene oder manuell gesetzte Pfade erkannt. Nur fehlende Programme werden beschafft. Die Downloads laufen außerhalb des UI-Threads; Archive und Binärdateien bleiben zunächst in einem temporären Ordner, werden verifiziert und müssen ihren `--version`-Starttest bestehen, bevor sie in `appdock/tools/` verschoben werden. Bei Fehlern gibt es eine verständliche Setup-Ansicht mit **Retry setup** und **Tool settings**.

Die Netzwerkverbindung muss bereits verfügbar sein. Der Installer verwendet `curl` oder `wget`; für ARMv7 benötigt er außerdem `unzip` (oder `busybox unzip`), und zum ffmpeg-Archiv `tar` mit xz-Unterstützung. Das ARMv7-yt-dlp-ZIP enthält neben dem Executable einen `_internal/`-Runtime-Ordner; beide werden gemeinsam in `appdock/tools/yt-dlp-runtime/` installiert und über `appdock/tools/yt-dlp` gestartet. Die Setup-Ansicht unterscheidet den Download des Prüfsummenmanifests, die SHA-256-Berechnung, das Entpacken und den Kompatibilitätstest; ein `yt-dlp --version`-Test, der länger als 120 Sekunden läuft, wird mit einer konkreten Timeout-Meldung abgebrochen. Die Hash-Berechnung einer rund 39-MB-Datei kann auf einem langsamen eReader sichtbar dauern. Diese Helfer sind auf gängigen Linux-eReadern meist vorhanden; falls ein Geräteimage sie nicht bereitstellt, wird der Fehler angezeigt und die App überschreibt keine Systemdateien. Der ffmpeg-Anbieter veröffentlicht laut FAQ einen MD5-Sidecar; diese Prüfung erkennt Übertragungsfehler, ist aber kein kryptografischer Herkunftsnachweis. Die Downloads erfolgen ausschließlich über HTTPS zu den oben genannten Anbietern.
