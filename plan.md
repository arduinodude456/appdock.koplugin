# YouTube Shorts für AppDock

## Umsetzung

Die bestehende `appdock_youtube.lua` bleibt die Download- und Wiedergabe-Pipeline. Eine neue `appdock_shorts.lua` kapselt den Shorts-Feed und nutzt ein eigenes YouTube-DApp-Hilfsobjekt für Suche, Download, Library und `appdock_player`. Der Feed startet eine yt-dlp-Suche mit `#shorts`, begrenzt Treffer auf maximal 180 Sekunden und zeigt ausschließlich diese Ergebnisse. Während ein Clip spielt, wird der nächste Feed-Eintrag im Hintergrund geladen; bereits geladene Dateien werden direkt aus der lokalen Library verwendet.

Likes und erkannte Hashtags werden lokal in `G_reader_settings` gespeichert. Empfehlungen erhalten einen Score aus beliebten Hashtags, Like-Häufigkeit und dem aktuellen Feed-Index; damit bleiben sie offline reproduzierbar und benötigen keine YouTube-OAuth- oder Schreibzugriffe. Die Oberfläche übernimmt die bestehende monochrome YouTube-Anmutung des Repositories, erhält aber eine vertikale Shorts-Lesart: großer Player, Creator-/Hashtag-Metadaten, Like-Aktion und Up-next-Stack.

## Projektstruktur

- `appdock.koplugin/appdock_shorts.lua`: Feed-State, lokale Likes/Hashtags, Vorladen, UI und reine Empfehlungs-/Filter-Helfer.
- `appdock.koplugin/appdock_dapps.lua`: Registrierung der neuen DApp und Lifecycle-Stop.
- `test_shorts.lua`: Tests für Short-Filter, Hashtag-Extraktion und Empfehlungsranking.
- `TODO.md`: lieferbare Akzeptanzkriterien und Status.

## Design

- **Stiloptionen:** E-Ink Editorial 0.07; Monochrome Creator Cards 0.06; Dense Terminal Feed 0.05.
- **Gewählt – E-Ink Editorial:** eine ruhige, schwarzweiße Shorts-Leseansicht mit starkem Video-Canvas, klaren Metadaten und kompakten Aktionschips.
- **Design Movement:** YouTube Shorts trifft auf eine gedruckte Magazinseite für E-Ink.
- **Core Principles:** Video zuerst; einhändige, große Aktionen; keine grauen UI-Flächen ohne Funktion; lokale Transparenz statt versteckter Personalisierung.
- **Color Philosophy:** Schwarz/Weiß mit Graustufen für Hierarchie, damit der Clip und der Like-Zustand auch auf monochromen Readern eindeutig bleiben.
- **Layout Paradigm:** vertikaler Story-Stream mit festem Player und darunterliegendem Up-next-Stapel, nicht als klassische Rasteransicht.
- **Signature Elements:** pillenförmiger `#shorts`-Chip, gefülltes Herz als Like-Zustand, kleine „Als Nächstes“-Karte.
- **Interaction Philosophy:** Tippen spielt; ein Like ist sofort lokal sichtbar; der nächste Clip lädt ohne zusätzlichen Dialog.
- **Animation:** keine dekorative Animation; nur schneller UI-Rebuild beim Feed-/Like-Wechsel und Player-Tick.
- **Typography System:** `cfont` für Clip-Titel und `smallinfofont` für Creator, Hashtags und Status.
- **Brand Essence:** „Shorts, die auf deinem Reader weiterlaufen“ – direkt, ruhig, persönlich.
- **Brand Voice:** „Als Nächstes wartet dein Feed.“ / „Deine Likes formen die nächsten Vorschläge.“
- **Wordmark & Logo:** vorhandenes YouTube-Zeichen mit zusätzlichem `#`-Chip, damit die DApp im AppDock wiedererkennbar bleibt.
- **Signature Brand Color:** reines Schwarz als aktive Shorts-Fläche; der Like-Zustand wird ausschließlich durch gefülltes Herz und Text markiert.
