# AppDock 2.5.0 — Homescreen arrangement

AppDock 2.5.0 adds local ordering for pinned apps and installed Store widgets.

## Apps

Open **Manage apps and widgets → Arrange apps**. Each pinned app is shown with a position counter and large **↑** and **↓** actions. Moving an app changes the existing `pinned_apps` order, so the launcher grid and its pages follow the new order immediately after the manager refreshes.

## Store widgets

Open **Manage apps and widgets → Arrange store widgets**. Installed Store widgets receive the same position counter and move actions. The resulting order controls the vertical order of visible Store widget cards on the Homescreen. A newly installed widget is appended alphabetically after already ordered widgets. Uninstalled or missing widget IDs are removed from the stored order automatically.

## Persistence and E-Ink behavior

The order is stored locally in `G_reader_settings`. Existing AppDock settings migrate without replacing a user's current pinned-app order. Drag-and-drop is intentionally not used: explicit large actions are more predictable on E-Ink touchscreens and require only the existing UI rebuild path. The change does not add network access, timers, background work, or a full refresh.

System status and current-book cards keep their existing fixed dashboard placement; the new ordering controls apply to pinned launcher apps and Store widgets.

## Validation

The Lua-5.1 syntax checks, AppDock smoke test, manager ordering UI test, DApp test, Quick Settings test and Theme/AppStore test pass for this change. Real-device touch spacing and page transitions should still be checked on Kobo/Tolino hardware.
