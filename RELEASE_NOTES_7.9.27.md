# AppDock 7.9.27

## Draw: Stylus-Samples nicht mehr durch UI-Scheduling verlieren

Das Refresh-Batching aus 7.9.26 wurde zurückgenommen. Auf bestimmten Kobo/KOReader-Kombinationen führte das geplante UI-Refresh dazu, dass bei schnellen Stylus-Bewegungen sichtbare Zwischenstände ausblieben.

Jetzt wird jede geänderte Stylus-Region wieder unmittelbar mit `setDirty` eingereiht und jeder Sample-Punkt direkt verarbeitet. Nur `forceRePaint()` wird höchstens alle 40 ms ausgeführt. Ein blockierendes `yieldToEPDC()` findet ausschließlich beim finalen Ende des Strichs statt.

Damit bleibt der Eingabepfad vollständig sample-basiert, während unnötige Zwischenblockaden reduziert werden.
