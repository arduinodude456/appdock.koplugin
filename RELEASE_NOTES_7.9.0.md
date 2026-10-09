# AppDock 7.9.0

## Deutsch

### Neue DApp: YouTube und E-Ink-Video

- Die neue System-DApp **YouTube** sucht, lädt und konvertiert Videos in ein Format, das ein monochromer Reader flüssig darstellen kann.
- AppDock spricht nie selbst mit YouTube. Es steuert **yt-dlp** zum Auflösen und Herunterladen und **ffmpeg** zum Dekodieren und für die Tonspur. Beide Programme bleiben optional und werden nicht mitgeliefert.
- Drei Eingabewege: **Search YouTube**, **Paste a video link** (Video-, Shorts-, Live- und Embed-Links sowie reine Video-IDs) und **Convert a local video file**.
- Unter der Suche stellen drei Felder Auflösung, Bildrate und Maximallänge ein. Die Ansicht **Tools** verwaltet zusätzlich die Programm-Pfade, den Ausgabeordner, die maximale Quellqualität und die Dither-Methode.
- Die DApp erkennt yt-dlp und ffmpeg über `command -v` und über den Ordner `appdock/tools` im KOReader-Datenverzeichnis. **Detect tools again** prüft erneut.

### BWR1 und Kompatibilität mit videoplayer.koplugin

- AppDock schreibt das Containerformat **BWR1** (32-Byte-Kopf, 1 Bit pro Pixel, MSB zuerst, 1 = Weiß). Das Layout ist byte-kompatibel zu den Dateien des Konverters `tools/make.py` aus dem Release **„Snake“** von `videoplayer.koplugin`.
- Die Graustufen werden mit derselben geordneten 8×8-Matrix gedithert wie in `make.py`. Ein Test vergleicht die Ausgabe Byte für Byte mit einer unabhängigen Referenzimplementierung.
- Optional übernimmt ffmpeg die 1-Bit-Umwandlung (`format=monow`). AppDock prüft die Bitrichtung des jeweiligen ffmpeg-Builds einmalig zur Laufzeit und weicht bei unklarer Antwort auf die eigene Matrix aus.
- Neben der `.bwr`-Datei entsteht eine gleichnamige `.wav`-Tonspur. Fehlt sie, läuft die Wiedergabe stumm weiter.

### Wiedergabe auf E-Ink

- Der neue Player zeigt den Frame, der zur tatsächlich verstrichenen Zeit gehört: Die Tonspur ist die Master-Uhr, sodass Zeitgeber-Schwankungen keine Drift erzeugen.
- Frames sind bereits gedithert und werden nur noch zu Bytes expandiert und geblittet. Der Player fordert einen **schnellen** Refresh seines eigenen Rechtecks an, statt den ganzen Bildschirm neu zu zeichnen.
- Bedienung: **-5 s**, **Play/Pause**, **+5 s**, **Restart**. Die Bibliothek listet alle konvertierten Videos; ein Tipp startet, langer Druck fragt vor dem Löschen nach.
- Der Player arbeitet vollständig innerhalb des zugewiesenen Pane-Rechtecks und funktioniert damit auch im Splitscreen.
- Ton läuft über die Geräteausgabe: `gst-launch-1.0` mit `mtkbtmwrpcaudiosink` (auch für eine bereits gekoppelte Bluetooth-Verbindung), sonst `aplay` oder `tinyplay`.

### Konvertierung im Hintergrund

- Download und Ton-Extraktion laufen als abgekoppelte Prozesse mit Exit-Markierungsdatei; die Konvertierung läuft deshalb auch weiter, wenn die DApp verlassen wird.
- Die Videokonvertierung liest frame-weise aus einer Pipe und bleibt dadurch ohne Zwischendateien aus.
- Fortschritt, Stufenmeldung und ein kurzer Log-Ausschnitt stehen im Fortschrittsbildschirm; **Cancel** beendet den Job und räumt das Arbeitsverzeichnis auf.
- Dateinamen werden aus dem Titel gebildet. Umlaute und andere UTF-8-Zeichen bleiben erhalten, kürzere Namen werden nie mitten in einer UTF-8-Sequenz abgeschnitten.

### Einstellungen und Migration

- Neue gespeicherte Werte: Pfade zu yt-dlp und ffmpeg, Ausgabeordner, Auflösungsstufe, Bildrate, Maximallänge, maximale Quellqualität und Dither-Methode. Alle Werte werden beim Laden begrenzt und auf gültige Stufen normalisiert.
- Bestehende Installationen erhalten die Kachel **YouTube** einmalig neben dem AppStore. Wer sie danach entfernt, behält seine eigene Startseite (`layout_version` 21).
- Neue Logo-Art `youtube`; die Logo-Bibliothek umfasst damit 45 Symbole.
- Neues Hilfe-Kapitel **16. YouTube und E-Ink-Video** in Deutsch und Englisch.

### Qualitätssicherung

