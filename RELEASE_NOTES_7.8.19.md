# AppDock 7.8.19

## YouTube-Setup: lange Fehlermeldungen vollständig anzeigen

Die Live-Ausgabe verwendete bislang ein einzeiliges Text-Widget und begrenzte einzelne Logzeilen. Dadurch konnte die entscheidende Ursache am Ende einer yt-dlp-Fehlermeldung unsichtbar bleiben. Das Setup verwendet nun ein umbrechendes KOReader-Textfeld und behält die vollständigen letzten Logzeilen bei. So sollten auch lange Meldungen über die gebündelte Python-Laufzeitbibliothek lesbar sein.
