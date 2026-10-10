# AppDock 7.8.49

## Video-Startverzögerung repariert

Auf Kobo-MTK-Geräten wird die konfigurierte Verzögerung jetzt auch dann korrekt angewendet, wenn der GStreamer-Audio-Clock erst kurz nach dem Start gemeldet wird. Zuvor wurde der Offset in diesem Pfad durch den Standardwert von 0 Sekunden ersetzt, wodurch Video und Audio sofort beziehungsweise mit falschem Abstand starteten.

Die Einstellung unter YouTube → Einstellungen → „Video start after audio“ bleibt weiterhin zwischen 0 und 60 Sekunden frei konfigurierbar.
