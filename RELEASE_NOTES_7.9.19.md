# AppDock 7.9.19

## Draw: RGB-Anzeige und Pinselstärke

Draw sendet Farbpixel nun über KOReaders `paintRectRGB32`-Framebufferpfad – wie die funktionierende Minecraft-DApp. Die Farberkennung berücksichtigt sowohl die Farbfähigkeit des Displays als auch KOReaders aktivierte Farbwiedergabe.

Die ausgewählte Pinselgröße wird nicht mehr durch die Canvas-Skalierung auf einen Pixel reduziert. Instabile Druckwerte von Fingereingaben verändern die Strichdicke nicht; explizite Drucksensitivität bleibt für Stylus-Eingaben verfügbar. Pinselstempel verwenden nun die gewählte Durchmessergröße.

## Tests

Alle 13 AppDock-LuaJIT-Regressionstests laufen durch. LuaJIT-Bytecodeprüfung und `git diff --check` sind sauber.
