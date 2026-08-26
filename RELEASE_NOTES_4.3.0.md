# AppDock 4.3.0 — Simple Mode

## Simple Mode

AppDock now offers a dedicated **Simple** category in Settings. Its three independent switches can be enabled separately and are saved locally.

- **Simple homescreen** hides the greeting, status cards, store widgets, search field and background content. It leaves an apps-only **4×3** grid and does not schedule hidden widget refreshes.
- **Simple quick settings** shows only **Wi-Fi**, **Night**, **Save power** and the brightness slider. Notifications and inbox actions are omitted.
- **Quick find** limits the visible AppDock selection to **Settings**, **File Browser**, **DReader**, **Library**, **BookTranslator** and the **Internet Browser**. Hidden app pins are preserved and return when the switch is disabled.

## Splitscreen feedback

The split divider now updates both pane sizes and the visible divider while it is dragged. Each changed drag position requests a bounded `fast` E-Ink refresh and yields to the display controller; the final position is persisted when the finger is released.

## Verification

The release was checked with Lua 5.1 syntax validation, byte-identical root/package mirrors, the AppDock DApp regression suite, Simple-Mode configuration and UI contracts, live split refresh behavior, compact geometry, lifecycle handling and formatting validation.
