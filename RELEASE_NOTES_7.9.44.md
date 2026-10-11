# AppDock 7.9.44

- Die Tastatur verwendet jetzt eine echte editierbare Offline-Datenbank: `appdock_suggestions.db`.
- Enthalten sind **3.000 deutsche und 3.000 englische Wörter** mit Häufigkeitswerten.
- Vorschläge werden nach Wortfrequenz priorisiert und weiterhin sofort lokal gefiltert.
- Die Datenbank ist bewusst TSV statt SQLite, damit sie auf Kobo ohne native Datenbank-Erweiterung funktioniert und direkt bearbeitet werden kann.
- Eigene Wörter können als weitere Zeilen mit `de` oder `en`, Häufigkeit und Wort ergänzt werden.
- Optional können Dialoge eine Sprache oder eine eigene `suggestions`-Liste übergeben.
