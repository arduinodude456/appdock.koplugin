# AppDock 6.0.6 — Setup Wizard

## Optional guided setup

AppDock 6.0.6 adds a short, local setup wizard. It is offered once after installing a new AppDock version and remains available at **Settings → Other → Setup wizard** whenever you want to review the choices again.

The wizard has three concise, E-Ink-friendly steps. You may keep the full AppDock interface or explicitly enable the existing Simple Mode; decide whether the normal homescreen should show an optional local app search field; and decide whether AppDock should restore explicitly permitted local DApps after a KOReader restart. Every step may be skipped and no option changes unless its corresponding action is selected.

## Safe update behavior

The offer status and completion status are stored locally with the current AppDock version. Selecting **Later** prevents repeat automatic prompts for that particular version but does not remove the Settings entry. Completing the wizard prevents another automatic prompt for that version. A future AppDock release can offer the assistant once again by advancing its local assistant-version marker.

The wizard does not fetch data, change documents, restore browser pages, grant DApp permissions, or enable workspace restoration without an explicit selection.

## Compatibility

Simple Mode remains its separate reduced layout path. The `Fixed Bounds` text-and-surface layout correction from 6.0.5 remains unchanged.

## Verification completed before release

Lua 5.1 syntax validation, the new setup-assistant update/finish/restart regression against source and package, the Core DApp suite, the Browser suite, byte-for-byte root/package mirror checks, archive structure, SHA-256 and a fresh public download check all passed.

## Hardware follow-up requested

After installation, fully restart KOReader once. Confirm that the update offer appears only once, that **Later** does not reappear after another restart, and that **Settings → Other → Setup wizard** always starts it again. Please also confirm that selecting **Skip this step** leaves the current Simple Mode state unchanged.
