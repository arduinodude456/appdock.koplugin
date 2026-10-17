# AppDock 8.2.7

Element-Hintergründe in Sleepscreens unterstützen jetzt Transparenz.

Im Editor kann die Deckkraft eines Element-Hintergrunds zwischen 0 % und 100 % eingestellt werden. Das deklarative Format verwendet dafür `background_alpha` zwischen `0` und `1`; bestehende Presets ohne dieses Feld bleiben vollständig opak. Auf farbfähigen Geräten wird die Deckkraft über den RGB-Blending-Pfad gerendert, während monochrome Geräte den kompatiblen Graustufen-Fallback behalten.
