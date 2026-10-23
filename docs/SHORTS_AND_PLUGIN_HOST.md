# Shorts und einheitliches Plugin-Hosting

Die Änderungen betreffen den installierbaren Code in `appdock.koplugin/`. Die älteren Lua-Kopien im Repository-Hauptverzeichnis bleiben unverändert. Es wird kein neues Release veröffentlicht und keine Installation auf einem Reader automatisch durchgeführt.

## YouTube Shorts

Der Feed hat getrennte Bereiche für Themen und Werkzeuge, das Video, Titel und Kanal sowie die Wiedergabesteuerung. Die Geometrie richtet sich nach dem zugewiesenen Pane; ein Videoframe kann Titel und Schaltflächen nicht mehr übermalen.

**Previous**, **Play/Pause** und **Next** sind direkt beschriftet. Ein Tipp auf das Video steuert ebenfalls die Wiedergabe. Nach oben wischen wechselt zum nächsten Short, nach unten zum vorherigen. Am ersten Eintrag springt „Previous“ nicht mehr überraschend an das Feed-Ende.

**Topics** wählt Hashtags, **Reload** lädt einen neuen Feed, **Tools** öffnet die vorhandene Werkzeugverwaltung, und **Like** bleibt ein lokales Empfehlungssignal. Die frühere „Share“-Schaltfläche, die lediglich die Themenauswahl öffnete, entfällt. Lade-, Fehler- und Leerzustände erläutern den nächsten sinnvollen Schritt.

Die KOReader-Gestenargumente und die Canvas-Positionierung sind korrigiert. Vorladen gehört jetzt eindeutig zu einem Feed und Videoeintrag. Schnelle Wechsel übernehmen einen passenden laufenden Prefetch oder brechen einen nicht mehr passenden Download ab. Ein verspäteter Abschluss darf keinen neuen Feed überschreiben oder das falsche Video starten. „Skip“ wird dem verlassenen Video zugeordnet, nicht seinem Nachfolger.

Fortschritts-Neuaufbauten erhalten den aktuellen Player. Tatsächliches Verlassen stoppt die Inline-Wiedergabe und die Feed-Suche; eine Konvertierung kann weiterlaufen, startet das Ergebnis aber nicht in einer unsichtbaren Oberfläche. Fehlerjobs blockieren die nächste Wiedergabe nicht dauerhaft. Der indeterminierte Suchbalken aktualisiert sich sparsam statt zehnmal pro Sekunde.

yt-dlp kann bei Shorts-Tab-Ergebnissen `original_url` als `NA` oder als Playlistadresse ausgeben. Ausschließlich bei einer ausdrücklich gestarteten Shorts-Tab-Abfrage wird deshalb die validierte Video-ID auf eine kanonische `/shorts/<id>`-Adresse abgebildet. Der allgemeine Parser bleibt ohne diesen Quellenkontext strikt.

## Normale KOReader-Plugins

Plugin-Kacheln starten immer eine AppDock-Sitzung, auch wenn eine ältere Installation `beta.plugin_dapp_host = false` gespeichert hat. Der Schalter ist nicht mehr abschaltbar. Die Sitzung nutzt AppDocks Kopfzeile, Navigation, Farbpalette und lokale Layout-Geometrie und bleibt in **Open apps** sichtbar.

Veröffentlichte Menüaktionen, dynamische Untermenüs, Informationsmeldungen, Bestätigungen und einfache Texteingaben werden als AppDock-Oberflächen dargestellt. Mehrstufige Menüs behalten ihren Rückweg. Bestätigungsaktionen und Eingabetext werden an die ursprünglichen Plugin-Callbacks weitergereicht. Weitere veröffentlichte Aktionen bleiben auch bei längeren Aktionslisten erreichbar.

Die UI-Brücke gilt nur während eines zugeordneten Plugin-Aufrufs und wird auch nach Fehlern wieder entfernt. Aus diesem Aufruf geplante `nextTick`- und `scheduleIn`-Fortsetzungen betreten die Brücke erneut und dürfen eine geschlossene oder fremde Sitzung nicht übernehmen. Die normale KOReader-Oberfläche und direkt außerhalb AppDocks gestartete Plugins werden nicht global umgestaltet.

Kooperierende Plugins mit `buildAppDockPane(context)` erhalten `context.palette`, `context.theme`, Text-/Kontrastrollen, Abstände und lokale Pane-Maße. Ereignisse und Lebenszyklusaufrufe ihres Pane bleiben dem AppDock-Host zugeordnet. Öffnen und Schließen können über `onAppDockHostOpened(context)` und `onAppDockHostClosed(context)` angebunden werden.

Unbekannte, nicht sicher adaptierbare Spezialoberflächen werden nicht separat geöffnet. Stattdessen zeigt AppDock eine interne Kompatibilitätsmeldung. Das verhindert den Wechsel in eine eigenständige Plugin-Oberfläche, ersetzt aber nicht automatisch sämtliche Funktionen einer beliebigen Spezial-UI. Für solche Oberflächen ist ein kooperierendes Pane oder ein zusätzlicher Adapter erforderlich. Plugin-Hosts bleiben vorerst von Splitscreen und Floating Windows ausgeschlossen.

Bereits aktivierte Plugins laufen weiterhin als vertrauenswürdiger Lua-Code im KOReader-Prozess. Die Brücke ist ein Darstellungs- und Lebenszyklusvertrag, keine Sicherheits-Sandbox für beliebigen Fremdcode oder dessen außerhalb AppDocks gestartete Hintergrundarbeit.

## Prüfen

Der portable Runner `bash scripts/test_appdock_ui.sh` prüft die Syntax aller installierbaren Lua-Module und die DApp-, Shorts-/YouTube-, YouTube-Music-, Dialog-, Setup-, Theme-, Gruppen-, Manager-, Tastatur- und Text-Regressionssuiten. Die YouTube-Suite konvertiert mit FFmpeg einen lokal erzeugten Testclip und prüft die BWR-Ausgabe, ohne echte YouTube-Videos herunterzuladen. GitHub Actions führt denselben Runner für relevante Pull Requests und Änderungen an `main` aus.

Die bisherigen Testfixtures für Bluetooth, Setup-Schritte, Versionsmigration und Bestätigungsdialoge wurden an die bereits vorhandenen Produktionsverträge angepasst; Produktionsverhalten wurde nicht zur Erfüllung veralteter Testannahmen zurückgebaut.

Ein Test auf einem physischen KOReader-/E-Ink-Gerät sowie eine Live-Abfrage gegen YouTube stehen weiterhin aus. Die lokalen Tests ersetzen insbesondere keinen gerätespezifischen Touch-, Schrift-, Refresh- oder Audioabgleich.
