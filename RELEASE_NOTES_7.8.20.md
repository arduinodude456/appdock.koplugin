# AppDock 7.8.20

## YouTube-Setup auf älteren ARMv7-Systemen

Die Fehlermeldung auf dem Kobo Libra Colour zeigte, dass yt-dlp selbst heruntergeladen und entpackt wurde, seine gebündelte Python-Bibliothek aber `GLIBC_2.29` voraussetzte, die das Gerät nicht bereitstellt. Außerdem konnte AppDock die lokale glibc-Version nicht zuverlässig ermitteln.

AppDock liest die Version nun sowohl aus `getconf GNU_LIBC_VERSION` als auch aus GNU-`ldd --version`. Für ARMv7 mit glibc 2.17–2.30 installiert es statt der inkompatiblen PyInstaller-Datei die aktuelle offizielle yt-dlp-Python-Zipapp zusammen mit einer portablen CPython-3.13.9-Laufzeit. Das Runtime-ZIP ist rund 28 MB groß und belegt entpackt etwa 82 MB. Der Python-Download wird mit einem festgelegten SHA-256-Wert geprüft, und der fertige Wrapper muss `yt-dlp --version` erfolgreich ausführen, bevor er installiert wird. Systeme mit glibc unter 2.17 oder nicht ermittelbarer glibc werden vor dem Download verständlich abgewiesen.

Die Python-Laufzeit stammt aus [bjia56/portable-python](https://github.com/bjia56/portable-python) und wird samt enthaltenen Lizenzdateien installiert. Die ARM-Python-Binärdateien benötigen laut ELF-Symbolprüfung höchstens glibc 2.17. Ein ARM-QEMU-Test mit glibc 2.28 bestätigte den Start von Python, `yt-dlp --version` und eine YouTube-Suche.
