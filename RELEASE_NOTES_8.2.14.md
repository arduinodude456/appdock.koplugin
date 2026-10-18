# AppDock 8.2.14

## Vollständige, transparente TextBoxen

Nicht editierbare mehrzeilige Texte aus TextBoxWidget werden jetzt ohne deckende weiße Rechtecke auf die bereits gezeichnete Fläche komponiert. Die Glyphenmaske erhält KOReaders Schriftglättung und funktioniert auch mit weißer Schrift, RGB-Themes und Inversions-/Nachtmodus. Native Layout- und Ressourcenverwaltung bleiben erhalten; globale KOReader-Widgetklassen werden nicht verändert. Für interaktive Sonderfälle und ältere Blitbuffer-Builds bleibt ein sicherer nativer Pfad mit passender Hintergrundfarbe erhalten. Einzeilige TextWidget-Beschriftungen bleiben unverändert.

Der AppDock-DApp-Manager stellt die lokale Komponente Store-DApps optional bereit. Das zugehörige DApps-Update nutzt sie in DChat, AI Chat, DReader, RSS Reader, Dex Document und DockUpdate; ältere AppDock-Hosts bleiben durch explizite Flächenfarben kompatibel.

## Prüfung

Pixel-Regressionen decken weiße und farbige Glyphen, Antialiasing, Leerraum, fehlende Kompositoren, Ressourcenzustände und globale Klassen-Unverändertheit ab. KOReaders echte Mono-/RGB-Blitbuffer sowie Inversion wurden zusätzlich geprüft. Der generische Gesamtlauf enthält weiterhin bereits zuvor bestehende Testprobleme in einem Store-Hook, YouTube/YouTube Music und Gmail. Physische E-Ink-Hardware wurde nicht getestet.
