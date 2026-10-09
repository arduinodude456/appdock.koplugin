# AppDock 7.8.26

## YouTube-Progressbars werden während des Jobs neu gezeichnet

Der Setup-Fortschritt und die Fortschrittsanzeigen von Download und Videokonvertierung werden jetzt bei aktivem YouTube-Pane in gedrosselten Abständen durch einen partiellen Pane-Neuaufbau aktualisiert. Dabei werden aktueller Prozentwert, Phasenpuls und Statuszeile aus dem laufenden Jobzustand erneut gerendert. Ein manueller Screen-Refresh ist nicht mehr nötig. Die Aktualisierung wird nicht per Vollbild-Refresh und nicht bei jedem einzelnen Frame ausgelöst.

Beim Neuaufbau bleibt außerdem die aktuelle Position des indeterminierten Setup-Fortschritts erhalten, statt auf den Anfang zurückzuspringen.

## Verifikation

Regressionstests prüfen, dass Setup- und Videojobs einen partiellen Pane-Neuaufbau anfordern und dass dabei aktueller Status beziehungsweise Prozentwert erneut in die sichtbaren Widgets übernommen werden. Die vollständige lokale Regressionstestsuite und die Lua-Syntaxprüfung aller Plugin-Dateien liefen erfolgreich.
