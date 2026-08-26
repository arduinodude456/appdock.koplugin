# AppDock 4.0.1 „Bueno“

This patch release repairs the **Plugin-in-DApp Beta** introduced with 4.0.0 for two real KOReader plugin contracts.

## Fixed plugin menu lifecycle

The core KOReader **Text editor** plugin exposes a dynamic `sub_item_table_func`. Its actions expect a TouchMenu-like argument with `item_table`, `page`, and `updateItems()`: it uses that object when creating or closing an editor to rebuild its dynamic history and settings menu. The AppDock plugin host now supplies a local compatibility adapter with those three responsibilities. Dynamic menus are therefore rebuilt inside the host instead of failing because the expected menu object was absent.

The external **AppStore.koplugin** entry is a direct callback that opens its own browser widget. The host now closes its temporary action menu first and starts that callback on KOReader’s next UI cycle. This removes the competing-menu timing that could prevent the plugin browser from appearing.

## Boundaries retained

The patch preserves the 4.0.0 safety and hardware-independent boundaries. Plugin host sessions remain non-splittable, existing generic callbacks remain supported, AppDock notifications are used for host errors, and AppDock does not globally intercept or rewrite arbitrary third-party plugin dialogs. A plugin that exposes `buildAppDockPane(context)` remains the only contract for a true plugin-owned local pane.

## Verification

Regression coverage now includes a Text editor-style dynamic menu that resets `item_table`, restores page 1, and calls `updateItems()`, plus an AppStore-style direct callback that runs after the AppDock host menu closes. The full Lua 5.1 syntax check and existing AppDock regression suite passed after the fix.
