# AppDock Homescreen für KOReader

**AppDock** ist ein KOReader-Plugin für einen anpassbaren Homescreen *innerhalb* von KOReader. Version **1.8.1** richtet sich gestalterisch an Android 16 und **Material 3 Expressive** aus: ein kohärentes, ruhiges Farbsystem, große gerundete Formen, betonte Informationshierarchie und schnell erfassbare Widgets. [1] [2]

> **E-Ink-Ansatz:** AppDock übernimmt bewusst die Formensprache und Informationsstruktur, nicht die Android-Animationen, Unschärfen oder Transparenzeffekte. Damit bleiben Aktualisierungen sparsam und die Darstellung auf monochromen Readern kontrastreich.

## Homescreen

| Zone | Android-16-inspirierte Umsetzung in AppDock |
|---|---|
| Systemzeile | Uhrzeit links, optionaler Akkustand rechts, ohne schwere App-Leiste. |
| Tagesbereich | Große Begrüßung und Datumszeile als klare visuelle Hierarchie. |
| Widgets | Abgerundete **Device**- und **Continue reading**-Karten sowie installierbare Store-Widgets mit großzügigem Innenabstand. |
| Apps | Einheitliches 3-Spalten-Iconraster mit großen, abgerundeten Symbolflächen und kurzen Labels. |
| Palette | Vier Material-You-artige Presets sowie selbst erstellbare Akzentfarben; auf Graustufen bleiben feste kontrastreiche KOReader-Grautöne erhalten. |
| Navigation | Zurückhaltende runde Seitenschalter erscheinen nur bei mehr als sechs angehefteten Apps. |
| Schnellzugriff | Ein gezeichnetes Dropdown mit Helligkeit, WLAN, Nachtmodus, Refresh und Editor öffnet sich über die Abwärtspfeil-Kachel in der Systemzeile. |
| DApps | Zustandsbehaftete, KOReader-interne Apps mit eigenem Pane, wiederverwendbaren grafischen Logos und eigener Open-Apps-Übersicht. |
| Periodischer Refresh | Alle 60 Sekunden fordert AppDock einen vollständigen E-Ink-Refresh an, um Geisterbilder zu reduzieren und statische Informationen sichtbar zu aktualisieren. |

Ein Antippen startet die zugewiesene Aktion. Ein Halten auf einer App-Kachel öffnet die Verwaltung. Die bestehende Plugin-App-Erkennung, das Hinzufügen und Entfernen sowie die sichere Menüausführung bleiben erhalten.

## Installation

Entpacke das Installationsarchiv und kopiere den vollständigen Ordner `appdock.koplugin` in den Plugin-Ordner deiner KOReader-Installation:

```text
…/plugins/
└── appdock.koplugin/
    ├── _meta.lua
    ├── main.lua
    ├── appdock_homescreen.lua
    ├── appdock_manager.lua
    ├── appdock_quicksettings.lua
    ├── appdock_dapps.lua
    ├── appdock_filemanager.lua
    ├── appdock_appstore.lua
    ├── appdock_theme.lua
    ├── appdock_logo.lua
    └── appdock_browser.lua
```

KOReader erkennt Pluginordner anhand der Endung `.koplugin` und erwartet darin eine `main.lua`; seine Plugin-Verwaltung durchsucht den Standardpluginpfad sowie den `plugins`-Unterordner des Datenverzeichnisses. [3]

Starte KOReader danach vollständig neu. Unter **More tools → Plugin management** muss **AppDock Homescreen** aktiviert sein. Der Einstieg lautet **AppDock Homescreen → Open homescreen**.

| Prüfschritt | Erwartetes Ergebnis |
|---|---|
| Ordnername | Endet exakt auf `.koplugin`. |
| Plugininhalt | Enthält `_meta.lua`, `main.lua`, `appdock_homescreen.lua`, `appdock_manager.lua`, `appdock_quicksettings.lua`, `appdock_dapps.lua`, `appdock_filemanager.lua`, `appdock_appstore.lua`, `appdock_theme.lua`, `appdock_logo.lua` und `appdock_browser.lua` direkt im Ordner. |
| Startansicht | Begrüßung, Datum, Widgetkarten und ein 3-Spalten-App-Raster werden angezeigt. |
| Langdruck auf Kachel | Öffnet **Manage AppDock**. |

