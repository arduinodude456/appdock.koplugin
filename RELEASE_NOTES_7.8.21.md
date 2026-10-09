# AppDock 7.8.21

## ARMv7-YouTube-Setup auf älteren Kobos

Der bisherige Download war erfolgreich; erst der Start von yt-dlp schlug fehl. Die aktuelle ARMv7-Standalone-Datei benötigt neuere glibc-Symbole. Der nachfolgende Python-Fallback aus 7.8.20 brauchte seinerseits mindestens glibc 2.17 und konnte deshalb auf manchen Geräten ebenfalls nicht starten.

Für ARMv7-Geräte mit glibc unter 2.17, ARMv7/musl und ARMv7-Geräte, deren libc-Version nicht festgestellt werden kann, verwendet AppDock nun weiterhin die offizielle yt-dlp-Python-Zipapp, startet sie aber mit einer eigenen Alpine-Python-3.12.15-/musl-Laufzeit. Diese ist in einem etwa 14 MB großen Runtime-Asset enthalten und wird nach SHA-256-Prüfung ausschließlich unter `appdock/tools/python-runtime/` installiert. Die Laufzeit bringt ihre Bibliotheken und CA-Zertifikate mit. AppDock ersetzt oder verändert keine KOReader-Systembibliotheken.

Der ARMv7-Fallback für glibc 2.17–2.30 bleibt unverändert bei portable-python CPython 3.13.9. Für neuere glibc-Systeme wird weiterhin das yt-dlp-Standalone-ZIP verwendet. FFmpeg bleibt das statisch gelinkte ARMHF-Build.

## Überprüfung

Die Runtime wurde mit ARM-QEMU gestartet. Dabei liefen `yt-dlp --version` (2026.08.19) und eine echte YouTube-Suche mit AppDocks `ytsearch8`-Aufruf; die Suche lieferte acht Videoergebnisse. Das statische ARMHF-FFmpeg 7.0.2 startete ebenfalls mit einer glibc-2.13-Testumgebung. Lua-Regressionstests prüfen die Plattformerkennung, den Runtime-Download, die feste SHA-256-Prüfung, das Entpacken, den Wrapper und die Shell-Syntax.

QEMU ist kein realer Kobo-Test. Bitte nach dem Update auf dem Libra Colour die YouTube-App erneut öffnen. Falls die Einrichtung noch scheitert, zeigt die Live-Shellausgabe jetzt den neuen Fehler vollständig an.

## Runtime-Provenienz

Die Runtime basiert auf den ARMHF-Paketen aus Alpine Linux v3.23, darunter [Python 3.12](https://pkgs.alpinelinux.org/package/v3.23/main/armhf/python3), [musl](https://pkgs.alpinelinux.org/package/v3.23/main/armhf/musl) und das [CA-Zertifikatsbundle](https://pkgs.alpinelinux.org/package/v3.23/main/armhf/ca-certificates-bundle). Die Runtime enthält `THIRD_PARTY_NOTICES.md`, Lizenztexte und CPythons Lizenzdatei.

Asset: `appdock-youtube-armhf-musl-python-3.12.15.tar.gz`  
SHA-256: `8f47867ba2349dff0936c0e4c24bdda71f97b1494c7703c972d7a5a2744620b5`
