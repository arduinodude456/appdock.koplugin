# AppDock 8.5.2 — NetSurf-Browser

AppDocks Browser startet jetzt standardmäßig NetSurf anstelle der integrierten Browser-Startseite. Der bisherige AppDock-Browser bleibt als Fallback verfügbar, falls NetSurf nicht installiert ist.

DockUpdate bezieht das neue Browser-Modul `appdock_netsurf.lua` ab Version 8.5.2. Bei einem bestätigten AppDock-Update wird das NetSurf-Paket nach `/mnt/onboard/.adds/netsurf` entpackt; vorhandene Installationen werden nicht überschrieben.

Nach der Aktualisierung AppDock bzw. KOReader neu starten. NetSurf benötigt das mitgelieferte Reader-Binary und ausreichend freien Speicher im `.adds`-Verzeichnis.
