# AppDock 7.8.22

## Kobo-Entpackfehler behoben

Auf dem Kobo konnte `tar` den v7.8.21-Runtime-Tarball laden, aber nicht entpacken: das Dateisystem verweigerte das Anlegen von `python-runtime/etc/ssl/cert.pem` als Symlink (`Operation not permitted`).

Das ARMHF-Runtime-Archiv enthält jetzt Kopien der verlinkten Bibliotheken und Zertifikate statt Symlinks. Der Installer lädt dieses neue Asset und prüft dessen neue SHA-256-Prüfsumme. Es ist rund 17 MB groß und belegt entpackt etwa 44 MB.

## Verifikation

Das veröffentlichungsfertige Archiv enthält keine Symlinks oder Hardlinks. Frisch entpackt starteten CPython/yt-dlp unter ARM-QEMU; yt-dlp meldete Version 2026.08.19 und die YouTube-Suche lieferte acht Treffer. Ein Test auf dem physischen Kobo steht noch aus.

**Für betroffene Geräte:** AppDock zuerst auf 7.8.22 aktualisieren, KOReader neu starten und dann in der YouTube-App **Retry setup** wählen.

Asset: `appdock-youtube-armhf-musl-python-3.12.15.tar.gz`  
SHA-256: `5348e11472e5ca6c07d7b0ec75a2f1df1d181be7eb52d9e3cafb43267b1f916c`
