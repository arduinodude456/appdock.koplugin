# AppDock 7.8.51

## Flüssigere Wiedergabe auf E-Ink-Geräten

Beim Start der YouTube-Wiedergabe deaktiviert der Player KOReaders Einstellung `color_rendering` temporär. Dadurch verwendet KOReader während der Wiedergabe den schnelleren Rendering-Pfad, was besonders auf Kobo-MTK-Geräten zu flüssigerem Video führt.

Beim Stoppen des Players wird der vorherige Wert exakt wiederhergestellt. Das gilt auch dann, wenn die Einstellung vorher nicht in der KOReader-Konfiguration vorhanden war. Die Änderung wird über `ColorRenderingUpdate` sofort an KOReader gemeldet.
