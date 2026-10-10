# AppDock 7.8.40

## Frame-gebundene YouTube-Synchronisation

Der angezeigte Videoframe ist jetzt die einzige Wiedergabe-Zeitbasis. Der Player berechnet die Position aus `Frame n / FPS`, statt eine unabhängig verstrichene Wandzeit als Videouhr zu verwenden.

- Jeder nächste Frame wird exakt aus dem Frameindex abgeleitet.
- Pause und Seek runden auf konkrete Videoframes.
- Audio-Seeks verwenden exakt dieselbe Frameposition.
- Die frühere feste MTK- und WAV-Dauer-Korrektur bleibt entfernt.

Bereits konvertierte Videos können weiterverwendet werden; für die Audio-Stille-Normalisierung aus 7.8.39 müssen Videos weiterhin neu konvertiert werden.
