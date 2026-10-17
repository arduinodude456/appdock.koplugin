# AppDock 8.2.2

A bug-fix release for publishing Sleep-Screen presets.

- Fixes publication failures caused by ambiguous PostgreSQL column references in the `tbs_publish_sleepscreen` RPC.
- Adds an additive Supabase migration to repair databases where the original Sleep-Screen migration was already applied.
- Updates the deployment guide with the migration order and clarifies that public catalog availability does not confirm that private publishing is configured correctly.
