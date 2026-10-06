# AppDock 7.5.1

## AppDock Store identity

- Replaced the external Play mark and “Google Play” wordmark in the store header with AppDock’s existing AppStore logo and the **AppDock Store** wordmark.
- Updated the AppStore regression test to require the AppDock identity and reject the old external branding.
- Clarification: current catalog rows use the catalog-declared AppDock logo kind and AppDock’s logo renderer; they do not currently load per-app PNG artwork directly from the remote catalog. The logo renderer can use bundled PNG assets for supported built-in logo kinds, with a procedural fallback when no bundled image exists.
