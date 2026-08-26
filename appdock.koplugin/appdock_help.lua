-- AppDock Help: offline, searchable, bilingual reference for the integrated Help DApp.

local Help = {}
Help.__index = Help

local function trim(value)
    if type(value) ~= "string" then return "" end
    return value:match("^%s*(.-)%s*$") or ""
end

local function escapeHTML(value)
    return tostring(value or ""):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;")
end

local function lower(value)
    return string.lower(tostring(value or ""))
end

local function section(id, logo, de_title, en_title, de_keywords, en_keywords, de_body, en_body)
    return {
        id = id, logo = logo,
        de = { title = de_title, keywords = de_keywords, body = de_body },
        en = { title = en_title, keywords = en_keywords, body = en_body },
    }
end

local SECTIONS = {
    section("start", "help", "1. Schnellstart", "1. Getting started", "start installieren plugin homescreen öffnen aktivieren", "start install plugin homescreen open enable", [[
<p><b>AppDock läuft innerhalb von KOReader.</b> Es ersetzt weder den Launcher des Readers noch Android. Aktiviere das Plugin in <b>More tools → Plugin management</b> und öffne anschließend <b>AppDock Homescreen → Open homescreen</b>.</p>
<p>Der Homescreen besteht aus Systemzeile, optionalen Karten, Widgets und angehefteten Apps. Tippe eine Kachel zum Starten an. Ein langer Druck öffnet die App-Verwaltung. AppDock speichert sein Layout, die ausgewählten Widgets, Themen und Store-Apps lokal in den KOReader-Einstellungen.</p>
<p>Beim ersten Öffnen pro KOReader-Sitzung zeigt AppDock kurz seine Hasenmarke und danach den Namen. Das sind zwei ruhige UI-Zustände, keine flüssige Animation und kein zusätzlicher Vollrefresh. Die Rückkehr zum Homescreen innerhalb derselben Sitzung überspringt die Startsequenz.</p>
<p>Wenn AppDock beim KOReader-Start erscheinen soll, aktiviere diese Option unter <b>Settings → Other → Startup homescreen</b>. Andernfalls bleibt der Einstieg manuell.</p>]], [[
<p><b>AppDock runs inside KOReader.</b> It does not replace the reader launcher or Android. Enable the plugin under <b>More tools → Plugin management</b>, then open <b>AppDock Homescreen → Open homescreen</b>.</p>
<p>The homescreen contains a system row, optional cards, widgets and pinned apps. Tap a tile to launch it. Hold a tile to open app management. AppDock stores its layout, selected widgets, themes and Store apps locally in KOReader settings.</p>
<p>On the first opening in each KOReader session, AppDock briefly shows its rabbit mark and then its name. These are two quiet UI states, not a fluid animation and not an extra full refresh. Returning home in the same session skips the start sequence.</p>
<p>To show AppDock when KOReader starts, enable the option in <b>Settings → Other → Startup homescreen</b>. Otherwise open it manually.</p>]]),
    section("homescreen", "settings", "2. Homescreen und Launcher", "2. Homescreen and launcher", "homescreen kacheln seiten app suche layout abstand kreis rund library menu history", "homescreen tiles pages app search layout spacing circle rounded library menu history", [[
<p>Die Systemzeile zeigt Uhrzeit und – wenn aktiviert – Akkustand. Der Abwärtspfeil öffnet die Schnellzugriffe. Darunter können <b>Device status</b>, <b>Current book</b> und Store-Widgets erscheinen. Die App-Kacheln sind die von dir angehefteten System-, Plugin- und DApp-Aktionen.</p>
<p>Die ersten sechs Apps füllen eine 3×2-Seite. Weitere angeheftete Apps werden über Seitenschalter erreicht. <b>Library</b>, <b>Menu</b>, <b>History</b>, <b>Manage apps and widgets</b> und <b>Open apps</b> sind Systemfunktionen; ihre Verfügbarkeit hängt teilweise vom aktiven KOReader-Kontext ab.</p>
<p>Öffne in der <b>Settings</b>-DApp den einzelnen Eintrag <b>Arrange apps &amp; widgets</b>. Dort verschiebst du angeheftete Apps mit <b>↑</b> und <b>↓</b>. Die Reihenfolge bestimmt anschließend Raster und Seiten des Launchers und wird lokal gespeichert. Der Long-Press-Manager bleibt für Hinzufügen und Entfernen zuständig.</p>
<p>Unter <b>Settings → Display → Launcher layout</b> stellst du Abstand zwischen Kacheln, abgerundete oder kreisförmige Logo-Flächen sowie die optionale App-Suche ein. Die Suchleiste filtert nur sichtbare AppDock-Kacheln, sie durchsucht weder Bücher noch das Web.</p>]], [[
<p>The system row shows time and, when enabled, battery status. The down arrow opens Quick Settings. Below it, <b>Device status</b>, <b>Current book</b> and Store widgets can appear. App tiles are your pinned system actions, plugin actions and DApps.</p>
<p>The first six apps fill one 3×2 page. Page controls access further pinned apps. <b>Library</b>, <b>Menu</b>, <b>History</b>, <b>Manage apps and widgets</b> and <b>Open apps</b> are system features; some depend on the active KOReader context.</p>
<p>Open the single <b>Arrange apps &amp; widgets</b> entry in the <b>Settings</b> DApp. There, move pinned apps with <b>↑</b> and <b>↓</b>. The order then determines the launcher grid and pages and is stored locally. The long-press manager remains for adding and removing items.</p>
<p>In <b>Settings → Display → Launcher layout</b>, adjust tile spacing, rounded or circular logo surfaces, and optional app search. The search bar filters AppDock tiles only; it does not search books or the web.</p>]]),
    section("manage", "other", "3. Apps und Widgets verwalten", "3. Managing apps and widgets", "verwalten hinzufügen entfernen langdruck widgets anheften plugin aktionen", "manage add remove hold widgets pin plugin actions", [[
<p>Halte eine Kachel gedrückt oder öffne <b>Manage apps and widgets</b>, um angeheftete Apps und Systemkarten zu ändern. <b>Add</b> fügt eine verfügbare App hinzu; <b>Added</b> entfernt die Verknüpfung vom Homescreen. Das Löschen einer Verknüpfung deaktiviert kein KOReader-Plugin.</p>
<p>Unter Widgets aktivierst oder deaktivierst du Clock, Device status, Current book und installierte Store-Widgets einzeln. Ein deaktiviertes Widget bleibt installiert, wird aber nicht auf dem Homescreen gezeichnet.</p>
<p>Im selben <b>Arrange apps &amp; widgets</b>-Dialog ordnest du installierte Store-Widgets mit <b>↑</b> und <b>↓</b> an. Die lokale Reihenfolge bestimmt ihre vertikale Reihenfolge auf dem Homescreen. Neue Widgets werden am Ende ergänzt; entfernte Widgets werden aus der Reihenfolge bereinigt.</p>
<p>Plugins mit einer klaren Hauptmenüaktion können als Kachel erscheinen. Bei mehreren Aktionen zeigt AppDock zunächst einen Dialog. Plugins ohne veröffentlichte Menüaktion werden absichtlich nicht als App angeboten.</p>]], [[
<p>Hold a tile or open <b>Manage apps and widgets</b> to change pinned apps and system cards. <b>Add</b> pins an available app; <b>Added</b> removes its homescreen shortcut. Removing a shortcut does not disable a KOReader plugin.</p>
<p>Under Widgets, enable or disable Clock, Device status, Current book and installed Store widgets individually. A disabled widget remains installed but is not drawn on the homescreen.</p>
<p>In the same <b>Arrange apps &amp; widgets</b> dialog, move installed Store widgets with <b>↑</b> and <b>↓</b>. The local order determines their vertical homescreen order. New widgets are appended; removed widgets are cleaned from the order.</p>
<p>Plugins with one clear main-menu action can appear as tiles. For multiple actions, AppDock first shows a dialog. Plugins without a published menu action are deliberately not offered as apps.</p>]]),
    section("quicksettings", "display", "4. Schnellzugriff", "4. Quick Settings", "schnellzugriff dropdown helligkeit wlan nacht refresh editor slider fast eink", "quick settings dropdown brightness wifi night refresh editor slider fast eink", [[
<p>Öffne den Schnellzugriff über den Abwärtspfeil in der Systemzeile. Die Oberfläche ist ein gezeichnetes AppDock-Blatt, kein Standard-Buttonmenü.</p>
<p><b>Brightness</b> setzt die native Frontlight-Intensität. Ziehen oder Antippen nutzt einen schnellen regionalen E-Ink-Refresh und fordert zusätzlich einen normalen UI-Refresh an. <b>Wi-Fi</b> schaltet KOReaders Netzwerkstatus. <b>Night</b> löst den vorhandenen Nachtmodus aus. <b>Refresh</b> baut die sichtbare Oberfläche neu auf und fordert einen vollständigen Refresh an. <b>Edit</b> öffnet den AppDock-Editor.</p>
<p>Auf sehr niedrigen Pane-Höhen wird der Inbox-Teil bewusst ausgeblendet, damit Basissteuerungen und der Helligkeitsregler nicht überlappen.</p>]], [[
<p>Open Quick Settings through the down arrow in the system row. It is a drawn AppDock sheet, not a standard button menu.</p>
<p><b>Brightness</b> sets native frontlight intensity. Dragging or tapping uses a fast regional E-Ink refresh and also requests a regular UI refresh. <b>Wi-Fi</b> toggles KOReader networking. <b>Night</b> triggers the existing night mode. <b>Refresh</b> redraws the visible UI and requests a full refresh. <b>Edit</b> opens the AppDock editor.</p>
<p>On very short panes, the Inbox area is intentionally hidden so essential controls and the brightness slider do not overlap.</p>]]),
    section("notifications", "mail", "5. Lokale Benachrichtigungen", "5. Local notifications", "benachrichtigungen inbox popup toast ungelesen gelesen löschen context notify", "notifications inbox popup toast unread read clear context notify", [[
<p>AppDock 2.1.0 besitzt eine lokale, persistente Inbox. Eine gültige Meldung zeigt kurz eine nicht animierte Karte am unteren Bildschirmrand und wird in den Schnellzugriff übernommen. Tippe die Pop-up-Karte an, um sie früher zu schließen.</p>
<p>Im Schnellzugriff siehst du den ungelesenen Zähler, aktuelle Einträge sowie <b>Read all</b> und <b>Clear all</b>. Ein Antippen eines ungelesenen Eintrags markiert ihn als gelesen. Die Inbox speichert maximal 50 Meldungen.</p>
<p>DApps können mit <b>context.notify({ title, message, priority, source })</b> lokale Meldungen auslösen. Titel und Text sind Pflicht und begrenzt; Benachrichtigungen sind für echte Ergebnisse oder Fehler gedacht, nicht für Repaints, Seitenwechsel oder Hintergrundschleifen.</p>]], [[
<p>AppDock 2.1.0 includes a local, persistent inbox. A valid message briefly shows a non-animated card at the bottom of the screen and is added to Quick Settings. Tap the pop-up card to dismiss it early.</p>
<p>Quick Settings shows the unread counter, recent entries, and <b>Read all</b> and <b>Clear all</b>. Tapping an unread entry marks it read. The inbox stores at most 50 messages.</p>
<p>DApps can create local messages with <b>context.notify({ title, message, priority, source })</b>. Title and text are required and bounded; notifications are for real results or errors, not repaints, page changes or background loops.</p>]]),
    section("dapps", "app_store", "6. DApps, Open apps und Splitscreen", "6. DApps, Open apps and split screen", "dapps offene apps recents schließen splitscreen analog clock settings files browser help", "dapps open apps recents close split screen analog clock settings files browser help", [[
<p>DApps sind zustandsbehaftete AppDock-Anwendungen. Sie bleiben nach dem Wechsel zum Homescreen logisch geöffnet. <b>Open apps</b> zeigt diese Sitzungen, erlaubt das Wiederherstellen und bietet ein Schließen-Symbol. Beim Schließen wird nur die DApp-Sitzung beendet.</p>
<p>Für Splitscreen öffne zuerst zwei DApps. Halte in <b>Open apps</b> eine Karte gedrückt, wähle <b>Splitscreen</b> und danach die zweite offene DApp. Beide erhalten getrennte Pane-Flächen untereinander. Home oder Open apps verlassen die sichtbare Teilung, ohne die beiden DApps automatisch zu schließen.</p>
<p>Die integrierten DApps sind Analog Clock, Settings, Files, AppStore, Web Browser und Help. Installierte Store-DApps folgen demselben Pane-Vertrag und können – sofern ihre Oberfläche auf kleinem Raum lesbar bleibt – ebenfalls im Splitscreen laufen. AppDock 4.0.0 ergänzt unter <b>Settings → Display → Beta features</b> einen freiwilligen Plugin-in-DApp-Host für bereits aktivierte Plugins. Ein kooperierendes Plugin kann einen lokalen Panevertrag und <b>context.notify(...)</b> verwenden; andere Plugins erhalten eine sichere Aktionsliste. Plugin-Hosts sind klar als Beta markiert und können nie im Splitscreen laufen. AppDock fängt fremde Plugin-Dialoge nicht global ab.</p>]], [[
<p>DApps are stateful AppDock applications. They remain logically open after you return home. <b>Open apps</b> lists these sessions, lets you restore them, and provides a close icon. Closing ends only the DApp session.</p>
<p>For split screen, open two DApps first. Hold a card in <b>Open apps</b>, choose <b>Splitscreen</b>, then choose the second open DApp. Both receive separate vertically stacked panes. Home or Open apps leaves the visible split without automatically closing either DApp.</p>
<p>Built-in DApps are Analog Clock, Settings, Files, AppStore, Web Browser and Help. Installed Store DApps use the same pane contract and can also run in split screen when their UI remains readable in the reduced space. AppDock 4.0.0 adds an opt-in Plugin-in-DApp host for already enabled plugins under <b>Settings → Display → Beta features</b>. A cooperating plugin can use a local pane contract and <b>context.notify(...)</b>; other plugins receive a safe action-list fallback. Plugin hosts are clearly marked as beta and never support Split Screen. AppDock does not globally intercept foreign plugin dialogs.</p>]]),
    section("settings", "settings", "7. Einstellungen", "7. Settings", "einstellungen netzwerk display speicher weiteres sprache startup themes layout bluetooth", "settings network display storage other language startup themes layout bluetooth", [[
<p><b>Network</b> enthält Wi-Fi. Bluetooth erscheint ausschließlich auf Kobo Libra Colour und öffnet nur das Menü einer separat installierten kompatiblen Erweiterung; AppDock steuert keine Treiber selbst.</p>
<p><b>Display</b> öffnet die nativen KOReader-Lichtsteuerungen, verwaltet Farbthemen, Launcher layout und Beta features. Der Plugin-in-DApp-Host ist dort ausdrücklich opt-in und ohne Splitscreen. <b>Storage</b> scannt lokale AppDock-Daten, zeigt eine kompakte Belegungsübersicht und listet installierte Store-DApps nach Dateigröße.</p>
<p><b>Other</b> enthält Layout, About AppDock, UI language, Startup homescreen und einen manuellen UI-Refresh. Die KOReader-UI-Sprache ist Deutsch oder Englisch; ein Neustart ist erforderlich, bevor alle KOReader-Texte die neue Sprache verwenden.</p>]], [[
<p><b>Network</b> contains Wi-Fi. Bluetooth appears only on Kobo Libra Colour and opens only the menu of a separately installed compatible plugin; AppDock does not control drivers itself.</p>
<p><b>Display</b> opens native KOReader light controls, manages color themes, Launcher layout, and Beta features. The Plugin-in-DApp host is explicitly opt-in there and has no Split Screen. <b>Storage</b> scans local AppDock data, shows a compact usage overview, and lists installed Store DApps by file size.</p>
<p><b>Other</b> contains Layout, About AppDock, UI language, Startup homescreen and a manual UI refresh. KOReader UI language can be German or English; restart is required before all KOReader text uses the new language.</p>]]),
    section("themes", "display", "8. Themen und Darstellung", "8. Themes and appearance", "themes lavender ocean forest sunset custom hex dark eink monochrome", "themes lavender ocean forest sunset custom hex dark eink monochrome", [[
<p>Unter <b>Color themes</b> stehen Lavender, Ocean, Forest und Sunset zur Auswahl. Mit <b>Create custom theme</b> vergibst du einen Namen und einen sechsstelligen Hex-Akzent wie <b>#4F8CC9</b>.</p>
<p>Das Theme steuert Homescreen, integrierte DApps, Schnellzugriff und File Manager. Auf monochromen Geräten werden Akzente absichtlich auf stabile Kontrastrollen abgebildet; ein Farbtheme macht einen Graustufen-Reader nicht farbig.</p>
<p>Der Nachtmodus bleibt eine KOReader-Funktion. Er kann über Schnellzugriff oder die thematische Display-Einstellung ausgelöst werden.</p>]], [[
<p>Under <b>Color themes</b>, choose Lavender, Ocean, Forest or Sunset. With <b>Create custom theme</b>, provide a name and a six-digit accent such as <b>#4F8CC9</b>.</p>
<p>The theme controls the homescreen, built-in DApps, Quick Settings and File Manager. On monochrome devices, accents intentionally map to stable contrast roles; a color theme does not make a grayscale reader color-capable.</p>
<p>Night mode remains a KOReader function. Trigger it from Quick Settings or the Display settings category.</p>]]),
    section("files", "file_manager", "9. Files, NightLua und DReader", "9. Files, NightLua and DReader", "files dateimanager ordner up home refresh lua nightlua epub html dreader readerui", "files file manager folders up home refresh lua nightlua epub html dreader readerui", [[
<p><b>Files</b> ist AppDocks eigener scrollbarer Dateibrowser. Er zeigt Ordner vor Dateien und bietet <b>Up</b>, <b>Home</b> und <b>Refresh</b>. Nicht unterstützte Dateien bleiben sichtbar und werden klar markiert statt still zu verschwinden.</p>
<p>Ist NightLua installiert, werden <b>.lua</b>-Dateien an NightLua übergeben. Ist DReader installiert, werden <b>.epub</b>, <b>.html</b>, <b>.htm</b> und <b>.xhtml</b> direkt an DReader übergeben. Andere unterstützte Dokumente verwenden weiterhin KOReaders sicheren ReaderUI-Übergang.</p>
<p>NightLua ist ein lokaler Lua-Editor mit Syntaxvorschau und sicherer Speicherung nach Syntaxprüfung. DReader ist ein separater Store-Reader für unterstützte Buch- und HTML-Dateien; seine Darstellung hängt von Dateiinhalt, Bildern und Readergröße ab.</p>]], [[
<p><b>Files</b> is AppDock’s own scrollable file browser. It lists folders before files and provides <b>Up</b>, <b>Home</b> and <b>Refresh</b>. Unsupported files remain visible and are clearly marked instead of silently disappearing.</p>
<p>If NightLua is installed, <b>.lua</b> files are handed to NightLua. If DReader is installed, <b>.epub</b>, <b>.html</b>, <b>.htm</b> and <b>.xhtml</b> are handed directly to DReader. Other supported documents still use KOReader’s safe ReaderUI route.</p>
<p>NightLua is a local Lua editor with syntax preview and syntax-checked saving. DReader is a separate Store reader for supported books and HTML files; its display depends on file content, images and reader size.</p>]]),
    section("store", "app_store", "10. AppStore und Widgets", "10. AppStore and widgets", "appstore installieren update deinstallieren katalog dapps txt https version widgets quote weather bestätigung", "appstore install update uninstall catalog dapps txt https version widgets quote weather confirmation", [[
<p>Der AppStore lädt den Katalog <b>dapps.txt</b> aus dem vertrauenswürdigen DApps-Repository über HTTPS. Beim Aktualisieren wird nur der Textkatalog gelesen; kein DApp-Code läuft dadurch automatisch.</p>
<p>Erst nach einer sichtbaren Bestätigung lädt AppDock die gewählte Lua-Datei über HTTPS, prüft Syntax und Version und speichert sie atomar. Eine höhere Katalogversion erscheint als <b>Update</b>. <b>Uninstall</b> entfernt nur die installierte DApp-Datei und ihre AppStore-Registry, nicht von der DApp erzeugte persönliche Dokumente oder Einstellungen.</p>
<p>Ein Katalogeintrag mit dem Typ <b>widget</b> installiert ein Homescreen-Widget. Quote Widget arbeitet vollständig offline. Weather Widget ruft Open-Meteo über HTTPS ab. Widgets können in Manage apps and widgets einzeln ein- oder ausgeblendet werden.</p>]], [[
<p>AppStore loads the <b>dapps.txt</b> catalog from the trusted DApps repository over HTTPS. Refreshing reads only the text catalog; it does not automatically execute DApp code.</p>
<p>Only after visible confirmation does AppDock download the selected Lua file over HTTPS, check syntax and version, and store it atomically. A higher catalog version appears as <b>Update</b>. <b>Uninstall</b> removes only the installed DApp file and AppStore registry, not personal documents or settings created by the DApp.</p>
<p>A catalog entry of type <b>widget</b> installs a homescreen widget. Quote Widget works entirely offline. Weather Widget requests Open-Meteo over HTTPS. Widgets can be shown or hidden individually in Manage apps and widgets.</p>]]),
    section("storeapps", "other", "11. Store-DApps im Überblick", "11. Store DApps at a glance", "2048 calculator calendar rss draw translator video browser status message gmail notifications dockupdate", "2048 calculator calendar rss draw translator video browser status message gmail notifications dockupdate", [[
<p>Der Store kann je nach Katalogstand unter anderem BookTranslator, NightLua, Draw, Calc, Calendar, RSS Reader, BWR Video, Video Player, DReader, 2048, DockUpdate, Status Message und Gmail Notifications enthalten. Jede DApp zeigt ihre eigene Kurzbeschreibung, Version und Logo im Store.</p>
<p><b>BookTranslator</b> übersetzt unterstützte lokale Texte mit einem konfigurierten Dienst. <b>Draw</b> bietet Seiten, Stift/Radierer, Farb- und Hintergrundoptionen sowie Geräteeingabe, soweit die Hardware sie bereitstellt. <b>Calc</b> berechnet Ausdrücke und zeichnet einfache Plots. <b>Calendar</b> und <b>RSS Reader</b> speichern ihre Inhalte lokal. <b>2048</b> nutzt Wischgesten und Tasten-Fallbacks. Video-DApps sind auf die dokumentierten lokalen Formate und Audio-/Gerätefähigkeiten begrenzt.</p>
<p><b>Status Message</b> ist eine Offline-Referenz für lokale AppDock-Benachrichtigungen. <b>Gmail Notifications</b> ist absichtlich manuell: Es prüft Gmail nur nach Antippen über einen lokalen Heimnetz-Adapter. Google-Tokens gehören auf den Adapter-Computer, nie in die DApp; der erste Abruf setzt nur eine stille Baseline.</p>
<p>Einzelne Apps benötigen zusätzliche Voraussetzungen: Übersetzer benötigen einen gewählten Dienst und Schlüssel, Netzwerk-DApps brauchen WLAN, Video-Funktionen hängen vom unterstützten Dateiformat und Gerät ab. Lies stets die Beschreibung und Release Notes der jeweiligen DApp.</p>]], [[
<p>Depending on catalog state, the Store can include BookTranslator, NightLua, Draw, Calc, Calendar, RSS Reader, BWR Video, Video Player, DReader, 2048, DockUpdate, Status Message and Gmail Notifications. Each DApp shows its own short description, version and logo in the Store.</p>
<p><b>BookTranslator</b> translates supported local text through a configured service. <b>Draw</b> provides pages, pen/eraser, color and background options, plus device input where hardware supports it. <b>Calc</b> evaluates expressions and draws simple plots. <b>Calendar</b> and <b>RSS Reader</b> keep their content locally. <b>2048</b> uses swipe gestures with key fallbacks. Video DApps are limited to their documented local formats and available audio/device capabilities.</p>
<p><b>Status Message</b> is an offline reference for local AppDock notifications. <b>Gmail Notifications</b> is deliberately manual: it checks Gmail only after a tap through a local home-network adapter. Google tokens belong on the adapter computer, never in the DApp; the first check only creates a quiet baseline.</p>
<p>Some apps need additional prerequisites: translators require a selected service and key, network DApps need Wi-Fi, and video features depend on supported file format and device. Always read the relevant DApp description and release notes.</p>]]),
    section("browser", "web_browser", "12. Web Browser", "12. Web Browser", "browser duckduckgo html adresse suche zurück reload javascript formulare downloads https http", "browser duckduckgo html address search back reload javascript forms downloads https http", [[
<p>Web Browser ist ein schlanker Lesebrowser. <b>Address</b> öffnet HTTP- oder HTTPS-Adressen, <b>Search</b> verwendet DuckDuckGo HTML, <b>Back</b> nutzt den lokalen Verlauf und <b>Reload</b> lädt die aktuelle Seite erneut.</p>
<p>Unterstützt werden serverseitig geliefertes HTML, relative Links und kurze lokale Historie. Bewusst nicht unterstützt werden JavaScript, WebSockets, eingebettete Medien, Formulare, Downloads und Nicht-HTTP(S)-Links. Das ist eine Sicherheits- und Lesbarkeitsentscheidung, kein Defekt.</p>
<p>Seiten können durch Antwortgröße, Netzwerkzeit, moderne JavaScript-Pflicht oder Login-Anforderungen eingeschränkt sein. Für Textseiten, Wikipedia, Project Gutenberg und DuckDuckGo HTML ist die DApp gedacht.</p>]], [[
<p>Web Browser is a lightweight reading browser. <b>Address</b> opens HTTP or HTTPS addresses, <b>Search</b> uses DuckDuckGo HTML, <b>Back</b> uses local history, and <b>Reload</b> reloads the current page.</p>
<p>It supports server-rendered HTML, relative links and short local history. JavaScript, WebSockets, embedded media, forms, downloads and non-HTTP(S) links are deliberately unsupported. This is a security and readability decision, not a defect.</p>
<p>Pages may be limited by response size, network time, modern JavaScript requirements or login requirements. The DApp is intended for text pages, Wikipedia, Project Gutenberg and DuckDuckGo HTML.</p>]]),
    section("developers", "code", "13. DApps entwickeln", "13. Building DApps", "entwickler developer buildpane context dimen requestrefresh requestrebuild notify widgets sicherheit", "developer buildpane context dimen requestrefresh requestrebuild notify widgets security", [[
<p>Eine Store-DApp ist eine Lua-Datei mit eindeutiger <b>id</b>, <b>version</b>, Titel, Logo und <b>buildPane(instance, context)</b>. Sie zeichnet ausschließlich innerhalb von <b>context.dimen</b>; dadurch kann der Host dieselbe DApp im Vollbild oder Splitscreen anzeigen.</p>
<p>Der Context bietet die verwaltete Instanz, Refresh- und Rebuild-Hilfen sowie für AppDock 2.1.0 <b>context.notify</b>. Verwende <b>requestRefresh</b> für gezielte sichtbare Änderungen und <b>requestRebuild("ui")</b> bei Strukturänderungen. Baue keine Dauer-Polling-Schleifen, keine versteckten Netzwerkzugriffe und keine Animationen ein.</p>
<p>Store-DApps werden aus dem Katalog nur nach Bestätigung über HTTPS geladen und syntaxgeprüft. Entwickler müssen Eingaben, Dateipfade, Antwortgrößen und externe URLs begrenzen. Weitere Details stehen in der DeveloperManual des DApps-Repositories.</p>]], [[
<p>A Store DApp is a Lua file with a unique <b>id</b>, <b>version</b>, title, logo and <b>buildPane(instance, context)</b>. It draws only within <b>context.dimen</b>, allowing the host to show the same DApp full-screen or in split screen.</p>
<p>The context provides the managed instance plus refresh and rebuild helpers, and AppDock 2.1.0 adds <b>context.notify</b>. Use <b>requestRefresh</b> for targeted visible changes and <b>requestRebuild("ui")</b> for structural changes. Do not build continuous polling loops, hidden network access or animations.</p>
<p>Store DApps are loaded from the catalog only after confirmation over HTTPS and are syntax-checked. Developers must bound input, file paths, response sizes and external URLs. Further detail is in the DApps repository DeveloperManual.</p>]]),
    section("updates", "download", "14. DockUpdate und AppDock-Updates", "14. DockUpdate and AppDock updates", "dockupdate release notes update github restart stable prerelease zip plugin", "dockupdate release notes update github restart stable prerelease zip plugin", [[
<p><b>DockUpdate</b> ist eine separate Store-DApp. Sie prüft das neueste stabile GitHub-Release des AppDock-Plugin-Repositories, zeigt Release Notes und kann die geprüften Plugin-Dateien installieren. Nach einem AppDock-Update muss KOReader vollständig neu gestartet werden.</p>
<p>DockUpdate akzeptiert nur erwartete, über HTTPS geladene Plugin-Dateien, prüft Syntax, staged Dateien und behält vor dem Austausch eine Rückfallkopie. Beta- oder Pre-Releases werden nicht automatisch als stabiles Update ausgewählt.</p>
<p>Bei einem manuellen Update verwende immer ein vollständiges Release-Archiv, ersetze den kompletten <b>appdock.koplugin</b>-Ordner und behalte bei Problemen die vorherige Kopie. Installiere keine zufälligen Lua-Dateien aus nicht vertrauenswürdigen Quellen.</p>]], [[
<p><b>DockUpdate</b> is a separate Store DApp. It checks the latest stable GitHub release of the AppDock plugin repository, shows release notes and can install verified plugin files. Restart KOReader completely after an AppDock update.</p>
<p>DockUpdate accepts only expected plugin files loaded over HTTPS, checks syntax, stages files, and retains a fallback copy before replacement. Beta or pre-releases are not automatically chosen as stable updates.</p>
<p>For a manual update, always use a complete release archive, replace the whole <b>appdock.koplugin</b> folder, and retain the previous copy for recovery. Do not install random Lua files from untrusted sources.</p>]]),
    section("eink", "display", "15. E-Ink, Datenschutz und Fehlerhilfe", "15. E-Ink, privacy and troubleshooting", "eink refresh fast full ghosting offline privacy wlan fehler problem benachrichtigungen gmail", "eink refresh fast full ghosting offline privacy wifi error problem notifications gmail", [[
<p>AppDock vermeidet absichtlich Animationen und Dauer-Polling. Schnelle regionale Refreshes werden nur für unmittelbare Steuerung wie Helligkeit eingesetzt. Ein periodischer vollständiger Refresh hilft gegen Ghosting. Wenn etwas veraltet aussieht, nutze den manuellen <b>Refresh</b> im Schnellzugriff.</p>
<p>Die meisten Einstellungen und die Benachrichtigungs-Inbox bleiben lokal auf dem Reader. Netzwerkzugriffe sind funktionsbezogen: AppStore und DockUpdate verwenden HTTPS, Wetter/RSS/Browser laden nur nach einer Nutzeraktion oder gemäß ihrer dokumentierten DApp-Logik. Prüfe WLAN und Datum/Uhrzeit bei Netzwerkfehlern.</p>
<p>Für Gmail Notifications muss der lokale Adapter laufen, seine Kobo-IP-Freigabe stimmen und das TLS-Zertifikat vertrauenswürdig sein. <b>Forget local data</b> entfernt die Kobo-Seite der Verbindung. Bei wiederholten Problemen lies die DApp-Release Notes, starte KOReader neu und teste auf echter Hardware mit ausreichend freiem Speicher.</p>]], [[
<p>AppDock deliberately avoids animations and continuous polling. Fast regional refreshes are used only for immediate controls such as brightness. A periodic full refresh helps reduce ghosting. If something looks stale, use manual <b>Refresh</b> in Quick Settings.</p>
<p>Most settings and the notification inbox remain local on the reader. Network access is feature-specific: AppStore and DockUpdate use HTTPS; Weather/RSS/Browser load only after a user action or according to their documented DApp logic. Check Wi-Fi and date/time when network errors occur.</p>
<p>For Gmail Notifications, the local adapter must be running, its Kobo-IP allow-list must be correct, and its TLS certificate must be trusted. <b>Forget local data</b> removes the Kobo side of the connection. For recurring problems, read the DApp release notes, restart KOReader, and test on real hardware with sufficient free storage.</p>]]),
}

