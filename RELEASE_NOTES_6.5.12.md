# AppDock 6.5.12

## Fünf integrierte DApps

AppDock bündelt jetzt fünf geprüfte, offline-first DApps aus dem Repository `arduinodude456/DApps`, damit eine neue Installation sofort mehr als die Kernwerkzeuge bietet und nicht zuerst den AppStore öffnen muss.

| App | Funktion |
|---|---|
| **Calc** | Wissenschaftlicher Taschenrechner und Funktionsplotter |
| **Calendar** | Lokaler Monatskalender mit Terminen |
| **Snake** | E-Ink-freundliches Snake-Spiel |
| **2048** | Lokales 2048-Kachelspiel |
| **Status Message** | Testet lokale AppDock-Benachrichtigungen |

Die Apps werden beim Start über einen sicheren, pluginrelativen Pfad geladen und nur dann registriert, wenn sie den erwarteten DApp-Vertrag mit `id`, `title` und `buildPane` erfüllen. Bestehende Store-Installationen und gespeicherte DApp-Zustände bleiben kompatibel.
