# AppDock 7.8.37

## YouTube-Audio-/Video-Synchronisation

Der Kobo-MTK-Audio-Sink meldet `New clock:` bereits vor dem hörbaren Beginn der Ausgabe. Auf der betroffenen Kobo-Audiokette beträgt diese Hardware-/Ringpuffer-Latenz rund vier Sekunden.

AppDock wartet deshalb nach dem echten GStreamer-Clock-Signal zusätzlich auf die gemessene MTK-Ausgabelatenz, bevor das erste Videobild startet. Die Raw-PCM-Audiopipeline aus 7.8.26 bleibt unverändert; aplay und tinyplay erhalten keine MTK-Korrektur.

## YouTube-Oberfläche

Die YouTube-DApp erhält einen kontrastreichen YouTube-Kopf, Suchsymbol, Kategorien und Videokarten mit Thumbnail-Fläche sowie Kanal-/Laufzeit-Metadaten für E-Ink-Geräte.
