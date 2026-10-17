# AppDock 8.2.6

Ein Farbfix für Sleepscreens auf farbfähigen E-Ink-Geräten.

Der Sleepscreen-Renderer verwendet definierte `#RRGGBB`-Farben nun als echte RGB-Farben und zeichnet farbige Hintergründe über den RGB-Blitbuffer-Pfad. Auf monochromen Geräten bleibt die luminanzbasierte Graustufen-Darstellung als kompatibler Fallback erhalten. Ein Regressionstest deckt beide Farbpfade ab.
