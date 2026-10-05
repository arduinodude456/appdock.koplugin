# AppDock 7.3.6 — Logo-Region Refresh

Der bestehende horizontale Homescreen-Seitenwechsel behält seine Bewegung und sein Timing, aktualisiert während der Animation aber nicht mehr den gesamten Grid-Bereich. Für jede alte und neue App-Kachel werden ausschließlich die einzelnen Logo-Rechtecke als schnelle E-Ink-Refresh-Regionen angefordert.

Seitenpfeile und Seitenzähler werden nicht als Logo-Regionen behandelt. Header, Widgets, Hintergrund und Quick-Access-Dock bleiben unverändert. Der bestehende Abschluss-Refresh nach der Motion bleibt erhalten, damit die finale Darstellung sauber synchronisiert wird.
