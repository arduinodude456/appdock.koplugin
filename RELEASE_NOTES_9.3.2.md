# AppDock 9.3.2 — Animationsstart und Dropdown-Abschluss

Dieses Patch-Release behebt verbleibendes Flackern beim Homescreen-Seitenwechsel und im Quick-Settings-Dropdown.

Der Animationsrunner startet nun direkt mit dem ersten bewegten Frame statt zunächst einen statischen `t=0`-Frame zu zeichnen. Dadurch entsteht vor dem Homescreen-Seitenwechsel kein zusätzlicher sichtbarer Refresh.

Das Quick-Settings-Dropdown startet ebenfalls ohne statischen Vorab-Frame. Beim Wegfahren werden Dropdown und Animationsebene zuerst vollständig entfernt; anschließend wird genau einmal ein normaler UI-Refresh für die darunterliegende Seite ausgeführt, um Ghosting sauber zu entfernen.
