# AppDock 8.2.17 — App-Gruppen

Behebt einen Absturz beim Erstellen einer App-Gruppe über **Add another App → Create App Group**. Die Übersetzung `_()` wurde in den Gruppenmenüs durch die erste Rückgabevariable von Lua-`ipairs`/`pairs` überschattet; damit wurde beim Öffnen der Auswahl ein Zahlenwert als Funktion aufgerufen.

Zusätzlich wird beim Wechseln der ausgewählten Apps jetzt nur das gerade offene Dialogfenster geschlossen. Ein neuer Regressionstest durchläuft das Erstellen einer Gruppe, den Mitgliedereditor und die Manageransicht mit vorhandener Gruppe.
