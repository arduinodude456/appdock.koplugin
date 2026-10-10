# AppDock 7.9.16

## YouTube Music: Suchfehler sichtbar machen und erneut versuchen können

Die Suche unterdrückt yt-dlp-Fehler nicht mehr mit `--ignore-errors`; brauchbare Teilergebnisse bleiben dennoch erhalten, auch wenn yt-dlp für einzelne YouTube-Einträge einen Fehlerstatus zurückgibt. Die Metadatenabfrage verwendet jetzt außerdem denselben Android-YouTube-Client wie der Audio-Download.

Wenn yt-dlp keine Treffer liefert, fehlschlägt oder in einen Timeout läuft, bleibt AppDock auf einer eigenen Diagnoseansicht statt zur leeren Mediathek mit einer kaum sichtbaren Randmeldung zurückzuspringen. Die Ansicht zeigt den Suchfehler und bietet **Erneut versuchen** sowie **Zur Mediathek**. Die Suche lädt weiterhin keine Mediendateien herunter.

## Tests

`test_ytmusic.lua` deckt eine normale Texteingabe wie „hallo“, sichtbare HTTP-Fehlerdiagnose sowie erneutes Versuchen und Zurücknavigation ab. Alle 13 AppDock-LuaJIT-Tests laufen durch; Syntax- und Diff-Prüfungen sind sauber.
