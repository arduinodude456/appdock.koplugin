# AppDock 4.1.1 „Bueno"

AppDock 4.1.1 improves the opt-in **Plugin-in-DApp beta host**. When a hosted plugin action synchronously opens a standard menu, confirmation dialog, information message, or input dialog, AppDock now captures the widget request and presents it as a local AppDock overlay inside the active plugin host.

For text entry, the overlay shows the current value and opens an AppDock-created text editor. Saving transfers the value back to the original plugin dialog object, so existing plugin callbacks can still read it through their normal interface. Dynamic Text editor-style menus continue to use the local adapter; AppStore-style direct actions retain their existing launch behavior.

This is a compatibility bridge, not a global replacement of KOReader's widget framework. Complex standalone plugin windows, asynchronously created third-party widgets, and plugins that bypass the hosted action path remain outside the bridge and may continue to use their own UI. Plugin hosts still cannot enter split screen.

## Verification

- All twelve existing AppDock Lua regression scripts pass under Lua 5.1.
- Plugin-host regressions cover dynamic Text editor menus, AppStore-style actions, standard dialogs, information messages, input-dialog capture, callback preservation, host return, and split-screen rejection.
- Package and root module mirrors are verified byte-for-byte before packaging.
