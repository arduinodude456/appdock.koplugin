# AppDock 8.9.3 — Faster Homescreen

This release reduces redundant work while the homescreen is built, without changing its appearance or functionality.

- Reuse one app-catalog snapshot for pinned apps, recent apps, search results, and the **All apps** dock item.
- Avoid enumerating Store widgets twice during homescreen initialization. Later rebuilds still refresh the widget list.
- Keep pinned-app lookup lazy while searching, preserving the previous search behavior.
