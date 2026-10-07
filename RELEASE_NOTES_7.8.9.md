# AppDock 7.8.9

## Deutsch

### Bildschirmschoner speicherschonend gemacht

Die Bildschirmschoner-Frames waren komprimiert jeweils ungefähr 1,6 MB groß, benötigten beim Dekodieren jedoch etwa 13,5 MB Speicher pro Bild. Beim Animieren mehrerer Frames konnte KOReader deshalb mit `not enough storage` abbrechen.

Die vier Frames wurden auf 816 × 1088 Pixel und 8-Bit-Graustufen optimiert. Der dekodierte Speicherbedarf sinkt dadurch auf unter 1 MB pro Frame. Zusätzlich werden animierte Frames nicht mehr im globalen `ImageWidget`-Cache gesammelt, und sie werden direkt in der benötigten Zielgröße geladen.

### Qualitätssicherung

- Lua-Syntax aller Plugin-Dateien geprüft.
- Keyboard-, AppStore-, Browser-, DApp-, Ordering- und Setup-Assistant-Regressionstests erfolgreich ausgeführt.
- Screensaver-Frames von insgesamt etwa 6,5 MB auf unter 1 MB komprimierte Asset-Größe reduziert.

## English

### Screensaver memory usage reduced

The screensaver frames were only about 1.6 MB each when compressed, but required approximately 13.5 MB of memory per image when decoded. Animating multiple frames could therefore make KOReader fail with `not enough storage`.

All four frames are now optimized to 816 × 1088 pixels and 8-bit grayscale. Decoded memory usage is reduced to under 1 MB per frame. Animated frames are also excluded from the global `ImageWidget` cache and loaded directly at the required target size.

### Quality assurance

- Lua syntax checked for all plugin files.
- Keyboard, AppStore, Browser, DApp, ordering, and setup-assistant regression tests pass.
- Screensaver frames reduced from approximately 6.5 MB to under 1 MB of compressed assets in total.
