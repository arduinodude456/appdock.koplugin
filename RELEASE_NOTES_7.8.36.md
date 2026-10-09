# AppDock 7.8.36

## Synchronisation über den tatsächlichen Audiostart

Die Raw-PCM-Audiopipeline aus 7.8.26 bleibt unverändert. GStreamer-Ausgaben werden nun zusätzlich protokolliert, damit AppDock das echte `New clock:`-Signal des MTK-Audio-Sinks erkennen kann.

Das Video startet erst, wenn dieser Audio-Clock aktiv ist. Es wird keine feste Verzögerung verwendet. Gibt eine Kobo-Firmware das optionale Signal nicht aus, bleibt Audio aktiv und das Video startet nach dem Fallback-Timeout.
