# AppDock Performance-Update

Keine Funktion und keine Grafik wurde entfernt oder verändert. Alles unten sind reine Beschleunigungen.

- **Bild-Cache (größter Effekt):** Der Cache für dekodierte Logos/Hintergrund fasste nur 6 Bilder, der Homescreen braucht aber ~10 Logos + Hintergrund. Bei jedem Seitenwechsel, jeder Suche und jedem Widget-Refresh wurden PNGs neu von Flash dekodiert. Jetzt: echter LRU-Cache mit Speicherbudget (24 MB, max. 96 Einträge).
- **Start:** Die zwei Boot-Frames sind unverändert, die Pausen sind aber kürzer (2,0 s → 1,1 s). In der Wartezeit werden Homescreen, Tastatur, DApp-Dienst und Schnelleinstellungen schon vorgeladen.
- **Theme:** Palette und aktives Design werden gecacht (vorher pro Kachel mehrfach neu berechnet, inkl. Hex-Validierung). Änderungen am Theme/Design/Kontrast/Farbmodus werden sofort erkannt.
- **Zeichnen:** Gestrichelte Naht (HeroBackdrop) wird nur noch einmal berechnet, Benachrichtigungs-Zähler pro Kachel in einem Durchlauf statt pro Kachel.
- **Sortierungen:** App-Listen sortieren mit vorberechneten Kleinbuchstaben-Schlüsseln.
- Logo-Dateiprüfung (`io.open`) nur einmal pro Logo.
