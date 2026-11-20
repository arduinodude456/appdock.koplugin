# AppDock 9.12.0
## DockAI-Sicherheit
- DockAI nutzt den dchat-Supabase-Proxy; Groq-API-Keys werden serverseitig gespeichert und nicht an AppDock zurückgegeben.
- Tageslimit 25 und Wochenlimit 100 werden serverseitig pro TBS-Geräte-ID atomar erzwungen; zurückgewiesene/fehlgeschlagene Provider-Anfragen werden wieder freigegeben.
- Admin kann in AppDock API-Keys hinzufügen. Anzeigen, Löschen, Dateiimport und lokale Limitänderungen wurden entfernt.
- DockAI benötigt ein angemeldetes TBS-Konto. Zähler setzen um Mitternacht UTC bzw. Montag UTC zurück.
- Admin-Passwortprüfung erfolgt auf dem Server; das frühere im Plugin enthaltene Passwort wurde aus dem Client entfernt.