## DApps und offene Apps

**DApps** sind AppDock-eigene Anwendungen. Anders als ein Plugin-Shortcut bleiben sie nach dem Verlassen logisch geöffnet und erscheinen in **Open apps**. Die neue Systemkachel **Open apps** entspricht der Android-Übersicht zuletzt geöffneter Apps: Ein Antippen einer Karte aktiviert die betreffende DApp, während das kleine Schließen-Symbol sie aus der Liste entfernt.

| DApp | Funktion | Besonderheit |
|---|---|---|
| **Analog Clock** | Zeigt ein gezeichnetes Ziffernblatt, Stunden-/Minutenzeiger, Digitalzeit und Datum. | Aktualisiert zum nächsten Minutenwechsel mit einem begrenzten schnellen Refresh. |
| **Settings** | Android-inspirierte Kategorienansicht für Netzwerk, Display und weitere AppDock-Funktionen. | Mini-Logos in einer Seitenleiste; WLAN, native Helligkeit/Wärme, Farbthemen, Layout, Über AppDock sowie klar markierte noch nicht implementierte Aktualisierung. |
| **Files** | Zeigt die Bibliothek in einem eigenen, scrollbaren AppDock-Dateibrowser. | Große Ordner- und Dateikarten, Ordner zuerst, **Up**, **Home** und **Refresh**; `.lua`-Dateien gehen direkt an NightLua. Nach DReader-Installation gehen `.epub`, `.html`, `.htm` und `.xhtml` direkt an DReader. Andere unterstützte Dokumente öffnen weiterhin über KOReaders sicheren ReaderUI-Pfad. |
| **AppStore** | Lädt den Katalog aus [`arduinodude456/DApps`](https://github.com/arduinodude456/DApps). | Liest nur `dapps.txt` über HTTPS; zeigt DApp- und Widget-Logos, erkennt neuere Repository-Versionen als **Update** und verlangt vor Installation, Update oder Deinstallation eine ausdrückliche Bestätigung. |
| **Web Browser** | Öffnet serverseitig bereitgestellte Webinhalte und sucht über DuckDuckGo HTML. | Startseite, Direktziele, Reload, lokale Historie und klarer Lesemodus; aktive Webinhalte bleiben deaktiviert. |
| **Help** | Offline verfügbare Bedienhilfe für AppDock. | Erläutert Homescreen, Schnellzugriff, DApps, Splitscreen, Browser und E-Ink-Refresh; auch im Splitscreen lesbar. |

Die Logo-Bibliothek umfasst jetzt **38** gezeichnete Symbole für Produktivität, Medien, Kommunikation, Daten und Navigation. Die vollständige Auswahl und die Einbindung über das Feld `logo` stehen in [`DAPP_LOGOS.md`](DAPP_LOGOS.md).

DApps bauen ihren Inhalt ausschließlich innerhalb eines vom DApp-Host zugewiesenen Pane-Rechtecks. Der Pane-Vertrag ist in einem echten Splitscreen umgesetzt: Ein gemeinsamer Host kann zwei geöffnete DApps untereinander mit klarer Trennlinie darstellen, ohne die DApps selbst umzuschreiben. Der **File Manager** behält dabei seinen aktuellen Ordner als DApp-Zustand und bleibt deshalb ebenfalls in Open apps sichtbar und splittbar. Seine Auflistung verwendet KOReaders LuaFileSystem-Schnittstelle; reguläre Dateien und Ordner werden angezeigt, nicht unterstützte Dateien ausdrücklich markiert und nicht geöffnet. Die detaillierte technische Beschreibung steht in `DAPP_ARCHITECTURE.md` und `SPLITSCREEN_DESIGN.md`. [7] [8]

## Store-Widgets

AppDock 1.8.0 unterstützt neben DApps einen getrennten Store-Widget-Vertrag. Seit **1.8.1** liegt die vollständige Store-Kartenliste in einer echten scrollbaren KOReader-Region; Einträge werden nicht mehr nach der sichtbaren Pane-Höhe abgeschnitten. Dadurch bleiben auch Weather Widget und spätere Katalogeinträge per Touch-Swipe, Seitentasten oder Scroll-Geste erreichbar. Ein Katalogeintrag mit dem vierten Feld `widget` wird nach ausdrücklicher Bestätigung als passive Homescreen-Karte installiert. Unter **Manage apps and widgets → Store widgets** kann jedes installierte Widget ein- oder ausgeblendet werden.

Ein Widget liefert über `buildWidget(instance, context)` ein KOReader-Widget und erhält ausschließlich seine lokale `context.dimen`-Geometrie. Sichtbare Widgets werden auf dem Homescreen in eigenen Karten angeordnet. AppDock prüft jede Minute, ob ein Drei-Minuten-Intervall abgelaufen ist, und baut den Homescreen anschließend regulär neu auf. Beim Verlassen des Homescreens wird dieser Timer abgemeldet. Widgets benötigen deshalb keine eigenen Hintergrundprozesse oder Android-Systemintegration.

Das Beispiel **Quote Widget** aus dem öffentlichen DApps-Repository enthält drei lokale Zitate und wechselt alle drei Minuten zu einem anderen Eintrag. Es verwendet weder Netzwerk noch Dateispeicherung.

## Themes und AppStore

In **Settings → Display → Color themes** lassen sich die eingebauten Themes **Lavender**, **Ocean**, **Forest** und **Sunset** auswählen. Über **Create custom theme** werden ein eigener Name und ein sechsstelliger Hex-Akzent wie `#4F8CC9` eingegeben. Das Theme gilt für Homescreen, DApps, Schnellzugriff und File Manager. Auf einem monochromen E-Ink-Gerät bleiben die Farben absichtlich in stabile Kontrastrollen überführt.

Der **AppStore** bezieht seine Katalogdatei aus dem öffentlichen Repository [`arduinodude456/DApps`](https://github.com/arduinodude456/DApps). Die Datei `dapps.txt` enthält pro Zeile einen eindeutigen relativen Lua-Dateipfad sowie optional eine numerische Version, ein geprüftes AppDock-Logo und den Typ `widget`, etwa `quote_widget.lua | 1.0.0 | help | widget`. Ohne das vierte Feld bleibt der Eintrag eine DApp. Beim Aktualisieren wird ausschließlich dieser Textkatalog geladen; es wird dabei kein DApp-Code ausgeführt. Erst nach sichtbarer Nutzerbestätigung lädt AppDock die gewählte Datei über HTTPS, prüft sie auf Lua-Syntax und speichert sie atomar im KOReader-Datenverzeichnis. Eine Repository-Version, die numerisch höher als die installierte DApp-Version ist, erscheint als **Update** statt als Sperrmeldung. Der Download muss dieselbe Versionsangabe deklarieren wie der Katalog, und ein Update darf die DApp-ID nicht verändern.

Jede Karte zeigt das deklarierte DApp-Logo. Bereits installierte DApps erhalten zusätzlich den Button **Uninstall**. Das Entfernen verlangt eine Bestätigung und löscht ausschließlich die installierte DApp-Datei sowie ihre AppStore-Registry; von der DApp angelegte persönliche Dokumente oder Einstellungen werden nicht gelöscht. Eine installierte DApp läuft anschließend als Lua-Code innerhalb von KOReader. Store-DApps können optional einen begrenzten `openFile(instance, path)`-Vertrag anbieten; AppDock Files nutzt ihn ausschließlich für eindeutige Dateitypen wie NightLuas `.lua`- und DReaders `.epub`/`.html`/`.htm`/`.xhtml`-Übergabe. Deshalb darf nur ein geprüftes und vertrauenswürdiges Repository verwendet werden.

> **Hinweis:** Der Katalog verwirft absolute Pfade, doppelte Einträge und Pfade mit `..`. Installierte DApps sind in der normalen AppDock-Appverwaltung und in Open Apps verfügbar.

## Web Browser

Die **Web Browser**-DApp ist ein schlanker, JavaScript-freier Browser für lesbare, serverseitig gelieferte Webseiten. Die Version-1.0-Startseite bietet klar getrennte Aktionen für **Address**, **Search**, **Back** und **Reload** sowie Direktziele für DuckDuckGo, Wikipedia, Project Gutenberg und KOReader. Nach der Navigation zeigt eine kompakte Statuszeile Seitentitel und Adresse; die dargestellte Seite lässt sich normal scrollen. Links in der HTML-Seite öffnen die nächste Seite innerhalb derselben DApp und **Back** nutzt die lokale Verlaufsliste.

| Unterstützt | Bewusst nicht unterstützt |
|---|---|
| HTTP/HTTPS, Weiterleitungen, serverseitiges HTML, DuckDuckGo HTML, relative Links, kleine lokale Historie | JavaScript, Formulare, Logins mit JavaScript, Videos, WebSockets, Downloads und Nicht-HTTP(S)-Links |

Der Browser akzeptiert ausschließlich `http://` und `https://` und verwirft etwa `javascript:`, `file:`, `data:` oder `mailto:`. Antwortgrößen und Netzwerkzeit sind begrenzt. Eine ausführliche Beschreibung steht in `BROWSER_DESIGN.md`.

## Splitscreen

Der Splitscreen arbeitet mit **zwei bereits offenen DApps**. Öffne zunächst beispielsweise **Analog Clock** und **Settings**, wechsle anschließend zu **Open apps** und halte eine der beiden DApp-Karten gedrückt. Im Kontextmenü wählst du **Splitscreen**; danach listet AppDock die übrigen offenen DApps als zweite App auf. Nach der Auswahl werden beide DApps untereinander im gemeinsamen Host dargestellt.

| Kontrolle | Wirkung im Splitscreen |
|---|---|
| **Home** | Verlässt die sichtbare Splitscreen-Ansicht und öffnet den Homescreen. Beide DApps bleiben in Open apps erhalten. |
| **Open apps** | Verlässt die sichtbare Splitscreen-Ansicht und öffnet die Übersicht der weiterhin geöffneten DApps. |
| **Schließen** | Beendet die sichtbare Splitscreen-Ansicht und wechselt zu Open apps. Einzelne DApps lassen sich dort über ihr Schließen-Symbol entfernen. |

## Schnellzugriff

Die kleine **Abwärtspfeil-Kachel** in der oberen Systemzeile öffnet eine echte, von oben ausgeklappte KOReader-Oberfläche. Sie verwendet ausschließlich gezeichnete KOReader-Widgets und kein Standard-Buttonmenü.

| Element | Wirkung |
|---|---|
| **Brightness** | Antippen oder Ziehen setzt die native Frontlight-Intensität. Bei jedem Slider-Schritt erfolgt ein schneller regionaler Refresh; danach wird die gesamte sichtbare KOReader-Oberfläche regulär als neu zu zeichnen markiert. |
| **Wi-Fi** | Schaltet WLAN über KOReaders `NetworkMgr` ein oder aus. |
| **Night** | Löst KOReaders vorhandenes `ToggleNightMode`-Ereignis aus. |
| **Refresh** | Baut die sichtbare Oberfläche neu auf und fordert eine vollständige Aktualisierung an. |
| **Edit** | Schließt die Leiste und öffnet den AppDock-Editor. |

Die Refresh-Logik kombiniert für Helligkeitsänderungen `UIManager:setDirty("all", "fast", slider_region)` mit einem normalen UI-Refresh über `UIManager:setDirty("all", "ui")`. Dadurch ist der Slider direkt sichtbar, ohne dass die darunterliegende normale KOReader-UI veraltet bleibt. Der Helligkeitsregler löst **keinen** `full`-Refresh aus; der vollständige E-Ink-Refresh erfolgt getrennt davon automatisch im 60-Sekunden-Takt. In **0.4.1** wurde zusätzlich die KOReader-spezifische Gestenargumentfolge korrigiert: Der Handler verarbeitet nun zuverlässig das zweite Argument, das die Touchposition enthält. [5] [6]

## Apps und Widgets verwalten

AppDock bietet reguläre KOReader-Plugins nur dann als Apps an, wenn sie bereits aktiviert und instanziiert sind. Dazu verwendet es die bestehende `addToMainMenu(menu_items)`-Konvention. Zusätzlich können ausdrücklich bestätigte DApps aus dem vertrauenswürdigen AppStore-Katalog installiert werden. Plugins ohne veröffentlichte Menüaktion werden nicht angeboten; der Store installiert keine Dateien ohne sichtbare Nutzerbestätigung. KOReader instanziiert aktivierte Plugins regulär im jeweiligen UI-Kontext. [3] [4]

| Einstellung | Wirkung |
|---|---|
| **Clock in status bar** | Schaltet die Uhrzeit in der oberen Systemzeile ein oder aus. |
| **Device status card** | Schaltet die Akkukarte und die Akkuanzeige ein oder aus. |
| **Current book card** | Schaltet die große Karte für das aktive Buch bzw. den Bibliothekshinweis ein oder aus. |
| **Store widgets** | Zeigt installierte Store-Widgets und schaltet jedes Widget unabhängig ein oder aus. |
| **Add / Added** | Fügt eine System- oder Plugin-App hinzu beziehungsweise entfernt sie. |

Die ersten sechs angehefteten Apps belegen die aktuelle 3×2-Seite. Weitere Apps werden auf zusätzlichen Seiten gezeigt. Die Standardkacheln **Library**, **Menu**, **History** und **Manage apps and widgets** bleiben weiterhin verfügbar.

## Kompatibilität und Grenzen

| Situation | Verhalten |
|---|---|
| Farbdisplay | Verwendet die Material-You-orientierten Akzentflächen. |
| Graustufen-E-Ink | Verwendet die gleichen Kontrastrollen in abgestuften Grautönen. |
| Plugin mit einer Aktion | Startet die Aktion direkt. |
| Plugin mit mehreren Aktionen | Öffnet zuerst einen Aktionsdialog. |
| Plugin mit tieferen Spezialmenüs | Stellt die erste Ebene als Dialog bereit. |
| Android-System-App | Wird bewusst nicht gestartet, weil AppDock ausschließlich KOReader-intern arbeitet. |
| Test auf dem konkreten Gerät | Steht noch aus; lokale Smoke-Tests und Syntaxprüfungen sind bestanden. |

## Qualitätssicherung

| Prüfung | Ergebnis |
|---|---|
| Lua-5.1-Syntaxprüfung aller Plugin-Dateien | Bestanden. |
| Kernlogik-Smoketest | Bestanden: Menüregistrierung, Plugin-Discovery, Migration, App- und Widgetverwaltung sowie Aktionen. |
| Homescreen-Layout-Smoketest | Bestanden: Widgetkarten, 3×2-Kachelraster, Kachelantippen und Seitenauswahl. |
| Schnellzugriffs-Smoketest | Bestanden: Overlayaufbau, Frontlight-Änderung, schneller Slider-Refresh, normaler UI-Refresh, WLAN, Nachtmodus und vollständiger Redraw. |
| DApp-Smoketest | Bestanden: Registry, Analog Clock, Settings, Zustandsbehaltung, DApp-Host, Recents und Schließen. |
| Splitscreen-Smoketest | Bestanden: Langdruck-Kontextmenü, Splitscreen-Aktion, Zweit-App-Auswahl, Zwei-Pane-Host, Rückkehr zu Open apps und DApp-Erhalt. |
| Refresh-/Logo-/File-Manager-Tests | Bestanden: 60-Sekunden-Timer mit Selbstneuplanung, Vollrefresh, `fast`-Sliderpfad, Logo-Integration sowie eigene Dateiauflistung, Sortierung, Ordnernavigation, Pane-Aufbau und ReaderUI-Übergabe. |
| Browser-Smoketest | Bestanden: HTTPS-Normalisierung, DuckDuckGo-HTML-Suche, Sanitierung, relative Links, Verlauf, DuckDuckGo-Weiterleitung, Startseite, Reload und Nicht-HTTP(S)-Sperre. |
| Hilfe-DApp-Test | Bestanden: Hilfe-Registry, offline scrollbarer Pane-Aufbau und DApp-Lebenszyklus. |
| Theme-/AppStore-Test | Bestanden: Hex-Validierung, Speicherung eigener Themes, sicherer Manifestparser, Traversal-Sperre, Versionsvergleich, Update-Karten mit Logos, bestätigte Store-Registrierung sowie atomare Deinstallation aus Datei und Registry. |
| Erweiterter Logo-Test | Bestanden: alle 38 Symbolnamen erzeugen bei Standardgröße sichtbare Geometrie; die Laufzeitliste enthält die vollständige Sammlung. |
| Abgleich verwendeter Modulpfade mit KOReader `master` | Bestanden für `PluginLoader`, `OverlapGroup`, `FrameContainer`, `InputContainer` und die benötigten Text-/Layoutcontainer. |
| Physischer E-Ink-Refresh- und Größenabgleich | Ausstehend. |

## Version 1.1

Version **1.1.0** ersetzt den bisherigen Verweis der File-Manager-DApp auf KOReaders Standard-Dateimanager durch einen eigenständigen **AppDock File Browser**. Er startet im konfigurierten KOReader-Bibliotheksordner, zeigt alle regulären Ordner und Dateien in klaren Karten, sortiert Ordner vor Dateien und bietet **Up**, **Home** sowie **Refresh**. Ein unterstütztes Dokument startet über `ReaderUI:showReader`, den von KOReader vorgesehenen sicheren Reader-Übergang; nicht unterstützte Dateien bleiben sichtbar und erhalten eine verständliche Meldung. [7] [8]

Version **1.1.1** korrigiert einen Crash beim Aufbau einer Ordnerliste mit nicht unterstützten Dateien: Eine lokale Indexvariable hatte die gettext-Übersetzungsfunktion `_` überschattet. Der Index trägt nun einen eindeutigen Namen; ein Regressionstest baut ausdrücklich eine Dateiliste mit einer nicht unterstützten Datei auf.

Version **1.1.2** vergrößert den reservierten Kopfbereich im File Manager, trennt dessen einzeilige **Up**-, **Home**- und **Refresh**-Aktionen klar von der Dateiliste und passt Dateikarten typografisch an. Der Schnellzugriff berechnet seine Blattgröße nun aus Kopf, Kacheln und Helligkeitsslider; bei engen Bildschirmhöhen verwendet er eine kompaktere, vollständig sichtbare Kachelvariante.

Version **1.2.0** gestaltet die Settings-DApp als thematisch gegliederte Einstellungsansicht mit einer schmalen Seitenleiste aus gezeichneten Mini-Logos. **Network** bündelt WLAN und den transparent als nicht verfügbar markierten Bluetooth-Eintrag. **Display** öffnet KOReaders native Steuerung für Helligkeit und Wärme und schaltet Farbthemen über den Nachtmodus. **Other** führt zu Layout, Informationen über AppDock sowie einer ausdrücklich noch nicht implementierten Aktualisierung.

Version **1.3.0** ergänzt einen persistierenden Theme-Editor mit vier Presets und frei benennbaren Hex-Akzenten. Die neue farbige **AppStore**-DApp lädt ausschließlich den Textkatalog des öffentlichen Repositories [`arduinodude456/DApps`](https://github.com/arduinodude456/DApps), prüft relative Lua-Pfade und verlangt vor jeder Installation eine sichtbare Bestätigung. Das Repository enthält bereits `dapps.txt`, eine Formatbeschreibung und die kleine offline Beispiel-DApp **Quote Card**.

Version **1.4.0** erweitert `appdock_logo.lua` von neun auf **38** vollständig gezeichnete, skalierbare E-Ink-Logos. Neben den AppDock-Kernsymbolen stehen nun unter anderem Kalender, Aufgaben, Notizen, Dokumente, Rechner, Musik, Galerie, Kamera, Suche, Cloud, Terminal, Code, Synchronisierung, Sicherheit, Karten und Übersetzen bereit. Die referenzierte Symbolsammlung ist in `DAPP_LOGOS.md` dokumentiert und über `DAppLogo.availableKinds()` abrufbar.

Version **1.5.0** ergänzt einen kontrollierten Dateiübergabevertrag für installierte Store-DApps. Die eigene **Files**-DApp erkennt nun `.lua`-Dateien und übergibt sie direkt an die installierte **NightLua**-DApp; der KOReader-Standard-Dateimanager wird dabei nicht geöffnet. NightLua selbst stellt einen nativen Vollbildeditor mit Monospace-Schrift, sichere Speicherung nach Lua-Syntaxprüfung und eine separate E-Ink-Syntaxvorschau bereit.

Version **1.6.0** macht den **AppStore** versionsbewusst: Ein Katalogeintrag kann eine numerische DApp-Version führen; ist diese neuer als die installierte, bietet die Karte **Update** an. Downloads werden vor dem Ersetzen geprüft und atomar übernommen, die DApp-ID sowie die deklarierte Version müssen zum Katalog passen. Store-Karten zeigen die jeweiligen gezeichneten Logos; installierte Karten bieten eine bestätigte **Uninstall**-Aktion, die die DApp-Datei und ihre AppStore-Registry entfernt, aber eigene Nutzerdateien bewahrt.

Version **1.7.0** erweitert den eigenen **Files**-Browser um einen klaren, direkten Übergabepfad für die Store-DApp **DReader**. EPUB, HTML, HTM und XHTML zeigen nach der DReader-Installation **Open in DReader** und werden ohne KOReaders Standard-Dateimanager an die stateful Reader-DApp übergeben. Lua-Dateien bleiben unverändert NightLua vorbehalten; alle anderen Dokumentformate folgen weiterhin dem sicheren ReaderUI-Pfad.

Die Version-1.0-Oberfläche konzentrierte sich auf eine **ruhige, zusammenhängende E-Ink-Hierarchie**: große gerundete Aktionsflächen, wiederverwendete DApp-Logos, klare Toolbar-Aktionen und offline nutzbare Hilfe. Die dazugehörigen Produktentscheidungen stehen in `V1_PRODUCT_DESIGN.md`.

## Referenzen

[1] [Google: Material 3 Expressive für Android und Wear OS](https://blog.google/products-and-platforms/platforms/android/material-3-expressive-android-wearos-launch/)

[2] [Android Developers: Material Design 3 in Compose](https://developer.android.com/develop/ui/compose/designsystems/material3)

[3] [KOReader: PluginLoader](https://github.com/koreader/koreader/blob/master/frontend/pluginloader.lua)

[4] [KOReader: Plugin-Instanziierung im FileManager](https://github.com/koreader/koreader/blob/master/frontend/apps/filemanager/filemanager.lua)

[5] [KOReader: `UIManager:setDirty`](https://github.com/koreader/koreader/blob/master/frontend/ui/uimanager.lua)

[6] [KOReader: Frontlight-Widget](https://github.com/koreader/koreader/blob/master/frontend/ui/widget/frontlightwidget.lua)

[7] [KOReader: File-Manager-Hilfsfunktionen und Bibliotheksordner](https://github.com/koreader/koreader/blob/master/frontend/apps/filemanager/filemanagerutil.lua)

[8] [KOReader: ReaderUI und sicherer Dokumentstart](https://github.com/koreader/koreader/blob/master/frontend/apps/reader/readerui.lua)
