# AppDock 7.9.9

## Draw-Absturz auf Farbgeräten behoben

Die Draw-Zeichenfläche vergleicht Farbwerte des BlitBuffers nicht mehr mit einem `nil`-Sentinel. Auf Farbgeräten sind diese Werte FFI-CData; ihr Vergleich konnte beim Start einen Fehler in der Gleichheits-Metamethode auslösen. Ein Regressionstest deckt diesen Farbpfad ab.

## Natürlichere YouTube-Farben durch Dithering

Die BRC2-Palettenzuordnung bewertet Kandidaten nun in einem farbempfindlichen YUV-Farbraum. So werden Mischfarben wie Gelb, Cyan und Magenta durch Dithering mit den passenden reinen Grundfarben dargestellt, statt überwiegend in Schwarzweiß oder mit unpassenden Farbtönen zu erscheinen. Die Ausgabe bleibt auf die fünf erlaubten Farben beschränkt.

## Kobo-MTK-Audiowiedergabe wiederhergestellt

Der MediaTek-GStreamer-Pfad verwendet wieder rohe PCM-Daten über `fdsrc`, wie im funktionierenden Release 7.8.51, statt vom optionalen `wavparse`-Plugin abzuhängen. Der tatsächliche WAV-Datenoffset wird auch bei zusätzlichen RIFF-Metadaten berücksichtigt; das PCM-Kanal-Layout ist explizit angegeben. Pause und Stopp steuern die zugehörige Prozessgruppe.

## Validierung

Alle 12 Lua-Regressionstests bestehen. Die Plugin-Module kompilieren mit LuaJIT; außerdem wurde die GStreamer-PCM-Pipeline mit einem Test-Sink und einer WAV-Datei mit zusätzlichem `LIST`-Chunk geprüft.
