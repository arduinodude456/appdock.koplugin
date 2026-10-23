# AppDock 8.2.23 — YouTube Shorts Feed

Die YouTube-Shorts-DApp nutzt jetzt ausschließlich Einträge aus echten YouTube-Shorts-Tabs. Sie akzeptiert nur kanonische URLs im Format `/shorts/<Video-ID>`; eine Suchanfrage nach `#shorts` oder eine bloße Laufzeitgrenze reicht nicht mehr aus.

Die Oberfläche ist als vertikaler Feed ausgelegt. Tippen startet oder pausiert den aktuellen Short. Ein Swipe nach oben öffnet den nächsten Eintrag, ein Swipe nach unten den vorherigen. Die Aktionen für Like, Next und Themen bleiben direkt im Feed sichtbar.

Likes bleiben lokal auf dem Gerät gespeichert. Sie erfassen die Creator-ID und Hashtags des Shorts und ergänzen dadurch spätere Feed-Quellen. Eigene Hashtags werden als eigene Shorts-Tabs abgefragt. Während ein Short läuft, wird der nächste Eintrag als expliziter Hintergrundjob geladen; er ersetzt weder die sichtbare Wiedergabe noch startet er eine zweite Konvertierung.

Beim Schließen der DApp werden Suche, Vorabruf und Player sauber beendet. Neu- und Bestandsinstallationen erhalten die Shorts-Kachel einmalig neben YouTube. Die YouTube- und Shorts-Regressionstests laufen nun auch in GitHub Actions.
