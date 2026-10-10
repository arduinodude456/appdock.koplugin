# AppDock 7.9.0 — Draw, YouTube-Farbe und Dialoge

## Neu in 7.9.0

- **Eigene AppDock-Dialoge:** Auswahl-, Eingabe-, Bestätigungs- und Statusdialoge der AppDock-Oberfläche verwenden jetzt ein gemeinsames, kontrastreiches AppDock-Overlay. WLAN-Schaltvorgänge zeigen AppDock-eigenen Verbindungsstatus statt KOReaders transienter Ein-/Ausschalt-Popups.
- **Optionale YouTube-Farbwiedergabe:** Der neue BRC2-Framepfad nutzt eine feste Palette aus Weiß, Schwarz sowie reinem Rot, Grün und Blau. Geordnetes Dithering kann räumlich zwischen diesen Palettenfarben wechseln; RGB-Mischpixel werden nicht ausgegeben. Monochromes BWR1/BWR2 bleibt abwärtskompatibel.
- **Draw-DApp:** Schnelle Zeichenfläche mit Stift, Radierer, vier Pinselgrößen, Linie, Rechteck, Kreis, Füllwerkzeug und bis zu sechs Ebenen.
- Zeichnungen lassen sich als begrenztes, nicht ausführbares `.adraw`-Projekt speichern und laden oder über ein bereits vorhandenes `ffmpeg` als JPEG exportieren.
- Optionales Dithering für die fünf reinen Farben. Druck- und Stylus-Tastenfelder werden genutzt, sofern KOReader sie im Eingabeereignis bereitstellt; Geräteunterstützung variiert.
- Bestehende Installationen erhalten Draw bei der Layoutmigration einmalig als Launcher-Kachel hinter YouTube. Eine später manuell entfernte Kachel wird nicht erneut angelegt.

## Umfangsgrenze

AppDock-eigene Oberflächen verwenden nun AppDock-Dialoge. Eigenständige Ansichten und Dialoge, die KOReader selbst oder fremde Plugins außerhalb der AppDock-Oberfläche öffnen, bleiben unter deren Kontrolle; AppDock verändert diese nicht global.
