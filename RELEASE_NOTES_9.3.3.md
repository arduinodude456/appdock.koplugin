# AppDock 9.3.3 — Kein Vorab-Refresh beim Seitenwechsel

Dieses Patch-Release behebt den noch sichtbaren Refresh unmittelbar vor der Homescreen-Seitenanimation.

Das Animations-Overlay wird nun ohne eigenen Vorab-Refresh registriert. Der erste bewegte Frame wird direkt in den bereits sichtbaren Screen-Puffer gezeichnet und erst anschließend aktualisiert. Dadurch beginnt die Animation ohne statischen Zwischenframe.

Nach dem Seitenwechsel wird das Overlay ohne zusätzlichen Zwischenrefresh entfernt. Erst danach wird genau einmal ein Full-Refresh ausgeführt, um E-Ink-Ghosting zu beseitigen.

Auch das Quick-Settings-Dropdown verwendet beim Schließen keinen zusätzlichen Overlay-Refresh vor dem abschließenden UI-Refresh.
