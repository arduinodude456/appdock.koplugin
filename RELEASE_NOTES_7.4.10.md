# AppDock 7.4.10 — Live keyboard input

## Live text entry

- The AppDock keyboard now reports every edit immediately through a live-change callback.
- AppDock-owned input flows no longer leave a KOReader `InputDialog` visible behind the AppDock keyboard.
- The original action callbacks remain compatible: `Search`, `Save`, `Unlock`, and similar actions still receive the current value when `Done` is pressed.
- The AppDock homescreen search bar now displays and filters the entered text while typing.
- Secure numeric fields remain masked.

## dChat compatibility

- dChat is integrated as an external KOReader plugin through AppDock's optional Beta plugin host, not as a built-in AppDock DApp.
- Standard dChat input dialogs captured by the host now use the same dialog-free AppDock editor and receive the value live through the original plugin input object.
- Complex standalone dChat windows that do not expose a standard KOReader input dialog remain outside AppDock's interception scope.

## Verification

- Lua 5.1 syntax validation passed for the plugin and tests.
- AppDock keyboard regression test passed, including live target updates and native-dialog closure.
- Browser regression test passed.
