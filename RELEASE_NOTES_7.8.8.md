# AppDock 7.8.8

## Deutsch

### Framebuffer-Crash endgültig behoben

Der vollständige Stacktrace zeigte die konkrete Ursache in `framecontainer.lua:55`: Der schwarze Füllbalken des Helligkeitsindikators war ein `FrameContainer` ohne Kind. KOReader rief deshalb `self[1]:getSize()` auf einem leeren Container auf.

Der Füllbalken besitzt jetzt ein echtes `HorizontalSpan`-Kind. Damit ist der Container gültig und der Fehler `attempt to index a nil value` beim Drücken der Blättertasten beseitigt.

### Qualitätssicherung

- Lua-Syntax aller Plugin-Dateien geprüft.
- Keyboard-, AppStore-, Browser-, DApp-, Ordering- und Setup-Assistant-Regressionstests erfolgreich ausgeführt.

## English

### Framebuffer crash definitively fixed

The complete stack trace identified the exact cause at `framecontainer.lua:55`: the black fill bar of the brightness indicator was a `FrameContainer` without a child. KOReader therefore called `self[1]:getSize()` on an empty container.

The fill bar now has a real `HorizontalSpan` child. The container is valid and the `attempt to index a nil value` error when pressing page keys is fixed.

### Quality assurance

- Lua syntax checked for all plugin files.
- Keyboard, AppStore, Browser, DApp, ordering, and setup-assistant regression tests pass.
