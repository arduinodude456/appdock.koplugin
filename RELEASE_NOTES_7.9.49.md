# AppDock 7.9.49 — Zuverlässigkeit und klare lokale Kontrolle

## Update-Hinweis

- Der Update-Dialog erscheint bei jedem AppDock-Start, bis **Don't show again** gewählt wird.
- Er verwendet einen stabilen AppDock-Modal-Dialog statt eines flüchtigen Standarddialogs.
- Die erste Seite enthält das mitgelieferte AppDock-Testbild aus dem Plugin-Archiv.
- Unter **Settings → Other → Update notice** kann ein ausgeblendeter Hinweis für die aktuelle Version wieder aktiviert werden.

## Boot-Rollback-Schutz

- Nach einem erfolgreichen Start speichert AppDock eine lokale **letzte funktionierende Plugin-Kopie** im KOReader-Datenverzeichnis.
- Falls eine spätere Version den Boot-Marker nicht erfolgreich abschließt, stellt der nächste KOReader-Start diese Kopie automatisch wieder her.
- Die Wiederherstellung hinterlässt einen klaren lokalen Hinweis. Die aktuelle Sitzung kann anschließend durch einen normalen KOReader-Neustart vollständig auf die wiederhergestellte Version wechseln.
- Der Schutz greift für zukünftige Updates, nachdem diese Version mindestens einmal erfolgreich gestartet wurde.

## YouTube

- Video- und Audio-Konvertierung laufen nun absichtlich **nacheinander**, nicht parallel. Das vermeidet zwei gleichzeitig speicherintensive FFmpeg-Dekoder auf Kobo-Geräten.
- FFmpeg arbeitet mit einer begrenzten Threadzahl; der Rohframe-Puffer hält nur ein Frame statt mehrerer Frames vor.
- Pro Gerät darf nur eine AppDock-YouTube-Konvertierung gleichzeitig laufen.
- Fehler und Abbrüche schließen Pipes, temporäre Writer und Hintergrundprozesse sauber, damit ein späterer Versuch nicht durch Altprozesse destabilisiert wird.

## Tastatur

- Vorschläge sind nach Sprache und Präfix indiziert; dadurch müssen bei normaler Eingabe nicht mehr alle Wörter durchsucht werden.
- Die Tastenrückmeldung ist kürzer, und Buchstabenlabels werden nur bei einem tatsächlichen Groß-/Kleinschreibwechsel neu gezeichnet.
- Unter **Settings → Other → Keyboard language** stehen **Automatic**, **German** und **English** zur Auswahl.

## Files

- **Sort my files** erkennt Documents, Images, Videos, Audio, Apps und Folders anhand von Dateityp, ausführbaren Dateien und Verzeichnisstatus.
- Die Sortierung ist vollständig **virtuell**: Sie verschiebt keine Dateien und legt keine Kategorieordner an.
- Ausgewählte Kategorie, manuell ausgeblendete Pfade und die Anzeige versteckter Elemente sind persistent.
- Ein langer Druck in der virtuellen Ansicht bietet **Hide from Sort my files** bzw. **Show in Sort my files**.

## Store-Themes

- Die öffentliche DApp-Palette enthält jetzt kontrastgeprüfte Rollen für `text`, `foreground`, `on_background` und `on_dropdown`.
- Dadurch können Store-DApps bei einem aktiven Farbdesign nicht mehr versehentlich denselben Text- und Hintergrundton übernehmen.
