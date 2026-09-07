# AppDock 6.1.3 — Stable Grid Editor

AppDock 6.1.3 removes the remaining destructive lifecycle operation from the App Grid editor. Toggling a widget or app no longer closes and reconstructs the popup from inside its own touch callback. The manager surface stays alive and is only marked dirty for redraw.

This eliminates the popup close, deferred rebuild and immediate native redraw sequence that can trigger Android's destroyed-mutex abort. The previous stable switch and popup paint fixes remain included.
