# AppDock 7.9.13

## Neue DApp: YouTube Music

**YouTube Music** ist bewusst kein Video-DApp: Es lädt ausschließlich die Tonspur und zeigt dazu das
Vollfarb-Titelbild.

- Eine `yt-dlp`-Abfrage holt die beste Tonspur (`bestaudio[ext=m4a]/bestaudio/best`). Es wird keine
  Videospur geladen und nichts zusammengeführt.
- Ein einzelner FFmpeg-Lauf erzeugt die 16-Bit-WAV-Begleitdatei, die die vorhandene AppDock-Audiokette
  bereits versteht. Es gibt **keinen** Frame-Umwandlungsschritt, kein BWR2/BRC2-Encoding und keine
  Dither-Berechnung.
- Das Titelbild kommt als gewöhnliches JPEG: zuerst `maxresdefault`, dann `hqdefault`, zuletzt die
  Bild-URL des Suchergebnisses. Damit ist das Cover ein echtes Vollfarbbild statt eines konvertierten
  Videoframes.
- Die Bibliothek zeigt Titelbild, Titel und Dauer. Wiedergabe, Pause, ±15 s, Neustart, Fortschrittsbalken
  und Löschen per langem Druck laufen über dieselbe Audiokette wie YouTube (`gst-launch-1.0`, `aplay`
  oder `tinyplay`).
- Suchfeld und Linkeingabe teilen sich die YouTube-Logik; ein Link startet den Download direkt.
- Eigener Musikordner (Standard `<Datenordner>/appdock/music`) über **Tools → Music folder**. yt-dlp und
  ffmpeg werden mit der YouTube-DApp geteilt, die Werkzeugverwaltung ist identisch.
- Eine bestehende Installation erhält die Kachel einmalig nach dem YouTube-Eintrag.

## Schnellere YouTube-Konvertierung

- **Audiospur und Video laufen parallel.** Beide FFmpeg-Durchläufe lesen dieselbe Quelldatei; der
  Audiopfad wurde bisher vollständig nach der Bildkonvertierung ausgeführt und addierte eine komplette
  Dekodierung zur Gesamtzeit. Jetzt bestimmt `max(Video, Audio)` die Dauer.
- **Parallele Fragmente beim Download.** yt-dlp lädt DASH-Fragmente mit `--concurrent-fragments 4`.
- **Gebündelte Frame-Lesung.** Der Video-Tick liest mehrere Frames pro Pipe-Zugriff in einen Puffer,
  statt für jeden Frame einen eigenen Lesevorgang zu starten.
- **`monow`-Erkennung zwischengespeichert.** Die Bitreihenfolge wird pro FFmpeg-Binary einmal geprüft
  statt bei jeder Konvertierung.
- **Ruhigerer Fortschrittsbalken.** Während der Videostufe wird die Ansicht seltener neu aufgebaut
  (1,5 s statt 0,75 s), damit mehr CPU-Zeit bei der Konvertierung bleibt. Downloadstufen bleiben bei
  0,75 s.
- Die maximale Frame-Zahl pro Tick steigt von 32 auf 64; das CPU-Zeitbudget bleibt unverändert, damit
  Abbruch und Fortschritt responsiv bleiben.

## Draw: Oberfläche und Bedienung

- **Herkömmliche Malprogramm-Oberfläche.** Werkzeugleiste mit sechs Werkzeugen (Stift, Radierer, Linie,
  Rechteck, Kreis, Füllen) und hervorgehobenem aktivem Werkzeug, daneben Undo, Redo und
  **Bildschirm reinigen**. Darunter eine Optionszeile mit Farbfeldern, Pinselgröße (−/+), Ebenen und
  Dithering-Schalter, unten eine Aktionsleiste (Leeren, Speichern, Öffnen, JPEG) mit Statuszeile
  („Stift · 2 px · Schwarz · Ebene 1/2“).
- **Striche beginnen beim Aufsetzen des Fingers.** Draw reagiert jetzt auf `touch`; der erste Abschnitt
  eines Strichs geht nicht mehr verloren. Ein Tippen malt einen Punkt.
- **Nur der berührte Bereich wird neu gezeichnet und aktualisiert.** Vorher wurde pro Touch-Ereignis die
  gesamte Zeichenfläche neu zusammengesetzt und ein vollständiger E-Ink-Refresh erzwungen; auf langsamen
  Geräten wirkte Draw dadurch wie eingefroren.
- **Formwerkzeuge mit Live-Vorschau.** Linie, Rechteck und Kreis werden während des Ziehens angezeigt und
  erst beim Loslassen übernommen.
- **Füllen läuft einmal pro Geste** statt bei jedem Bewegungsereignis (jedes Füllen läuft über die ganze
  Fläche und war als Dauerläufer der teuerste Fehler).
- **Undo/Redo** mit bis zu 8 Schritten, inklusive der Aktionen *Leeren* und *Strich*.
- **Fingerdruck verkleinert den Pinsel nicht mehr.** Ein Finger meldet Druck 0; dieser Wert wurde
  bisher als „sehr leichter Druck“ gelesen und reduzierte jeden Strich auf ein Pixel.
- Werkzeuge, Farben und Optionen haben echte Symbolschaltflächen mit Kontur, statt Textzeilen über der
  Zeichenfläche.

## Fenster (Beta) und Vollbild

- **Bildschirmrefresh nach Ziehen oder Skalieren.** Ein DApp-Fenster beendet die Geste jetzt mit einem
  vollständigen Refresh der Fensteroberfläche. Die regionalen Fast-Refreshes während der Geste konnten
  den alten Rahmen nicht entfernen.
- **Die YouTube-Vollbild-Schaltfläche wechselt nur noch den Modus.** Sie lag innerhalb der Trefferfläche
  des MiniPlayers, der die Taps zuerst bekam und zusätzlich die Wiedergabe umschaltete. Der MiniPlayer
  gibt den Streifen mit den Schaltflächen jetzt frei.

## Tests

- `test_ytmusic.lua` prüft den Audio-only-Vertrag (kein Videoformat, kein Merge), den WAV-Vertrag
  (16 Bit, 44,1 kHz, Stereo), die Titelbild-Reihenfolge, die Titelbenennung und die komplette
  Konvertierung gegen eine echte FFmpeg-Ausgabe.
- `test_draw.lua` prüft zusätzlich Undo/Redo, die Werkzeugleiste mit hervorgehobenem Werkzeug, das
  Aufsetzen des ersten Strichs, die einmalige Füllung pro Geste, die Formvorschau und den Teil-Refresh.
- `test_dapps.lua` erwartet den erweiterten Katalog inklusive `dapp:youtube_music`.
- Alle 13 Testsuiten laufen mit LuaJIT und Lua 5.1 durch.