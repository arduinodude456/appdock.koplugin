# AppDock 9.3.1 — Flackerfreie Animationen

Dieses Patch-Release entfernt die zusätzlichen Full-/Partial-Refreshes vor und nach den UI-Animationen.

- Homescreen-Seitenwechsel übergeben jetzt regional mit `fast` an die echte UI.
- Quick Settings und Recently-used/Open Apps verwenden beim Ein- und Ausblenden keine zusätzlichen `partial`- oder normalen UI-Refreshes mehr.
- Die kurzen Schalteranimationen in Quick Settings lösen keinen abschließenden Full-Refresh mehr aus.
- Die Animationsebene bleibt beim Übergang auf die echte UI im regionalen Fast-Refresh-Pfad, wodurch das sichtbare Flackern auf E-Ink-Geräten entfällt.
