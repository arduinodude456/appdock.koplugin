# AppDock 6.2.5 — Keyboard Lifecycle and Visible eInk Frames

AppDock 6.2.5 removes the recursive `UIManager:close()` call from the keyboard's `onCloseWidget` hook. KOReader has already entered the close lifecycle at that point; re-closing the widget could access a destroyed render mutex.

The eInk motion helper now requests a `fast` dirty region and immediately asks KOReader for a repaint after every frame. This makes the Quick Settings switch thumb movement visible on devices where a dirty mark alone is deferred. Standard dialogs remain unchanged.