local CSS = [[
body { font-family: sans-serif; line-height: 1.36; color: #202020; background: #ffffff; }
h1 { font-size: 1.40em; margin: 0.2em 0 0.32em; }
h2 { font-size: 1.12em; margin: 0.92em 0 0.28em; border-bottom: 1px solid #a0a0a0; padding-bottom: 0.12em; }
p { margin: 0.24em 0 0.56em; }
.note { color: #555555; font-size: 0.88em; }
.count { color: #555555; font-size: 0.9em; }
]]

function Help:new(ui)
    return setmetatable({ ui = ui }, self)
end

function Help.defaultLanguage()
    return G_reader_settings:readSetting("language") == "de" and "de" or "en"
end

function Help.normalizeQuery(query)
    query = trim(query)
    if #query > 80 then query = query:sub(1, 80) end
    return query
end

function Help.search(language, query)
    language = language == "de" and "de" or "en"
    query = Help.normalizeQuery(query)
    if query == "" then return SECTIONS end
    local needle, results = lower(query), {}
    for _, item in ipairs(SECTIONS) do
        local entry = item[language]
        local haystack = lower(item.id .. " " .. entry.title .. " " .. entry.keywords .. " " .. entry.body)
        if haystack:find(needle, 1, true) then results[#results + 1] = item end
    end
    return results
end

function Help.render(language, query)
    language = language == "de" and "de" or "en"
    query = Help.normalizeQuery(query)
    local title = language == "de" and "AppDock Hilfe · Offline-Handbuch" or "AppDock Help · Offline guide"
    local intro = language == "de" and "Durchsuche alle Kapitel über die obere Suchaktion. Diese Hilfe benötigt kein Netzwerk und ist auch im Splitscreen lesbar." or "Search all chapters using the action at the top. This guide needs no network and remains readable in split screen."
    local results = Help.search(language, query)
    local body = { "<h1>", title, "</h1><p class='note'>", intro, "</p>" }
    if query ~= "" then
        local label = language == "de" and "Suche" or "Search"
        local count = language == "de" and "passende Kapitel" or "matching chapters"
        body[#body + 1] = "<p class='count'><b>" .. label .. ":</b> “" .. escapeHTML(query) .. "” · " .. tostring(#results) .. " " .. count .. "</p>"
    end
    if #results == 0 then
        body[#body + 1] = "<h2>" .. (language == "de" and "Keine Treffer" or "No results") .. "</h2><p>" .. (language == "de" and "Versuche einen kürzeren Begriff wie WLAN, Inbox, Store, Dateien, Layout oder Update." or "Try a shorter term such as Wi-Fi, inbox, Store, files, layout or update.") .. "</p>"
    else
        for _, item in ipairs(results) do
            local entry = item[language]
            body[#body + 1] = "<h2>" .. entry.title .. "</h2>" .. entry.body
        end
    end
    return table.concat(body)
end

function Help:showSearch(instance, context)
    local InputDialog, UIManager, _ = self.ui.InputDialog, self.ui.UIManager, self.ui._
    local state = instance.help_state
    local dialog
    dialog = InputDialog:new{
        title = state.language == "de" and "Hilfe durchsuchen" or "Search help",
        input_hint = state.language == "de" and "z. B. Inbox, WLAN, Store oder Update" or "e.g. inbox, Wi-Fi, Store or update",
        input = state.query or "",
        buttons = { { { text = _("Cancel"), callback = function() UIManager:close(dialog) end }, { text = state.language == "de" and "Suchen" or "Search", is_enter_default = true, callback = function()
            state.query = Help.normalizeQuery(dialog:getInputText())
            UIManager:close(dialog)
            context.requestRebuild("ui")
        end } } },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function Help:buildPane(instance, context)
    local ui = self.ui
    instance.help_state = instance.help_state or { language = Help.defaultLanguage(), query = "" }
    local state = instance.help_state
    local width, height = context.dimen.w, context.dimen.h
    local margin, header_height, chip_width = ui.scale(12), ui.scale(54), ui.scale(72)
    local pane = ui.WidgetContainer:new{ dimen = ui.Geom:new{ w = width, h = height } }
    local language_title = state.language == "de" and "EN" or "DE"
    local scroll = ui.ScrollHtmlWidget:new{
        html_body = Help.render(state.language, state.query), css = CSS,
        width = width - 2 * margin, height = math.max(ui.scale(70), height - header_height - margin),
        default_font_size = ui.scale(15), dialog = context.host,
        overlap_offset = { margin, header_height },
    }
    local search_title = state.language == "de" and "Suche" or "Search"
    pane[1] = ui.OverlapGroup:new{
        dimen = pane.dimen, allow_mirroring = false,
        ui.FrameContainer:new{ width = width, height = height, padding = 0, bordersize = 0, background = ui.palette.background, ui.emptySizedWidget(width, height) },
        ui.TextWidget:new{ text = state.language == "de" and "AppDock Hilfe" or "AppDock Help", face = ui.Font:getFace("cfont", ui.scale(20)), fgcolor = ui.palette.on_surface, bold = true, overlap_offset = { margin, ui.scale(13) } },
        ui.ActionChip:new{ title = search_title, symbol = "⌕", width = chip_width, height = ui.scale(42), background = ui.palette.primary, foreground = ui.palette.on_primary, callback = function() self:showSearch(instance, context) end, overlap_offset = { width - margin - chip_width * 2 - ui.scale(7), ui.scale(6) } },
        ui.ActionChip:new{ title = language_title, symbol = "A", width = chip_width, height = ui.scale(42), background = ui.palette.surface_variant, foreground = ui.palette.on_surface, callback = function()
            state.language = state.language == "de" and "en" or "de"
            context.requestRebuild("ui")
        end, overlap_offset = { width - margin - chip_width, ui.scale(6) } },
        scroll,
    }
    pane.help_layout = { language = state.language, query = state.query, result_count = #Help.search(state.language, state.query) }
    return pane
end

Help._test = { sections = SECTIONS, normalizeQuery = Help.normalizeQuery, search = Help.search, render = Help.render }

return Help
