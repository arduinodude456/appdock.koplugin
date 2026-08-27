# AppDock 4.4.0 — AppStore Designs

AppDock 4.4.0 introduces **Designs** as a new AppStore category. A design is a complete visual preset rather than a single highlight color. It can set the highlight, background, button, text and quick-settings dropdown colors; an optional local homescreen background image; a rounded or 3D button style; and round or rounded app-logo tiles.

Designs are intentionally **declarative data**. AppDock validates their fixed fields and optional local PNG, JPG, JPEG or WEBP background path, but never loads or executes a design as Lua code. Installing, updating, reactivating and removing a design always requires explicit confirmation.

The first two example designs are available in AppStore under **Category: Designs**:

| Design | Visual direction | Controls |
|---|---|---|
| **Galaxy** | Deep indigo space field with a restrained violet nebula | 3D buttons and circular app-logo tiles |
| **Forest** | Calm moss-green forest layers with diffuse morning light | Rounded buttons and rounded app-logo tiles |

An installed design activates immediately. Tap its **Use** action to activate it again later. The new **Settings → Display → Store design** row shows the active design and offers **Use personal appearance** to return to the existing theme, launcher-shape and personal wallpaper settings. Uninstalling the active design also returns to that appearance and removes its local design files.

## Compatibility and verification

AppDock continues to use the established grayscale fallback palette on monochrome E-Ink devices. The 4.4.0 package was checked with Lua 5.1 syntax validation, root/package mirror comparison, AppStore manifest and category-filter regression tests, active-design style checks, existing Simple Mode and live-split tests, archive integrity validation and a fresh release download check.
