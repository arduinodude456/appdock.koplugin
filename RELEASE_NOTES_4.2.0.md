# AppDock 4.2.0 — Navigation

## Adjustable split screen

Split screen now includes a visible horizontal divider. Drag the divider up or down to resize both DApp panes. AppDock maintains safe minimum pane heights and saves the final valid divider position for the next split-screen session.

## Android-style system navigation

The three system actions have moved out of the top-left title area. **Home**, **Open Apps**, and **Close** are now grouped in a centered navigation bar at the bottom of every DApp host. The DApp content region ends above this bar, so its controls do not overlap running DApps.

## Validation

The core regression suite covers the lower navigation placement, drag and release gestures, bounded resizing, persistence, active DApp continuity, root/package mirror equality, and Lua 5.1 syntax.
