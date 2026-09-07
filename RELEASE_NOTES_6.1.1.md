# AppDock 6.1.1 — Grid Editor Crash Fix

AppDock 6.1.1 fixes a lifecycle crash that could occur while editing the App Grid. The custom switch renderer now reuses stable widget objects instead of creating native drawing containers during every paint pass.

The button feedback path is synchronous and no longer schedules a delayed callback that can run after the grid editor popup has been closed. This avoids accessing destroyed UI resources during popup refresh and prevents the `pthread_mutex_lock called on a destroyed mutex` abort reported on Android.

The release also synchronizes the shared UI fix into the VideoPlayer plugin and passes Lua 5.1 syntax validation.
