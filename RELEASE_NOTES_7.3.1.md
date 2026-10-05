# AppDock 7.3.1 „E-Ink Clean Motion"

## Ghosting-Hotfix

- Die Farbpalette von Homescreen, Recently-used-Drawer, DApps und Quick Settings wird auf die sechs schnellen Panel-Farben quantisiert: reines Rot, Grün, Blau, Gelb, Schwarz und Weiß.
- Für monochrome Geräte werden Flächen ebenfalls konsequent auf Schwarz oder Weiß abgebildet, statt Zwischen-Grautöne in schnellen UI-Bereichen zu erzeugen.
- Nach dem letzten schnellen Animationsframe wird genau einmal eine vollständige KOReader-Aktualisierung ausgelöst. Dadurch werden Restbilder nach Seitenwechseln, Drawer-Animationen und Quick-Settings-Bewegungen entfernt.
- Die Animationen bleiben kurz und unverändert; der Hotfix ändert nur die Farbquantisierung, die Abschlussaktualisierung und die Plugin-Versionskennung.

Der Fix ist für die Installation über DockUpdate 1.1.2 vorbereitet. Nach der Aktualisierung von DockUpdate auf 1.1.2 kann AppDock 7.3.1 direkt installiert werden.
