# AppDock 9.1.4 — ColorRGB32 Cache Fix

AppDock 9.1.4 behebt den tatsächlichen Absturz beim Öffnen der Quick Settings. Auf bestimmten KOReader-/Android-Geräten löste der Vergleich eines nativen `ColorRGB32`-Werts mit `nil` dessen fehlerhaften `__eq`-Operator aus. Der Glass-Farbcache verwendet nun einen typensicheren Nil-Check und vermeidet diesen nativen Vergleich vollständig.
