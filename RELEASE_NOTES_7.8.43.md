# AppDock 7.8.43

## Stabilität der Audio-/Video-Wiedergabe

Die fehlerhafte Frame-Lock-Wiedergabe aus 7.8.40 wird zurückgenommen. Sie koppelte den Videofortschritt an unregelmäßige UI-Ticks, während der Audioprozess unabhängig in Echtzeit lief. Dadurch konnte sich der Versatz während der Wiedergabe scheinbar zufällig ändern.

7.8.43 verwendet wieder die stabile Echtzeit-Zeitbasis des Players. Der frei einstellbare Offset aus 7.8.41 bleibt erhalten und gilt weiterhin für alle Audio-Backends.
