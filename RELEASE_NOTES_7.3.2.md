# AppDock 7.3.2 — Animation Color Scope Fix

## Fehlerbehebung

- Die Farbquantisierung des E-Ink-Animations-Hotfixes wird nicht mehr beim Aufbau der gesamten statischen UI verwendet.
- Homescreen, DApps, Quick Settings und zentrale Themes verwenden außerhalb laufender Animationen wieder ihre normale Farb-/Graustufenlogik.
- Der Animations- und Fast-Refresh-Pfad bleibt erhalten.

Dieses Release korrigiert die unbeabsichtigte globale Farbänderung aus AppDock 7.3.1.
