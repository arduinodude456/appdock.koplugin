# AppDock 7.9.26

## Draw: schnelleres Stylus-Zeichnen

Schnelle Stylus-Samples werden jetzt direkt im Zeichenpuffer verarbeitet, während die teuren UI-/E-Ink-Refresh-Anfragen in einem 35-ms-Fenster gebündelt werden. Dadurch wächst die Refresh-Warteschlange nicht mehr mit der Stylus-Sample-Rate an.

Das finale Refresh beim Abheben des Stifts bleibt synchron, damit der vollständige Strich sicher sichtbar ist. Die Zwischen-Refreshes warten nicht mehr blockierend auf den E-Ink-Controller.

Dadurch reagiert Draw bei schnellen Stiftbewegungen deutlich unmittelbarer und verarbeitet die zusätzlichen Stylus-Punkte ohne unnötige Repaint-Blockaden.
