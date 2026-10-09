# AppDock 7.8.30

## Schnellere Videokonvertierung

- FFmpeg übernimmt standardmäßig die 1-Bit-Umwandlung (`monow`) statt jeden Grauwert-Frame pixelweise durch den Lua-Bayer-Encoder zu schicken. Bestehende Installationen werden einmalig auf diesen schnelleren Modus umgestellt. Die Bayer-Matrix bleibt unter **YouTube → Tools → Dithering** auswählbar.
- Die BWR2-Frameverarbeitung nutzt größere CPU-Batches (bis zu 12 Frames bzw. 160 ms pro Tick) mit kürzeren Leerlaufzeiten zwischen UI-Ticks.
- Der BWR2-Writer bildet XOR-Deltas mit 32-Bit-Operationen, vermeidet eine zusätzliche Kopie zum zlib-Encoder und überspringt bei bereits kompakter DEFLATE-Ausgabe den zweiten, Lua-basierten RLE-Scan.

Im Sandbox-Benchmark mit 600×800-Testframes stieg die gemessene Rate von etwa 1.003 Frames/s (Bayer) auf 3.380 Frames/s (FFmpeg), ungefähr **3,4×** in diesem synthetischen Test. Das ist keine Messung des KOReader-Geräts; die reale Beschleunigung hängt von CPU, Auflösung, Quellvideo und Speicherkarte ab.
