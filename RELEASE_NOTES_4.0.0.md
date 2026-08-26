# AppDock 4.0.0 „Bueno“

AppDock 4.0.0 „Bueno“ is a limited-edition core release centered on an **opt-in Plugin-in-DApp Beta**. It narrows the gap between AppDock DApps and normal KOReader plugins without claiming to virtualize arbitrary foreign plugin interfaces.

## Plugin-in-DApp Beta

Enable the beta in **Settings → Display → Beta features → Run plugin tiles in AppDock hosts**. It is disabled by default. When enabled, a supported plugin tile opens an AppDock-managed session that remains visible in **Open apps** and provides the plugin’s published main-menu actions inside a local AppDock pane.

| Plugin capability | AppDock behavior |
|---|---|
| `buildAppDockPane(context)` is implemented | The plugin renders its own local pane inside the AppDock host. The context provides local pane geometry, E-Ink refresh helpers, and `context.notify(...)`. |
| No pane contract is implemented | AppDock shows a local action-host fallback using the plugin’s published `addToMainMenu(menu_items)` entries. Existing callbacks retain their no-argument contract. |
| Plugin uses its own normal KOReader dialog or screen | AppDock leaves that UI under the plugin’s control. It does not globally capture, replace, or claim to embed arbitrary third-party dialogs. |

The beta works only with already activated plugins that publish a launchable KOReader main-menu action. It adds no network access, shell execution, driver control, or background permissions.

## Split screen is intentionally unavailable

Plugin-host sessions are marked **Plugin host · Beta** in Open Apps and cannot enter split screen. The long-press UI omits the split action, the split picker excludes plugin hosts, and the low-level split path rejects them again defensively. AppDock’s own DApps and eligible Store DApps retain their existing split-screen behavior.

## AppDock notifications

A cooperating plugin pane can call `context.notify({ title, message, priority, source })`. The message enters AppDock’s local persistent inbox and uses the existing AppDock toast, subject to its normal field and retention limits. Plugin-host launch failures, unavailable menu actions, and blocked split attempts also use that AppDock notification path.

> AppDock does not globally intercept arbitrary existing plugin pop-ups. A normal plugin that has not adopted the optional pane contract may still open its own KOReader dialog or view. This is an intentional compatibility and safety boundary, not a device-level notification system.

## Verification

The release adds regression coverage for the disabled legacy launch path, opt-in plugin-host activation, an actual cooperative local pane, the safe action-list fallback, AppDock notification routing, Open Apps labeling, every split-screen rejection layer, and cleanup of closed transient plugin-host sessions. The existing full Lua 5.1 syntax and AppDock regression suite also passed.
