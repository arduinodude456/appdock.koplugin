# BWR2: komprimiertes, seekbares E-Ink-Videoformat

BWR2 speichert dieselben bereits geditherten 1-Bit-Bildpunkte wie BWR1, reduziert aber die Dateigröße mit Keyframes und zeitlichen Deltas. Der Player muss höchstens eine Keyframe-Gruppe dekodieren, bevor er einen beliebigen Frame anzeigen kann.

## Kompatibilität

- AppDock liest weiterhin bestehende **BWR1**-Dateien.
- Neue YouTube-Konvertierungen werden als **BWR2** gespeichert; die Dateiendung bleibt `.bwr`.
- Andere Player, die ausschließlich BWR1 implementieren, können BWR2-Dateien nicht abspielen.
- BWR2 verwendet System-zlib nur, wenn die Bibliothek verfügbar ist. Ohne zlib schreibt der Encoder weiterhin gültige BWR2-Dateien mit den eingebauten Raw-, Wiederholungs- und Null-Lauf-Codecs.

## Header: 32 Byte, Little Endian

| Offset | Größe | Bedeutung |
|---:|---:|---|
| 0 | 4 | ASCII `BWR2` |
| 4 | 1 | Version `2` |
| 5 | 1 | Pixelmodus `1`: 1 Bit pro Pixel, MSB zuerst, Bit `1` bedeutet Weiß |
| 6 | 2 | Breite in Pixeln; muss durch 8 teilbar sein |
| 8 | 2 | Höhe in Pixeln |
| 10 | 2 | Bildrate × 100 |
| 12 | 4 | Framezahl |
| 16 | 4 | Größe eines entpackten Frames in Byte: `width × height / 8` |
| 20 | 2 | Keyframe-Intervall; AppDock-Standard: 12 Frames |
| 22 | 2 | Reservierte Flags, derzeit 0 |
| 24 | 4 | Absoluter Dateioffset zum Keyframe-Index |
| 28 | 4 | Reserviert, derzeit 0 |

BWR2 verwendet dieselbe 32-Byte-Basis und dieselbe Frame-Geometrie wie BWR1. Im Gegensatz zu BWR1 folgt auf den Header aber kein fester Block gleich großer Frames.

## Frame-Pakete

Frames stehen in zeitlicher Reihenfolge. Jedes Paket beginnt mit einer 4-Byte-Länge (Little Endian), die das folgende 1-Byte-Codec-Feld **mitzählt**. Danach folgen die Codec-Nutzdaten.

| Codec | Bedeutung |
|---:|---|
| 0 | Unkomprimierter absoluter Frame; Nutzdaten haben exakt `frame_bytes` Byte. Darf auch als Fallback innerhalb einer Keyframe-Gruppe vorkommen. |
| 1 | zlib-DEFLATE-Keyframe; dekomprimiert auf exakt `frame_bytes` Byte. Nur an Keyframe-Positionen zulässig. |
| 2 | zlib-DEFLATE-XOR-Delta zum vorherigen Frame; dekomprimiertes Delta wird byteweise mit dem vorherigen Frame XOR-verknüpft. |
| 3 | Null-Lauf-kodiertes XOR-Delta. Steuerbytes 0–127 bedeuten 1–128 Nullbytes; Steuerbytes 128–255 bedeuten 1–128 folgende Literalbytes. |
| 4 | Identischer Frame wie unmittelbar zuvor; keine Nutzdaten. |

Codec 2 oder 3 darf keine Keyframe-Gruppe beginnen. Der Writer legt standardmäßig für Frame 0 und anschließend alle 12 Frames einen Keyframe an. Der Index am Dateiende enthält je einen absoluten 32-Bit-Offset pro Keyframe in derselben Reihenfolge.

Für zufälligen Zugriff springt der Reader zum Indexeintrag der Gruppe und dekodiert bis zum Ziel-Frame. Bei Intervall 12 sind somit höchstens 11 Delta-Schritte nötig. Die Größe jedes Pakets und der Indexzugriff werden vor der Dekodierung validiert.

## Kompression und Wiedergabe

- Keyframes werden mit zlib-Level 1 gespeichert, falls das Ergebnis kleiner als der rohe Frame ist; andernfalls bleibt der Keyframe roh.
- Deltas wählen zwischen DEFLATE, Null-Lauf-Kodierung, Wiederholungsmarker und rohem absolutem Fallback.
- Die Kompression ändert weder die 1-Bit-Bilddaten noch das Bayer-Dithering. Das KOReader-Playback expandiert weiterhin nur den benötigten gepackten Frame in den Bildpuffer.
- Auf einem synthetischen bewegten 600×800-`testsrc2`-Clip mit 36 Frames betrug die BWR2-Datei in der Sandbox 150.044 Byte gegenüber 2.160.000 Byte rohen Frame-Daten. Das ist ein Testszenario, keine zugesicherte Kompressionsrate für beliebige Videos.
