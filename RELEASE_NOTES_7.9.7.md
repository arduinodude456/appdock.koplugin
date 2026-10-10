# AppDock 7.9.7

## Schnellere E-Ink-Videoerstellung

- Der normale FFmpeg-1-Bit-Pfad skaliert jetzt mit `fast_bilinear`, weil die anschließende Monochrom-Reduktion den Mehrwert von Lanczos nicht nutzt.
- Die Konvertierungs-Schleife verarbeitet größere, weiterhin zeitlich begrenzte Batches. Dadurch bleibt die Bedienoberfläche responsiv, ohne schnelle Encoder künstlich auszubremsen.
- Die BRC2-Farbkonvertierung vermeidet eine vollständige RGB-Kopie pro Frame und nutzt vorberechnete, phasenspezifische FFI-Tabellen für die bestehende 8×8-Ditherung. Palette, Auflösung, FPS und Ausgabeformat bleiben kompatibel.
- Bei FFmpeg-`monow`-Inversion arbeitet der BWR2-Encoder wortweise statt byteweise.

## Oberfläche und Stabilität

- AppDock-eigene Dialoge erhalten einen kontrastreichen Kopfbereich, einen ruhigen E-Ink-Hintergrund, klarere Primäraktionen, sichtbare Seitennavigation und sichere zweispaltige Aktionsreihen.
- AppDock-Benachrichtigungen verwenden das gleiche Kartenprinzip mit separatem Titelbereich und lesbarem Nachrichtentext.
- **Draw** startet auch dann sicher, wenn ein Gerät beim frühen Bildschirmaufbau ungültige Größen oder Skalierungswerte liefert. Die Zeichenfläche nutzt begrenzte Fallback-Geometrie statt durch Null- oder Nilwerte abzubrechen.

## Beta: Fenster für DApps

Unter **Settings → Display → Beta features** kann **Open apps as movable, resizable windows** aktiviert werden.

1. In **Open apps** eine DApp lange gedrückt halten.
2. **Open as window · Beta** wählen.
3. Die Titelzeile ziehen, um das Fenster zu verschieben; den Griff unten rechts ziehen, um die Größe zu ändern.

Nur reguläre DApps verwenden diesen Modus. Plugin-Hosts bleiben ausgeschlossen. Die letzte Fenstergeometrie wird lokal pro DApp gespeichert. DApps erhalten dabei dieselbe flexible lokale Pane-Geometrie wie im Splitscreen.

## Blättertasten

Die Blättertasten ändern nun die Helligkeit auch in DApps, Fenster-DApps, Open Apps, dem Recent-Apps-Drawer und Quick Settings. Das bisherige Gedrückthalten bleibt erhalten: obere/zurück-Taste öffnet das Power-Menü, untere/vorwärts-Taste startet den lokalen Bildschirmschoner.

## Tests

Die Regressionstests decken BWR/BRC2, die YouTube-Konvertierung, Dialoge, Draw, DApp-Hosts und die neue Fenstergeometrie ab.
