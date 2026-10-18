# AppDock 8.2.8

## Codefreie Custom-Widgets

Der Sleepscreen-Editor enthält eine neue Sektion **Custom widgets**. Benutzer können ohne Lua- oder sonstigen Code eigene wiederverwendbare Text-Widgets erstellen:

- Basistexte mit `{time}`, `{date}`, `{battery}`, `{device}` und `{sleeping}`
- zeitabhängige Texte über einfache Zeitbereiche wie `06:00-12:00=Guten Morgen`
- zyklische Animationen über mehrere Textframes, die pro Sleep-Zyklus wechseln
- Einfügen eigener Widgets als Layer im Sleepscreen

Die Definitionen bleiben deklarativ, werden lokal und serverseitig validiert und akzeptieren keine ausführbaren Inhalte.

## Transparenz

Der Element-Hintergrund verwendet nun den zuverlässigen RGB-Blending-Pfad auch dann, wenn die Farbdisplay-Erkennung im Sleep-/Suspend-Pfad unvollständig ist. Bestehende Presets bleiben kompatibel.
