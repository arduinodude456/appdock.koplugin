# AppDock 9.3.0 — Slide-Animationen

Kurze Animationen für Homescreen, Open apps, Quick Settings und die Recently-used-Leiste. Gemeinsame Regeln:

- Während einer Animation besteht jedes Bild nur aus Schwarz, Weiß, Rot, Grün, Blau, #ff00ff, #ffff00 und #00ffff. Der Bildschirm wird einmal zu Beginn mit dem bekannten Bayer-Dither (`appdock_dither.lua`) in diese acht Farben gerastert; die Einzelbilder sind danach reine Kopien. Das Muster wandert mit dem Inhalt und flimmert nicht.
- Jedes Bild nutzt Fast Refresh, nur für die bewegte Fläche.
- Nach dem letzten Bild schließt sich die Animationsebene, KOReader zeichnet die echten Farben einmal mit normalem „ui“-Refresh.
- Berührungen werden während der Animation geschluckt (kein Doppel-Wisch, kein versehentliches Antippen).
- Schlägt etwas fehl, greift sofort das bisherige Verhalten ohne Animation.

## Wo

- **Homescreen:** Beim Wischen (oder über Seitenpunkte/Tasten) schiebt sich die neue App-Seite seitlich herein. Das Dock bleibt stehen.
- **Open apps:** Die Ansicht fährt von unten herauf; Wischen zwischen den Karten schiebt seitlich; eine geschlossene Karte fliegt nach oben weg.
- **Quick Settings:** Der Schnellzugriff fährt von oben herunter und beim Schließen wieder hinauf.
- **Recently-used-Leiste:** Fährt von unten herauf und beim Schließen/Starten einer App wieder hinunter.

## Einstellungen

- Menü **AppDock Homescreen → Slide animations** schaltet alles ab (`settings.animations`).
- Im Energiesparmodus sind die Animationen aus.

## Technik

- Neu: `appdock_anim.lua` (capture, offscreen render, Push-/Sprite-Kompositionen, Runner mit Overlay und Watchdog).
- Hilfe-Texte aktualisiert.
