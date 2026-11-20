# AppDock 9.9.0

## Deutsch
- **Neu:** Liquid-Glass-Uhr mit echten Glas-Ziffern. Die Ziffern selbst sind das Glas (Brechung des Hintergrunds an den Kanten, heller Lichtrand, Schatten) statt einer Glaskarte dahinter. Ein eigenes Modul (`appdock_glassclock.lua`) berechnet das einmal pro Uhrzeit und zeichnet danach nur noch ein fertiges Bild. Schlägt das fehl, bleibt die Uhr als schlichte weiße Schrift lesbar.
- **Neu:** Standby beim Laden. Am Ladegerät fragt AppDock, ob der eReader in den Standby gehen soll. Der Standby ist der Sperrbildschirm mit sehr großer Uhr (Stunden über Minuten, in allen drei Uhrenstilen), Datum und Akkustand; die Uhr aktualisiert sich jede Minute. Antippen oder Abziehen des Ladegeräts beendet ihn. Einstellungen > Sperrbildschirm > Standby: fragen, automatisch oder aus. Beim Lesen wird nicht gefragt.
- **Fix:** Die Textvorschau der Tastatur verschwand bei breiten Zeichen hinter dem rechten Rand, weil die Breite nur geschätzt wurde. Sie wird jetzt mit der echten Textbreite gemessen, der Cursor bleibt immer sichtbar.

## English
- **New:** Liquid Glass clock with real glass digits. The digits themselves are the glass (the wallpaper refracts at their edges, bright rim light, drop shadow) instead of a glass card behind them. A dedicated module (`appdock_glassclock.lua`) renders it once per time and only blits the finished bitmap afterwards. If that fails, the clock stays readable as plain white text.
- **New:** Standby while charging. When the charger is plugged in, AppDock asks whether the eReader should go to standby. Standby is the lockscreen with a very large clock (hours above minutes, in all three clock styles), the date and the battery level; the clock updates every minute. Tapping or unplugging the charger ends it. Settings > Lockscreen > Standby: ask, automatic or off. It does not ask while a book is open.
- **Fix:** The keyboard text preview could disappear behind the right edge with wide characters because its width was only estimated. It is now measured with the real text width and the cursor always stays visible.
