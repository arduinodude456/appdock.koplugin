# AppDock 7.6.1

## Hotfix: App-Verschieben im Homescreen-Editor

Fixes a crash when moving pinned apps in the homescreen editor. The app-order helper is now loaded at plugin scope, where `AppDock:movePinned()` can access it. A regression test exercises the real `movePinned` method and verifies persistence of the new order.
