# AppDock 6.0.5 — Fixed Bounds

## Critical layout correction

AppDock 6.0.5 replaces the fragile internal text-overlap arrangement used by the main fixed-height cards and rows. The affected controls now use a shared `FixedStack` foreground container. It draws only after the enclosing `FrameContainer` background and clamps every text or icon position to the exact width and height of that visible surface.

This is deliberately different from a further spacing tweak. It makes text placement independent of KOReader's platform-specific widget metric variation and prevents a child label from being painted outside its own card or below a later internal background layer.

## Affected standard surfaces

- Settings rows and action chips
- Open Apps cards and navigation controls
- Quick Settings tiles and notification rows
- Homescreen information cards, app labels and search controls
- AppStore controls and catalog cards
- Files rows and toolbar controls
- Browser toolbar controls

All fixed one-line controls above explicitly disable `TextWidget` vertical padding before their glyph size is used for positioning.

## Scope and compatibility

- **Simple Mode is unchanged.** Its independent reduced Homescreen and Quick Settings layouts do not use the new expressive layout path.
- No remote content, DApp permission, file-handler or workspace behavior changed.
- The package includes matching root and `appdock.koplugin/` copies of every altered core module.

## Verification completed before release

- Lua 5.1 syntax validation for all Lua files
- Core DApp regression suite against source and installable package
- Browser regression suite against source and installable package
- New direct test that attempts to draw children beyond every edge of a fixed card and confirms that they are clamped inside it
- Source contracts requiring the affected standard controls to use the fixed-bounds container
- Package-mirror byte comparison and whitespace validation

## Hardware follow-up requested

Please fully restart KOReader after installing 6.0.5, then send screenshots of Settings, Homescreen, AppStore, Quick Settings and Files. This final display check is intentionally kept open because the report must be confirmed on the reader hardware that exposed the issue.
