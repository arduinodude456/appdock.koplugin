# AppDock 8.1.0

A homescreen and account update focused on the Android-inspired setup flow, app organization, and device migration.

- Repairs the new setup wizard entry in Settings and makes its multi-step dialog flow resilient to E-Ink redraws and modal transitions.
- Adds a bundled default homescreen wallpaper for first-time setup.
- Adds Android-style app groups: one homescreen-sized tile can contain multiple apps.
- Adds TBS account registration and recovery-code migration between readers, with compact settings sync and an installed-app manifest.
- Requires a TBS account to open AppStore, YouTube, YouTube Music, and DockUpdate.
- Keeps reader-specific files and paths, books, DChat messages, lockscreen secrets, and server keys out of TBS cloud snapshots. App installs on a new reader remain individually confirmed.
- Adds the TBS Supabase migration and Edge Function. TBS cloud features require the operator to apply the SQL migration and deploy the `tbs-account` Edge Function to the existing DChat Supabase project first. See [`TBS_SUPABASE_EINFACH.md`](TBS_SUPABASE_EINFACH.md).
- Updates DockUpdate's allowlist so it can install the new AppDock modules and the static default wallpaper.
