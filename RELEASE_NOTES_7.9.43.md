# AppDock 7.9.43

- **Tastatur-Cancel repariert:** Bereits geschlossene Eingabedialoge werden nicht mehr ein zweites Mal geschlossen.
- Der Update-Hinweis verwendet jetzt eine AppDock-eigene helle Modal-Karte statt den gesamten Inhalt in den ButtonDialog-Titel zu packen.
- Der Feature-Dialog besitzt keinen Timeout und bleibt bei periodischen E-Ink-Vollrefreshes sichtbar.
- Seitenwechsel, `Weiter`, `Später` und `Fertig` bleiben erhalten.

Hinweis: Die allgemeine Testsuite konnte bis zur Dialogprüfung ausgeführt werden; `test_dapps.lua` benötigt außerhalb einer KOReader-Umgebung das KOReader-Modul `json`.
