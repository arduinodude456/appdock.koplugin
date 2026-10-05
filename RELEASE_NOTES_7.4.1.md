# AppDock 7.4.1

## Boot-Hotfix für Rasterlogos

Die farbigen PNG-Applogos werden jetzt über den bereits bewährten und abgesicherten `Wallpaper.buildPath`-Bildpfad geladen, der auch für das Lockscreen-Profilbild verwendet wird. Fehlende oder nicht ladbare Assets fallen dadurch sicher auf die vorhandenen gezeichneten Logos zurück, statt den Homescreen beim Start zu beeinträchtigen.

Die PNG-Dateien selbst bleiben unverändert erhalten. Der Lockscreen und sein Profilbildpfad werden nicht verändert.
