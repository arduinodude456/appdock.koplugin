# AppDock 2.0.0

AppDock 2.0.0 is the stable release following the tested 2.0.0-beta.1 and 2.0.0-beta.2 hardware pre-releases.

## Included

- Storage settings category with a real, bounded overview of AppDock and KOReader data usage and an E-Ink-friendly proportional visualization.
- Launcher layout controls for app spacing and logo shape: Rounded Box or Circle.
- Optional beta App Search on the homescreen.
- Optional automatic AppDock homescreen display when KOReader starts.
- German/English AppDock UI language selection using KOReader's language API and restart handling.
- Custom AppDock themes, DApps, Store Widgets, AppStore catalog updates, DockUpdate support, Files, NightLua, Draw, Calc, Calendar, RSS Reader, browser, help, and existing multitasking functionality.
- Library launch redraw fix and the previously tested E-Ink regional refresh behavior.

## Compatibility

The existing DApp and Store Widget contracts remain compatible. DReader is maintained separately and is available as DReader 2.0.1 in the DApps repository; its HTML image and contrast fixes do not require an AppDock core update.

## Release boundary

This release is based on real-device testing of the two pre-releases. The separately requested Splitscreen bug fix is not included in this release. DReader 2.0 functionality is also delivered separately through the DReader DApp rather than by changing the AppDock core.

After installation, restart KOReader so all core modules are loaded. Existing user settings are migrated conservatively and new launcher options default to their previous-safe behavior: AppDock startup is disabled and App Search is optional.