- Lua-Syntax aller Plugin-Dateien geprüft.
- Neuer Test `test_bwr.lua`: Kopf-Roundtrip, Geometrieprüfung, Fehlerfälle, Dither-Vergleich gegen die Referenzmatrix, Vorwärts-/Invertierungspfad und Bit-Expansion.
- Neuer Test `test_youtube.lua`: Hilfsfunktionen, Link- und Sucheingabe, Fortschrittsauswertung, Einstellungsplumbing, Pane-Aufbau sowie eine vollständige Konvertierung mit echtem ffmpeg über beide Dither-Wege, inklusive erneutem Dekodieren der erzeugten Datei.
- Bestehende DApp-, Keyboard-, AppStore-, Browser-, Ordering- und Setup-Assistant-Regressionstests laufen unverändert durch.

### Bekannte Grenzen

- Nur YouTube-Quellen und lokale Dateien, die ffmpeg dekodieren kann. Andere Videodienste werden ausdrücklich als nicht unterstützt gemeldet.
- Speicherplatz und Rechenleistung des Readers begrenzen Länge, Auflösung und Bildrate.
- Ohne Netzwerk gibt es keine Suche und keinen Download; ohne yt-dlp oder ffmpeg zeigt die DApp den fehlenden Pfad statt zu raten.
- Der Download kann je nach Quelle scheitern, wenn yt-dlp veraltet ist. Die DApp gibt dann den Log-Ausschnitt aus, statt einen Erfolg vorzutäuschen.

## English

### New DApp: YouTube and E-Ink video

- The new built-in DApp **YouTube** searches, downloads and converts videos into a format a monochrome reader can display fluidly.
- AppDock never talks to YouTube itself. It drives **yt-dlp** to resolve and download and **ffmpeg** to decode and to extract the audio track. Both programs stay optional and are not bundled.
- Three inputs: **Search YouTube**, **Paste a video link** (video, Shorts, live and embed links plus bare video ids) and **Convert a local video file**.
- Three fields below the search set resolution, frame rate and maximum length. The **Tools** view additionally manages the program paths, the output folder, the maximum source quality and the dithering method.
- Tools are detected through `command -v` and through the `appdock/tools` folder inside the KOReader data directory. **Detect tools again** re-runs the search.

### BWR1 and videoplayer.koplugin compatibility

- AppDock writes the **BWR1** container (32-byte header, 1 bit per pixel, MSB first, 1 = white). The layout is byte-compatible with the files produced by `tools/make.py` from the **"Snake"** release of `videoplayer.koplugin`.
- Grey frames are dithered with the same ordered 8x8 matrix as `make.py`. A test compares the output byte for byte against an independent reference implementation.
- Optionally ffmpeg performs the 1-bit conversion (`format=monow`). AppDock probes the bit sense of that ffmpeg build once at runtime and falls back to its own matrix when the answer is unclear.
- A same-name `.wav` file is written next to the `.bwr` file. When it is missing, playback simply continues silently.

### E-Ink playback

- The new player shows the frame that belongs to the actually elapsed time: the audio track is the master clock, so timer jitter cannot accumulate into drift.
- Frames are already dithered and only have to be expanded to bytes and blitted. The player requests a **fast** refresh of its own rectangle instead of redrawing the whole screen.
- Controls: **-5 s**, **Play/Pause**, **+5 s**, **Restart**. The library lists every converted video; a tap starts playback, a long press asks before deleting.
- The player stays inside the assigned pane rectangle and therefore works in split screen too.
- Audio uses the device output: `gst-launch-1.0` with `mtkbtmwrpcaudiosink` (which also serves an already paired Bluetooth connection), otherwise `aplay` or `tinyplay`.

### Background conversion

- Download and audio extraction run as detached processes with an exit marker file, so a conversion keeps running after the DApp is left.
- Video conversion reads frame by frame from a pipe and therefore needs no intermediate files.
- Progress, stage message and a short log excerpt appear on the progress screen; **Cancel** stops the job and removes its working directory.
- File names are derived from the title. Umlauts and other UTF-8 characters survive, and shortened names are never cut inside a UTF-8 sequence.

### Settings and migration

- New stored values: yt-dlp and ffmpeg paths, output folder, resolution step, frame rate, maximum length, maximum source quality and dithering method. All values are bounded and normalized to valid steps while loading.
- Existing installations receive the **YouTube** tile once next to the AppStore. Removing it afterwards keeps the user's own launcher (`layout_version` 21).
- New logo kind `youtube`; the logo library now holds 45 symbols.
- New help chapter **16. YouTube and E-Ink video** in German and English.

### Quality assurance

- Lua syntax checked for all plugin files.
- New `test_bwr.lua`: header round-trip, geometry validation, error paths, dithering against the reference matrix, forward/inversion path and bit expansion.
- New `test_youtube.lua`: helpers, link and search classification, progress parsing, settings plumbing, pane construction and a complete conversion with a real ffmpeg through both dithering paths, including decoding the produced file again.
- Existing DApp, keyboard, AppStore, browser, ordering and setup-assistant regression tests still pass unchanged.

### Known limits

- YouTube sources and local files ffmpeg can decode only. Other video services are explicitly reported as unsupported.
- Reader storage and CPU bound length, resolution and frame rate.
- Without network there is no search and no download; without yt-dlp or ffmpeg the DApp shows the missing path instead of guessing.
- A download can fail when yt-dlp is outdated. The DApp then prints the log excerpt instead of pretending success.
