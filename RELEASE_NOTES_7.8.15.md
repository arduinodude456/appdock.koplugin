# AppDock 7.8.15

## YouTube: yt-dlp-Ersteinrichtung auf eReadern

- Der Setup-Status unterscheidet jetzt explizit den Download des offiziellen SHA-256-Manifests, die Berechnung des Hashes, das Entpacken und den abschließenden Kompatibilitätstest. Das hilft einzuordnen, wenn die SHA-256-Berechnung einer rund 39-MB-Datei auf langsamer Reader-Hardware einige Zeit benötigt.
- Korrigiert die ARMv7-Installation: Das offizielle `yt-dlp_linux_armv7l.zip` enthält ein Executable **und** einen `_internal/`-Runtime-Ordner. AppDock entpackt das vollständige ZIP, testet das Executable in seiner Runtime-Umgebung und installiert einen kleinen Launcher, der die relative Runtime-Struktur erhält. Zuvor wurden alle ZIP-Dateien mit `unzip -p` zu einer einzigen Datei zusammengefügt, sodass ARMv7-yt-dlp nach erfolgreicher Prüfsumme nicht startfähig war.
- Die offizielle Prüfsumme bleibt verpflichtend. Der aktuell veröffentlichte Upstream-ARMv7-Download (38.661.544 Byte) wurde mit seinem `SHA2-256SUMS`-Eintrag abgeglichen; beide Hashes stimmen überein.

Der YouTube-Regressionsfall prüft die getrennten Setup-Phasen, die Erzeugung des ARMv7-Entpack-/Launcher-Skripts und dessen POSIX-Shellsyntax. Die bereits in **7.8.14** eingeführte Korrektur des asynchronen `hostIsActive`-Callbacks bleibt enthalten.
