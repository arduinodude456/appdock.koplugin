# AppDock-Plugin-Host: verbindlicher Pane- und Dialogvertrag

Dieses Dokument ersetzt den früheren abschaltbaren Plugin-in-DApp-Beta-Vertrag. Normale KOReader-Plugin-Kacheln werden jetzt immer innerhalb einer AppDock-verwalteten Sitzung geöffnet. Der alte gespeicherte Beta-Wert ist kein Start-Gate mehr.

## Darstellung und Bedienung

Eine Sitzung erhält die ID `plugin_host:<Pluginname>`, AppDocks Kopfzeile und Navigation sowie einen Eintrag in **Open apps**. Menüaktionen und dynamische Untermenüs werden als thematische Aktionsflächen dargestellt. Informations-, Bestätigungs- und einfache Eingabedialoge werden in AppDock-Overlays umgewandelt; verschachtelte Ansichten erhalten einen lokalen Rückweg.

Ein Plugin mit `buildAppDockPane(context)` erhält die aktuelle Farbpalette, Kontrastrollen, Texthelfer, UI-Metriken und eine lokale Pane-Geometrie. Sein Ereignis- und Lebenszyklusvertrag bleibt an den Host gebunden. Optionale `onAppDockHostOpened(context)`- und `onAppDockHostClosed(context)`-Hooks laufen ebenfalls innerhalb dieses Vertrags.

Unbekannte oder nicht adaptierbare Spezialoberflächen werden nicht als separate KOReader-Fenster geöffnet. Stattdessen erscheint eine AppDock-interne Kompatibilitätsmeldung. Eine solche Meldung ist keine funktional vollständige Umsetzung der blockierten Spezialansicht; dafür braucht das Plugin ein angepasstes Pane oder einen weiteren Adapter.

## Ausführung und Lebenszyklus

Nur bereits aktivierte und instanziierte Plugins werden angeboten. Der Host führt ihre veröffentlichten Aktionen geschützt aus und reicht bei Menü-Callbacks den vorhandenen TouchMenu-kompatiblen Adapter weiter. Dialog-Callbacks erhalten keine zusätzlich erfundenen Argumente.

Die UIManager-Brücke ist zeitlich auf einen Plugin-Aufruf begrenzt und wird nach Erfolg oder Fehler wieder entfernt. Geplante UI-Fortsetzungen werden erneut zugeordnet, solange ihre AppDock-Sitzung aktiv ist. Eine geschlossene oder fremde Sitzung darf nicht übernommen werden. Eingabezugriffe sowie Widget-Close/Free-Aufrufe sind ebenfalls Teil des gebrückten Plugin-Lebenszyklus.

Plugin-Hosts bleiben technisch nicht splittbar und nicht fensterfähig. Sie werden nicht über den lokalen Workspace nach einem KOReader-Neustart wiederhergestellt. Nachrichten gehen über `context.notify(...)` an AppDocks vorhandene lokale Inbox.

## Grenzen

Der Vertrag betrifft Starts und zugeordnete Ausführung innerhalb AppDocks. Er installiert keine dauerhafte globale UIManager-Interzeption und verändert außerhalb AppDocks gestartete KOReader-Plugins nicht. Vertrauenswürdiger Plugin-Lua-Code bleibt Code im selben KOReader-Prozess; der Host ist keine Sicherheits-Sandbox.

Ausführliche Änderungen und lokale Prüfanweisungen: [Shorts und einheitliches Plugin-Hosting](docs/SHORTS_AND_PLUGIN_HOST.md).
