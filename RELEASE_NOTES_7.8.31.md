# AppDock 7.8.31

## YouTube-Audio-/Video-Synchronisation

- Behebt den Versatz, der entstehen konnte, wenn GStreamer während des Audiostarts noch keine Startbestätigung gemeldet hatte.
- Das Video berücksichtigt jetzt die bereits verstrichene Audiostartzeit, statt nach der Initialisierung an der alten Position zu beginnen.
- Der Korrekturmechanismus greift auch bei Geräten, die kein erwartetes GStreamer-Logsignal liefern und in den Startup-Timeout laufen.
- Seek-Vorgänge während der Audioinitialisierung setzen den Synchronisationszeitpunkt korrekt zurück.
